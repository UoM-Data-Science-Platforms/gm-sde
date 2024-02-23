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

--┌──────────────────────────────────────────────────────────────────────┐
--│ Define Cohort for RQ045: COVID-19 vaccine hesitancy and acceptance   │
--└──────────────────────────────────────────────────────────────────────┘

-- OBJECTIVE: To build the cohort of patients needed for RQ045. This reduces
--						duplication of code in the template scripts. The cohort is any
--						patient who have no missing data for YOB, sex, LSOA and ethnicity

-- OUTPUT: A temp tables as follows:
-- #Patients
-- - PatientID
-- - Sex
-- - YOB
-- - LSOA
-- - Ethnicity

DECLARE @StartDate datetime;
SET @StartDate = '2020-01-01';

--=========================================================================================================================================================== 
--┌───────────────────────────────────────────────────────────┐
--│ Create table of patients who are registered with a GM GP  │
--└───────────────────────────────────────────────────────────┘

-- INPUT REQUIREMENTS: @StartDate

-- Find all patients alive at start date
IF OBJECT_ID('tempdb..#PossiblePatients') IS NOT NULL DROP TABLE #PossiblePatients;
SELECT PK_Patient_Link_ID as FK_Patient_Link_ID, EthnicMainGroup, EthnicGroupDescription, DeathDate INTO #PossiblePatients FROM [SharedCare].Patient_Link
WHERE 
	(DeathDate IS NULL OR (DeathDate >= @StartDate))

-- Find all patients registered with a GP
IF OBJECT_ID('tempdb..#PatientsWithGP') IS NOT NULL DROP TABLE #PatientsWithGP;
SELECT DISTINCT FK_Patient_Link_ID INTO #PatientsWithGP FROM [SharedCare].Patient
where FK_Reference_Tenancy_ID = 2;

-- Make cohort from patients alive at start date and registered with a GP
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT pp.* INTO #Patients FROM #PossiblePatients pp
INNER JOIN #PatientsWithGP gp on gp.FK_Patient_Link_ID = pp.FK_Patient_Link_ID;

------------------------------------------

-- OUTPUT: #Patients
--┌─────┐
--│ Sex │
--└─────┘

-- OBJECTIVE: To get the Sex for each patient.

-- INPUT: Assumes there exists a temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: A temp table as follows:
-- #PatientSex (FK_Patient_Link_ID, Sex)
-- 	- FK_Patient_Link_ID - unique patient id
--	- Sex - M/F

-- ASSUMPTIONS:
--	- Patient data is obtained from multiple sources. Where patients have multiple sexes we determine the sex as follows:
--	-	If the patients has a sex in their primary care data feed we use that as most likely to be up to date
--	-	If every sex for a patient is the same, then we use that
--	-	If there is a single most recently updated sex in the database then we use that
--	-	Otherwise the patient's sex is considered unknown

-- Get all patients sex for the cohort
IF OBJECT_ID('tempdb..#AllPatientSexs') IS NOT NULL DROP TABLE #AllPatientSexs;
SELECT 
	FK_Patient_Link_ID,
	FK_Reference_Tenancy_ID,
	HDMModifDate,
	Sex
INTO #AllPatientSexs
FROM SharedCare.Patient p
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND Sex IS NOT NULL;


-- If patients have a tenancy id of 2 we take this as their most likely Sex
-- as this is the GP data feed and so most likely to be up to date
IF OBJECT_ID('tempdb..#PatientSex') IS NOT NULL DROP TABLE #PatientSex;
SELECT FK_Patient_Link_ID, MIN(Sex) as Sex INTO #PatientSex FROM #AllPatientSexs
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_Tenancy_ID = 2
GROUP BY FK_Patient_Link_ID
HAVING MIN(Sex) = MAX(Sex);

-- Find the patients who remain unmatched
IF OBJECT_ID('tempdb..#UnmatchedSexPatients') IS NOT NULL DROP TABLE #UnmatchedSexPatients;
SELECT FK_Patient_Link_ID INTO #UnmatchedSexPatients FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientSex;

-- If every Sex is the same for all their linked patient ids then we use that
INSERT INTO #PatientSex
SELECT FK_Patient_Link_ID, MIN(Sex) FROM #AllPatientSexs
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedSexPatients)
GROUP BY FK_Patient_Link_ID
HAVING MIN(Sex) = MAX(Sex);

-- Find any still unmatched patients
TRUNCATE TABLE #UnmatchedSexPatients;
INSERT INTO #UnmatchedSexPatients
SELECT FK_Patient_Link_ID FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientSex;

-- If there is a unique most recent Sex then use that
INSERT INTO #PatientSex
SELECT p.FK_Patient_Link_ID, MIN(p.Sex) FROM #AllPatientSexs p
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(HDMModifDate) MostRecentDate FROM #AllPatientSexs
	WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedSexPatients)
	GROUP BY FK_Patient_Link_ID
) sub ON sub.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND sub.MostRecentDate = p.HDMModifDate
GROUP BY p.FK_Patient_Link_ID
HAVING MIN(Sex) = MAX(Sex);

-- Tidy up - helpful in ensuring the tempdb doesn't run out of space mid-query
DROP TABLE #AllPatientSexs;
DROP TABLE #UnmatchedSexPatients;
--┌───────────────┐
--│ Year of birth │
--└───────────────┘

-- OBJECTIVE: To get the year of birth for each patient.

-- INPUT: Assumes there exists a temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: A temp table as follows:
-- #PatientYearOfBirth (FK_Patient_Link_ID, YearOfBirth)
-- 	- FK_Patient_Link_ID - unique patient id
--	- YearOfBirth - INT

-- ASSUMPTIONS:
--	- Patient data is obtained from multiple sources. Where patients have multiple YOBs we determine the YOB as follows:
--	-	If the patients has a YOB in their primary care data feed we use that as most likely to be up to date
--	-	If every YOB for a patient is the same, then we use that
--	-	If there is a single most recently updated YOB in the database then we use that
--	-	Otherwise we take the highest YOB for the patient that is not in the future

-- Get all patients year of birth for the cohort
IF OBJECT_ID('tempdb..#AllPatientYearOfBirths') IS NOT NULL DROP TABLE #AllPatientYearOfBirths;
SELECT 
	FK_Patient_Link_ID,
	FK_Reference_Tenancy_ID,
	HDMModifDate,
	YEAR(Dob) AS YearOfBirth
INTO #AllPatientYearOfBirths
FROM SharedCare.Patient p
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND Dob IS NOT NULL;


-- If patients have a tenancy id of 2 we take this as their most likely YOB
-- as this is the GP data feed and so most likely to be up to date
IF OBJECT_ID('tempdb..#PatientYearOfBirth') IS NOT NULL DROP TABLE #PatientYearOfBirth;
SELECT FK_Patient_Link_ID, MIN(YearOfBirth) as YearOfBirth INTO #PatientYearOfBirth FROM #AllPatientYearOfBirths
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_Tenancy_ID = 2
GROUP BY FK_Patient_Link_ID
HAVING MIN(YearOfBirth) = MAX(YearOfBirth);

-- Find the patients who remain unmatched
IF OBJECT_ID('tempdb..#UnmatchedYobPatients') IS NOT NULL DROP TABLE #UnmatchedYobPatients;
SELECT FK_Patient_Link_ID INTO #UnmatchedYobPatients FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientYearOfBirth;

-- If every YOB is the same for all their linked patient ids then we use that
INSERT INTO #PatientYearOfBirth
SELECT FK_Patient_Link_ID, MIN(YearOfBirth) FROM #AllPatientYearOfBirths
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedYobPatients)
GROUP BY FK_Patient_Link_ID
HAVING MIN(YearOfBirth) = MAX(YearOfBirth);

-- Find any still unmatched patients
TRUNCATE TABLE #UnmatchedYobPatients;
INSERT INTO #UnmatchedYobPatients
SELECT FK_Patient_Link_ID FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientYearOfBirth;

-- If there is a unique most recent YOB then use that
INSERT INTO #PatientYearOfBirth
SELECT p.FK_Patient_Link_ID, MIN(p.YearOfBirth) FROM #AllPatientYearOfBirths p
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(HDMModifDate) MostRecentDate FROM #AllPatientYearOfBirths
	WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedYobPatients)
	GROUP BY FK_Patient_Link_ID
) sub ON sub.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND sub.MostRecentDate = p.HDMModifDate
GROUP BY p.FK_Patient_Link_ID
HAVING MIN(YearOfBirth) = MAX(YearOfBirth);

-- Find any still unmatched patients
TRUNCATE TABLE #UnmatchedYobPatients;
INSERT INTO #UnmatchedYobPatients
SELECT FK_Patient_Link_ID FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientYearOfBirth;

-- Otherwise just use the highest value (with the exception that can't be in the future)
INSERT INTO #PatientYearOfBirth
SELECT FK_Patient_Link_ID, MAX(YearOfBirth) FROM #AllPatientYearOfBirths
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedYobPatients)
GROUP BY FK_Patient_Link_ID
HAVING MAX(YearOfBirth) <= YEAR(GETDATE());

-- Tidy up - helpful in ensuring the tempdb doesn't run out of space mid-query
DROP TABLE #AllPatientYearOfBirths;
DROP TABLE #UnmatchedYobPatients;
--┌───────────────────────────────┐
--│ Lower level super output area │
--└───────────────────────────────┘

-- OBJECTIVE: To get the LSOA for each patient.

-- INPUT: Assumes there exists a temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: A temp table as follows:
-- #PatientLSOA (FK_Patient_Link_ID, LSOA)
-- 	- FK_Patient_Link_ID - unique patient id
--	- LSOA_Code - nationally recognised LSOA identifier

-- ASSUMPTIONS:
--	- Patient data is obtained from multiple sources. Where patients have multiple LSOAs we determine the LSOA as follows:
--	-	If the patients has an LSOA in their primary care data feed we use that as most likely to be up to date
--	-	If every LSOA for a paitent is the same, then we use that
--	-	If there is a single most recently updated LSOA in the database then we use that
--	-	Otherwise the patient's LSOA is considered unknown

-- Get all patients LSOA for the cohort
IF OBJECT_ID('tempdb..#AllPatientLSOAs') IS NOT NULL DROP TABLE #AllPatientLSOAs;
SELECT 
	FK_Patient_Link_ID,
	FK_Reference_Tenancy_ID,
	HDMModifDate,
	LSOA_Code
INTO #AllPatientLSOAs
FROM SharedCare.Patient p
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND LSOA_Code IS NOT NULL;


-- If patients have a tenancy id of 2 we take this as their most likely LSOA_Code
-- as this is the GP data feed and so most likely to be up to date
IF OBJECT_ID('tempdb..#PatientLSOA') IS NOT NULL DROP TABLE #PatientLSOA;
SELECT FK_Patient_Link_ID, MIN(LSOA_Code) as LSOA_Code INTO #PatientLSOA FROM #AllPatientLSOAs
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_Tenancy_ID = 2
GROUP BY FK_Patient_Link_ID
HAVING MIN(LSOA_Code) = MAX(LSOA_Code);

-- Find the patients who remain unmatched
IF OBJECT_ID('tempdb..#UnmatchedLsoaPatients') IS NOT NULL DROP TABLE #UnmatchedLsoaPatients;
SELECT FK_Patient_Link_ID INTO #UnmatchedLsoaPatients FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientLSOA;
-- 38710 rows
-- 00:00:00

-- If every LSOA_Code is the same for all their linked patient ids then we use that
INSERT INTO #PatientLSOA
SELECT FK_Patient_Link_ID, MIN(LSOA_Code) FROM #AllPatientLSOAs
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedLsoaPatients)
GROUP BY FK_Patient_Link_ID
HAVING MIN(LSOA_Code) = MAX(LSOA_Code);

-- Find any still unmatched patients
TRUNCATE TABLE #UnmatchedLsoaPatients;
INSERT INTO #UnmatchedLsoaPatients
SELECT FK_Patient_Link_ID FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientLSOA;

-- If there is a unique most recent lsoa then use that
INSERT INTO #PatientLSOA
SELECT p.FK_Patient_Link_ID, MIN(p.LSOA_Code) FROM #AllPatientLSOAs p
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(HDMModifDate) MostRecentDate FROM #AllPatientLSOAs
	WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedLsoaPatients)
	GROUP BY FK_Patient_Link_ID
) sub ON sub.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND sub.MostRecentDate = p.HDMModifDate
GROUP BY p.FK_Patient_Link_ID
HAVING MIN(LSOA_Code) = MAX(LSOA_Code);

-- Tidy up - helpful in ensuring the tempdb doesn't run out of space mid-query
DROP TABLE #AllPatientLSOAs;
DROP TABLE #UnmatchedLsoaPatients;


-- The cohort table========================================================================================================================================
IF OBJECT_ID('tempdb..#Cohort') IS NOT NULL DROP TABLE #Cohort;
SELECT
  p.FK_Patient_Link_ID,
  Sex,
  YearOfBirth,
  LSOA_Code,
  Ethnicity = EthnicGroupDescription,
  DeathDate
INTO #Cohort
FROM #Patients p
LEFT OUTER JOIN #PatientYearOfBirth y ON p.FK_Patient_Link_ID = y.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientLSOA l ON l.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE y.YearOfBirth IS NOT NULL AND sex.Sex IS NOT NULL AND l.LSOA_Code IS NOT NULL
	AND YEAR(GETDATE()) - y.YearOfBirth >= 18;


-- Change the cohort table name into #Patients to use for other reusable queries===========================================================================
DELETE FROM #Patients
WHERE FK_Patient_Link_ID NOT IN 
	(SELECT FK_Patient_Link_ID FROM #Cohort);
--┌─────────────────────────────────────────────┐
--│ Patients with a COVID test result           │
--└─────────────────────────────────────────────┘

-- OBJECTIVE: To get all patients with a positive and negative COVID test result.


-- INPUT: Takes one parameter
--  - start-date: string - (YYYY-MM-DD) the date to count diagnoses from. Usually this should be 2020-01-01.

-- OUTPUT: Three temp tables as follows:
-- #CovidPositiveTests (FK_Patient_Link_ID, CovidTestDate, CovidTestResult)
-- #CovidNegativeTests (FK_Patient_Link_ID, CovidTestDate, CovidTestResult)
-- 	- FK_Patient_Link_ID - unique patient id
--  - CovidTestDate - Date, assume that only 1 test per day
--	- CovidTestResult - Varchar, 'Positive', 'Negative'.
-- #AllCovidTests (FK_Patient_Link_ID, CovidTestDate, CovidTestDescription, ClinicalCode)
-- 	- FK_Patient_Link_ID - unique patient id
--  - CovidTestDate - Date, assume that only 1 test per day
--	- CovidTestResult - Varchar, This field concatenates the information in the GroupDescription and SubGroupDescription from the COVID19 table.
--  - ClinicalCode - The clinical code retrieved from 'MainCode' in the COVID19 table. 


IF OBJECT_ID('tempdb..#CovidPositiveTests') IS NOT NULL DROP TABLE #CovidPositiveTests;
SELECT DISTINCT FK_Patient_Link_ID, CONVERT(DATE, [EventDate]) AS CovidTestDate, 'Positive' AS CovidTestResult INTO #CovidPositiveTests
FROM [SharedCare].[COVID19]
WHERE (
	(GroupDescription = 'Confirmed' AND SubGroupDescription != 'Negative') OR
	(GroupDescription = 'Tested' AND SubGroupDescription = 'Positive')
)
AND EventDate >= '2020-01-01'
AND EventDate <= GETDATE();

IF OBJECT_ID('tempdb..#CovidNegativeTests') IS NOT NULL DROP TABLE #CovidNegativeTests;
SELECT DISTINCT FK_Patient_Link_ID, CONVERT(DATE, [EventDate]) AS CovidTestDate, 'Negative' AS CovidTestResult INTO #CovidNegativeTests
FROM [SharedCare].[COVID19]
WHERE (
	(GroupDescription = 'Confirmed' AND SubGroupDescription = 'Negative') OR
	(GroupDescription = 'Tested' AND SubGroupDescription = 'Negative') OR
	(GroupDescription = 'Excluded' AND SubGroupDescription = 'Negative') 
)
AND EventDate >= '2020-01-01'
AND EventDate <= GETDATE();


-- Get all covid tests, the date, and the clinical code. This includes positive, negative, excluded, suspected. 
IF OBJECT_ID('tempdb..#AllCovidTests') IS NOT NULL DROP TABLE #AllCovidTests;
SELECT DISTINCT FK_Patient_Link_ID, CONVERT(DATE, [EventDate]) AS CovidTestDate, CONCAT(GroupDescription, ' - ', SubGroupDescription)  AS CovidTestResult, MainCode AS ClinicalCode INTO #AllCovidTests
FROM [SharedCare].[COVID19]
WHERE (
	GroupDescription = 'Assessed'  OR
	GroupDescription = 'Confirmed'  OR
	GroupDescription = 'Tested'  OR
	GroupDescription = 'Excluded' OR
	GroupDescription = 'Suspected'  OR
	GroupDescription = 'Unknown' 
)
AND EventDate >= '2020-01-01'
AND EventDate <= GETDATE();

-- FINAL TABLE : ALL COVID TESTS FOR THE STUDY COHORT

SELECT PatientId = FK_Patient_Link_ID, 
	CovidTestDate,
	CovidTestResult, 
	ClinicalCode
FROM #AllCovidTests
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)