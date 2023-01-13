--┌────────────────────────────────────────────────────┐
--│ Define Cohort for RQ038: COVID + frailty project   │
--└────────────────────────────────────────────────────┘

-- OBJECTIVE: To build the cohort of patients needed for RQ038. This reduces
--						duplication of code in the template scripts. The cohort is any
--						patient who was >=60 years old on 1 Jan 2020 and have at least
--				 		one GP recorded positive COVID test
--            UPDATE 21/12/22 - recent SURG approved ALL patients >= 60 years
-- INPUT: A variable:
--	@TEMPRQ038EndDate - the date that we will not get records beyond

-- OUTPUT: Temp tables as follows:
-- #Patients - list of patient ids of the cohort

------------------------------------------------------------------------------

-- Only include patients who were first registered at a GP practice prior
-- to June 2022. This is 1 month before COPI expired and so acts as a buffer.
-- If we only looked at patients who first registered before July 2022, then
-- there is a chance that their data was processed after COPI expired.
IF OBJECT_ID('tempdb..#PatientsToInclude') IS NOT NULL DROP TABLE #PatientsToInclude;
SELECT FK_Patient_Link_ID INTO #PatientsToInclude
FROM SharedCare.Patient_GP_History
GROUP BY FK_Patient_Link_ID
HAVING MIN(StartDate) < @TEMPRQ038EndDate;

-- Table of all patients with COVID at least once
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT FK_Patient_Link_ID INTO #Patients FROM #PatientsToInclude

--> EXECUTE query-patient-year-of-birth.sql

-- Now restrict to those >=60 on 1st January 2020
TRUNCATE TABLE #Patients;
INSERT INTO #Patients
SELECT FK_Patient_Link_ID FROM #PatientYearOfBirth
WHERE YearOfBirth <= 1959;