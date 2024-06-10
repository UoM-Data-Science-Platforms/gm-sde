--┌─────────────────────────────────────────────────────────────────────────┐
--│ Define Cohort for LH014: Patients that have been on a virtual wards     │
--└─────────────────────────────────────────────────────────────────────────┘

-- OBJECTIVE: To build the cohort of patients needed for LH014. This reduces duplication of code in the template scripts.

-- COHORT: Any patient that has been admitted to a virtual ward

-- INPUT: assumes there exists one temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: Temp tables as follows:
-- #Cohort

--> EXECUTE query-get-possible-patients.sql
--> EXECUTE query-patient-year-of-birth.sql
--> EXECUTE query-patient-sex.sql

-- create cohort of patients who have been on a virtual ward
SELECT DISTINCT PatientId
INTO #VIRTUAL_WARDS
FROM VIRTUAL_WARD_OCCUPANCY



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
WHERE p.FK_Patient_Link_ID IN (SELECT PatientId FROM #VIRTUAL_WARDS) 


---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
