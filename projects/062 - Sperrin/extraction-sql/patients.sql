--+--------------------------------------------------------------------------------+
--¦ Patient information                                                            ¦
--+--------------------------------------------------------------------------------+

-------- RESEARCH DATA ENGINEER CHECK ---------

-- OUTPUT: Data with the following fields
-- PatientId
-- WeekOfBirth (dd/mm/yyyy)
-- MonthAndYearOfBirth (mm/yyyy)
-- Sex
-- Ethnicity
-- GPID
-- RegistrationGPDate 
-- DeregistrationGPDate
-- LSOA
-- IMD 
-- NumberGPEncounterBeforeSept2013


--Just want the output, not the messages
SET NOCOUNT ON;


--┌───────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
--│ Define Cohort for RQ062: all individuals registered with a GP who were aged 50 years or older on September 1 2013 │
--└───────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

-- OBJECTIVE: To build the cohort of patients needed for RQ062. This reduces duplication of code in the template scripts.

-- COHORT: All individuals who registered with a GP, and were aged 50 years or older on September 1 2013 (the start of the herpes zoster vaccine programme in the UK)

-- OUTPUT: Temp tables as follows:
-- #Patients (FK_Patient_Link_ID)
-- A distinct list of FK_Patient_Link_IDs for each patient in the cohort

------------------------------------------------------------------------------------------------------------------------------------------------------------

-- Create table #Patients for the reusable queries =========================================================================================================================
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT PK_Patient_Link_ID AS FK_Patient_Link_ID INTO #Patients
FROM [SharedCare].[Patient_Link]

--┌───────────────────────────────────────┐
--│ GET practice and ccg for each patient │
--└───────────────────────────────────────┘

-- OBJECTIVE:	For each patient to get the practice id that they are registered to, and 
--						the CCG name that the practice belongs to.

-- INPUT: Assumes there exists a temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: Two temp tables as follows:
-- #PatientPractice (FK_Patient_Link_ID, GPPracticeCode)
--	- FK_Patient_Link_ID - unique patient id
--	- GPPracticeCode - the nationally recognised practice id for the patient
-- #PatientPracticeAndCCG (FK_Patient_Link_ID, GPPracticeCode, CCG)
--	- FK_Patient_Link_ID - unique patient id
--	- GPPracticeCode - the nationally recognised practice id for the patient
--	- CCG - the name of the patient's CCG

-- If patients have a tenancy id of 2 we take this as their most likely GP practice
-- as this is the GP data feed and so most likely to be up to date
IF OBJECT_ID('tempdb..#PatientPractice') IS NOT NULL DROP TABLE #PatientPractice;
SELECT FK_Patient_Link_ID, MIN(GPPracticeCode) as GPPracticeCode INTO #PatientPractice FROM SharedCare.Patient
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_Tenancy_ID = 2
AND GPPracticeCode IS NOT NULL
GROUP BY FK_Patient_Link_ID;
-- 1298467 rows
-- 00:00:11

-- Find the patients who remain unmatched
IF OBJECT_ID('tempdb..#UnmatchedPatientsForPracticeCode') IS NOT NULL DROP TABLE #UnmatchedPatientsForPracticeCode;
SELECT FK_Patient_Link_ID INTO #UnmatchedPatientsForPracticeCode FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientPractice;
-- 12702 rows
-- 00:00:00

-- If every GPPracticeCode is the same for all their linked patient ids then we use that
INSERT INTO #PatientPractice
SELECT FK_Patient_Link_ID, MIN(GPPracticeCode) FROM SharedCare.Patient
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedPatientsForPracticeCode)
AND GPPracticeCode IS NOT NULL
GROUP BY FK_Patient_Link_ID
HAVING MIN(GPPracticeCode) = MAX(GPPracticeCode);
-- 12141
-- 00:00:00

-- Find any still unmatched patients
TRUNCATE TABLE #UnmatchedPatientsForPracticeCode;
INSERT INTO #UnmatchedPatientsForPracticeCode
SELECT FK_Patient_Link_ID FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientPractice;
-- 561 rows
-- 00:00:00

-- If there is a unique most recent gp practice then we use that
INSERT INTO #PatientPractice
SELECT p.FK_Patient_Link_ID, MIN(p.GPPracticeCode) FROM SharedCare.Patient p
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(HDMModifDate) MostRecentDate FROM SharedCare.Patient
	WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedPatientsForPracticeCode)
	GROUP BY FK_Patient_Link_ID
) sub ON sub.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND sub.MostRecentDate = p.HDMModifDate
WHERE p.GPPracticeCode IS NOT NULL
GROUP BY p.FK_Patient_Link_ID
HAVING MIN(GPPracticeCode) = MAX(GPPracticeCode);
-- 15

--┌──────────────────┐
--│ CCG lookup table │
--└──────────────────┘

-- OBJECTIVE: To provide lookup table for CCG names. The GMCR provides the CCG id (e.g. '00T', '01G') but not 
--            the CCG name. This table can be used in other queries when the output is required to be a ccg 
--            name rather than an id.

-- INPUT: No pre-requisites

-- OUTPUT: A temp table as follows:
-- #CCGLookup (CcgId, CcgName)
-- 	- CcgId - Nationally recognised ccg id
--	- CcgName - Bolton, Stockport etc..

IF OBJECT_ID('tempdb..#CCGLookup') IS NOT NULL DROP TABLE #CCGLookup;
CREATE TABLE #CCGLookup (CcgId nchar(3), CcgName nvarchar(20));
INSERT INTO #CCGLookup VALUES ('01G', 'Salford'); 
INSERT INTO #CCGLookup VALUES ('00T', 'Bolton'); 
INSERT INTO #CCGLookup VALUES ('01D', 'HMR'); 
INSERT INTO #CCGLookup VALUES ('02A', 'Trafford'); 
INSERT INTO #CCGLookup VALUES ('01W', 'Stockport');
INSERT INTO #CCGLookup VALUES ('00Y', 'Oldham'); 
INSERT INTO #CCGLookup VALUES ('02H', 'Wigan'); 
INSERT INTO #CCGLookup VALUES ('00V', 'Bury'); 
INSERT INTO #CCGLookup VALUES ('14L', 'Manchester'); 
INSERT INTO #CCGLookup VALUES ('01Y', 'Tameside Glossop'); 

IF OBJECT_ID('tempdb..#PatientPracticeAndCCG') IS NOT NULL DROP TABLE #PatientPracticeAndCCG;
SELECT p.FK_Patient_Link_ID, ISNULL(pp.GPPracticeCode,'') AS GPPracticeCode, ISNULL(ccg.CcgName, '') AS CCG
INTO #PatientPracticeAndCCG
FROM #Patients p
LEFT OUTER JOIN #PatientPractice pp ON pp.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN SharedCare.Reference_GP_Practice gp ON gp.OrganisationCode = pp.GPPracticeCode
LEFT OUTER JOIN #CCGLookup ccg ON ccg.CcgId = gp.Commissioner;
--┌────────────────────────────────┐
--│ Year and quarter month of birth│
--└────────────────────────────────┘

-- OBJECTIVE: To get the year of birth for each patient.

-- INPUT: Assumes there exists a temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: A temp table as follows:
-- #PatientYearAndQuarterMonthOfBirth (FK_Patient_Link_ID, YearAndQuarterMonthOfBirth)
-- 	- FK_Patient_Link_ID - unique patient id
--	- YearAndQuarterMonthOfBirth - (YYYY-MM-01)

-- ASSUMPTIONS:
--	- Patient data is obtained from multiple sources. Where patients have multiple YearAndQuarterMonthOfBirths we determine the YearAndQuarterMonthOfBirth as follows:
--	-	If the patients has a YearAndQuarterMonthOfBirth in their primary care data feed we use that as most likely to be up to date
--	-	If every YearAndQuarterMonthOfBirth for a patient is the same, then we use that
--	-	If there is a single most recently updated YearAndQuarterMonthOfBirth in the database then we use that
--	-	Otherwise we take the highest YearAndQuarterMonthOfBirth for the patient that is not in the future

-- Get all patients year and quarter month of birth for the cohort
IF OBJECT_ID('tempdb..#AllPatientYearAndQuarterMonthOfBirths') IS NOT NULL DROP TABLE #AllPatientYearAndQuarterMonthOfBirths;
SELECT 
	FK_Patient_Link_ID,
	FK_Reference_Tenancy_ID,
	HDMModifDate,
	CONVERT(date, Dob) AS YearAndQuarterMonthOfBirth
INTO #AllPatientYearAndQuarterMonthOfBirths
FROM SharedCare.Patient p
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND Dob IS NOT NULL;


-- If patients have a tenancy id of 2 we take this as their most likely YearAndQuarterMonthOfBirth
-- as this is the GP data feed and so most likely to be up to date
IF OBJECT_ID('tempdb..#PatientYearAndQuarterMonthOfBirth') IS NOT NULL DROP TABLE #PatientYearAndQuarterMonthOfBirth;
SELECT FK_Patient_Link_ID, MIN(YearAndQuarterMonthOfBirth) as YearAndQuarterMonthOfBirth INTO #PatientYearAndQuarterMonthOfBirth FROM #AllPatientYearAndQuarterMonthOfBirths
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_Tenancy_ID = 2
GROUP BY FK_Patient_Link_ID
HAVING MIN(YearAndQuarterMonthOfBirth) = MAX(YearAndQuarterMonthOfBirth);

-- Find the patients who remain unmatched
IF OBJECT_ID('tempdb..#UnmatchedYobPatients') IS NOT NULL DROP TABLE #UnmatchedYobPatients;
SELECT FK_Patient_Link_ID INTO #UnmatchedYobPatients FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientYearAndQuarterMonthOfBirth;

-- If every YearAndQuarterMonthOfBirth is the same for all their linked patient ids then we use that
INSERT INTO #PatientYearAndQuarterMonthOfBirth
SELECT FK_Patient_Link_ID, MIN(YearAndQuarterMonthOfBirth) FROM #AllPatientYearAndQuarterMonthOfBirths
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedYobPatients)
GROUP BY FK_Patient_Link_ID
HAVING MIN(YearAndQuarterMonthOfBirth) = MAX(YearAndQuarterMonthOfBirth);

-- Find any still unmatched patients
TRUNCATE TABLE #UnmatchedYobPatients;
INSERT INTO #UnmatchedYobPatients
SELECT FK_Patient_Link_ID FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientYearAndQuarterMonthOfBirth;

-- If there is a unique most recent YearAndQuarterMonthOfBirth then use that
INSERT INTO #PatientYearAndQuarterMonthOfBirth
SELECT p.FK_Patient_Link_ID, MIN(p.YearAndQuarterMonthOfBirth) FROM #AllPatientYearAndQuarterMonthOfBirths p
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(HDMModifDate) MostRecentDate FROM #AllPatientYearAndQuarterMonthOfBirths
	WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedYobPatients)
	GROUP BY FK_Patient_Link_ID
) sub ON sub.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND sub.MostRecentDate = p.HDMModifDate
GROUP BY p.FK_Patient_Link_ID
HAVING MIN(YearAndQuarterMonthOfBirth) = MAX(YearAndQuarterMonthOfBirth);

-- Find any still unmatched patients
TRUNCATE TABLE #UnmatchedYobPatients;
INSERT INTO #UnmatchedYobPatients
SELECT FK_Patient_Link_ID FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientYearAndQuarterMonthOfBirth;

-- Otherwise just use the highest value (with the exception that can't be in the future)
INSERT INTO #PatientYearAndQuarterMonthOfBirth
SELECT FK_Patient_Link_ID, MAX(YearAndQuarterMonthOfBirth) FROM #AllPatientYearAndQuarterMonthOfBirths
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedYobPatients)
GROUP BY FK_Patient_Link_ID
HAVING MAX(YearAndQuarterMonthOfBirth) <= GETDATE();

-- Tidy up - helpful in ensuring the tempdb doesn't run out of space mid-query
DROP TABLE #AllPatientYearAndQuarterMonthOfBirths;
DROP TABLE #UnmatchedYobPatients;
