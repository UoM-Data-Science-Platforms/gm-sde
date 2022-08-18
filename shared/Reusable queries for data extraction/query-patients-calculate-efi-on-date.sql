--┌────────────────────────────────────┐
--│ Calcluate Electronic Frailty Index │
--└────────────────────────────────────┘

-- OBJECTIVE: To calculate the EFI for all patients on a given date

-- INPUT: Takes three parameters
--  - efi-date: string - (YYYY-MM-DD) the date on which to calculate the EFI
--	-	all-patients: boolean - (true/false) if true, then all patients are included, otherwise only those in the pre-existing #Patients table.
--	- gp-events-table: string - (table name) the name of the table containing the GP events. Usually is "RLS.vw_GP_Events" but can be anything with the columns: FK_Patient_Link_ID, EventDate, and SuppliedCode
--	- gp-medications-table: string - (table name) the name of the table containing the GP medications. Usually is "RLS.vw_GP_Medications" but can be anything with the columns: FK_Patient_Link_ID, MedicationDate, and SuppliedCode

-- OUTPUT: One temp tables as follows:
--	#PatientEFI (FK_Patient_Link_ID, ListOfDeficits, NumberOfDeficits)
--	- FK_Patient_Link_ID - unique patient id
--	- ListOfDeficits - a "/"" separated list of deficits (e.g. 'diabetes/hypertension/falls')
--	- NumberOfDeficits - the number of deficits (e.g. 3)

-- Most of the logic occurs in the following subquery, which is also used
-- in the query-patients-calculate-efi-over-time.sql query
--> EXECUTE subquery-efi-common.sql all-patients:{param:all-patients} gp-events-table:{param:gp-events-table} gp-medications-table:{param:gp-medications-table}

-- Create a table of deficits the person had on a particular date. Combines the 35
-- deficits that just require a code, and the polypharmacy one as well
IF OBJECT_ID('tempdb..#EFICombinedDeficits') IS NOT NULL DROP TABLE #EFICombinedDeficits;
SELECT FK_Patient_Link_ID, Deficit INTO #EFICombinedDeficits FROM #EfiEvents
WHERE EventDate <= '{param:efi-date}'
UNION
SELECT FK_Patient_Link_ID, 'polypharmacy' FROM #PolypharmacyPeriods p
WHERE DateFrom <= '{param:efi-date}' AND DateTo >= '{param:efi-date}';

-- Produce the final table with the number of deficits and which deficits for each person
IF OBJECT_ID('tempdb..#PatientEFI') IS NOT NULL DROP TABLE #PatientEFI;
SELECT FK_Patient_Link_ID, STRING_AGG(Deficit, '/') AS ListOfDeficits, count(*) AS NumberOfDeficits
INTO #PatientEFI
FROM #EFICombinedDeficits
GROUP BY FK_Patient_Link_ID;