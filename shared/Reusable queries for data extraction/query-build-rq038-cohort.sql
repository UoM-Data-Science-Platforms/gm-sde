--┌────────────────────────────────────────────────────┐
--│ Define Cohort for RQ038: COVID + frailty project   │
--└────────────────────────────────────────────────────┘

-- OBJECTIVE: To build the cohort of patients needed for RQ038. This reduces
--						duplication of code in the template scripts. The cohort is any
--						patient who was >=60 years old on 1 Jan 2020 and have at least
--				 		one GP recorded positive COVID test
--            UPDATE 21/12/22 - recent SURG approved ALL patients >= 60 years
-- INPUT: None

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

-- Now restrict to those >=60 on 1st January 2020
TRUNCATE TABLE #Patients;
INSERT INTO #Patients
SELECT FK_Patient_Link_ID FROM #PatientYearOfBirth
WHERE YearOfBirth <= 1959;