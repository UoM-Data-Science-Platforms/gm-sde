--┌────────────────────────────────────────────────────────────┐
--│ Covid tests for patient cohort                             │
--└────────────────────────────────────────────────────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------
------------------------------------------------------

-- OUTPUT: Data with the following fields
-- Patient Id
-- TestOutcome
-- TestType
-- TestDate


-- Set the start date
DECLARE @EndDate datetime;
SET @EndDate = '2023-12-31';

--Just want the output, not the messages
SET NOCOUNT ON;

--> EXECUTE query-build-rq045-cohort.sql
--> EXECUTE query-patients-covid-tests.sql start-date:2020-01-01

-- FINAL TABLE : ALL COVID TESTS FOR THE STUDY COHORT

SELECT PatientId = FK_Patient_Link_ID, 
	CovidTestDate,
	CovidTestResult, 
	ClinicalCode
FROM #AllCovidTests
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)