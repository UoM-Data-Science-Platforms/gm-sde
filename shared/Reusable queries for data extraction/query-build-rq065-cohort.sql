--┌───────────────────────────────────────────┐
--│ Define Cohort for RQ065: Hypothyroidism   │
--└───────────────────────────────────────────┘

-- OBJECTIVE: To build the cohort of patients needed for RQ065. This reduces
--						duplication of code in the template scripts. The cohort is any
--						patient who is >=18 years old with a Free T4 test in their record
-- INPUT: No inputs
--
-- OUTPUT: Temp tables as follows:
-- #Patients - list of patient ids of the cohort

------------------------------------------------------------------------------

-- Table of all patients with a GP record
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT DISTINCT FK_Patient_Link_ID
INTO #Patients
FROM SharedCare.Patient
WHERE FK_Reference_Tenancy_ID=2
AND GPPracticeCode NOT LIKE 'ZZZ%';

--> EXECUTE query-patient-year-of-birth.sql

-- Now restrict to those >=18
TRUNCATE TABLE #Patients;
INSERT INTO #Patients
SELECT FK_Patient_Link_ID FROM #PatientYearOfBirth
WHERE YearOfBirth <= YEAR(GETDATE()) - 18;

-- NB get-first-diagnosis is fine even though T4 level is not a diagnosis as both codes appear in the Events table
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:SharedCare.GP_Events code-set:t4 version:1 temp-table-name:#FirstT4Level

-- Now restrict patients to just those with a T4 level
TRUNCATE TABLE #Patients;
INSERT INTO #Patients
SELECT FK_Patient_Link_ID FROM #FirstT4Level;