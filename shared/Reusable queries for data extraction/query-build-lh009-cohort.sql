--┌─────────────────────────────────────────────────┐
--│ Define Cohort for LH009: Women aged 40 - 65     │
--└─────────────────────────────────────────────────┘

-- OBJECTIVE: To build the cohort of patients needed for LH003. This reduces duplication of code in the template scripts.

-- COHORT: Any women aged 40 - 65.

-- INPUT: assumes there exists one temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: Temp tables as follows:
-- #Cohort

--> EXECUTE query-get-possible-patients.sql
--> EXECUTE query-patient-year-of-birth.sql
--> EXECUTE query-patient-sex.sql

-- create cohort of patients with non-cancer pain who received 3+ prescriptions within 90 days of diagnosis

IF OBJECT_ID('tempdb..#Cohort') IS NOT NULL DROP #Cohort;
SELECT
	 p.FK_Patient_Link_ID
	,yob.YearOfBirth
	,sex.Sex
	,EthnicMainGroup ----- CHANGE TO MORE SPECIFIC ETHNICITY ?
	,DeathDate
INTO #Cohort
FROM #Patients p
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE 
	YEAR(@StartDate) - YearOfBirth BETWEEN 40 AND 65 -- AGED BETWEEN 40 AND 65
	AND Sex = 'F' -- WOMEN ONLY 


---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
