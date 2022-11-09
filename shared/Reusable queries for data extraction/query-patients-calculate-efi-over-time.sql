--┌────────────────────────────────────┐
--│ Calcluate Electronic Frailty Index │
--└────────────────────────────────────┘

-- OBJECTIVE: To calculate the EFI for all patients and how it has changed over time

-- INPUT: Takes three parameters
--	-	all-patients: boolean - (true/false) if true, then all patients are included, otherwise only those in the pre-existing #Patients table.
--	- gp-events-table: string - (table name) the name of the table containing the GP events. Usually is "SharedCare.GP_Events" but can be anything with the columns: FK_Patient_Link_ID, EventDate, and SuppliedCode
--	- gp-medications-table: string - (table name) the name of the table containing the GP medications. Usually is "SharedCare.GP_Medications" but can be anything with the columns: FK_Patient_Link_ID, MedicationDate, and SuppliedCode

-- OUTPUT: One temp tables as follows:
--	#PatientEFIOverTime (FK_Patient_Link_ID, NumberOfDeficits, DateFrom)
--	- FK_Patient_Link_ID - unique patient id
--	- DateFrom - the date from which the patient had this number of deficits
--	- NumberOfDeficits - the number of deficits (e.g. 3)

-- Most of the logic occurs in the following subquery, which is also used
-- in the query-patients-calculate-efi-on-date.sql query
--> EXECUTE subquery-efi-common.sql all-patients:{param:all-patients} gp-events-table:{param:gp-events-table} gp-medications-table:{param:gp-medications-table}


-- count on each day
IF OBJECT_ID('tempdb..#DeficitCountsTEMP') IS NOT NULL DROP TABLE #DeficitCountsTEMP;
SELECT FK_Patient_Link_ID, EventDate, count(*) AS DailyDeficitIncrease
INTO #DeficitCountsTEMP
FROM #EfiEvents
GROUP BY FK_Patient_Link_ID, EventDate;

-- add polypharmacy
INSERT INTO #DeficitCountsTEMP
SELECT FK_Patient_Link_ID, DateFrom, 1 FROM #PolypharmacyPeriods -- we add 1 to the deficit on the date from
UNION
SELECT FK_Patient_Link_ID, DateTo, -1 FROM #PolypharmacyPeriods; -- we subtract 1 on the date to

-- Will have introduced some duplicate dates - remove them by summing
IF OBJECT_ID('tempdb..#DeficitCounts') IS NOT NULL DROP TABLE #DeficitCounts;
SELECT FK_Patient_Link_ID, EventDate, SUM(DailyDeficitIncrease) AS DailyDeficitIncrease
INTO #DeficitCounts
FROM #DeficitCountsTEMP
GROUP BY FK_Patient_Link_ID, EventDate;

IF OBJECT_ID('tempdb..#PatientEFIOverTime') IS NOT NULL DROP TABLE #PatientEFIOverTime;
SELECT t1.FK_Patient_Link_ID, t1.EventDate AS DateFrom, sum(t2.DailyDeficitIncrease) AS NumberOfDeficits
INTO #PatientEFIOverTime
FROM #DeficitCounts t1
LEFT OUTER JOIN #DeficitCounts t2
	ON t1.FK_Patient_Link_ID = t2.FK_Patient_Link_ID
	AND t2.EventDate <= t1.EventDate
GROUP BY t1.FK_Patient_Link_ID, t1.EventDate
ORDER BY t1.FK_Patient_Link_ID,t1.EventDate;