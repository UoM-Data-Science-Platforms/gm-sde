{if:verbose}
--┌──────────────────────────┐
--│ Gets a patient's height  │
--└──────────────────────────┘

-- OBJECTIVE: Gets the most recent measurement of a person's height

-- INPUT: A variable:
--  -	all-patients: boolean - (true/false) if true, then all patients are included, otherwise only those in the pre-existing #Patients table.
--  - gp-events-table: string - (table name) the name of the table containing the GP events. Usually is "SharedCare.GP_Events" but can be anything with the columns: FK_Patient_Link_ID, EventDate, and SuppliedCode

-- OUTPUT: Temp tables as follows:
-- #PatientHeight - two column table linking patient link id with the most recent height value
{endif:verbose}

--> EXECUTE query-get-most-recent-value.sql min-value:0.01 max-value:2.5 unit:m all-patients:{param:all-patients} gp-events-table:{param:gp-events-table} code-set:height version:1 max-or-min:max temp-table-name:#PatientHeightInMetres
--> EXECUTE query-get-most-recent-value.sql min-value:10 max-value:250 unit:cm all-patients:{param:all-patients} gp-events-table:{param:gp-events-table} code-set:height version:1 max-or-min:max temp-table-name:#PatientHeightInCentimetres

IF OBJECT_ID('tempdb..#PatientHeight') IS NOT NULL DROP TABLE #PatientHeight;
SELECT 
	CASE WHEN hm.FK_Patient_Link_ID IS NULL THEN hcm.FK_Patient_Link_ID ELSE hm.FK_Patient_Link_ID END AS FK_Patient_Link_ID,
	CASE
		WHEN hm.FK_Patient_Link_ID IS NULL THEN hcm.MostRecentValue
		WHEN hcm.FK_Patient_Link_ID IS NULL THEN hm.MostRecentValue * 100
		WHEN hm.MostRecentDate > hcm.MostRecentDate THEN hm.MostRecentValue * 100
		ELSE hcm.MostRecentValue
	END AS HeightInCentimetres,
	CASE
		WHEN hm.FK_Patient_Link_ID IS NULL THEN hcm.MostRecentDate
		WHEN hcm.FK_Patient_Link_ID IS NULL THEN hm.MostRecentDate
		WHEN hm.MostRecentDate > hcm.MostRecentDate THEN hm.MostRecentDate
		ELSE hcm.MostRecentDate
	END AS HeightDate
INTO #PatientHeight
FROM #PatientHeightInCentimetres hcm
FULL JOIN #PatientHeightInMetres hm ON hm.FK_Patient_Link_ID = hcm.FK_Patient_Link_ID;
