--┌────────────────────────────────────┐
--│ LH004 Patient file                 │
--└────────────────────────────────────┘

-- OUTPUT: Data with the following fields
-- 	- PatientId (int)
-- 

--Just want the output, not the messages
SET NOCOUNT ON;

DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2020-01-01'; 
SET @EndDate = '2023-10-31';

-- Set dates for BMI and blood tests
DECLARE @MinDate datetime;
SET @MinDate = '1900-01-01';
DECLARE @IndexDate datetime;
SET @IndexDate = '2023-10-31';

-- smoking, alcohol are based on most recent codes available

--┌───────────────────────────────────────────────────────────────┐
--│ Define Cohort for LH004: patients that had an SLE diagnosis   │
--└───────────────────────────────────────────────────────────────┘

-- OBJECTIVE: To build the cohort of patients needed for LH004. This reduces duplication of code in the template scripts.

-- COHORT: Any patient with a SLE diagnosis between start and end date.

-- INPUT: None

-- OUTPUT: Temp tables as follows:
-- #Cohort

DECLARE @StudyStartDate datetime;
SET @StudyStartDate = '2020-01-01'; 

--┌───────────────────────────────────────────────────────────┐
--│ Create table of patients who are registered with a GM GP  │
--└───────────────────────────────────────────────────────────┘

-- INPUT REQUIREMENTS: @StudyStartDate

-- Find all patients alive at start date
IF OBJECT_ID('tempdb..#PossiblePatients') IS NOT NULL DROP TABLE #PossiblePatients;
SELECT PK_Patient_Link_ID as FK_Patient_Link_ID, EthnicMainGroup, EthnicGroupDescription, DeathDate INTO #PossiblePatients FROM [SharedCare].Patient_Link
WHERE 
	(DeathDate IS NULL OR (DeathDate >= @StudyStartDate))

-- Find all patients registered with a GP
IF OBJECT_ID('tempdb..#PatientsWithGP') IS NOT NULL DROP TABLE #PatientsWithGP;
SELECT DISTINCT FK_Patient_Link_ID INTO #PatientsWithGP FROM [SharedCare].Patient
where FK_Reference_Tenancy_ID = 2
AND GPPracticeCode NOT LIKE 'ZZZ%';

-- Make cohort from patients alive at start date and registered with a GP
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT pp.* INTO #Patients FROM #PossiblePatients pp
INNER JOIN #PatientsWithGP gp on gp.FK_Patient_Link_ID = pp.FK_Patient_Link_ID;

------------------------------------------

-- OUTPUT: #Patients
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

-- >>> Codesets required... Inserting the code set code
--
--┌────────────────────┐
--│ Clinical code sets │
--└────────────────────┘

-- OBJECTIVE: To populate temporary tables with the existing clinical code sets.
--            See the [SQL-generation-process.md](SQL-generation-process.md) for more details.

-- INPUT: No pre-requisites

-- OUTPUT: Five temp tables as follows:
--  #AllCodes (Concept, Version, Code)
--  #CodeSets (FK_Reference_Coding_ID, Concept)
--  #SnomedSets (FK_Reference_SnomedCT_ID, FK_SNOMED_ID)
--  #VersionedCodeSets (FK_Reference_Coding_ID, Concept, Version)
--  #VersionedSnomedSets (FK_Reference_SnomedCT_ID, Version, FK_SNOMED_ID)

--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
--!!! DO NOT EDIT THIS FILE MANUALLY !!!
--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

--#region Clinical code sets

IF OBJECT_ID('tempdb..#AllCodes') IS NOT NULL DROP TABLE #AllCodes;
CREATE TABLE #AllCodes (
  [Concept] [varchar](255) NOT NULL,
  [Version] INT NOT NULL,
  [Code] [varchar](20) COLLATE Latin1_General_CS_AS NOT NULL,
  [description] [varchar] (255) NULL 
);

IF OBJECT_ID('tempdb..#codesreadv2') IS NOT NULL DROP TABLE #codesreadv2;
CREATE TABLE #codesreadv2 (
  [concept] [varchar](255) NOT NULL,
  [version] INT NOT NULL,
	[code] [varchar](20) COLLATE Latin1_General_CS_AS NOT NULL,
	[term] [varchar](20) COLLATE Latin1_General_CS_AS NULL,
	[description] [varchar](255) NULL
) ON [PRIMARY];

INSERT INTO #codesreadv2
VALUES ('chronic-kidney-disease',1,'1Z1f.',NULL,'CKD G5A3 - chronic kidney disease with glomerular filtration rate category G5 and albuminuria category A3'),('chronic-kidney-disease',1,'1Z1f.00',NULL,'CKD G5A3 - chronic kidney disease with glomerular filtration rate category G5 and albuminuria category A3'),('chronic-kidney-disease',1,'1Z1e.',NULL,'CKD G5A2 - chronic kidney disease with glomerular filtration rate category G5 and albuminuria category A2'),('chronic-kidney-disease',1,'1Z1e.00',NULL,'CKD G5A2 - chronic kidney disease with glomerular filtration rate category G5 and albuminuria category A2'),('chronic-kidney-disease',1,'1Z1d.',NULL,'CKD G5A1 - chronic kidney disease with glomerular filtration rate category G5 and albuminuria category A1'),('chronic-kidney-disease',1,'1Z1d.00',NULL,'CKD G5A1 - chronic kidney disease with glomerular filtration rate category G5 and albuminuria category A1'),('chronic-kidney-disease',1,'1Z1c.',NULL,'CKD G4A3 - chronic kidney disease with glomerular filtration rate category G4 and albuminuria category A3'),('chronic-kidney-disease',1,'1Z1c.00',NULL,'CKD G4A3 - chronic kidney disease with glomerular filtration rate category G4 and albuminuria category A3'),('chronic-kidney-disease',1,'1Z1b.',NULL,'CKD G4A2 - chronic kidney disease with glomerular filtration rate category G4 and albuminuria category A2'),('chronic-kidney-disease',1,'1Z1b.00',NULL,'CKD G4A2 - chronic kidney disease with glomerular filtration rate category G4 and albuminuria category A2'),('chronic-kidney-disease',1,'1Z1a.',NULL,'CKD G4A1 - chronic kidney disease with glomerular filtration rate category G4 and albuminuria category A1'),('chronic-kidney-disease',1,'1Z1a.00',NULL,'CKD G4A1 - chronic kidney disease with glomerular filtration rate category G4 and albuminuria category A1'),('chronic-kidney-disease',1,'1Z1Z.',NULL,'CKD G3bA3 - chronic kidney disease with glomerular filtration rate category G3b and albuminuria category A3'),('chronic-kidney-disease',1,'1Z1Z.00',NULL,'CKD G3bA3 - chronic kidney disease with glomerular filtration rate category G3b and albuminuria category A3'),('chronic-kidney-disease',1,'1Z1Y.',NULL,'CKD G3bA2 - chronic kidney disease with glomerular filtration rate category G3b and albuminuria category A2'),('chronic-kidney-disease',1,'1Z1Y.00',NULL,'CKD G3bA2 - chronic kidney disease with glomerular filtration rate category G3b and albuminuria category A2'),('chronic-kidney-disease',1,'1Z1X.',NULL,'CKD G3bA1 - chronic kidney disease with glomerular filtration rate category G3b and albuminuria category A1'),('chronic-kidney-disease',1,'1Z1X.00',NULL,'CKD G3bA1 - chronic kidney disease with glomerular filtration rate category G3b and albuminuria category A1'),('chronic-kidney-disease',1,'1Z1W.',NULL,'CKD G3aA3 - chronic kidney disease with glomerular filtration rate category G3a and albuminuria category A3'),('chronic-kidney-disease',1,'1Z1W.00',NULL,'CKD G3aA3 - chronic kidney disease with glomerular filtration rate category G3a and albuminuria category A3'),('chronic-kidney-disease',1,'1Z1V.',NULL,'CKD G3aA2 - chronic kidney disease with glomerular filtration rate category G3a and albuminuria category A2'),('chronic-kidney-disease',1,'1Z1V.00',NULL,'CKD G3aA2 - chronic kidney disease with glomerular filtration rate category G3a and albuminuria category A2'),('chronic-kidney-disease',1,'1Z1T.',NULL,'CKD G3aA1 - chronic kidney disease with glomerular filtration rate category G3a and albuminuria category A1'),('chronic-kidney-disease',1,'1Z1T.00',NULL,'CKD G3aA1 - chronic kidney disease with glomerular filtration rate category G3a and albuminuria category A1'),('chronic-kidney-disease',1,'1Z1S.',NULL,'CKD G2A3 - chronic kidney disease with glomerular filtration rate category G2 and albuminuria category A3'),('chronic-kidney-disease',1,'1Z1S.00',NULL,'CKD G2A3 - chronic kidney disease with glomerular filtration rate category G2 and albuminuria category A3'),('chronic-kidney-disease',1,'1Z1R.',NULL,'CKD G2A2 - chronic kidney disease with glomerular filtration rate category G2 and albuminuria category A2'),('chronic-kidney-disease',1,'1Z1R.00',NULL,'CKD G2A2 - chronic kidney disease with glomerular filtration rate category G2 and albuminuria category A2'),('chronic-kidney-disease',1,'1Z1Q.',NULL,'CKD G2A1 - chronic kidney disease with glomerular filtration rate category G2 and albuminuria category A1'),('chronic-kidney-disease',1,'1Z1Q.00',NULL,'CKD G2A1 - chronic kidney disease with glomerular filtration rate category G2 and albuminuria category A1'),('chronic-kidney-disease',1,'1Z1P.',NULL,'CKD G1A3 - chronic kidney disease with glomerular filtration rate category G1 and albuminuria category A3'),('chronic-kidney-disease',1,'1Z1P.00',NULL,'CKD G1A3 - chronic kidney disease with glomerular filtration rate category G1 and albuminuria category A3'),('chronic-kidney-disease',1,'1Z1N.',NULL,'CKD G1A2 - chronic kidney disease with glomerular filtration rate category G1 and albuminuria category A2'),('chronic-kidney-disease',1,'1Z1N.00',NULL,'CKD G1A2 - chronic kidney disease with glomerular filtration rate category G1 and albuminuria category A2'),('chronic-kidney-disease',1,'1Z1M.',NULL,'CKD G1A1 - chronic kidney disease with glomerular filtration rate category G1 and albuminuria category A1'),('chronic-kidney-disease',1,'1Z1M.00',NULL,'CKD G1A1 - chronic kidney disease with glomerular filtration rate category G1 and albuminuria category A1'),('chronic-kidney-disease',1,'1Z16.',NULL,'Chronic kidney disease stage 3B'),('chronic-kidney-disease',1,'1Z16.00',NULL,'Chronic kidney disease stage 3B'),('chronic-kidney-disease',1,'1Z15.',NULL,'Chronic kidney disease stage 3A'),('chronic-kidney-disease',1,'1Z15.00',NULL,'Chronic kidney disease stage 3A'),('chronic-kidney-disease',1,'1Z14.',NULL,'Chronic kidney disease stage 5'),('chronic-kidney-disease',1,'1Z14.00',NULL,'Chronic kidney disease stage 5'),('chronic-kidney-disease',1,'1Z13.',NULL,'Chronic kidney disease stage 4'),('chronic-kidney-disease',1,'1Z13.00',NULL,'Chronic kidney disease stage 4'),('chronic-kidney-disease',1,'1Z12.',NULL,'Chronic kidney disease stage 3'),('chronic-kidney-disease',1,'1Z12.00',NULL,'Chronic kidney disease stage 3'),('chronic-kidney-disease',1,'1Z11.',NULL,'Chronic kidney disease stage 2'),('chronic-kidney-disease',1,'1Z11.00',NULL,'Chronic kidney disease stage 2'),('chronic-kidney-disease',1,'1Z10.',NULL,'Chronic kidney disease stage 1'),('chronic-kidney-disease',1,'1Z10.00',NULL,'Chronic kidney disease stage 1'),('chronic-kidney-disease',1,'1Z1L.',NULL,'Chronic kidney disease stage 5 without proteinuria'),('chronic-kidney-disease',1,'1Z1L.00',NULL,'Chronic kidney disease stage 5 without proteinuria'),('chronic-kidney-disease',1,'1Z1K.',NULL,'Chronic kidney disease stage 5 with proteinuria'),('chronic-kidney-disease',1,'1Z1K.00',NULL,'Chronic kidney disease stage 5 with proteinuria'),('chronic-kidney-disease',1,'1Z1J.',NULL,'Chronic kidney disease stage 4 without proteinuria'),('chronic-kidney-disease',1,'1Z1J.00',NULL,'Chronic kidney disease stage 4 without proteinuria'),('chronic-kidney-disease',1,'1Z1H.',NULL,'Chronic kidney disease stage 4 with proteinuria'),('chronic-kidney-disease',1,'1Z1H.00',NULL,'Chronic kidney disease stage 4 with proteinuria'),('chronic-kidney-disease',1,'1Z1G.',NULL,'Chronic kidney disease stage 3B without proteinuria'),('chronic-kidney-disease',1,'1Z1G.00',NULL,'Chronic kidney disease stage 3B without proteinuria'),('chronic-kidney-disease',1,'1Z1F.',NULL,'Chronic kidney disease stage 3B with proteinuria'),('chronic-kidney-disease',1,'1Z1F.00',NULL,'Chronic kidney disease stage 3B with proteinuria'),('chronic-kidney-disease',1,'1Z1E.',NULL,'Chronic kidney disease stage 3A without proteinuria'),('chronic-kidney-disease',1,'1Z1E.00',NULL,'Chronic kidney disease stage 3A without proteinuria'),('chronic-kidney-disease',1,'1Z1D.',NULL,'Chronic kidney disease stage 3A with proteinuria'),('chronic-kidney-disease',1,'1Z1D.00',NULL,'Chronic kidney disease stage 3A with proteinuria'),('chronic-kidney-disease',1,'1Z1C.',NULL,'Chronic kidney disease stage 3 without proteinuria'),('chronic-kidney-disease',1,'1Z1C.00',NULL,'Chronic kidney disease stage 3 without proteinuria'),('chronic-kidney-disease',1,'1Z1B.',NULL,'Chronic kidney disease stage 3 with proteinuria'),('chronic-kidney-disease',1,'1Z1B.00',NULL,'Chronic kidney disease stage 3 with proteinuria'),('chronic-kidney-disease',1,'1Z1A.',NULL,'Chronic kidney disease stage 2 without proteinuria'),('chronic-kidney-disease',1,'1Z1A.00',NULL,'Chronic kidney disease stage 2 without proteinuria'),('chronic-kidney-disease',1,'1Z19.',NULL,'Chronic kidney disease stage 2 with proteinuria'),('chronic-kidney-disease',1,'1Z19.00',NULL,'Chronic kidney disease stage 2 with proteinuria'),('chronic-kidney-disease',1,'1Z18.',NULL,'Chronic kidney disease stage 1 without proteinuria'),('chronic-kidney-disease',1,'1Z18.00',NULL,'Chronic kidney disease stage 1 without proteinuria'),('chronic-kidney-disease',1,'1Z17.',NULL,'Chronic kidney disease stage 1 with proteinuria'),('chronic-kidney-disease',1,'1Z17.00',NULL,'Chronic kidney disease stage 1 with proteinuria'),('chronic-kidney-disease',1,'K05..',NULL,'Chronic renal failure'),('chronic-kidney-disease',1,'K05..00',NULL,'Chronic renal failure'),('chronic-kidney-disease',1,'K055.',NULL,'Chronic kidney disease stage 5'),('chronic-kidney-disease',1,'K055.00',NULL,'Chronic kidney disease stage 5'),('chronic-kidney-disease',1,'K054.',NULL,'Chronic kidney disease stage 4'),('chronic-kidney-disease',1,'K054.00',NULL,'Chronic kidney disease stage 4'),('chronic-kidney-disease',1,'K053.',NULL,'Chronic kidney disease stage 3'),('chronic-kidney-disease',1,'K053.00',NULL,'Chronic kidney disease stage 3'),('chronic-kidney-disease',1,'K052.',NULL,'Chronic kidney disease stage 2'),('chronic-kidney-disease',1,'K052.00',NULL,'Chronic kidney disease stage 2'),
('chronic-kidney-disease',1,'K051.',NULL,'Chronic kidney disease stage 1'),('chronic-kidney-disease',1,'K051.00',NULL,'Chronic kidney disease stage 1'),('chronic-kidney-disease',1,'1Z1..',NULL,'Chronic renal impairment'),('chronic-kidney-disease',1,'1Z1..00',NULL,'Chronic renal impairment'),('chronic-kidney-disease',1,'K050.',NULL,'End stage renal failure'),('chronic-kidney-disease',1,'K050.00',NULL,'End stage renal failure'),('chronic-kidney-disease',1,'K0D..',NULL,'End-stage renal disease'),('chronic-kidney-disease',1,'K0D..00',NULL,'End-stage renal disease');
INSERT INTO #codesreadv2
VALUES ('ckd-stage-1',1,'1Z1P.',NULL,'CKD G1A3 - chronic kidney disease with glomerular filtration rate category G1 and albuminuria category A3'),('ckd-stage-1',1,'1Z1P.00',NULL,'CKD G1A3 - chronic kidney disease with glomerular filtration rate category G1 and albuminuria category A3'),('ckd-stage-1',1,'1Z1N.',NULL,'CKD G1A2 - chronic kidney disease with glomerular filtration rate category G1 and albuminuria category A2'),('ckd-stage-1',1,'1Z1N.00',NULL,'CKD G1A2 - chronic kidney disease with glomerular filtration rate category G1 and albuminuria category A2'),('ckd-stage-1',1,'1Z1M.',NULL,'CKD G1A1 - chronic kidney disease with glomerular filtration rate category G1 and albuminuria category A1'),('ckd-stage-1',1,'1Z1M.00',NULL,'CKD G1A1 - chronic kidney disease with glomerular filtration rate category G1 and albuminuria category A1'),('ckd-stage-1',1,'1Z10.',NULL,'Chronic kidney disease stage 1'),('ckd-stage-1',1,'1Z10.00',NULL,'Chronic kidney disease stage 1'),('ckd-stage-1',1,'1Z18.',NULL,'Chronic kidney disease stage 1 without proteinuria'),('ckd-stage-1',1,'1Z18.00',NULL,'Chronic kidney disease stage 1 without proteinuria'),('ckd-stage-1',1,'1Z17.',NULL,'Chronic kidney disease stage 1 with proteinuria'),('ckd-stage-1',1,'1Z17.00',NULL,'Chronic kidney disease stage 1 with proteinuria'),('ckd-stage-1',1,'K051.',NULL,'Chronic kidney disease stage 1'),('ckd-stage-1',1,'K051.00',NULL,'Chronic kidney disease stage 1');
INSERT INTO #codesreadv2
VALUES ('ckd-stage-2',1,'1Z1S.',NULL,'CKD G2A3 - chronic kidney disease with glomerular filtration rate category G2 and albuminuria category A3'),('ckd-stage-2',1,'1Z1S.00',NULL,'CKD G2A3 - chronic kidney disease with glomerular filtration rate category G2 and albuminuria category A3'),('ckd-stage-2',1,'1Z1R.',NULL,'CKD G2A2 - chronic kidney disease with glomerular filtration rate category G2 and albuminuria category A2'),('ckd-stage-2',1,'1Z1R.00',NULL,'CKD G2A2 - chronic kidney disease with glomerular filtration rate category G2 and albuminuria category A2'),('ckd-stage-2',1,'1Z1Q.',NULL,'CKD G2A1 - chronic kidney disease with glomerular filtration rate category G2 and albuminuria category A1'),('ckd-stage-2',1,'1Z1Q.00',NULL,'CKD G2A1 - chronic kidney disease with glomerular filtration rate category G2 and albuminuria category A1'),('ckd-stage-2',1,'1Z11.',NULL,'Chronic kidney disease stage 2'),('ckd-stage-2',1,'1Z11.00',NULL,'Chronic kidney disease stage 2'),('ckd-stage-2',1,'1Z1A.',NULL,'Chronic kidney disease stage 2 without proteinuria'),('ckd-stage-2',1,'1Z1A.00',NULL,'Chronic kidney disease stage 2 without proteinuria'),('ckd-stage-2',1,'1Z19.',NULL,'Chronic kidney disease stage 2 with proteinuria'),('ckd-stage-2',1,'1Z19.00',NULL,'Chronic kidney disease stage 2 with proteinuria'),('ckd-stage-2',1,'K052.',NULL,'Chronic kidney disease stage 2'),('ckd-stage-2',1,'K052.00',NULL,'Chronic kidney disease stage 2');
INSERT INTO #codesreadv2
VALUES ('ckd-stage-3',1,'1Z1Z.',NULL,'CKD G3bA3 - chronic kidney disease with glomerular filtration rate category G3b and albuminuria category A3'),('ckd-stage-3',1,'1Z1Z.00',NULL,'CKD G3bA3 - chronic kidney disease with glomerular filtration rate category G3b and albuminuria category A3'),('ckd-stage-3',1,'1Z1Y.',NULL,'CKD G3bA2 - chronic kidney disease with glomerular filtration rate category G3b and albuminuria category A2'),('ckd-stage-3',1,'1Z1Y.00',NULL,'CKD G3bA2 - chronic kidney disease with glomerular filtration rate category G3b and albuminuria category A2'),('ckd-stage-3',1,'1Z1X.',NULL,'CKD G3bA1 - chronic kidney disease with glomerular filtration rate category G3b and albuminuria category A1'),('ckd-stage-3',1,'1Z1X.00',NULL,'CKD G3bA1 - chronic kidney disease with glomerular filtration rate category G3b and albuminuria category A1'),('ckd-stage-3',1,'1Z1W.',NULL,'CKD G3aA3 - chronic kidney disease with glomerular filtration rate category G3a and albuminuria category A3'),('ckd-stage-3',1,'1Z1W.00',NULL,'CKD G3aA3 - chronic kidney disease with glomerular filtration rate category G3a and albuminuria category A3'),('ckd-stage-3',1,'1Z1V.',NULL,'CKD G3aA2 - chronic kidney disease with glomerular filtration rate category G3a and albuminuria category A2'),('ckd-stage-3',1,'1Z1V.00',NULL,'CKD G3aA2 - chronic kidney disease with glomerular filtration rate category G3a and albuminuria category A2'),('ckd-stage-3',1,'1Z1T.',NULL,'CKD G3aA1 - chronic kidney disease with glomerular filtration rate category G3a and albuminuria category A1'),('ckd-stage-3',1,'1Z1T.00',NULL,'CKD G3aA1 - chronic kidney disease with glomerular filtration rate category G3a and albuminuria category A1'),('ckd-stage-3',1,'1Z16.',NULL,'Chronic kidney disease stage 3B'),('ckd-stage-3',1,'1Z16.00',NULL,'Chronic kidney disease stage 3B'),('ckd-stage-3',1,'1Z15.',NULL,'Chronic kidney disease stage 3A'),('ckd-stage-3',1,'1Z15.00',NULL,'Chronic kidney disease stage 3A'),('ckd-stage-3',1,'1Z12.',NULL,'Chronic kidney disease stage 3'),('ckd-stage-3',1,'1Z12.00',NULL,'Chronic kidney disease stage 3'),('ckd-stage-3',1,'1Z1G.',NULL,'Chronic kidney disease stage 3B without proteinuria'),('ckd-stage-3',1,'1Z1G.00',NULL,'Chronic kidney disease stage 3B without proteinuria'),('ckd-stage-3',1,'1Z1F.',NULL,'Chronic kidney disease stage 3B with proteinuria'),('ckd-stage-3',1,'1Z1F.00',NULL,'Chronic kidney disease stage 3B with proteinuria'),('ckd-stage-3',1,'1Z1E.',NULL,'Chronic kidney disease stage 3A without proteinuria'),('ckd-stage-3',1,'1Z1E.00',NULL,'Chronic kidney disease stage 3A without proteinuria'),('ckd-stage-3',1,'1Z1D.',NULL,'Chronic kidney disease stage 3A with proteinuria'),('ckd-stage-3',1,'1Z1D.00',NULL,'Chronic kidney disease stage 3A with proteinuria'),('ckd-stage-3',1,'1Z1C.',NULL,'Chronic kidney disease stage 3 without proteinuria'),('ckd-stage-3',1,'1Z1C.00',NULL,'Chronic kidney disease stage 3 without proteinuria'),('ckd-stage-3',1,'1Z1B.',NULL,'Chronic kidney disease stage 3 with proteinuria'),('ckd-stage-3',1,'1Z1B.00',NULL,'Chronic kidney disease stage 3 with proteinuria'),('ckd-stage-3',1,'K053.',NULL,'Chronic kidney disease stage 3'),('ckd-stage-3',1,'K053.00',NULL,'Chronic kidney disease stage 3');
INSERT INTO #codesreadv2
VALUES ('ckd-stage-4',1,'1Z1c.',NULL,'CKD G4A3 - chronic kidney disease with glomerular filtration rate category G4 and albuminuria category A3'),('ckd-stage-4',1,'1Z1c.00',NULL,'CKD G4A3 - chronic kidney disease with glomerular filtration rate category G4 and albuminuria category A3'),('ckd-stage-4',1,'1Z1b.',NULL,'CKD G4A2 - chronic kidney disease with glomerular filtration rate category G4 and albuminuria category A2'),('ckd-stage-4',1,'1Z1b.00',NULL,'CKD G4A2 - chronic kidney disease with glomerular filtration rate category G4 and albuminuria category A2'),('ckd-stage-4',1,'1Z1a.',NULL,'CKD G4A1 - chronic kidney disease with glomerular filtration rate category G4 and albuminuria category A1'),('ckd-stage-4',1,'1Z1a.00',NULL,'CKD G4A1 - chronic kidney disease with glomerular filtration rate category G4 and albuminuria category A1'),('ckd-stage-4',1,'1Z13.',NULL,'Chronic kidney disease stage 4'),('ckd-stage-4',1,'1Z13.00',NULL,'Chronic kidney disease stage 4'),('ckd-stage-4',1,'1Z1J.',NULL,'Chronic kidney disease stage 4 without proteinuria'),('ckd-stage-4',1,'1Z1J.00',NULL,'Chronic kidney disease stage 4 without proteinuria'),('ckd-stage-4',1,'1Z1H.',NULL,'Chronic kidney disease stage 4 with proteinuria'),('ckd-stage-4',1,'1Z1H.00',NULL,'Chronic kidney disease stage 4 with proteinuria'),('ckd-stage-4',1,'K054.',NULL,'Chronic kidney disease stage 4'),('ckd-stage-4',1,'K054.00',NULL,'Chronic kidney disease stage 4');
INSERT INTO #codesreadv2
VALUES ('ckd-stage-5',1,'1Z1f.',NULL,'CKD G5A3 - chronic kidney disease with glomerular filtration rate category G5 and albuminuria category A3'),('ckd-stage-5',1,'1Z1f.00',NULL,'CKD G5A3 - chronic kidney disease with glomerular filtration rate category G5 and albuminuria category A3'),('ckd-stage-5',1,'1Z1e.',NULL,'CKD G5A2 - chronic kidney disease with glomerular filtration rate category G5 and albuminuria category A2'),('ckd-stage-5',1,'1Z1e.00',NULL,'CKD G5A2 - chronic kidney disease with glomerular filtration rate category G5 and albuminuria category A2'),('ckd-stage-5',1,'1Z1d.',NULL,'CKD G5A1 - chronic kidney disease with glomerular filtration rate category G5 and albuminuria category A1'),('ckd-stage-5',1,'1Z1d.00',NULL,'CKD G5A1 - chronic kidney disease with glomerular filtration rate category G5 and albuminuria category A1'),('ckd-stage-5',1,'1Z14.',NULL,'Chronic kidney disease stage 5'),('ckd-stage-5',1,'1Z14.00',NULL,'Chronic kidney disease stage 5'),('ckd-stage-5',1,'1Z1L.',NULL,'Chronic kidney disease stage 5 without proteinuria'),('ckd-stage-5',1,'1Z1L.00',NULL,'Chronic kidney disease stage 5 without proteinuria'),('ckd-stage-5',1,'1Z1K.',NULL,'Chronic kidney disease stage 5 with proteinuria'),('ckd-stage-5',1,'1Z1K.00',NULL,'Chronic kidney disease stage 5 with proteinuria'),('ckd-stage-5',1,'K055.',NULL,'Chronic kidney disease stage 5'),('ckd-stage-5',1,'K055.00',NULL,'Chronic kidney disease stage 5'),('ckd-stage-5',1,'K0D..',NULL,'End-stage renal disease'),('ckd-stage-5',1,'K0D..00',NULL,'End-stage renal disease'),('ckd-stage-5',1,'K050.',NULL,'End stage renal failure'),('ckd-stage-5',1,'K050.00',NULL,'End stage renal failure');
INSERT INTO #codesreadv2
VALUES ('sle',1,'F3710',NULL,'Polyneuropathy in disseminated lupus erythematosus'),('sle',1,'F371000',NULL,'Polyneuropathy in disseminated lupus erythematosus'),('sle',1,'F3961',NULL,'Myopathy due to disseminated lupus erythematosus'),('sle',1,'F396100',NULL,'Myopathy due to disseminated lupus erythematosus'),('sle',1,'F4D33',NULL,'Eyelid discoid lupus erythematosus'),('sle',1,'F4D3300',NULL,'Eyelid discoid lupus erythematosus'),('sle',1,'H57y4',NULL,'Lung disease with systemic lupus erythematosus'),('sle',1,'H57y400',NULL,'Lung disease with systemic lupus erythematosus'),('sle',1,'K01x4',NULL,'Nephrotic syndrome in systemic lupus erythematosus'),('sle',1,'K01x400',NULL,'Nephrotic syndrome in systemic lupus erythematosus'),('sle',1,'M154.',NULL,'Lupus erythematosus'),('sle',1,'M154.00',NULL,'Lupus erythematosus'),('sle',1,'M1540',NULL,'Lupus erythematosus chronicus'),('sle',1,'M154000',NULL,'Lupus erythematosus chronicus'),('sle',1,'M1541',NULL,'Discoid lupus erythematosus'),('sle',1,'M154100',NULL,'Discoid lupus erythematosus'),('sle',1,'M1542',NULL,'Lupus erythematosus migrans'),('sle',1,'M154200',NULL,'Lupus erythematosus migrans'),('sle',1,'M1543',NULL,'Lupus erythematosus nodularis'),('sle',1,'M154300',NULL,'Lupus erythematosus nodularis'),('sle',1,'M1544',NULL,'Lupus erythematosus profundus'),('sle',1,'M154400',NULL,'Lupus erythematosus profundus'),('sle',1,'M1545',NULL,'Lupus erythematosus tumidus'),('sle',1,'M154500',NULL,'Lupus erythematosus tumidus'),('sle',1,'M1546',NULL,'Lupus erythematosus unguium mutilans'),('sle',1,'M154600',NULL,'Lupus erythematosus unguium mutilans'),('sle',1,'M154z',NULL,'Lupus erythematosus NOS'),('sle',1,'M154z00',NULL,'Lupus erythematosus NOS'),('sle',1,'Myu78',NULL,'[X]Other local lupus erythematosus'),('sle',1,'Myu7800',NULL,'[X]Other local lupus erythematosus'),('sle',1,'N000.',NULL,'Systemic lupus erythematosus'),('sle',1,'N000.00',NULL,'Systemic lupus erythematosus'),('sle',1,'N0002',NULL,'Drug-induced systemic lupus erythematosus'),('sle',1,'N000200',NULL,'Drug-induced systemic lupus erythematosus'),('sle',1,'N000z',NULL,'Systemic lupus erythematosus NOS'),('sle',1,'N000z00',NULL,'Systemic lupus erythematosus NOS'),('sle',1,'Nyu43',NULL,'[X]Other forms of systemic lupus erythematosus'),('sle',1,'Nyu4300',NULL,'[X]Other forms of systemic lupus erythematosus'),('sle',1,'K0B40',NULL,'Renal tubulo-interstitial disorder in systemic lupus erythematosus'),('sle',1,'K0B4000',NULL,'Renal tubulo-interstitial disorder in systemic lupus erythematosus'),('sle',1,'M1547',NULL,'Subacute cutaneous lupus erythematosus'),('sle',1,'M154700',NULL,'Subacute cutaneous lupus erythematosus'),('sle',1,'N0000',NULL,'Disseminated lupus erythematosus'),('sle',1,'N000000',NULL,'Disseminated lupus erythematosus'),('sle',1,'N0003',NULL,'Systemic lupus erythematosus with organ or system involvement'),('sle',1,'N000300',NULL,'Systemic lupus erythematosus with organ or system involvement'),('sle',1,'N0004',NULL,'Systemic lupus erythematosus with pericarditis'),('sle',1,'N000400',NULL,'Systemic lupus erythematosus with pericarditis'),('sle',1,'N0005',NULL,'Neonatal lupus erythematosus'),('sle',1,'N000500',NULL,'Neonatal lupus erythematosus'),('sle',1,'N0006',NULL,'Cerebral lupus'),('sle',1,'N000600',NULL,'Cerebral lupus');
INSERT INTO #codesreadv2
VALUES ('tuberculosis',1,'A10..',NULL,'Primary tuberculous infection'),('tuberculosis',1,'A10..00',NULL,'Primary tuberculous infection'),('tuberculosis',1,'A100.',NULL,'Primary tuberculous complex'),('tuberculosis',1,'A100.00',NULL,'Primary tuberculous complex'),('tuberculosis',1,'A101.',NULL,'Tuberculous pleurisy in primary progressive tuberculosis'),('tuberculosis',1,'A101.00',NULL,'Tuberculous pleurisy in primary progressive tuberculosis'),('tuberculosis',1,'A10y.',NULL,'Other primary progressive tuberculosis'),('tuberculosis',1,'A10y.00',NULL,'Other primary progressive tuberculosis'),('tuberculosis',1,'A10z.',NULL,'Primary tuberculous infection NOS'),('tuberculosis',1,'A10z.00',NULL,'Primary tuberculous infection NOS'),('tuberculosis',1,'A11..',NULL,'Lung tuberculosis'),('tuberculosis',1,'A11..00',NULL,'Lung tuberculosis'),('tuberculosis',1,'A110.',NULL,'Infiltrative lung tuberculosis'),('tuberculosis',1,'A110.00',NULL,'Infiltrative lung tuberculosis'),('tuberculosis',1,'A111.',NULL,'Nodular lung tuberculosis'),('tuberculosis',1,'A111.00',NULL,'Nodular lung tuberculosis'),('tuberculosis',1,'A113.',NULL,'Tuberculosis of bronchus'),('tuberculosis',1,'A113.00',NULL,'Tuberculosis of bronchus'),('tuberculosis',1,'A115.',NULL,'Tuberculous bronchiectasis'),('tuberculosis',1,'A115.00',NULL,'Tuberculous bronchiectasis'),('tuberculosis',1,'A116.',NULL,'Tuberculous pneumonia'),('tuberculosis',1,'A116.00',NULL,'Tuberculous pneumonia'),('tuberculosis',1,'A117.',NULL,'Tuberculous pneumothorax'),('tuberculosis',1,'A117.00',NULL,'Tuberculous pneumothorax'),('tuberculosis',1,'A11y.',NULL,'Other specified pulmonary tuberculosis'),('tuberculosis',1,'A11y.00',NULL,'Other specified pulmonary tuberculosis'),('tuberculosis',1,'A11z.',NULL,'Pulmonary tuberculosis NOS'),('tuberculosis',1,'A11z.00',NULL,'Pulmonary tuberculosis NOS'),('tuberculosis',1,'A12..',NULL,'Other respiratory tuberculosis'),('tuberculosis',1,'A12..00',NULL,'Other respiratory tuberculosis'),('tuberculosis',1,'A120.',NULL,'Tuberculous pleurisy'),('tuberculosis',1,'A120.00',NULL,'Tuberculous pleurisy'),('tuberculosis',1,'A1201',NULL,'Tuberculous empyema'),('tuberculosis',1,'A120100',NULL,'Tuberculous empyema'),('tuberculosis',1,'A1202',NULL,'Tuberculous hydrothorax'),('tuberculosis',1,'A120200',NULL,'Tuberculous hydrothorax'),('tuberculosis',1,'A120z',NULL,'Tuberculous pleurisy NOS'),('tuberculosis',1,'A120z00',NULL,'Tuberculous pleurisy NOS'),('tuberculosis',1,'A121.',NULL,'Tuberculosis of intrathoracic lymph nodes'),('tuberculosis',1,'A121.00',NULL,'Tuberculosis of intrathoracic lymph nodes'),('tuberculosis',1,'A1210',NULL,'Tuberculosis of hilar lymph nodes'),('tuberculosis',1,'A121000',NULL,'Tuberculosis of hilar lymph nodes'),('tuberculosis',1,'A1211',NULL,'Tuberculosis of mediastinal lymph nodes'),('tuberculosis',1,'A121100',NULL,'Tuberculosis of mediastinal lymph nodes'),('tuberculosis',1,'A1212',NULL,'Tuberculosis of tracheobronchial lymph nodes'),('tuberculosis',1,'A121200',NULL,'Tuberculosis of tracheobronchial lymph nodes'),('tuberculosis',1,'A121z',NULL,'Tuberculosis of intrathoracic lymph nodes NOS'),('tuberculosis',1,'A121z00',NULL,'Tuberculosis of intrathoracic lymph nodes NOS'),('tuberculosis',1,'A122.',NULL,'Isolated tracheal or bronchial tuberculosis'),('tuberculosis',1,'A122.00',NULL,'Isolated tracheal or bronchial tuberculosis'),('tuberculosis',1,'A1220',NULL,'Isolated tracheal tuberculosis'),('tuberculosis',1,'A122000',NULL,'Isolated tracheal tuberculosis'),('tuberculosis',1,'A1221',NULL,'Isolated bronchial tuberculosis'),('tuberculosis',1,'A122100',NULL,'Isolated bronchial tuberculosis'),('tuberculosis',1,'A122z',NULL,'Isolated tracheal or bronchial tuberculosis NOS'),('tuberculosis',1,'A122z00',NULL,'Isolated tracheal or bronchial tuberculosis NOS'),('tuberculosis',1,'A123.',NULL,'Tuberculous laryngitis'),('tuberculosis',1,'A123.00',NULL,'Tuberculous laryngitis'),('tuberculosis',1,'A124.',NULL,'Respiratory tuberculosis, bacteriologically and histologically confirmed'),('tuberculosis',1,'A124.00',NULL,'Respiratory tuberculosis, bacteriologically and histologically confirmed'),('tuberculosis',1,'A1240',NULL,'Tuberculosis of lung, confirmed by sputum microscopy with or without culture'),('tuberculosis',1,'A124000',NULL,'Tuberculosis of lung, confirmed by sputum microscopy with or without culture'),('tuberculosis',1,'A1241',NULL,'Tuberculosis of lung, confirmed by culture only'),('tuberculosis',1,'A124100',NULL,'Tuberculosis of lung, confirmed by culture only'),('tuberculosis',1,'A1242',NULL,'Tuberculosis of lung, confirmed histologically'),('tuberculosis',1,'A124200',NULL,'Tuberculosis of lung, confirmed histologically'),('tuberculosis',1,'A1243',NULL,'Tuberculosis of lung, confirmed by unspecified means'),('tuberculosis',1,'A124300',NULL,'Tuberculosis of lung, confirmed by unspecified means'),('tuberculosis',1,'A1244',NULL,'Tuberculosis of intrathoracic lymph nodes, confirmed bacteriologically and histologically'),('tuberculosis',1,'A124400',NULL,'Tuberculosis of intrathoracic lymph nodes, confirmed bacteriologically and histologically'),('tuberculosis',1,'A1245',NULL,'Tuberculosis of larynx, trachea and bronchus, confirmed bacteriologically and histologically'),('tuberculosis',1,'A124500',NULL,'Tuberculosis of larynx, trachea and bronchus, confirmed bacteriologically and histologically'),('tuberculosis',1,'A1246',NULL,'Tuberculous pleurisy, confirmed bacteriologically and histologically'),('tuberculosis',1,'A124600',NULL,'Tuberculous pleurisy, confirmed bacteriologically and histologically'),('tuberculosis',1,'A1247',NULL,'Primary respiratory tuberculosis, confirmed bacteriologically and histologically'),('tuberculosis',1,'A124700',NULL,'Primary respiratory tuberculosis, confirmed bacteriologically and histologically'),('tuberculosis',1,'A125.',NULL,'Respiratory tuberculosis, not confirmed bacteriologically or histologically'),('tuberculosis',1,'A125.00',NULL,'Respiratory tuberculosis, not confirmed bacteriologically or histologically'),('tuberculosis',1,'A1250',NULL,'Tuberculosis of lung, bacteriologically and histologically negative'),('tuberculosis',1,'A125000',NULL,'Tuberculosis of lung, bacteriologically and histologically negative'),('tuberculosis',1,'A1251',NULL,'Tuberculosis of lung, bacteriological and histological examination not done'),('tuberculosis',1,'A125100',NULL,'Tuberculosis of lung, bacteriological and histological examination not done'),('tuberculosis',1,'A1252',NULL,'Primary respiratory tuberculosis without mention of bacteriological or histological confirmation'),('tuberculosis',1,'A125200',NULL,'Primary respiratory tuberculosis without mention of bacteriological or histological confirmation'),('tuberculosis',1,'A12y.',NULL,'Other specified respiratory tuberculosis'),('tuberculosis',1,'A12y.00',NULL,'Other specified respiratory tuberculosis'),('tuberculosis',1,'A12y0',NULL,'Tuberculosis of mediastinum'),('tuberculosis',1,'A12y000',NULL,'Tuberculosis of mediastinum'),('tuberculosis',1,'A12y1',NULL,'Tuberculosis of nasopharynx'),('tuberculosis',1,'A12y100',NULL,'Tuberculosis of nasopharynx'),('tuberculosis',1,'A12y2',NULL,'Tuberculosis of nasal septum'),('tuberculosis',1,'A12y200',NULL,'Tuberculosis of nasal septum'),('tuberculosis',1,'A12y3',NULL,'Tuberculosis of nasal sinus'),('tuberculosis',1,'A12y300',NULL,'Tuberculosis of nasal sinus'),('tuberculosis',1,'A12yz',NULL,'Other specified respiratory tuberculosis NOS'),('tuberculosis',1,'A12yz00',NULL,'Other specified respiratory tuberculosis NOS'),('tuberculosis',1,'A14..',NULL,'Tuberculosis of intestines, peritoneum and mesenteric glands'),('tuberculosis',1,'A14..00',NULL,'Tuberculosis of intestines, peritoneum and mesenteric glands'),('tuberculosis',1,'A14y.',NULL,'Other gastrointestinal tract tuberculosis'),('tuberculosis',1,'A14y.00',NULL,'Other gastrointestinal tract tuberculosis'),('tuberculosis',1,'A14y5',NULL,'Tuberculosis of retroperitoneal lymph nodes'),('tuberculosis',1,'A14y500',NULL,'Tuberculosis of retroperitoneal lymph nodes'),('tuberculosis',1,'A14yz',NULL,'Other gastrointestinal tract tuberculosis NOS'),('tuberculosis',1,'A14yz00',NULL,'Other gastrointestinal tract tuberculosis NOS'),('tuberculosis',1,'A15..',NULL,'Tuberculous synovitis'),('tuberculosis',1,'A15..00',NULL,'Tuberculous synovitis'),('tuberculosis',1,'A15z.',NULL,'Tuberculosis of bones or joints NOS'),('tuberculosis',1,'A15z.00',NULL,'Tuberculosis of bones or joints NOS'),('tuberculosis',1,'A16..',NULL,'Tuberculosis of genitourinary system'),('tuberculosis',1,'A16..00',NULL,'Tuberculosis of genitourinary system'),('tuberculosis',1,'A163.',NULL,'Tuberculosis of other urinary organs'),('tuberculosis',1,'A163.00',NULL,'Tuberculosis of other urinary organs'),('tuberculosis',1,'A165.',NULL,'Tuberculosis of other male genital organs'),('tuberculosis',1,'A165.00',NULL,'Tuberculosis of other male genital organs'),('tuberculosis',1,'A165z',NULL,'Tuberculosis of other male genital organs NOS'),('tuberculosis',1,'A165z00',NULL,'Tuberculosis of other male genital organs NOS'),('tuberculosis',1,'A167.',NULL,'Tuberculosis of other female genital organs'),('tuberculosis',1,'A167.00',NULL,'Tuberculosis of other female genital organs'),('tuberculosis',1,'A167z',NULL,'Tuberculosis of other female genital organs NOS'),('tuberculosis',1,'A167z00',NULL,'Tuberculosis of other female genital organs NOS'),('tuberculosis',1,'A16z.',NULL,'Genitourinary tuberculosis NOS'),('tuberculosis',1,'A16z.00',NULL,'Genitourinary tuberculosis NOS'),('tuberculosis',1,'A17..',NULL,'Tuberculosis of other organs'),('tuberculosis',1,'A17..00',NULL,'Tuberculosis of other organs'),('tuberculosis',1,'A1702',NULL,'Tuberculosis - scrofuloderma'),('tuberculosis',1,'A170200',NULL,'Tuberculosis - scrofuloderma'),('tuberculosis',1,'A1703',NULL,'Tuberculosis - lupus NOS'),('tuberculosis',1,'A170300',NULL,'Tuberculosis - lupus NOS'),('tuberculosis',1,'A1706',NULL,'Tuberculosis lichenoides'),
('tuberculosis',1,'A170600',NULL,'Tuberculosis lichenoides'),('tuberculosis',1,'A1707',NULL,'Tuberculosis papulonecrotica'),('tuberculosis',1,'A170700',NULL,'Tuberculosis papulonecrotica'),('tuberculosis',1,'A1708',NULL,'Tuberculosis verrucosa cutis'),('tuberculosis',1,'A170800',NULL,'Tuberculosis verrucosa cutis'),('tuberculosis',1,'A170z',NULL,'Tuberculosis of skin and subcutaneous tissue NOS'),('tuberculosis',1,'A170z00',NULL,'Tuberculosis of skin and subcutaneous tissue NOS'),('tuberculosis',1,'A171.',NULL,'Tuberculosis with erythema nodosum hypersensitivity reaction'),('tuberculosis',1,'A171.00',NULL,'Tuberculosis with erythema nodosum hypersensitivity reaction'),('tuberculosis',1,'A171z',NULL,'Erythema nodosum with tuberculosis NOS'),('tuberculosis',1,'A171z00',NULL,'Erythema nodosum with tuberculosis NOS'),('tuberculosis',1,'A1720',NULL,'Scrofula - tuberculous cervical lymph nodes'),('tuberculosis',1,'A172000',NULL,'Scrofula - tuberculous cervical lymph nodes'),('tuberculosis',1,'A1721',NULL,'Scrofulous tuberculous abscess'),('tuberculosis',1,'A172100',NULL,'Scrofulous tuberculous abscess'),('tuberculosis',1,'A172z',NULL,'Tuberculosis of peripheral lymph nodes NOS'),('tuberculosis',1,'A172z00',NULL,'Tuberculosis of peripheral lymph nodes NOS'),('tuberculosis',1,'A173.',NULL,'Tuberculosis of eye'),('tuberculosis',1,'A173.00',NULL,'Tuberculosis of eye'),('tuberculosis',1,'A173z',NULL,'Tuberculosis of eye NOS'),('tuberculosis',1,'A173z00',NULL,'Tuberculosis of eye NOS'),('tuberculosis',1,'A174.',NULL,'Tuberculosis of ear'),('tuberculosis',1,'A174.00',NULL,'Tuberculosis of ear'),('tuberculosis',1,'A17y.',NULL,'Tuberculosis of other specified organs'),('tuberculosis',1,'A17y.00',NULL,'Tuberculosis of other specified organs'),('tuberculosis',1,'A17yz',NULL,'Tuberculosis of other specified organs NOS'),('tuberculosis',1,'A17yz00',NULL,'Tuberculosis of other specified organs NOS'),('tuberculosis',1,'A17z.',NULL,'Tuberculosis of other organs NOS'),('tuberculosis',1,'A17z.00',NULL,'Tuberculosis of other organs NOS'),('tuberculosis',1,'A18..',NULL,'Miliary tuberculosis'),('tuberculosis',1,'A18..00',NULL,'Miliary tuberculosis'),('tuberculosis',1,'A180.',NULL,'Acute miliary tuberculosis'),('tuberculosis',1,'A180.00',NULL,'Acute miliary tuberculosis'),('tuberculosis',1,'A1800',NULL,'Acute miliary tuberculosis of a single specified site'),('tuberculosis',1,'A180000',NULL,'Acute miliary tuberculosis of a single specified site'),('tuberculosis',1,'A1801',NULL,'Acute miliary tuberculosis of multiple sites'),('tuberculosis',1,'A180100',NULL,'Acute miliary tuberculosis of multiple sites'),('tuberculosis',1,'A18y.',NULL,'Other specified miliary tuberculosis'),('tuberculosis',1,'A18y.00',NULL,'Other specified miliary tuberculosis'),('tuberculosis',1,'A18z.',NULL,'Miliary tuberculosis NOS'),('tuberculosis',1,'A18z.00',NULL,'Miliary tuberculosis NOS'),('tuberculosis',1,'A1y..',NULL,'Other specified tuberculosis'),('tuberculosis',1,'A1y..00',NULL,'Other specified tuberculosis'),('tuberculosis',1,'A1z..',NULL,'Tuberculosis NOS'),('tuberculosis',1,'A1z..00',NULL,'Tuberculosis NOS'),('tuberculosis',1,'Ayu10',NULL,'[X]Other respiratory tuberculosis, confirmed bacteriologically and histologically'),('tuberculosis',1,'Ayu1000',NULL,'[X]Other respiratory tuberculosis, confirmed bacteriologically and histologically'),('tuberculosis',1,'Ayu11',NULL,'[X]Respiratory tuberculosis unspecified, confirmed bacteriologically and histologically'),('tuberculosis',1,'Ayu1100',NULL,'[X]Respiratory tuberculosis unspecified, confirmed bacteriologically and histologically'),('tuberculosis',1,'Ayu12',NULL,'[X]Other respiratory tuberculosis, without mention of bacteriological or histological confirmation'),('tuberculosis',1,'Ayu1200',NULL,'[X]Other respiratory tuberculosis, without mention of bacteriological or histological confirmation'),('tuberculosis',1,'Ayu13',NULL,'[X]Respiratory tuberculosis unspecified, without mention of bacteriological or histological confirmation'),('tuberculosis',1,'Ayu1300',NULL,'[X]Respiratory tuberculosis unspecified, without mention of bacteriological or histological confirmation'),('tuberculosis',1,'Ayu14',NULL,'[X]Other tuberculosis of nervous system'),('tuberculosis',1,'Ayu1400',NULL,'[X]Other tuberculosis of nervous system'),('tuberculosis',1,'Ayu15',NULL,'[X]Tuberculosis of nervous system, unspecified'),('tuberculosis',1,'Ayu1500',NULL,'[X]Tuberculosis of nervous system, unspecified'),('tuberculosis',1,'Ayu16',NULL,'[X]Tuberculosis of other specified organs'),('tuberculosis',1,'Ayu1600',NULL,'[X]Tuberculosis of other specified organs'),('tuberculosis',1,'Ayu17',NULL,'[X]Acute miliary tuberculosis, unspecified'),('tuberculosis',1,'Ayu1700',NULL,'[X]Acute miliary tuberculosis, unspecified'),('tuberculosis',1,'Ayu18',NULL,'[X]Other miliary tuberculosis'),('tuberculosis',1,'Ayu1800',NULL,'[X]Other miliary tuberculosis'),('tuberculosis',1,'Ayu19',NULL,'[X]Miliary tuberculosis, unspecified'),('tuberculosis',1,'Ayu1900',NULL,'[X]Miliary tuberculosis, unspecified'),('tuberculosis',1,'G5320',NULL,'Concatos disease'),('tuberculosis',1,'G532000',NULL,'Concatos disease'),('tuberculosis',1,'H510.',NULL,'Pleurisy without effusion or active tuberculosis'),('tuberculosis',1,'H510.00',NULL,'Pleurisy without effusion or active tuberculosis'),('tuberculosis',1,'H510z',NULL,'Pleurisy without effusion or active tuberculosis NOS'),('tuberculosis',1,'H510z00',NULL,'Pleurisy without effusion or active tuberculosis NOS'),('tuberculosis',1,'A1...',NULL,'Tuberculosis'),('tuberculosis',1,'A1...00',NULL,'Tuberculosis'),('tuberculosis',1,'A1200',NULL,'Tuberculosis of pleura'),('tuberculosis',1,'A120000',NULL,'Tuberculosis of pleura'),('tuberculosis',1,'A125X',NULL,'Respiratory tuberculosis unspecified, without mention of bacteriological or histological confirmation'),('tuberculosis',1,'A125X00',NULL,'Respiratory tuberculosis unspecified, without mention of bacteriological or histological confirmation'),('tuberculosis',1,'A13..',NULL,'Tuberculosis of meninges and central nervous system'),('tuberculosis',1,'A13..00',NULL,'Tuberculosis of meninges and central nervous system'),('tuberculosis',1,'A13y.',NULL,'Other specified tuberculosis of central nervous system'),('tuberculosis',1,'A13y.00',NULL,'Other specified tuberculosis of central nervous system'),('tuberculosis',1,'A13z.',NULL,'Tuberculosis of central nervous system NOS'),('tuberculosis',1,'A13z.00',NULL,'Tuberculosis of central nervous system NOS'),('tuberculosis',1,'A14z.',NULL,'Tuberculosis of gastrointestinal tract NOS'),('tuberculosis',1,'A14z.00',NULL,'Tuberculosis of gastrointestinal tract NOS'),('tuberculosis',1,'A15y.',NULL,'Tuberculosis of other specified joint'),('tuberculosis',1,'A15y.00',NULL,'Tuberculosis of other specified joint'),('tuberculosis',1,'A166.',NULL,'Tuberculous oophoritis or salpingitis'),('tuberculosis',1,'A166.00',NULL,'Tuberculous oophoritis or salpingitis'),('tuberculosis',1,'A168.',NULL,'Tuberculosis of urinary tract'),('tuberculosis',1,'A168.00',NULL,'Tuberculosis of urinary tract'),('tuberculosis',1,'A1700',NULL,'Tuberculosis - lupus exedens'),('tuberculosis',1,'A170000',NULL,'Tuberculosis - lupus exedens'),('tuberculosis',1,'A1701',NULL,'Tuberculosis - lupus vulgaris'),('tuberculosis',1,'A170100',NULL,'Tuberculosis - lupus vulgaris'),('tuberculosis',1,'A1704',NULL,'Tuberculosis colliquativa'),('tuberculosis',1,'A170400',NULL,'Tuberculosis colliquativa'),('tuberculosis',1,'A1711',NULL,'Tuberculous erythema nodosum'),('tuberculosis',1,'A171100',NULL,'Tuberculous erythema nodosum'),('tuberculosis',1,'A172.',NULL,'Tuberculosis of peripheral lymph nodes'),('tuberculosis',1,'A172.00',NULL,'Tuberculosis of peripheral lymph nodes'),('tuberculosis',1,'Ayu1.',NULL,'[X]Tuberculosis'),('tuberculosis',1,'Ayu1.00',NULL,'[X]Tuberculosis'),('tuberculosis',1,'Jyu93',NULL,'[X]Tuberculous disorders of intestine and mesentery'),('tuberculosis',1,'Jyu9300',NULL,'[X]Tuberculous disorders of intestine and mesentery'),('tuberculosis',1,'N018.',NULL,'Tuberculous arthritis'),('tuberculosis',1,'N018.00',NULL,'Tuberculous arthritis');
INSERT INTO #codesreadv2
VALUES ('alcohol-heavy-drinker',1,'136b.',NULL,'Feels should cut down drinking'),('alcohol-heavy-drinker',1,'136b.00',NULL,'Feels should cut down drinking'),('alcohol-heavy-drinker',1,'136c.',NULL,'Higher risk drinking'),('alcohol-heavy-drinker',1,'136c.00',NULL,'Higher risk drinking'),('alcohol-heavy-drinker',1,'136K.',NULL,'Alcohol intake above recommended sensible limits'),('alcohol-heavy-drinker',1,'136K.00',NULL,'Alcohol intake above recommended sensible limits'),('alcohol-heavy-drinker',1,'136P.',NULL,'Heavy drinker'),('alcohol-heavy-drinker',1,'136P.00',NULL,'Heavy drinker'),('alcohol-heavy-drinker',1,'136Q.',NULL,'Very heavy drinker'),('alcohol-heavy-drinker',1,'136Q.00',NULL,'Very heavy drinker'),('alcohol-heavy-drinker',1,'136R.',NULL,'Binge drinker'),('alcohol-heavy-drinker',1,'136R.00',NULL,'Binge drinker'),('alcohol-heavy-drinker',1,'136S.',NULL,'Hazardous alcohol use'),('alcohol-heavy-drinker',1,'136S.00',NULL,'Hazardous alcohol use'),('alcohol-heavy-drinker',1,'136T.',NULL,'Harmful alcohol use'),('alcohol-heavy-drinker',1,'136T.00',NULL,'Harmful alcohol use'),('alcohol-heavy-drinker',1,'136W.',NULL,'Alcohol misuse'),('alcohol-heavy-drinker',1,'136W.00',NULL,'Alcohol misuse'),('alcohol-heavy-drinker',1,'136Y.',NULL,'Drinks in morning to get rid of hangover'),('alcohol-heavy-drinker',1,'136Y.00',NULL,'Drinks in morning to get rid of hangover'),('alcohol-heavy-drinker',1,'E23..','12','Alcohol problem drinking'),('alcohol-heavy-drinker',1,'E23..','12','Alcohol problem drinking');
INSERT INTO #codesreadv2
VALUES ('alcohol-light-drinker',1,'1362.',NULL,'Trivial drinker - <1u/day'),('alcohol-light-drinker',1,'1362.00',NULL,'Trivial drinker - <1u/day'),('alcohol-light-drinker',1,'136N.',NULL,'Light drinker'),('alcohol-light-drinker',1,'136N.00',NULL,'Light drinker'),('alcohol-light-drinker',1,'136d.',NULL,'Lower risk drinking'),('alcohol-light-drinker',1,'136d.00',NULL,'Lower risk drinking');
INSERT INTO #codesreadv2
VALUES ('alcohol-moderate-drinker',1,'136O.',NULL,'Moderate drinker'),('alcohol-moderate-drinker',1,'136O.00',NULL,'Moderate drinker'),('alcohol-moderate-drinker',1,'136F.',NULL,'Spirit drinker'),('alcohol-moderate-drinker',1,'136F.00',NULL,'Spirit drinker'),('alcohol-moderate-drinker',1,'136G.',NULL,'Beer drinker'),('alcohol-moderate-drinker',1,'136G.00',NULL,'Beer drinker'),('alcohol-moderate-drinker',1,'136H.',NULL,'Drinks beer and spirits'),('alcohol-moderate-drinker',1,'136H.00',NULL,'Drinks beer and spirits'),('alcohol-moderate-drinker',1,'136I.',NULL,'Drinks wine'),('alcohol-moderate-drinker',1,'136I.00',NULL,'Drinks wine'),('alcohol-moderate-drinker',1,'136J.',NULL,'Social drinker'),('alcohol-moderate-drinker',1,'136J.00',NULL,'Social drinker'),('alcohol-moderate-drinker',1,'136L.',NULL,'Alcohol intake within recommended sensible limits'),('alcohol-moderate-drinker',1,'136L.00',NULL,'Alcohol intake within recommended sensible limits'),('alcohol-moderate-drinker',1,'136Z.',NULL,'Alcohol consumption NOS'),('alcohol-moderate-drinker',1,'136Z.00',NULL,'Alcohol consumption NOS'),('alcohol-moderate-drinker',1,'136a.',NULL,'Increasing risk drinking'),('alcohol-moderate-drinker',1,'136a.00',NULL,'Increasing risk drinking');
INSERT INTO #codesreadv2
VALUES ('alcohol-non-drinker',1,'1361.',NULL,'Teetotaller'),('alcohol-non-drinker',1,'1361.00',NULL,'Teetotaller'),('alcohol-non-drinker',1,'136M.',NULL,'Current non drinker'),('alcohol-non-drinker',1,'136M.00',NULL,'Current non drinker');
INSERT INTO #codesreadv2
VALUES ('alcohol-weekly-intake',1,'136V.',NULL,'Alcohol units per week'),('alcohol-weekly-intake',1,'136V.00',NULL,'Alcohol units per week'),('alcohol-weekly-intake',1,'136..',NULL,'Alcohol consumption'),('alcohol-weekly-intake',1,'136..00',NULL,'Alcohol consumption');
INSERT INTO #codesreadv2
VALUES ('bmi',2,'22K..',NULL,'Body Mass Index'),('bmi',2,'22K..00',NULL,'Body Mass Index'),('bmi',2,'22KB.',NULL,'Baseline body mass index'),('bmi',2,'22KB.00',NULL,'Baseline body mass index');
INSERT INTO #codesreadv2
VALUES ('smoking-status-current',1,'137P.',NULL,'Cigarette smoker'),('smoking-status-current',1,'137P.00',NULL,'Cigarette smoker'),('smoking-status-current',1,'1374.',NULL,'Moderate smoker - 10-19 cigs/d'),('smoking-status-current',1,'1374.00',NULL,'Moderate smoker - 10-19 cigs/d'),('smoking-status-current',1,'137G.',NULL,'Trying to give up smoking'),('smoking-status-current',1,'137G.00',NULL,'Trying to give up smoking'),('smoking-status-current',1,'137R.',NULL,'Current smoker'),('smoking-status-current',1,'137R.00',NULL,'Current smoker'),('smoking-status-current',1,'1376.',NULL,'Very heavy smoker - 40+cigs/d'),('smoking-status-current',1,'1376.00',NULL,'Very heavy smoker - 40+cigs/d'),('smoking-status-current',1,'1375.',NULL,'Heavy smoker - 20-39 cigs/day'),('smoking-status-current',1,'1375.00',NULL,'Heavy smoker - 20-39 cigs/day'),('smoking-status-current',1,'1373.',NULL,'Light smoker - 1-9 cigs/day'),('smoking-status-current',1,'1373.00',NULL,'Light smoker - 1-9 cigs/day'),('smoking-status-current',1,'137M.',NULL,'Rolls own cigarettes'),('smoking-status-current',1,'137M.00',NULL,'Rolls own cigarettes'),('smoking-status-current',1,'137o.',NULL,'Waterpipe tobacco consumption'),('smoking-status-current',1,'137o.00',NULL,'Waterpipe tobacco consumption'),('smoking-status-current',1,'137m.',NULL,'Failed attempt to stop smoking'),('smoking-status-current',1,'137m.00',NULL,'Failed attempt to stop smoking'),('smoking-status-current',1,'137h.',NULL,'Minutes from waking to first tobacco consumption'),('smoking-status-current',1,'137h.00',NULL,'Minutes from waking to first tobacco consumption'),('smoking-status-current',1,'137g.',NULL,'Cigarette pack-years'),('smoking-status-current',1,'137g.00',NULL,'Cigarette pack-years'),('smoking-status-current',1,'137f.',NULL,'Reason for restarting smoking'),('smoking-status-current',1,'137f.00',NULL,'Reason for restarting smoking'),('smoking-status-current',1,'137e.',NULL,'Smoking restarted'),('smoking-status-current',1,'137e.00',NULL,'Smoking restarted'),('smoking-status-current',1,'137d.',NULL,'Not interested in stopping smoking'),('smoking-status-current',1,'137d.00',NULL,'Not interested in stopping smoking'),('smoking-status-current',1,'137c.',NULL,'Thinking about stopping smoking'),('smoking-status-current',1,'137c.00',NULL,'Thinking about stopping smoking'),('smoking-status-current',1,'137b.',NULL,'Ready to stop smoking'),('smoking-status-current',1,'137b.00',NULL,'Ready to stop smoking'),('smoking-status-current',1,'137C.',NULL,'Keeps trying to stop smoking'),('smoking-status-current',1,'137C.00',NULL,'Keeps trying to stop smoking'),('smoking-status-current',1,'137J.',NULL,'Cigar smoker'),('smoking-status-current',1,'137J.00',NULL,'Cigar smoker'),('smoking-status-current',1,'137H.',NULL,'Pipe smoker'),('smoking-status-current',1,'137H.00',NULL,'Pipe smoker'),('smoking-status-current',1,'137a.',NULL,'Pipe tobacco consumption'),('smoking-status-current',1,'137a.00',NULL,'Pipe tobacco consumption'),('smoking-status-current',1,'137Z.',NULL,'Tobacco consumption NOS'),('smoking-status-current',1,'137Z.00',NULL,'Tobacco consumption NOS'),('smoking-status-current',1,'137Y.',NULL,'Cigar consumption'),('smoking-status-current',1,'137Y.00',NULL,'Cigar consumption'),('smoking-status-current',1,'137X.',NULL,'Cigarette consumption'),('smoking-status-current',1,'137X.00',NULL,'Cigarette consumption'),('smoking-status-current',1,'137V.',NULL,'Smoking reduced'),('smoking-status-current',1,'137V.00',NULL,'Smoking reduced'),('smoking-status-current',1,'137Q.',NULL,'Smoking started'),('smoking-status-current',1,'137Q.00',NULL,'Smoking started'),('smoking-status-current',1,'137D.',NULL,'Admitted tobacco cons untrue ?'),('smoking-status-current',1,'137D.00',NULL,'Admitted tobacco cons untrue ?'),('smoking-status-current',1,'137n.',NULL,'Total time smoked'),('smoking-status-current',1,'137n.00',NULL,'Total time smoked');
INSERT INTO #codesreadv2
VALUES ('smoking-status-currently-not',1,'137L.',NULL,'Current non-smoker'),('smoking-status-currently-not',1,'137L.00',NULL,'Current non-smoker');
INSERT INTO #codesreadv2
VALUES ('smoking-status-ex',1,'137l.',NULL,'Ex roll-up cigarette smoker'),('smoking-status-ex',1,'137l.00',NULL,'Ex roll-up cigarette smoker'),('smoking-status-ex',1,'137j.',NULL,'Ex-cigarette smoker'),('smoking-status-ex',1,'137j.00',NULL,'Ex-cigarette smoker'),('smoking-status-ex',1,'137S.',NULL,'Ex smoker'),('smoking-status-ex',1,'137S.00',NULL,'Ex smoker'),('smoking-status-ex',1,'137O.',NULL,'Ex cigar smoker'),('smoking-status-ex',1,'137O.00',NULL,'Ex cigar smoker'),('smoking-status-ex',1,'137N.',NULL,'Ex pipe smoker'),('smoking-status-ex',1,'137N.00',NULL,'Ex pipe smoker'),('smoking-status-ex',1,'137F.',NULL,'Ex-smoker - amount unknown'),('smoking-status-ex',1,'137F.00',NULL,'Ex-smoker - amount unknown'),('smoking-status-ex',1,'137B.',NULL,'Ex-very heavy smoker (40+/day)'),('smoking-status-ex',1,'137B.00',NULL,'Ex-very heavy smoker (40+/day)'),('smoking-status-ex',1,'137A.',NULL,'Ex-heavy smoker (20-39/day)'),('smoking-status-ex',1,'137A.00',NULL,'Ex-heavy smoker (20-39/day)'),('smoking-status-ex',1,'1379.',NULL,'Ex-moderate smoker (10-19/day)'),('smoking-status-ex',1,'1379.00',NULL,'Ex-moderate smoker (10-19/day)'),('smoking-status-ex',1,'1378.',NULL,'Ex-light smoker (1-9/day)'),('smoking-status-ex',1,'1378.00',NULL,'Ex-light smoker (1-9/day)'),('smoking-status-ex',1,'137K.',NULL,'Stopped smoking'),('smoking-status-ex',1,'137K.00',NULL,'Stopped smoking'),('smoking-status-ex',1,'137K0',NULL,'Recently stopped smoking'),('smoking-status-ex',1,'137K000',NULL,'Recently stopped smoking'),('smoking-status-ex',1,'137T.',NULL,'Date ceased smoking'),('smoking-status-ex',1,'137T.00',NULL,'Date ceased smoking'),('smoking-status-ex',1,'13p4.',NULL,'Smoking free weeks'),('smoking-status-ex',1,'13p4.00',NULL,'Smoking free weeks');
INSERT INTO #codesreadv2
VALUES ('smoking-status-ex-trivial',1,'1377.',NULL,'Ex-trivial smoker (<1/day)'),('smoking-status-ex-trivial',1,'1377.00',NULL,'Ex-trivial smoker (<1/day)');
INSERT INTO #codesreadv2
VALUES ('smoking-status-never',1,'1371.',NULL,'Never smoked tobacco'),('smoking-status-never',1,'1371.00',NULL,'Never smoked tobacco');
INSERT INTO #codesreadv2
VALUES ('smoking-status-passive',1,'137I.',NULL,'Passive smoker'),('smoking-status-passive',1,'137I.00',NULL,'Passive smoker'),('smoking-status-passive',1,'137I0',NULL,'Exposed to tobacco smoke at home'),('smoking-status-passive',1,'137I000',NULL,'Exposed to tobacco smoke at home'),('smoking-status-passive',1,'13WF4',NULL,'Passive smoking risk'),('smoking-status-passive',1,'13WF400',NULL,'Passive smoking risk');
INSERT INTO #codesreadv2
VALUES ('smoking-status-trivial',1,'1372.',NULL,'Trivial smoker - < 1 cig/day'),('smoking-status-trivial',1,'1372.00',NULL,'Trivial smoker - < 1 cig/day');
INSERT INTO #codesreadv2
VALUES ('creatinine',1,'44J3.',NULL,'Serum creatinine'),('creatinine',1,'44J3.00',NULL,'Serum creatinine'),('creatinine',1,'44JC.',NULL,'Corrected plasma creatinine level'),('creatinine',1,'44JC.00',NULL,'Corrected plasma creatinine level'),('creatinine',1,'44JD.',NULL,'Corrected serum creatinine level'),('creatinine',1,'44JD.00',NULL,'Corrected serum creatinine level'),('creatinine',1,'44JF.',NULL,'Plasma creatinine level'),('creatinine',1,'44JF.00',NULL,'Plasma creatinine level'),('creatinine',1,'44J3z',NULL,'Serum creatinine NOS'),('creatinine',1,'44J3z00',NULL,'Serum creatinine NOS');
INSERT INTO #codesreadv2
VALUES ('egfr',1,'451E.',NULL,'Glomerular filtration rate calculated by abbreviated Modification of Diet in Renal Disease Study Group calculation'),('egfr',1,'451E.00',NULL,'Glomerular filtration rate calculated by abbreviated Modification of Diet in Renal Disease Study Group calculation'),('egfr',1,'451G.',NULL,'Glomerular filtration rate calculated by abbreviated Modification of Diet in Renal Disease Study Group calculation adjusted for African American origin'),('egfr',1,'451G.00',NULL,'Glomerular filtration rate calculated by abbreviated Modification of Diet in Renal Disease Study Group calculation adjusted for African American origin'),('egfr',1,'451K.',NULL,'Estimated glomerular filtration rate using Chronic Kidney Disease Epidemiology Collaboration formula per 1.73 square metres'),('egfr',1,'451K.00',NULL,'Estimated glomerular filtration rate using Chronic Kidney Disease Epidemiology Collaboration formula per 1.73 square metres'),('egfr',1,'451M.',NULL,'Estimated glomerular filtration rate using cystatin C Chronic Kidney Disease Epidemiology Collaboration equation per 1.73 square metres'),('egfr',1,'451M.00',NULL,'Estimated glomerular filtration rate using cystatin C Chronic Kidney Disease Epidemiology Collaboration equation per 1.73 square metres'),('egfr',1,'451N.',NULL,'Estimated glomerular filtration rate using creatinine Chronic Kidney Disease Epidemiology Collaboration equation per 1.73 square metres'),('egfr',1,'451N.00',NULL,'Estimated glomerular filtration rate using creatinine Chronic Kidney Disease Epidemiology Collaboration equation per 1.73 square metres'),('egfr',1,'451F.',NULL,'Glomerular filtration rate'),('egfr',1,'451F.00',NULL,'Glomerular filtration rate');
INSERT INTO #codesreadv2
VALUES ('hdl-cholesterol',1,'44PC.',NULL,'Serum random HDL cholesterol level'),('hdl-cholesterol',1,'44PC.00',NULL,'Serum random HDL cholesterol level'),('hdl-cholesterol',1,'44P5.',NULL,'Serum HDL cholesterol level'),('hdl-cholesterol',1,'44P5.00',NULL,'Serum HDL cholesterol level'),('hdl-cholesterol',1,'44dA.',NULL,'Plasma HDL cholesterol level'),('hdl-cholesterol',1,'44dA.00',NULL,'Plasma HDL cholesterol level'),('hdl-cholesterol',1,'44d2.',NULL,'Plasma random HDL cholesterol level'),('hdl-cholesterol',1,'44d2.00',NULL,'Plasma random HDL cholesterol level'),('hdl-cholesterol',1,'44d3.',NULL,'Plasma fasting HDL cholesterol level'),('hdl-cholesterol',1,'44d3.00',NULL,'Plasma fasting HDL cholesterol level'),('hdl-cholesterol',1,'44PB.',NULL,'Serum fasting HDL cholesterol level'),('hdl-cholesterol',1,'44PB.00',NULL,'Serum fasting HDL cholesterol level');
INSERT INTO #codesreadv2
VALUES ('ldl-cholesterol',1,'44PI.',NULL,'Calculated LDL cholesterol level'),('ldl-cholesterol',1,'44PI.00',NULL,'Calculated LDL cholesterol level'),('ldl-cholesterol',1,'44P6.',NULL,'Serum LDL cholesterol level'),('ldl-cholesterol',1,'44P6.00',NULL,'Serum LDL cholesterol level'),('ldl-cholesterol',1,'44dB.',NULL,'Plasma LDL cholesterol level'),('ldl-cholesterol',1,'44dB.00',NULL,'Plasma LDL cholesterol level'),('ldl-cholesterol',1,'44d4.',NULL,'Plasma random LDL cholesterol level'),('ldl-cholesterol',1,'44d4.00',NULL,'Plasma random LDL cholesterol level'),('ldl-cholesterol',1,'44d5.',NULL,'Plasma fasting LDL cholesterol level'),('ldl-cholesterol',1,'44d5.00',NULL,'Plasma fasting LDL cholesterol level'),('ldl-cholesterol',1,'44PD.',NULL,'Serum fasting LDL cholesterol level'),('ldl-cholesterol',1,'44PD.00',NULL,'Serum fasting LDL cholesterol level'),('ldl-cholesterol',1,'44PE.',NULL,'Serum random LDL cholesterol level'),('ldl-cholesterol',1,'44PE.00',NULL,'Serum random LDL cholesterol level');
INSERT INTO #codesreadv2
VALUES ('triglycerides',1,'44Q..',NULL,'Serum triglycerides'),('triglycerides',1,'44Q..00',NULL,'Serum triglycerides'),('triglycerides',1,'44Q4.',NULL,'Serum fasting triglyceride level'),('triglycerides',1,'44Q4.00',NULL,'Serum fasting triglyceride level'),('triglycerides',1,'44Q5.',NULL,'Serum random triglyceride level'),('triglycerides',1,'44Q5.00',NULL,'Serum random triglyceride level'),('triglycerides',1,'44QZ.',NULL,'Serum triglycerides NOS'),('triglycerides',1,'44QZ.00',NULL,'Serum triglycerides NOS'),('triglycerides',1,'44e..',NULL,'Plasma triglyceride level'),('triglycerides',1,'44e..00',NULL,'Plasma triglyceride level'),('triglycerides',1,'44e0.',NULL,'Plasma random triglyceride level'),('triglycerides',1,'44e0.00',NULL,'Plasma random triglyceride level'),('triglycerides',1,'44e1.',NULL,'Plasma fasting triglyceride level'),('triglycerides',1,'44e1.00',NULL,'Plasma fasting triglyceride level'),('triglycerides',1,'4QA1.',NULL,'Triglyceride level'),('triglycerides',1,'4QA1.00',NULL,'Triglyceride level')

INSERT INTO #AllCodes
SELECT [concept], [version], [code], [description] from #codesreadv2;

IF OBJECT_ID('tempdb..#codesctv3') IS NOT NULL DROP TABLE #codesctv3;
CREATE TABLE #codesctv3 (
  [concept] [varchar](255) NOT NULL,
  [version] INT NOT NULL,
	[code] [varchar](20) COLLATE Latin1_General_CS_AS NOT NULL,
	[term] [varchar](20) COLLATE Latin1_General_CS_AS NULL,
	[description] [varchar](255) NULL
) ON [PRIMARY];

INSERT INTO #codesctv3
VALUES ('chronic-kidney-disease',1,'X30In',NULL,'Chronic kidney disease'),('chronic-kidney-disease',1,'XaLHG',NULL,'Chronic kidney disease stage 1'),('chronic-kidney-disease',1,'XaLHH',NULL,'Chronic kidney disease stage 2'),('chronic-kidney-disease',1,'XaLHI',NULL,'Chronic kidney disease stage 3'),('chronic-kidney-disease',1,'XaLHJ',NULL,'Chronic kidney disease stage 4'),('chronic-kidney-disease',1,'XaLHK',NULL,'Chronic kidney disease stage 5'),('chronic-kidney-disease',1,'Xac9y',NULL,'CKD G1A1 - chronic kidney disease with glomerular filtration rate category G1 and albuminuria category A1'),('chronic-kidney-disease',1,'Xac9z',NULL,'CKD G1A2 - chronic kidney disease with glomerular filtration rate category G1 and albuminuria category A2'),('chronic-kidney-disease',1,'XacA2',NULL,'CKD G1A3 - chronic kidney disease with glomerular filtration rate category G1 and albuminuria category A3'),('chronic-kidney-disease',1,'XacA4',NULL,'CKD G2A1 - chronic kidney disease with glomerular filtration rate category G2 and albuminuria category A1'),('chronic-kidney-disease',1,'XacA6',NULL,'CKD G2A2 - chronic kidney disease with glomerular filtration rate category G2 and albuminuria category A2'),('chronic-kidney-disease',1,'XacA9',NULL,'CKD G2A3 - chronic kidney disease with glomerular filtration rate category G2 and albuminuria category A3'),('chronic-kidney-disease',1,'XacAM',NULL,'CKD G3aA1 - chronic kidney disease with glomerular filtration rate category G3a and albuminuria category A1'),('chronic-kidney-disease',1,'XacAN',NULL,'CKD G3aA2 - chronic kidney disease with glomerular filtration rate category G3a and albuminuria category A2'),('chronic-kidney-disease',1,'XacAO',NULL,'CKD G3aA3 - chronic kidney disease with glomerular filtration rate category G3a and albuminuria category A3'),('chronic-kidney-disease',1,'XacAV',NULL,'CKD G3bA1 - chronic kidney disease with glomerular filtration rate category G3b and albuminuria category A1'),('chronic-kidney-disease',1,'XacAW',NULL,'CKD G3bA2 - chronic kidney disease with glomerular filtration rate category G3b and albuminuria category A2'),('chronic-kidney-disease',1,'XacAX',NULL,'CKD G3bA3 - chronic kidney disease with glomerular filtration rate category G3b and albuminuria category A3'),('chronic-kidney-disease',1,'XacAb',NULL,'CKD G4A1 - chronic kidney disease with glomerular filtration rate category G4 and albuminuria category A1'),('chronic-kidney-disease',1,'XacAd',NULL,'CKD G4A2 - chronic kidney disease with glomerular filtration rate category G4 and albuminuria category A2'),('chronic-kidney-disease',1,'XacAe',NULL,'CKD G4A3 - chronic kidney disease with glomerular filtration rate category G4 and albuminuria category A3'),('chronic-kidney-disease',1,'XacAf',NULL,'CKD G5A1 - chronic kidney disease with glomerular filtration rate category G5 and albuminuria category A1'),('chronic-kidney-disease',1,'XacAh',NULL,'CKD G5A2 - chronic kidney disease with glomerular filtration rate category G5 and albuminuria category A2'),('chronic-kidney-disease',1,'XacAi',NULL,'CKD G5A3 - chronic kidney disease with glomerular filtration rate category G5 and albuminuria category A3'),('chronic-kidney-disease',1,'XaO3p',NULL,'Chronic kidney disease stage 1 with proteinuria'),('chronic-kidney-disease',1,'XaO3s',NULL,'Chronic kidney disease stage 2 without proteinuria'),('chronic-kidney-disease',1,'XaNbn',NULL,'Chronic kidney disease stage 3A'),('chronic-kidney-disease',1,'XaNbo',NULL,'Chronic kidney disease stage 3B'),('chronic-kidney-disease',1,'XaO3t',NULL,'Chronic kidney disease stage 3 with proteinuria'),('chronic-kidney-disease',1,'XaO3u',NULL,'Chronic kidney disease stage 3 without proteinuria'),('chronic-kidney-disease',1,'XaO40',NULL,'Chronic kidney disease stage 4 without proteinuria'),('chronic-kidney-disease',1,'XaO3w',NULL,'Chronic kidney disease stage 3A without proteinuria'),('chronic-kidney-disease',1,'XaO3x',NULL,'Chronic kidney disease stage 3B with proteinuria'),('chronic-kidney-disease',1,'XaO3y',NULL,'Chronic kidney disease stage 3B without proteinuria'),('chronic-kidney-disease',1,'XaMFs',NULL,'Chronic kidney disease monitoring administration'),('chronic-kidney-disease',1,'XaMFt',NULL,'Chronic kidney disease monitoring first letter'),('chronic-kidney-disease',1,'XaMFu',NULL,'Chronic kidney disease monitoring second letter'),('chronic-kidney-disease',1,'XaMFv',NULL,'Chronic kidney disease monitoring third letter'),('chronic-kidney-disease',1,'XaMFw',NULL,'Chronic kidney disease monitoring verbal invite'),('chronic-kidney-disease',1,'XaMFx',NULL,'Chronic kidney disease monitoring telephone invite'),('chronic-kidney-disease',1,'XaMLh',NULL,'Predicted stage chronic kidney disease'),('chronic-kidney-disease',1,'X30J0',NULL,'ESCRF - End stage chronic renal failure'),('chronic-kidney-disease',1,'XaO3q',NULL,'Chronic kidney disease stage 1 without proteinuria'),('chronic-kidney-disease',1,'XaO3r',NULL,'Chronic kidney disease stage 2 with proteinuria'),('chronic-kidney-disease',1,'XaO3v',NULL,'Chronic kidney disease stage 3A with proteinuria'),('chronic-kidney-disease',1,'XaO3z',NULL,'Chronic kidney disease stage 4 with proteinuria'),('chronic-kidney-disease',1,'XaO41',NULL,'Chronic kidney disease stage 5 with proteinuria'),('chronic-kidney-disease',1,'XaO42',NULL,'Chronic kidney disease stage 5 without proteinuria');
INSERT INTO #codesctv3
VALUES ('ckd-stage-1',1,'XaLHG',NULL,'Chronic kidney disease stage 1'),('ckd-stage-1',1,'Xac9y',NULL,'CKD G1A1 - chronic kidney disease with glomerular filtration rate category G1 and albuminuria category A1'),('ckd-stage-1',1,'Xac9z',NULL,'CKD G1A2 - chronic kidney disease with glomerular filtration rate category G1 and albuminuria category A2'),('ckd-stage-1',1,'XacA2',NULL,'CKD G1A3 - chronic kidney disease with glomerular filtration rate category G1 and albuminuria category A3'),('ckd-stage-1',1,'XaO3p',NULL,'Chronic kidney disease stage 1 with proteinuria'),('ckd-stage-1',1,'XaO3q',NULL,'Chronic kidney disease stage 1 without proteinuria');
INSERT INTO #codesctv3
VALUES ('ckd-stage-2',1,'XaLHH',NULL,'Chronic kidney disease stage 2'),('ckd-stage-2',1,'XacA4',NULL,'CKD G2A1 - chronic kidney disease with glomerular filtration rate category G2 and albuminuria category A1'),('ckd-stage-2',1,'XacA6',NULL,'CKD G2A2 - chronic kidney disease with glomerular filtration rate category G2 and albuminuria category A2'),('ckd-stage-2',1,'XacA9',NULL,'CKD G2A3 - chronic kidney disease with glomerular filtration rate category G2 and albuminuria category A3'),('ckd-stage-2',1,'XaO3s',NULL,'Chronic kidney disease stage 2 without proteinuria'),('ckd-stage-2',1,'XaO3r',NULL,'Chronic kidney disease stage 2 with proteinuria');
INSERT INTO #codesctv3
VALUES ('ckd-stage-3',1,'XaLHI',NULL,'Chronic kidney disease stage 3'),('ckd-stage-3',1,'XacAM',NULL,'CKD G3aA1 - chronic kidney disease with glomerular filtration rate category G3a and albuminuria category A1'),('ckd-stage-3',1,'XacAN',NULL,'CKD G3aA2 - chronic kidney disease with glomerular filtration rate category G3a and albuminuria category A2'),('ckd-stage-3',1,'XacAO',NULL,'CKD G3aA3 - chronic kidney disease with glomerular filtration rate category G3a and albuminuria category A3'),('ckd-stage-3',1,'XacAV',NULL,'CKD G3bA1 - chronic kidney disease with glomerular filtration rate category G3b and albuminuria category A1'),('ckd-stage-3',1,'XacAW',NULL,'CKD G3bA2 - chronic kidney disease with glomerular filtration rate category G3b and albuminuria category A2'),('ckd-stage-3',1,'XacAX',NULL,'CKD G3bA3 - chronic kidney disease with glomerular filtration rate category G3b and albuminuria category A3'),('ckd-stage-3',1,'XaNbn',NULL,'Chronic kidney disease stage 3A'),('ckd-stage-3',1,'XaNbo',NULL,'Chronic kidney disease stage 3B'),('ckd-stage-3',1,'XaO3t',NULL,'Chronic kidney disease stage 3 with proteinuria'),('ckd-stage-3',1,'XaO3u',NULL,'Chronic kidney disease stage 3 without proteinuria'),('ckd-stage-3',1,'XaO3w',NULL,'Chronic kidney disease stage 3A without proteinuria'),('ckd-stage-3',1,'XaO3x',NULL,'Chronic kidney disease stage 3B with proteinuria'),('ckd-stage-3',1,'XaO3y',NULL,'Chronic kidney disease stage 3B without proteinuria'),('ckd-stage-3',1,'XaO3v',NULL,'Chronic kidney disease stage 3A with proteinuria');
INSERT INTO #codesctv3
VALUES ('ckd-stage-4',1,'XaLHJ',NULL,'Chronic kidney disease stage 4'),('ckd-stage-4',1,'XacAb',NULL,'CKD G4A1 - chronic kidney disease with glomerular filtration rate category G4 and albuminuria category A1'),('ckd-stage-4',1,'XacAd',NULL,'CKD G4A2 - chronic kidney disease with glomerular filtration rate category G4 and albuminuria category A2'),('ckd-stage-4',1,'XacAe',NULL,'CKD G4A3 - chronic kidney disease with glomerular filtration rate category G4 and albuminuria category A3'),('ckd-stage-4',1,'XaO40',NULL,'Chronic kidney disease stage 4 without proteinuria'),('ckd-stage-4',1,'XaO3z',NULL,'Chronic kidney disease stage 4 with proteinuria');
INSERT INTO #codesctv3
VALUES ('ckd-stage-5',1,'XaLHK',NULL,'Chronic kidney disease stage 5'),('ckd-stage-5',1,'XacAf',NULL,'CKD G5A1 - chronic kidney disease with glomerular filtration rate category G5 and albuminuria category A1'),('ckd-stage-5',1,'XacAh',NULL,'CKD G5A2 - chronic kidney disease with glomerular filtration rate category G5 and albuminuria category A2'),('ckd-stage-5',1,'XacAi',NULL,'CKD G5A3 - chronic kidney disease with glomerular filtration rate category G5 and albuminuria category A3'),('ckd-stage-5',1,'XaO41',NULL,'Chronic kidney disease stage 5 with proteinuria'),('ckd-stage-5',1,'XaO42',NULL,'Chronic kidney disease stage 5 without proteinuria'),('ckd-stage-5',1,'X30J0',NULL,'ESCRF - End stage chronic renal failure'),('ckd-stage-5',1,'X30J1',NULL,'End stage renal failure untreated by renal replacement therapy'),('ckd-stage-5',1,'X30J2',NULL,'End stage renal failure on dialysis'),('ckd-stage-5',1,'X30J3',NULL,'End stage renal failure with renal transplant');
INSERT INTO #codesctv3
VALUES ('sle',1,'F3710',NULL,'Polyneuropathy in disseminated lupus erythematosus'),('sle',1,'F3961',NULL,'Myopathy due to disseminated lupus erythematosus'),('sle',1,'F4D33',NULL,'Discoid lupus eyelid'),('sle',1,'H57y4',NULL,'Lung disease with systemic lupus erythematosus'),('sle',1,'K01x4',NULL,'(Nephr synd in system lupus erythemat) or (lupus nephritis]'),('sle',1,'M154.',NULL,'Lupus erythematosus'),('sle',1,'M1540',NULL,'Lupus erythematosus chronicus'),('sle',1,'M1541',NULL,'Discoid lupus erythematosus'),('sle',1,'M1542',NULL,'Lupus erythematosus migrans'),('sle',1,'M1543',NULL,'Lupus erythematosus nodularis'),('sle',1,'M1544',NULL,'Lupus erythematosus profundus'),('sle',1,'M1545',NULL,'Lupus erythematosus tumidus'),('sle',1,'M1546',NULL,'Lupus erythematosus unguium mutilans'),('sle',1,'M154z',NULL,'Lupus erythematosus NOS'),('sle',1,'Myu78',NULL,'[X]Other local lupus erythematosus'),('sle',1,'N000.',NULL,'Systemic lupus erythematosus'),('sle',1,'N0002',NULL,'Drug-induced systemic lupus erythematosus'),('sle',1,'N000z',NULL,'Systemic lupus erythematosus NOS'),('sle',1,'Nyu43',NULL,'[X]Other forms of systemic lupus erythematosus'),('sle',1,'X00Dx',NULL,'Cerebral lupus'),('sle',1,'X30Kn',NULL,'Lupus nephritis - WHO Class I'),('sle',1,'X30Ko',NULL,'Lupus nephritis - WHO Class II'),('sle',1,'X30Kp',NULL,'Lupus nephritis - WHO Class III'),('sle',1,'X30Kq',NULL,'Lupus nephritis - WHO Class IV'),('sle',1,'X30Kr',NULL,'Lupus nephritis - WHO Class V'),('sle',1,'X30Ks',NULL,'Lupus nephritis - WHO Class VI'),('sle',1,'X50Ew',NULL,'Lupus erythematosus and erythema multiforme-like syndrome'),('sle',1,'X50Ex',NULL,'Chronic discoid lupus erythematosus'),('sle',1,'X50Ez',NULL,'Chilblain lupus erythematosus'),('sle',1,'X704W',NULL,'Limited lupus erythematosus'),('sle',1,'X704X',NULL,'Systemic lupus erythematosus with organ/system involvement'),('sle',1,'X704a',NULL,'Lupus panniculitis'),('sle',1,'X704b',NULL,'Bullous systemic lupus erythematosus'),('sle',1,'X704c',NULL,'Systemic lupus erythematosus with multisystem involvement'),('sle',1,'X704d',NULL,'Cutaneous lupus erythematosus'),('sle',1,'X704g',NULL,'Neonatal lupus erythematosus'),('sle',1,'X704h',NULL,'Subacute cutaneous lupus erythematosus'),('sle',1,'XE0da',NULL,'Lupus nephritis'),('sle',1,'XM197',NULL,'[EDTA] Lupus erythematosus associated with renal failure'),('sle',1,'XaBE1',NULL,'Renal tubulo-interstitial disord in systemic lupus erythemat'),('sle',1,'XaC1J',NULL,'Systemic lupus erythematosus with pericarditis'),('sle',1,'X0046',NULL,'Chorea in systemic lupus erythematosus'),('sle',1,'X1038',NULL,'Lupus pneumonia'),('sle',1,'X705w',NULL,'Lupus vasculitis');
INSERT INTO #codesctv3
VALUES ('tuberculosis',1,'A1...',NULL,'Tuberculosis'),('tuberculosis',1,'A10..',NULL,'Primary tuberculous infection'),('tuberculosis',1,'A100.',NULL,'Primary tuberculous complex'),('tuberculosis',1,'A101.',NULL,'Tuberculous pleurisy in primary progressive tuberculosis'),('tuberculosis',1,'A10y.',NULL,'Other primary progressive tuberculosis'),('tuberculosis',1,'A10z.',NULL,'Primary tuberculous infection NOS'),('tuberculosis',1,'A11..',NULL,'Pulmonary tuberculosis'),('tuberculosis',1,'A110.',NULL,'Infiltrative lung tuberculosis'),('tuberculosis',1,'A111.',NULL,'Nodular lung tuberculosis'),('tuberculosis',1,'A113.',NULL,'Tuberculosis of bronchus'),('tuberculosis',1,'A115.',NULL,'Tuberculous bronchiectasis'),('tuberculosis',1,'A116.',NULL,'Tuberculous pneumonia'),('tuberculosis',1,'A117.',NULL,'Tuberculous pneumothorax'),('tuberculosis',1,'A11y.',NULL,'Other specified pulmonary tuberculosis'),('tuberculosis',1,'A11z.',NULL,'Pulmonary tuberculosis NOS'),('tuberculosis',1,'A12..',NULL,'Other respiratory tuberculosis'),('tuberculosis',1,'A120.',NULL,'Tuberculosis of pleura'),('tuberculosis',1,'A1201',NULL,'Tuberculous empyema (& pleural)'),('tuberculosis',1,'A1202',NULL,'Tuberculous hydrothorax'),('tuberculosis',1,'A120z',NULL,'Tuberculous pleurisy NOS'),('tuberculosis',1,'A121.',NULL,'Tuberculosis of intrathoracic lymph nodes'),('tuberculosis',1,'A1210',NULL,'Tuberculosis of hilar lymph nodes'),('tuberculosis',1,'A1211',NULL,'Tuberculosis of mediastinal lymph nodes'),('tuberculosis',1,'A1212',NULL,'Tuberculosis of tracheobronchial lymph nodes'),('tuberculosis',1,'A121z',NULL,'Tuberculosis of intrathoracic lymph nodes NOS'),('tuberculosis',1,'A122.',NULL,'Isolated tracheal or bronchial tuberculosis'),('tuberculosis',1,'A1220',NULL,'Isolated tracheal tuberculosis'),('tuberculosis',1,'A1221',NULL,'Isolated bronchial tuberculosis'),('tuberculosis',1,'A122z',NULL,'Isolated tracheal or bronchial tuberculosis NOS'),('tuberculosis',1,'A123.',NULL,'Laryngeal tuberculosis'),('tuberculosis',1,'A124.',NULL,'Respiratory tuberculosis, bacteriologically and histologically confirmed'),('tuberculosis',1,'A1240',NULL,'Tuberculosis of lung, confirmed by sputum microscopy with or without culture'),('tuberculosis',1,'A1241',NULL,'Tuberculosis of lung, confirmed by culture only'),('tuberculosis',1,'A1242',NULL,'Tuberculosis of lung, confirmed histologically'),('tuberculosis',1,'A1243',NULL,'Tuberculosis of lung, confirmed by unspecified means'),('tuberculosis',1,'A1244',NULL,'Tuberculosis of intrathoracic lymph nodes, confirmed bacteriologically and histologically'),('tuberculosis',1,'A1245',NULL,'Tuberculosis of larynx, trachea and bronchus, confirmed bacteriologically and histologically'),('tuberculosis',1,'A1246',NULL,'Tuberculous pleurisy, confirmed bacteriologically and histologically'),('tuberculosis',1,'A1247',NULL,'Primary respiratory tuberculosis, confirmed bacteriologically and histologically'),('tuberculosis',1,'A125.',NULL,'Respiratory tuberculosis, not confirmed bacteriologically or histologically'),('tuberculosis',1,'A1250',NULL,'Tuberculosis of lung, bacteriologically and histologically negative'),('tuberculosis',1,'A1251',NULL,'Tuberculosis of lung, bacteriological and histological examination not done'),('tuberculosis',1,'A1252',NULL,'Primary respiratory tuberculosis without mention of bacteriological or histological confirmation'),('tuberculosis',1,'A12y.',NULL,'Other specified respiratory tuberculosis'),('tuberculosis',1,'A12y0',NULL,'Tuberculosis of mediastinum'),('tuberculosis',1,'A12y1',NULL,'Tuberculosis of nasopharynx'),('tuberculosis',1,'A12y2',NULL,'Tuberculosis of nasal septum'),('tuberculosis',1,'A12y3',NULL,'Tuberculosis of nasal sinus'),('tuberculosis',1,'A12yz',NULL,'Other specified respiratory tuberculosis NOS'),('tuberculosis',1,'A13..',NULL,'Tuberculosis of meninges and central nervous system'),('tuberculosis',1,'A13y.',NULL,'Other specified tuberculosis of central nervous system'),('tuberculosis',1,'A13z.',NULL,'Tuberculosis of central nervous system NOS'),('tuberculosis',1,'A14..',NULL,'Tuberculosis of intestines, peritoneum and mesenteric glands'),('tuberculosis',1,'A14y.',NULL,'Other gastrointestinal tract tuberculosis'),('tuberculosis',1,'A14y5',NULL,'Tuberculosis of retroperitoneal lymph nodes'),('tuberculosis',1,'A14yz',NULL,'Other gastrointestinal tract tuberculosis NOS'),('tuberculosis',1,'A14z.',NULL,'Tuberculosis of gastrointestinal tract NOS'),('tuberculosis',1,'A15y.',NULL,'Tuberculosis of other specified joint'),('tuberculosis',1,'A15z.',NULL,'Tuberculosis of bones or joints NOS'),('tuberculosis',1,'A16..',NULL,'Urogenital tuberculosis'),('tuberculosis',1,'A163.',NULL,'Tuberculosis of other urinary organs'),('tuberculosis',1,'A165.',NULL,'Tuberculosis of other male genital organs'),('tuberculosis',1,'A165z',NULL,'Tuberculosis of other male genital organs NOS'),('tuberculosis',1,'A166.',NULL,'Tuberculous oophoritis or salpingitis'),('tuberculosis',1,'A167.',NULL,'Tuberculosis of other female genital organs'),('tuberculosis',1,'A167z',NULL,'Tuberculosis of other female genital organs NOS'),('tuberculosis',1,'A16z.',NULL,'Genitourinary tuberculosis NOS'),('tuberculosis',1,'A17..',NULL,'Tuberculosis of other organs'),('tuberculosis',1,'A1700',NULL,'Lupus vulgaris'),('tuberculosis',1,'A1703',NULL,'Tuberculosis - lupus NOS'),('tuberculosis',1,'A1706',NULL,'Lichen scrofulosorum'),('tuberculosis',1,'A1707',NULL,'Tuberculosis papulonecrotica'),('tuberculosis',1,'A1708',NULL,'Tuberculosis verrucosa cutis'),('tuberculosis',1,'A170z',NULL,'Tuberculosis of skin and subcutaneous tissue NOS'),('tuberculosis',1,'A171.',NULL,'Tuberculous erythema nodosum'),('tuberculosis',1,'A171z',NULL,'Erythema nodosum with tuberculosis NOS'),('tuberculosis',1,'A1720',NULL,'Tuberculous cervical lymphadenitis'),('tuberculosis',1,'A1721',NULL,'Scrofulous tuberculous abscess'),('tuberculosis',1,'A172z',NULL,'Tuberculosis of peripheral lymph nodes NOS'),('tuberculosis',1,'A173.',NULL,'Ocular tuberculosis'),('tuberculosis',1,'A173z',NULL,'Tuberculosis of eye NOS'),('tuberculosis',1,'A174.',NULL,'Tuberculosis of ear'),('tuberculosis',1,'A17y.',NULL,'Tuberculosis of other specified organs'),('tuberculosis',1,'A17yz',NULL,'Tuberculosis of other specified organs NOS'),('tuberculosis',1,'A17z.',NULL,'Tuberculosis of other organs NOS'),('tuberculosis',1,'A18..',NULL,'Miliary tuberculosis'),('tuberculosis',1,'A180.',NULL,'Acute miliary tuberculosis'),('tuberculosis',1,'A1800',NULL,'Acute miliary tuberculosis of a single specified site'),('tuberculosis',1,'A1801',NULL,'Acute miliary tuberculosis of multiple sites'),('tuberculosis',1,'A18y.',NULL,'Other specified miliary tuberculosis'),('tuberculosis',1,'A18z.',NULL,'Miliary tuberculosis NOS'),('tuberculosis',1,'A1y..',NULL,'Other specified tuberculosis'),('tuberculosis',1,'A1z..',NULL,'Tuberculosis NOS'),('tuberculosis',1,'Ayu10',NULL,'[X]Other respiratory tuberculosis, confirmed bacteriologically and histologically'),('tuberculosis',1,'Ayu11',NULL,'[X]Respiratory tuberculosis unspecified, confirmed bacteriologically and histologically'),('tuberculosis',1,'Ayu12',NULL,'[X]Other respiratory tuberculosis, without mention of bacteriological or histological confirmation'),('tuberculosis',1,'Ayu13',NULL,'[X]Respiratory tuberculosis unspecified, without mention of bacteriological or histological confirmation'),('tuberculosis',1,'Ayu14',NULL,'[X]Other tuberculosis of nervous system'),('tuberculosis',1,'Ayu15',NULL,'[X]Tuberculosis of nervous system, unspecified'),('tuberculosis',1,'Ayu16',NULL,'[X]Tuberculosis of other specified organs'),('tuberculosis',1,'Ayu17',NULL,'[X]Acute miliary tuberculosis, unspecified'),('tuberculosis',1,'Ayu18',NULL,'[X]Other miliary tuberculosis'),('tuberculosis',1,'Ayu19',NULL,'[X]Miliary tuberculosis, unspecified'),('tuberculosis',1,'G5320',NULL,'Concatos disease'),('tuberculosis',1,'H510.',NULL,'Pleurisy without effusion or active tuberculosis'),('tuberculosis',1,'H510z',NULL,'Pleurisy without effusion or active tuberculosis NOS'),('tuberculosis',1,'Jyu93',NULL,'[X]Tuberculous disorders of intestine and mesentery'),('tuberculosis',1,'X70Gw',NULL,'Primary progressive tuberculosis'),('tuberculosis',1,'X70H0',NULL,'Tuberculosis of gastrointestinal tract'),('tuberculosis',1,'X70H8',NULL,'Tuberculosis of male genital organs'),('tuberculosis',1,'X70H9',NULL,'Tuberculosis of female genital organs'),('tuberculosis',1,'Xa1p4',NULL,'Urinary tuberculosis'),('tuberculosis',1,'Xa97Y',NULL,'Tuberculosis of trachea'),('tuberculosis',1,'XE0Qr',NULL,'Tuberculosis of bones and joints'),('tuberculosis',1,'XE0T4',NULL,'Tuberculosis of kidney with other genitourinary organ'),('tuberculosis',1,'XE2aj',NULL,'Tuberculosis of peripheral lymph nodes'),('tuberculosis',1,'XE2uC',NULL,'Tuberculosis of skin and subcutaneous tissue'),('tuberculosis',1,'XE2wL',NULL,'Tuberculous pleural empyema'),('tuberculosis',1,'XSCD2',NULL,'Tuberculosis of central nervous system');
INSERT INTO #codesctv3
VALUES ('alcohol-heavy-drinker',1,'136K.',NULL,'Alcohol intake above recommended sensible limits'),('alcohol-heavy-drinker',1,'E23..',NULL,'Alcohol problem drinking'),('alcohol-heavy-drinker',1,'Eu101',NULL,'[X]Mental and behavioural disorders due to use of alcohol: harmful use'),('alcohol-heavy-drinker',1,'Ub0lO',NULL,'Drinks heavily'),('alcohol-heavy-drinker',1,'Ub0lP',NULL,'Very heavy drinker'),('alcohol-heavy-drinker',1,'Ub0lt',NULL,'Drinks in morning to get rid of hangover'),('alcohol-heavy-drinker',1,'Ub0ly',NULL,'Binge drinker'),('alcohol-heavy-drinker',1,'Ub0mj',NULL,'Feels should cut down drinking'),('alcohol-heavy-drinker',1,'Xa1yZ',NULL,'Alcohol abuse'),('alcohol-heavy-drinker',1,'XaA1V',NULL,'Ethanol abuse'),('alcohol-heavy-drinker',1,'XaKvA',NULL,'Hazardous alcohol use'),('alcohol-heavy-drinker',1,'XaKvB',NULL,'Harmful alcohol use'),('alcohol-heavy-drinker',1,'XaXje',NULL,'Higher risk drinking'),('alcohol-heavy-drinker',1,'XE1YQ',NULL,'Alcohol problem drinking');
INSERT INTO #codesctv3
VALUES ('alcohol-light-drinker',1,'1362.00',NULL,'Trivial drinker - <1u/day');
INSERT INTO #codesctv3
VALUES ('alcohol-moderate-drinker',1,'136F.',NULL,'Spirit drinker'),('alcohol-moderate-drinker',1,'136G.',NULL,'Beer drinker'),('alcohol-moderate-drinker',1,'136H.',NULL,'Drinks beer and spirits'),('alcohol-moderate-drinker',1,'136I.',NULL,'Drinks wine'),('alcohol-moderate-drinker',1,'136J.',NULL,'Social drinker'),('alcohol-moderate-drinker',1,'136L.',NULL,'Alcohol intake within recommended sensible limits'),('alcohol-moderate-drinker',1,'136Z.',NULL,'Alcohol consumption NOS'),('alcohol-moderate-drinker',1,'Ub0lM',NULL,'Moderate drinker'),('alcohol-moderate-drinker',1,'XaXjd',NULL,'Increasing risk drinking'),('alcohol-moderate-drinker',1,'XaXjd',NULL,'Increasing risk drinking');
INSERT INTO #codesctv3
VALUES ('alcohol-non-drinker',1,'1361.',NULL,'Teetotaller'),('alcohol-non-drinker',1,'136M.',NULL,'Current non-drinker');
INSERT INTO #codesctv3
VALUES ('alcohol-weekly-intake',1,'136..',NULL,'AI - Alcohol intake'),('alcohol-weekly-intake',1,'Ub173',NULL,'Alcohol units per week');
INSERT INTO #codesctv3
VALUES ('bmi',2,'22K..',NULL,'Body Mass Index'),('bmi',2,'X76CO',NULL,'Quetelet index'),('bmi',2,'Xa7wG',NULL,'Observation of body mass index'),('bmi',2,'XaZcl',NULL,'Baseline body mass index');
INSERT INTO #codesctv3
VALUES ('smoking-status-current',1,'1373.',NULL,'Lt cigaret smok, 1-9 cigs/day'),('smoking-status-current',1,'1374.',NULL,'Mod cigaret smok, 10-19 cigs/d'),('smoking-status-current',1,'1375.',NULL,'Hvy cigaret smok, 20-39 cigs/d'),('smoking-status-current',1,'1376.',NULL,'Very hvy cigs smoker,40+cigs/d'),('smoking-status-current',1,'137C.',NULL,'Keeps trying to stop smoking'),('smoking-status-current',1,'137D.',NULL,'Admitted tobacco cons untrue ?'),('smoking-status-current',1,'137G.',NULL,'Trying to give up smoking'),('smoking-status-current',1,'137H.',NULL,'Pipe smoker'),('smoking-status-current',1,'137J.',NULL,'Cigar smoker'),('smoking-status-current',1,'137M.',NULL,'Rolls own cigarettes'),('smoking-status-current',1,'137P.',NULL,'Cigarette smoker'),('smoking-status-current',1,'137Q.',NULL,'Smoking started'),('smoking-status-current',1,'137R.',NULL,'Current smoker'),('smoking-status-current',1,'137Z.',NULL,'Tobacco consumption NOS'),('smoking-status-current',1,'Ub1tI',NULL,'Cigarette consumption'),('smoking-status-current',1,'Ub1tJ',NULL,'Cigar consumption'),('smoking-status-current',1,'Ub1tK',NULL,'Pipe tobacco consumption'),('smoking-status-current',1,'XaBSp',NULL,'Smoking restarted'),('smoking-status-current',1,'XaIIu',NULL,'Smoking reduced'),('smoking-status-current',1,'XaIkW',NULL,'Thinking about stop smoking'),('smoking-status-current',1,'XaIkX',NULL,'Ready to stop smoking'),('smoking-status-current',1,'XaIkY',NULL,'Not interested stop smoking'),('smoking-status-current',1,'XaItg',NULL,'Reason for restarting smoking'),('smoking-status-current',1,'XaIuQ',NULL,'Cigarette pack-years'),('smoking-status-current',1,'XaJX2',NULL,'Min from wake to 1st tobac con'),('smoking-status-current',1,'XaWNE',NULL,'Failed attempt to stop smoking'),('smoking-status-current',1,'XaZIE',NULL,'Waterpipe tobacco consumption'),('smoking-status-current',1,'XE0oq',NULL,'Cigarette smoker'),('smoking-status-current',1,'XE0or',NULL,'Smoking started'),('smoking-status-current',1,'Ub0p2',NULL,'Total time smoked'),('smoking-status-current',1,'Ub0p3',NULL,'Age at starting smoking'),('smoking-status-current',1,'Ub1tS',NULL,'Light cigarette smoker'),('smoking-status-current',1,'Ub1tT',NULL,'Moderate cigarette smoker'),('smoking-status-current',1,'Ub1tU',NULL,'Heavy cigarette smoker'),('smoking-status-current',1,'Ub1tV',NULL,'Very heavy cigarette smoker'),('smoking-status-current',1,'Ub1tW',NULL,'Chain smoker'),('smoking-status-current',1,'Xaa26',NULL,'Number of previous attempts to stop smoking'),('smoking-status-current',1,'XaLQh',NULL,'Wants to stop smoking');
INSERT INTO #codesctv3
VALUES ('smoking-status-currently-not',1,'Ub0oq',NULL,'Non-smoker'),('smoking-status-currently-not',1,'137L.',NULL,'Current non-smoker');
INSERT INTO #codesctv3
VALUES ('smoking-status-ex',1,'1378.',NULL,'Ex-light smoker (1-9/day)'),('smoking-status-ex',1,'1379.',NULL,'Ex-moderate smoker (10-19/day)'),('smoking-status-ex',1,'137A.',NULL,'Ex-heavy smoker (20-39/day)'),('smoking-status-ex',1,'137B.',NULL,'Ex-very heavy smoker (40+/day)'),('smoking-status-ex',1,'137F.',NULL,'Ex-smoker - amount unknown'),('smoking-status-ex',1,'137K.',NULL,'Stopped smoking'),('smoking-status-ex',1,'137N.',NULL,'Ex-pipe smoker'),('smoking-status-ex',1,'137O.',NULL,'Ex-cigar smoker'),('smoking-status-ex',1,'137T.',NULL,'Date ceased smoking'),('smoking-status-ex',1,'Ub1na',NULL,'Ex-smoker'),('smoking-status-ex',1,'Xa1bv',NULL,'Ex-cigarette smoker'),('smoking-status-ex',1,'XaIr7',NULL,'Smoking free weeks'),('smoking-status-ex',1,'XaKlS',NULL,'[V]PH of tobacco abuse'),('smoking-status-ex',1,'XaQ8V',NULL,'Ex roll-up cigarette smoker'),('smoking-status-ex',1,'XaQzw',NULL,'Recently stopped smoking'),('smoking-status-ex',1,'XE0ok',NULL,'Ex-light cigaret smok, 1-9/day'),('smoking-status-ex',1,'XE0ol',NULL,'Ex-mod cigaret smok, 10-19/day'),('smoking-status-ex',1,'XE0om',NULL,'Ex-heav cigaret smok,20-39/day'),('smoking-status-ex',1,'XE0on',NULL,'Ex-very hv cigaret smk,40+/day'),('smoking-status-ex',1,'Ub0p1',NULL,'Time since stopped smoking'),('smoking-status-ex',1,'XaXP8',NULL,'Stopped smoking before pregnancy'),('smoking-status-ex',1,'XE0op',NULL,'Ex-cigarette smoker amount unknown');
INSERT INTO #codesctv3
VALUES ('smoking-status-ex-trivial',1,'XE0oj',NULL,'Ex-triv cigaret smoker, <1/day'),('smoking-status-ex-trivial',1,'1377.',NULL,'Ex-trivial smoker (<1/day)');
INSERT INTO #codesctv3
VALUES ('smoking-status-never',1,'XE0oh',NULL,'Never smoked tobacco'),('smoking-status-never',1,'1371.',NULL,'Never smoked tobacco');
INSERT INTO #codesctv3
VALUES ('smoking-status-passive',1,'137I.',NULL,'Passive smoker'),('smoking-status-passive',1,'Ub0pe',NULL,'Exposed to tobacco smoke at work'),('smoking-status-passive',1,'Ub0pf',NULL,'Exposed to tobacco smoke at home'),('smoking-status-passive',1,'Ub0pg',NULL,'Exposed to tobacco smoke in public places'),('smoking-status-passive',1,'13WF4',NULL,'Passive smoking risk'),('smoking-status-passive',1,'XaXPD',NULL,'Smoker in household');
INSERT INTO #codesctv3
VALUES ('smoking-status-trivial',1,'XagO3',NULL,'Occasional tobacco smoker'),('smoking-status-trivial',1,'XE0oi',NULL,'Triv cigaret smok, < 1 cig/day'),('smoking-status-trivial',1,'1372.',NULL,'Trivial smoker - < 1 cig/day');
INSERT INTO #codesctv3
VALUES ('creatinine',1,'XE2q5',NULL,'Serum creatinine'),('creatinine',1,'XE2q5',NULL,'Serum creatinine level'),('creatinine',1,'XaERc',NULL,'Corrected serum creatinine level'),('creatinine',1,'XaERX',NULL,'Corrected plasma creatinine level'),('creatinine',1,'44J3z',NULL,'Serum creatinine NOS'),('creatinine',1,'XaETQ',NULL,'Plasma creatinine level');
INSERT INTO #codesctv3
VALUES ('egfr',1,'X70kK',NULL,'Tc99m-DTPA clearance - GFR'),('egfr',1,'X70kL',NULL,'Cr51- EDTA clearance - GFR'),('egfr',1,'X90kf',NULL,'With GFR'),('egfr',1,'XaK8y',NULL,'Glomerular filtration rate calculated by abbreviated Modification of Diet in Renal Disease Study Group calculation'),('egfr',1,'XaMDA',NULL,'Glomerular filtration rate calculated by abbreviated Modification of Diet in Renal Disease Study Group calculation adjusted for African American origin'),('egfr',1,'XaZpN',NULL,'Estimated glomerular filtration rate using Chronic Kidney Disease Epidemiology Collaboration formula per 1.73 square metres'),('egfr',1,'XacUJ',NULL,'Estimated glomerular filtration rate using cystatin C Chronic Kidney Disease Epidemiology Collaboration equation per 1.73 square metres'),('egfr',1,'XacUK',NULL,'Estimated glomerular filtration rate using creatinine Chronic Kidney Disease Epidemiology Collaboration equation per 1.73 square metres'),('egfr',1,'XSFyN',NULL,'Glomerular filtration rate');
INSERT INTO #codesctv3
VALUES ('hdl-cholesterol',1,'44P5.',NULL,'Serum HDL cholesterol level'),('hdl-cholesterol',1,'44PC.',NULL,'Ser random HDL cholesterol lev'),('hdl-cholesterol',1,'XaEVr',NULL,'Plasma HDL cholesterol level'),('hdl-cholesterol',1,'44d2.',NULL,'Plasma random HDL cholesterol level'),('hdl-cholesterol',1,'44d3.',NULL,'Plasma fasting HDL cholesterol level'),('hdl-cholesterol',1,'44PB.',NULL,'Serum fasting HDL cholesterol level');
INSERT INTO #codesctv3
VALUES ('ldl-cholesterol',1,'44P6.',NULL,'Serum LDL cholesterol level'),('ldl-cholesterol',1,'XaIp4',NULL,'Calculated LDL cholesterol lev'),('ldl-cholesterol',1,'XaEVs',NULL,'Plasma LDL cholesterol level'),('ldl-cholesterol',1,'44d4.',NULL,'Plasma random LDL cholesterol levell'),('ldl-cholesterol',1,'44d5.',NULL,'Plasma fasting LDL cholesterol level'),('ldl-cholesterol',1,'44PD.',NULL,'Serum fasting LDL cholesterol level'),('ldl-cholesterol',1,'44PE.',NULL,'Serum random LDL cholesterol level');
INSERT INTO #codesctv3
VALUES ('triglycerides',1,'XE2q9',NULL,'Serum triglycerides'),('triglycerides',1,'XE2q9',NULL,'Serum triglyceride levels'),('triglycerides',1,'44Q4.',NULL,'Serum fasting triglyceride level'),('triglycerides',1,'44QZ.',NULL,'Serum triglycerides NOS'),('triglycerides',1,'44e..',NULL,'Plasma triglyceride level'),('triglycerides',1,'44e0.',NULL,'Plasma random triglyceride level'),('triglycerides',1,'44e1.',NULL,'Plasma fasting triglyceride level'),('triglycerides',1,'44Q..',NULL,'Serum triglycerides'),('triglycerides',1,'44Q5.',NULL,'Serum random triglyceride level'),('triglycerides',1,'X772O',NULL,'Triglyceride level')

INSERT INTO #AllCodes
SELECT [concept], [version], [code], [description] from #codesctv3;

IF OBJECT_ID('tempdb..#codessnomed') IS NOT NULL DROP TABLE #codessnomed;
CREATE TABLE #codessnomed (
  [concept] [varchar](255) NOT NULL,
  [version] INT NOT NULL,
	[code] [varchar](20) COLLATE Latin1_General_CS_AS NOT NULL,
	[term] [varchar](20) COLLATE Latin1_General_CS_AS NULL,
	[description] [varchar](255) NULL
) ON [PRIMARY];

INSERT INTO #codessnomed
VALUES ('chronic-kidney-disease',1,'46177005',NULL,'End-stage renal disease'),('chronic-kidney-disease',1,'431855005',NULL,'CKD stage 1'),('chronic-kidney-disease',1,'431856006',NULL,'CKD stage 2'),('chronic-kidney-disease',1,'431857002',NULL,'CKD stage 4'),('chronic-kidney-disease',1,'433144002',NULL,'CKD stage 3'),('chronic-kidney-disease',1,'433146000',NULL,'CKD stage 5'),('chronic-kidney-disease',1,'700378005',NULL,'Chronic kidney disease stage 3A (disorder)'),('chronic-kidney-disease',1,'700379002',NULL,'Chronic kidney disease stage 3B (disorder)'),('chronic-kidney-disease',1,'707323002',NULL,'Anemia in chronic kidney disease'),('chronic-kidney-disease',1,'709044004',NULL,'Chronic renal disease'),('chronic-kidney-disease',1,'713313000',NULL,'Chronic kidney disease mineral and bone disorder (disorder)'),('chronic-kidney-disease',1,'714152005',NULL,'Chronic kidney disease stage 5 on dialysis'),('chronic-kidney-disease',1,'714153000',NULL,'CKD (chronic kidney disease) stage 5t'),('chronic-kidney-disease',1,'722098007',NULL,'Chronic kidney disease following donor nephrectomy'),('chronic-kidney-disease',1,'722149000',NULL,'Chronic kidney disease due to tumour nephrectomy'),('chronic-kidney-disease',1,'722150000',NULL,'Chronic kidney disease due to systemic infection'),('chronic-kidney-disease',1,'722467000',NULL,'Chronic kidney disease due to traumatic loss of kidney'),('chronic-kidney-disease',1,'140121000119100',NULL,'Hypertension in chronic kidney disease stage 3 due to type II diabetes mellitus'),('chronic-kidney-disease',1,'140131000119102',NULL,'Hypertension in chronic kidney disease stage 2 due to type II diabetes mellitus'),('chronic-kidney-disease',1,'140101000119109',NULL,'Hypertension in chronic kidney disease stage 5 due to type II diabetes mellitus'),('chronic-kidney-disease',1,'140111000119107',NULL,'Hypertension in chronic kidney disease stage 4 due to type II diabetes mellitus'),('chronic-kidney-disease',1,'71701000119105',NULL,'Hypertension in chronic kidney disease due to type I diabetes mellitus'),('chronic-kidney-disease',1,'71421000119105',NULL,'Hypertension in chronic kidney disease due to type II diabetes mellitus'),('chronic-kidney-disease',1,'104931000119100',NULL,'Chronic kidney disease due to hypertension (disorder)'),('chronic-kidney-disease',1,'731000119105',NULL,'Chronic kidney disease stage 3 due to type II diabetes mellitus'),('chronic-kidney-disease',1,'741000119101',NULL,'Chronic kidney disease stage 2 due to type II diabetes mellitus'),('chronic-kidney-disease',1,'711000119100',NULL,'Chronic kidney disease stage 5 due to type II diabetes mellitus'),('chronic-kidney-disease',1,'721000119107',NULL,'Chronic kidney disease stage 4 due to type II diabetes mellitus'),('chronic-kidney-disease',1,'96441000119101',NULL,'Chronic kidney disease due to type I diabetes mellitus'),('chronic-kidney-disease',1,'771000119108',NULL,'Chronic kidney disease due to type 2 diabetes mellitus (disorder)'),('chronic-kidney-disease',1,'10757481000119107',NULL,'Preexisting hypertensive heart and chronic kidney disease in pregnancy'),('chronic-kidney-disease',1,'285831000119108',NULL,'Malignant hypertensive chronic kidney disease (disorder)'),('chronic-kidney-disease',1,'129161000119100',NULL,'Chronic kidney disease stage 5 due to hypertension (disorder)'),('chronic-kidney-disease',1,'117681000119102',NULL,'Chronic kidney disease stage 1 due to hypertension (disorder)'),('chronic-kidney-disease',1,'129171000119106',NULL,'Chronic kidney disease stage 3 due to hypertension (disorder)'),('chronic-kidney-disease',1,'129181000119109',NULL,'Chronic kidney disease stage 2 due to hypertension (disorder)'),('chronic-kidney-disease',1,'129151000119102',NULL,'Chronic kidney disease stage 4 due to hypertension (disorder)'),('chronic-kidney-disease',1,'8501000119104',NULL,'Hypertensive heart and chronic kidney disease (disorder)'),('chronic-kidney-disease',1,'96701000119107',NULL,'Hypertensive heart AND chronic kidney disease on dialysis (disorder)'),('chronic-kidney-disease',1,'284961000119106',NULL,'Chronic kidney disease due to benign hypertension (disorder)'),('chronic-kidney-disease',1,'324281000000104',NULL,'Chronic kidney disease stage 3 without proteinuria'),('chronic-kidney-disease',1,'324251000000105',NULL,'Chronic kidney disease stage 3 with proteinuria'),('chronic-kidney-disease',1,'285871000119106',NULL,'Malignant hypertensive chronic kidney disease stage 3 (disorder)'),('chronic-kidney-disease',1,'96731000119100',NULL,'Hypertensive heart AND chronic kidney disease stage 3 (disorder)'),('chronic-kidney-disease',1,'90741000119107',NULL,'Chronic kidney disease stage 3 due to type I diabetes mellitus'),('chronic-kidney-disease',1,'284991000119104',NULL,'Chronic kidney disease stage 3 due to benign hypertension'),('chronic-kidney-disease',1,'691421000119108',NULL,'Anemia co-occurrent and due to chronic kidney disease stage 3'),('chronic-kidney-disease',1,'324211000000106',NULL,'Chronic kidney disease stage 2 without proteinuria'),('chronic-kidney-disease',1,'324181000000105',NULL,'Chronic kidney disease stage 2 with proteinuria'),('chronic-kidney-disease',1,'285861000119100',NULL,'Malignant hypertensive chronic kidney disease stage 2 (disorder)'),('chronic-kidney-disease',1,'96741000119109',NULL,'Hypertensive heart AND chronic kidney disease stage 2 (disorder)'),('chronic-kidney-disease',1,'90731000119103',NULL,'Chronic kidney disease stage 2 due to type I diabetes mellitus'),('chronic-kidney-disease',1,'284981000119102',NULL,'Chronic kidney disease stage 2 due to benign hypertension (disorder)'),('chronic-kidney-disease',1,'324541000000105',NULL,'Chronic kidney disease stage 5 without proteinuria'),('chronic-kidney-disease',1,'324501000000107',NULL,'Chronic kidney disease stage 5 with proteinuria'),('chronic-kidney-disease',1,'153851000119106',NULL,'Malignant hypertensive chronic kidney disease stage 5 (disorder)'),('chronic-kidney-disease',1,'96711000119105',NULL,'Hypertensive heart AND chronic kidney disease stage 5 (disorder)'),('chronic-kidney-disease',1,'90761000119106',NULL,'Chronic kidney disease stage 5 due to type I diabetes mellitus'),('chronic-kidney-disease',1,'285011000119108',NULL,'Chronic kidney disease stage 5 due to benign hypertension'),('chronic-kidney-disease',1,'324441000000106',NULL,'Chronic kidney disease stage 4 with proteinuria'),('chronic-kidney-disease',1,'324471000000100',NULL,'Chronic kidney disease stage 4 without proteinuria'),('chronic-kidney-disease',1,'285881000119109',NULL,'Malignant hypertensive chronic kidney disease stage 4 (disorder)'),('chronic-kidney-disease',1,'96721000119103',NULL,'Hypertensive heart AND chronic kidney disease stage 4 (disorder)'),('chronic-kidney-disease',1,'90751000119109',NULL,'Chronic kidney disease stage 4 due to type I diabetes mellitus'),('chronic-kidney-disease',1,'285001000119105',NULL,'Chronic kidney disease stage 4 due to benign hypertension (disorder)'),('chronic-kidney-disease',1,'90721000119101',NULL,'Chronic kidney disease stage 1 due to type I diabetes mellitus'),('chronic-kidney-disease',1,'751000119104',NULL,'Chronic kidney disease stage 1 due to type II diabetes mellitus'),('chronic-kidney-disease',1,'285851000119102',NULL,'Malignant hypertensive chronic kidney disease stage 1 (disorder)'),('chronic-kidney-disease',1,'96751000119106',NULL,'Hypertensive heart AND chronic kidney disease stage 1 (disorder)'),('chronic-kidney-disease',1,'284971000119100',NULL,'Chronic kidney disease stage 1 due to benign hypertension (disorder)'),('chronic-kidney-disease',1,'10757401000119104',NULL,'Pre-existing hypertensive heart and chronic kidney disease in mother complicating childbirth'),('chronic-kidney-disease',1,'324311000000101',NULL,'Chronic kidney disease stage 3A with proteinuria'),('chronic-kidney-disease',1,'324341000000100',NULL,'Chronic kidney disease stage 3A without proteinuria'),('chronic-kidney-disease',1,'324371000000106',NULL,'Chronic kidney disease stage 3B with proteinuria'),('chronic-kidney-disease',1,'324411000000105',NULL,'Chronic kidney disease stage 3B without proteinuria'),('chronic-kidney-disease',1,'949521000000108',NULL,'Chronic kidney disease with glomerular filtration rate category G2 and albuminuria category A1'),('chronic-kidney-disease',1,'949561000000100',NULL,'Chronic kidney disease with glomerular filtration rate category G2 and albuminuria category A2'),('chronic-kidney-disease',1,'949621000000109',NULL,'Chronic kidney disease with glomerular filtration rate category G2 and albuminuria category A3'),('chronic-kidney-disease',1,'950251000000106',NULL,'Chronic kidney disease with glomerular filtration rate category G5 and albuminuria category A1'),('chronic-kidney-disease',1,'950291000000103',NULL,'Chronic kidney disease with glomerular filtration rate category G5 and albuminuria category A2'),('chronic-kidney-disease',1,'950311000000102',NULL,'Chronic kidney disease with glomerular filtration rate category G5 and albuminuria category A3'),('chronic-kidney-disease',1,'950181000000106',NULL,'Chronic kidney disease with glomerular filtration rate category G4 and albuminuria category A1'),('chronic-kidney-disease',1,'950211000000107',NULL,'Chronic kidney disease with glomerular filtration rate category G4 and albuminuria category A2'),('chronic-kidney-disease',1,'950231000000104',NULL,'Chronic kidney disease with glomerular filtration rate category G4 and albuminuria category A3'),('chronic-kidney-disease',1,'324151000000104',NULL,'Chronic kidney disease stage 1 without proteinuria'),('chronic-kidney-disease',1,'324121000000109',NULL,'Chronic kidney disease stage 1 with proteinuria'),('chronic-kidney-disease',1,'949881000000106',NULL,'CKD G3aA1 - chronic kidney disease with glomerular filtration rate category G3a and albuminuria category A1'),('chronic-kidney-disease',1,'949901000000109',NULL,'Chronic kidney disease with glomerular filtration rate category G3a and albuminuria category A2'),
('chronic-kidney-disease',1,'949921000000100',NULL,'Chronic kidney disease with glomerular filtration rate category G3a and albuminuria category A3'),('chronic-kidney-disease',1,'950061000000103',NULL,'Chronic kidney disease with glomerular filtration rate category G3b and albuminuria category A1'),('chronic-kidney-disease',1,'950081000000107',NULL,'Chronic kidney disease with glomerular filtration rate category G3b and albuminuria category A2'),('chronic-kidney-disease',1,'950101000000101',NULL,'Chronic kidney disease with glomerular filtration rate category G3b and albuminuria category A3'),('chronic-kidney-disease',1,'949401000000103',NULL,'Chronic kidney disease with glomerular filtration rate category G1 and albuminuria category A1'),('chronic-kidney-disease',1,'949421000000107',NULL,'Chronic kidney disease with glomerular filtration rate category G1 and albuminuria category A2'),('chronic-kidney-disease',1,'949481000000108',NULL,'Chronic kidney disease with glomerular filtration rate category G1 and albuminuria category A3'),('chronic-kidney-disease',1,'691401000119104',NULL,'Anaemia in chronic kidney disease stage 4'),('chronic-kidney-disease',1,'691411000119101',NULL,'Anaemia in chronic kidney disease stage 5'),('chronic-kidney-disease',1,'444271000',NULL,'Erythropoietin resistance in anemia of chronic kidney disease'),('chronic-kidney-disease',1,'15781000119107',NULL,'Hypertensive heart AND chronic kidney disease with congestive heart failure (disorder)');
INSERT INTO #codessnomed
VALUES ('ckd-stage-1',1,'431855005',NULL,'CKD stage 1'),('ckd-stage-1',1,'117681000119102',NULL,'Chronic kidney disease stage 1 due to hypertension (disorder)'),('ckd-stage-1',1,'90721000119101',NULL,'Chronic kidney disease stage 1 due to type I diabetes mellitus'),('ckd-stage-1',1,'751000119104',NULL,'Chronic kidney disease stage 1 due to type II diabetes mellitus'),('ckd-stage-1',1,'285851000119102',NULL,'Malignant hypertensive chronic kidney disease stage 1 (disorder)'),('ckd-stage-1',1,'96751000119106',NULL,'Hypertensive heart AND chronic kidney disease stage 1 (disorder)'),('ckd-stage-1',1,'284971000119100',NULL,'Chronic kidney disease stage 1 due to benign hypertension (disorder)'),('ckd-stage-1',1,'324151000000104',NULL,'Chronic kidney disease stage 1 without proteinuria'),('ckd-stage-1',1,'324121000000109',NULL,'Chronic kidney disease stage 1 with proteinuria'),('ckd-stage-1',1,'949401000000103',NULL,'Chronic kidney disease with glomerular filtration rate category G1 and albuminuria category A1'),('ckd-stage-1',1,'949421000000107',NULL,'Chronic kidney disease with glomerular filtration rate category G1 and albuminuria category A2'),('ckd-stage-1',1,'949481000000108',NULL,'Chronic kidney disease with glomerular filtration rate category G1 and albuminuria category A3');
INSERT INTO #codessnomed
VALUES ('ckd-stage-2',1,'431856006',NULL,'CKD stage 2'),('ckd-stage-2',1,'140131000119102',NULL,'Hypertension in chronic kidney disease stage 2 due to type II diabetes mellitus'),('ckd-stage-2',1,'741000119101',NULL,'Chronic kidney disease stage 2 due to type II diabetes mellitus'),('ckd-stage-2',1,'129181000119109',NULL,'Chronic kidney disease stage 2 due to hypertension (disorder)'),('ckd-stage-2',1,'324211000000106',NULL,'Chronic kidney disease stage 2 without proteinuria'),('ckd-stage-2',1,'324181000000105',NULL,'Chronic kidney disease stage 2 with proteinuria'),('ckd-stage-2',1,'285861000119100',NULL,'Malignant hypertensive chronic kidney disease stage 2 (disorder)'),('ckd-stage-2',1,'96741000119109',NULL,'Hypertensive heart AND chronic kidney disease stage 2 (disorder)'),('ckd-stage-2',1,'90731000119103',NULL,'Chronic kidney disease stage 2 due to type I diabetes mellitus'),('ckd-stage-2',1,'284981000119102',NULL,'Chronic kidney disease stage 2 due to benign hypertension (disorder)'),('ckd-stage-2',1,'949521000000108',NULL,'Chronic kidney disease with glomerular filtration rate category G2 and albuminuria category A1'),('ckd-stage-2',1,'949561000000100',NULL,'Chronic kidney disease with glomerular filtration rate category G2 and albuminuria category A2'),('ckd-stage-2',1,'949621000000109',NULL,'Chronic kidney disease with glomerular filtration rate category G2 and albuminuria category A3');
INSERT INTO #codessnomed
VALUES ('ckd-stage-3',1,'433144002',NULL,'CKD stage 3'),('ckd-stage-3',1,'700378005',NULL,'Chronic kidney disease stage 3A (disorder)'),('ckd-stage-3',1,'700379002',NULL,'Chronic kidney disease stage 3B (disorder)'),('ckd-stage-3',1,'140121000119100',NULL,'Hypertension in chronic kidney disease stage 3 due to type II diabetes mellitus'),('ckd-stage-3',1,'731000119105',NULL,'Chronic kidney disease stage 3 due to type II diabetes mellitus'),('ckd-stage-3',1,'129171000119106',NULL,'Chronic kidney disease stage 3 due to hypertension (disorder)'),('ckd-stage-3',1,'324281000000104',NULL,'Chronic kidney disease stage 3 without proteinuria'),('ckd-stage-3',1,'324251000000105',NULL,'Chronic kidney disease stage 3 with proteinuria'),('ckd-stage-3',1,'285871000119106',NULL,'Malignant hypertensive chronic kidney disease stage 3 (disorder)'),('ckd-stage-3',1,'96731000119100',NULL,'Hypertensive heart AND chronic kidney disease stage 3 (disorder)'),('ckd-stage-3',1,'90741000119107',NULL,'Chronic kidney disease stage 3 due to type I diabetes mellitus'),('ckd-stage-3',1,'284991000119104',NULL,'Chronic kidney disease stage 3 due to benign hypertension'),('ckd-stage-3',1,'691421000119108',NULL,'Anemia co-occurrent and due to chronic kidney disease stage 3'),('ckd-stage-3',1,'324311000000101',NULL,'Chronic kidney disease stage 3A with proteinuria'),('ckd-stage-3',1,'324341000000100',NULL,'Chronic kidney disease stage 3A without proteinuria'),('ckd-stage-3',1,'324371000000106',NULL,'Chronic kidney disease stage 3B with proteinuria'),('ckd-stage-3',1,'324411000000105',NULL,'Chronic kidney disease stage 3B without proteinuria'),('ckd-stage-3',1,'949881000000106',NULL,'CKD G3aA1 - chronic kidney disease with glomerular filtration rate category G3a and albuminuria category A1'),('ckd-stage-3',1,'949901000000109',NULL,'Chronic kidney disease with glomerular filtration rate category G3a and albuminuria category A2'),('ckd-stage-3',1,'949921000000100',NULL,'Chronic kidney disease with glomerular filtration rate category G3a and albuminuria category A3'),('ckd-stage-3',1,'950061000000103',NULL,'Chronic kidney disease with glomerular filtration rate category G3b and albuminuria category A1'),('ckd-stage-3',1,'950081000000107',NULL,'Chronic kidney disease with glomerular filtration rate category G3b and albuminuria category A2'),('ckd-stage-3',1,'950101000000101',NULL,'Chronic kidney disease with glomerular filtration rate category G3b and albuminuria category A3');
INSERT INTO #codessnomed
VALUES ('ckd-stage-4',1,'431857002',NULL,'CKD stage 4'),('ckd-stage-4',1,'140111000119107',NULL,'Hypertension in chronic kidney disease stage 4 due to type II diabetes mellitus'),('ckd-stage-4',1,'721000119107',NULL,'Chronic kidney disease stage 4 due to type II diabetes mellitus'),('ckd-stage-4',1,'129151000119102',NULL,'Chronic kidney disease stage 4 due to hypertension (disorder)'),('ckd-stage-4',1,'324441000000106',NULL,'Chronic kidney disease stage 4 with proteinuria'),('ckd-stage-4',1,'324471000000100',NULL,'Chronic kidney disease stage 4 without proteinuria'),('ckd-stage-4',1,'285881000119109',NULL,'Malignant hypertensive chronic kidney disease stage 4 (disorder)'),('ckd-stage-4',1,'96721000119103',NULL,'Hypertensive heart AND chronic kidney disease stage 4 (disorder)'),('ckd-stage-4',1,'90751000119109',NULL,'Chronic kidney disease stage 4 due to type I diabetes mellitus'),('ckd-stage-4',1,'285001000119105',NULL,'Chronic kidney disease stage 4 due to benign hypertension (disorder)'),('ckd-stage-4',1,'950181000000106',NULL,'Chronic kidney disease with glomerular filtration rate category G4 and albuminuria category A1'),('ckd-stage-4',1,'950211000000107',NULL,'Chronic kidney disease with glomerular filtration rate category G4 and albuminuria category A2'),('ckd-stage-4',1,'950231000000104',NULL,'Chronic kidney disease with glomerular filtration rate category G4 and albuminuria category A3'),('ckd-stage-4',1,'691401000119104',NULL,'Anaemia in chronic kidney disease stage 4');
INSERT INTO #codessnomed
VALUES ('ckd-stage-5',1,'433146000',NULL,'CKD stage 5'),('ckd-stage-5',1,'714152005',NULL,'Chronic kidney disease stage 5 on dialysis'),('ckd-stage-5',1,'140101000119109',NULL,'Hypertension in chronic kidney disease stage 5 due to type II diabetes mellitus'),('ckd-stage-5',1,'711000119100',NULL,'Chronic kidney disease stage 5 due to type II diabetes mellitus'),('ckd-stage-5',1,'129161000119100',NULL,'Chronic kidney disease stage 5 due to hypertension (disorder)'),('ckd-stage-5',1,'324541000000105',NULL,'Chronic kidney disease stage 5 without proteinuria'),('ckd-stage-5',1,'324501000000107',NULL,'Chronic kidney disease stage 5 with proteinuria'),('ckd-stage-5',1,'153851000119106',NULL,'Malignant hypertensive chronic kidney disease stage 5 (disorder)'),('ckd-stage-5',1,'96711000119105',NULL,'Hypertensive heart AND chronic kidney disease stage 5 (disorder)'),('ckd-stage-5',1,'90761000119106',NULL,'Chronic kidney disease stage 5 due to type I diabetes mellitus'),('ckd-stage-5',1,'285011000119108',NULL,'Chronic kidney disease stage 5 due to benign hypertension'),('ckd-stage-5',1,'950251000000106',NULL,'Chronic kidney disease with glomerular filtration rate category G5 and albuminuria category A1'),('ckd-stage-5',1,'950291000000103',NULL,'Chronic kidney disease with glomerular filtration rate category G5 and albuminuria category A2'),('ckd-stage-5',1,'950311000000102',NULL,'Chronic kidney disease with glomerular filtration rate category G5 and albuminuria category A3'),('ckd-stage-5',1,'691411000119101',NULL,'Anaemia in chronic kidney disease stage 5'),('ckd-stage-5',1,'46177005',NULL,'End-stage renal disease'),('ckd-stage-5',1,'714153000',NULL,'Chronic kidney disease stage 5 with transplant'),('ckd-stage-5',1,'707324008',NULL,'Anemia co-occurrent and due to end stage renal disease (disorder)'),('ckd-stage-5',1,'16320631000119104',NULL,'Dependence on continuous ambulatory peritoneal dialysis due to end stage renal disease (finding)'),('ckd-stage-5',1,'429075005',NULL,'Dependence on dialysis due to end stage renal disease (finding)'),('ckd-stage-5',1,'428982002',NULL,'Dependence on hemodialysis due to end stage renal disease (finding)'),('ckd-stage-5',1,'428937001',NULL,'Dependence on peritoneal dialysis due to end stage renal disease (finding)'),('ckd-stage-5',1,'111411000119103',NULL,'End stage renal disease due to hypertension (disorder)'),('ckd-stage-5',1,'236435004',NULL,'End stage renal failure on dialysis (disorder)'),('ckd-stage-5',1,'236434000',NULL,'End stage renal failure untreated by renal replacement therapy (disorder)'),('ckd-stage-5',1,'236436003',NULL,'End stage renal failure with renal transplant (disorder)'),('ckd-stage-5',1,'712487000',NULL,'End stage renal disease due to benign hypertension (disorder)'),('ckd-stage-5',1,'153891000119101',NULL,'End stage renal disease on dialysis due to hypertension (disorder)'),('ckd-stage-5',1,'285841000119104',NULL,'Malignant hypertensive end stage renal disease (disorder)'),('ckd-stage-5',1,'286371000119107',NULL,'Malignant hypertensive end stage renal disease on dialysis (disorder)');
INSERT INTO #codessnomed
VALUES ('sle',1,'11013005',NULL,'SLE glomerulonephritis syndrome, WHO class VI (disorder)'),('sle',1,'15084002',NULL,'Lupus erythematosus profundus (disorder)'),('sle',1,'193178008',NULL,'Polyneuropathy in disseminated lupus erythematosus (disorder)'),('sle',1,'193248005',NULL,'Myopathy due to disseminated lupus erythematosus (disorder)'),('sle',1,'196138005',NULL,'Lung disease with systemic lupus erythematosus (disorder)'),('sle',1,'200936003',NULL,'Lupus erythematosus (disorder)'),('sle',1,'200937007',NULL,'Lupus erythematosus chronicus (disorder)'),('sle',1,'200938002',NULL,'Discoid lupus erythematosus (disorder)'),('sle',1,'200939005',NULL,'Lupus erythematosus migrans (disorder)'),('sle',1,'200940007',NULL,'Lupus erythematosus nodularis (disorder)'),('sle',1,'200941006',NULL,'Lupus erythematosus tumidus (disorder)'),('sle',1,'200942004',NULL,'Lupus erythematosus unguium mutilans (disorder)'),('sle',1,'201436003',NULL,'Drug-induced systemic lupus erythematosus (disorder)'),('sle',1,'238926009',NULL,'Lupus erythematosus and erythema multiforme-like syndrome (disorder)'),('sle',1,'238927000',NULL,'Chronic discoid lupus erythematosus (disorder)'),('sle',1,'238928005',NULL,'Chilblain lupus erythematosus (disorder)'),('sle',1,'239886003',NULL,'Limited lupus erythematosus (disorder)'),('sle',1,'239887007',NULL,'Systemic lupus erythematosus with organ/system involvement (disorder)'),('sle',1,'239888002',NULL,'Lupus panniculitis (disorder)'),('sle',1,'239889005',NULL,'Bullous systemic lupus erythematosus (disorder)'),('sle',1,'239890001',NULL,'Systemic lupus erythematosus with multisystem involvement (disorder)'),('sle',1,'239891002',NULL,'Subacute cutaneous lupus erythematosus (disorder)'),('sle',1,'307755009',NULL,'Renal tubulo-interstitial disorder in systemic lupus erythematosus (disorder)'),('sle',1,'309762007',NULL,'Systemic lupus erythematosus with pericarditis (disorder)'),('sle',1,'36402006',NULL,'SLE glomerulonephritis syndrome, WHO class IV (disorder)'),('sle',1,'4676006',NULL,'SLE glomerulonephritis syndrome, WHO class II (disorder)'),('sle',1,'52042003',NULL,'SLE glomerulonephritis syndrome, WHO class V (disorder)'),('sle',1,'55464009',NULL,'Systemic lupus erythematosus (disorder)'),('sle',1,'68815009',NULL,'SLE glomerulonephritis syndrome (disorder)'),('sle',1,'7119001',NULL,'Cutaneous lupus erythematosus (disorder)'),('sle',1,'73286009',NULL,'SLE glomerulonephritis syndrome, WHO class I (disorder)'),('sle',1,'76521009',NULL,'SLE glomerulonephritis syndrome, WHO class III (disorder)'),('sle',1,'79291003',NULL,'Discoid lupus erythematosus of eyelid (disorder)'),('sle',1,'95609003',NULL,'Neonatal lupus erythematosus (disorder)'),('sle',1,'95644001',NULL,'Systemic lupus erythematosus encephalitis (disorder)'),('sle',1,'758321000000100',NULL,'Cerebral lupus'),('sle',1,'1144942002',NULL,'Neuropsychiatric disorder due to systemic lupus erythematosus (disorder)'),('sle',1,'403508004',NULL,'Lupus erythematosus-associated nailfold telangiectasia (disorder)'),('sle',1,'1220590003',NULL,'Familial chilblain lupus erythematosus (disorder)'),('sle',1,'239944008',NULL,'Lupus vasculitis (disorder)'),('sle',1,'1144973003',NULL,'Disorder of kidney due to systemic lupus erythematosus (disorder)'),('sle',1,'430961000124105',NULL,'Cheilitis due to lupus erythematosus (disorder)'),('sle',1,'403512005',NULL,'Lupus erythematosus-associated poikiloderma (disorder)'),('sle',1,'274553000',NULL,'[EDTA] Lupus erythematosus associated with renal failure (disorder)'),('sle',1,'590791000000108',NULL,'Lupus erythematosus NOS (disorder)'),('sle',1,'403511003',NULL,'Lupus erythematosus-associated necrotizing vasculitis (disorder)'),('sle',1,'593481000000109',NULL,'Systemic lupus erythematosus NOS (disorder)'),('sle',1,'1144921004',NULL,'Disorder of heart due to systemic lupus erythematosus (disorder)'),('sle',1,'403507009',NULL,'Lupus erythematosus-associated hypermelanosis (disorder)'),('sle',1,'233730002',NULL,'Lupus pneumonia (disorder)'),('sle',1,'25380002',NULL,'Pericarditis co-occurrent and due to systemic lupus erythematosus (disorder)'),('sle',1,'1144970000',NULL,'Disorder of joint due to systemic lupus erythematosus (disorder)'),('sle',1,'95332009',NULL,'Rash of systemic lupus erythematosus (disorder)'),('sle',1,'403513000',NULL,'Lupus erythematosus-associated nail dystrophy (disorder)'),('sle',1,'77753005',NULL,'Lupus disease of the lung (disorder)'),('sle',1,'707301001',NULL,'Lupus erythematosus of oral mucous membrane (disorder)'),('sle',1,'724767000',NULL,'Chorea co-occurrent and due to systemic lupus erythematosus (disorder)'),('sle',1,'1144923001',NULL,'Disorder of immune function due to systemic lupus erythematosus (disorder)'),('sle',1,'773333003',NULL,'Autosomal systemic lupus erythematosus (disorder)'),('sle',1,'201435004',NULL,'Systemic lupus erythematosus (disorder)'),('sle',1,'200944003',NULL,'Lupus erythematosus NOS (disorder)'),('sle',1,'905381000000108',NULL,'Systemic lupus erythematosus/Sjogrens overlap syndrome (disorder)'),('sle',1,'403488004',NULL,'Systemic lupus erythematosus of childhood (disorder)'),('sle',1,'201439005',NULL,'Systemic lupus erythematosus NOS (disorder)'),('sle',1,'156450004',NULL,'Systemic lupus erythematosus (disorder)'),('sle',1,'1263518006',NULL,'Meningitis due to systemic lupus erythematosus (disorder)'),('sle',1,'203784000',NULL,'[X]Other forms of systemic lupus erythematosus (disorder)'),('sle',1,'197608009',NULL,'(Nephrotic syndrome in systemic lupus erythematosus) or (lupus nephritis) (disorder)'),('sle',1,'403505001',NULL,'Lupus erythematosus-associated calcinosis (disorder)'),('sle',1,'201437007',NULL,'Systemic lupus erythematosus with organ/system involvement (disorder)'),('sle',1,'1263491001',NULL,'Myelitis due to systemic lupus erythematosus (disorder)'),('sle',1,'403509007',NULL,'Lupus erythematosus-associated vasculitis (disorder)'),('sle',1,'1144927000',NULL,'Disorder of gastrointestinal tract due to systemic lupus erythematosus (disorder)'),('sle',1,'95408003',NULL,'Systemic lupus erythematosus arthritis (disorder)'),('sle',1,'403503008',NULL,'Lupus erythematosus-associated anetoderma (disorder)'),('sle',1,'403510002',NULL,'Lupus erythematosus-associated urticarial vasculitis (disorder)'),('sle',1,'19682006',NULL,'Lupus hepatitis (disorder)'),('sle',1,'732960002',NULL,'Secondary autoimmune hemolytic anemia co-occurrent and due to systemic lupus erythematosus (disorder)'),('sle',1,'402711009',NULL,'Lupus erythematosus overlap syndrome (disorder)'),('sle',1,'698694005',NULL,'Systemic lupus erythematosus in remission (disorder)'),('sle',1,'724781003',NULL,'Demyelination of central nervous system co-occurrent and due to systemic lupus erythematosus (disorder)'),('sle',1,'295121000119101',NULL,'Nephrosis co-occurrent and due to systemic lupus erythematosus (disorder)'),('sle',1,'403506000',NULL,'Lupus erythematosus-associated papulonodular mucinosis (disorder)'),('sle',1,'69746005',NULL,'Hemolytic anemia associated with systemic lupus erythematosus (disorder)'),('sle',1,'295111000119108',NULL,'Nephrotic syndrome co-occurrent and due to systemic lupus erythematosus (disorder)'),('sle',1,'295101000119105',NULL,'Nephropathy co-occurrent and due to systemic lupus erythematosus (disorder)'),('sle',1,'197746009',NULL,'Renal tubulo-interstitial disorder in systemic lupus erythematosus (disorder)'),('sle',1,'308751000119106',NULL,'Glomerular disease due to systemic lupus erythematosus (disorder)'),('sle',1,'36471000',NULL,'Dilated cardiomyopathy due to systemic lupus erythematosus (disorder)'),('sle',1,'201438002',NULL,'Systemic lupus erythematosus with pericarditis (disorder)'),('sle',1,'417303004',NULL,'Retinal vasculitis due to systemic lupus erythematosus (disorder)'),('sle',1,'403487009',NULL,'Fulminating systemic lupus erythematosus (disorder)'),('sle',1,'409421000000100',NULL,'[X]Other forms of systemic lupus erythematosus (disorder)'),('sle',1,'1259517005',NULL,'Dementia due to systemic lupus erythematosus (disorder)'),('sle',1,'230307005',NULL,'Chorea due to systemic lupus erythematosus (disorder)'),('sle',1,'713225000',NULL,'Gingival disease due to lupus erythematosus (disorder)'),('sle',1,'403486000',NULL,'Acute systemic lupus erythematosus (disorder)'),('sle',1,'72181000119109',NULL,'Endocarditis due to systemic lupus erythematosus (disorder)'),('sle',1,'417161000000107',NULL,'Lupus erythematosus associated with renal failure - European Dialysis and Transplant Association (disorder)'),('sle',1,'80258006',NULL,'Drug-induced lupus erythematosus (disorder)'),('sle',1,'397856003',NULL,'Systemic lupus erythematosus-related syndrome (disorder)'),('sle',1,'402865003',NULL,'Systemic lupus erythematosus-associated antiphospholipid syndrome (disorder)');
INSERT INTO #codessnomed
VALUES ('tuberculosis',1,'10528009',NULL,'Lupus vulgaris (disorder)'),('tuberculosis',1,'10706006',NULL,'Tuberculosis of central nervous system (disorder)'),('tuberculosis',1,'111830007',NULL,'Tuberculosis of urinary organs (disorder)'),('tuberculosis',1,'111832004',NULL,'Primary progressive tuberculosis (disorder)'),('tuberculosis',1,'14527007',NULL,'Tuberculous empyema (disorder)'),('tuberculosis',1,'154283005',NULL,'Pulmonary tuberculosis'),('tuberculosis',1,'16409009',NULL,'Tuberculosis of retroperitoneal lymph nodes (disorder)'),('tuberculosis',1,'17653001',NULL,'Tuberculosis of bones AND/OR joints (disorder)'),('tuberculosis',1,'186172004',NULL,'Tuberculous pleurisy in primary progressive tuberculosis (disorder)'),('tuberculosis',1,'186175002',NULL,'Infiltrative lung tuberculosis (disorder)'),('tuberculosis',1,'186178000',NULL,'Tuberculosis of bronchus (disorder)'),('tuberculosis',1,'186182003',NULL,'Tuberculosis of pleura (disorder)'),('tuberculosis',1,'186192006',NULL,'Respiratory tuberculosis, bacteriologically and histologically confirmed (disorder)'),('tuberculosis',1,'186193001',NULL,'Tuberculosis of lung, confirmed by sputum microscopy with or without culture (disorder)'),('tuberculosis',1,'186194007',NULL,'Tuberculosis of lung, confirmed by culture only (disorder)'),('tuberculosis',1,'186195008',NULL,'Tuberculosis of lung, confirmed histologically (disorder)'),('tuberculosis',1,'186199002',NULL,'Tuberculosis of larynx, trachea and bronchus, confirmed bacteriologically and histologically (disorder)'),('tuberculosis',1,'186200004',NULL,'Tuberculous pleurisy, confirmed bacteriologically and histologically (disorder)'),('tuberculosis',1,'186201000',NULL,'Primary respiratory tuberculosis, confirmed bacteriologically and histologically (disorder)'),('tuberculosis',1,'186202007',NULL,'Respiratory tuberculosis, not confirmed bacteriologically or histologically (disorder)'),('tuberculosis',1,'186203002',NULL,'Tuberculosis of lung, bacteriologically and histologically negative (disorder)'),('tuberculosis',1,'186204008',NULL,'Tuberculosis of lung, bacteriological and histological examination not done (disorder)'),('tuberculosis',1,'186225008',NULL,'Tuberculosis of intestines, peritoneum and mesenteric glands (disorder)'),('tuberculosis',1,'186259007',NULL,'Scrofulous tuberculous abscess (disorder)'),('tuberculosis',1,'186269001',NULL,'Tuberculosis of ear (disorder)'),('tuberculosis',1,'186276006',NULL,'Acute miliary tuberculosis (disorder)'),('tuberculosis',1,'186278007',NULL,'Acute miliary tuberculosis of multiple sites (disorder)'),('tuberculosis',1,'190710003',NULL,'Tuberculous arthritis (disorder)'),('tuberculosis',1,'196076002',NULL,'Pleurisy without effusion or active tuberculosis (disorder)'),('tuberculosis',1,'23022004',NULL,'Tuberculous bronchiectasis (disorder)'),('tuberculosis',1,'240376003',NULL,'Tuberculosis of gastrointestinal tract (disorder)'),('tuberculosis',1,'240379005',NULL,'Tuberculosis of male genital organs (disorder)'),('tuberculosis',1,'24235005',NULL,'Tuberculous hydrothorax (disorder)'),('tuberculosis',1,'25738004',NULL,'Tuberculous synovitis (disorder)'),('tuberculosis',1,'25831001',NULL,'Tuberculosis of nasal septum (disorder)'),('tuberculosis',1,'271423008',NULL,'Tuberculosis of skin and subcutaneous tissue (disorder)'),('tuberculosis',1,'29731002',NULL,'Tuberculous pneumothorax (disorder)'),('tuberculosis',1,'33893009',NULL,'Tuberculosis verrucosa cutis (disorder)'),('tuberculosis',1,'37980001',NULL,'Concatos disease (disorder)'),('tuberculosis',1,'41156006',NULL,'Tuberculosis papulonecrotica (disorder)'),('tuberculosis',1,'4445009',NULL,'Tuberculosis of genitourinary system (disorder)'),('tuberculosis',1,'47604008',NULL,'Miliary tuberculosis (disorder)'),('tuberculosis',1,'49107007',NULL,'Tuberculosis of eye (disorder)'),('tuberculosis',1,'52721006',NULL,'Tuberculosis of nasal sinus (disorder)'),('tuberculosis',1,'54084005',NULL,'Cervical tuberculous lymphadenitis (disorder)'),('tuberculosis',1,'56498009',NULL,'Tuberculosis of nasopharynx (disorder)'),('tuberculosis',1,'56717001',NULL,'Tuberculosis (disorder)'),('tuberculosis',1,'58764007',NULL,'Tuberculous osteomyelitis (disorder)'),('tuberculosis',1,'63309002',NULL,'Primary tuberculosis (disorder)'),('tuberculosis',1,'700273003',NULL,'Isolated tracheobronchial tuberculosis (disorder)'),('tuberculosis',1,'70341005',NULL,'Tuberculous laryngitis (disorder)'),('tuberculosis',1,'74181004',NULL,'Tuberculosis of female genital organs (disorder)'),('tuberculosis',1,'74387008',NULL,'Tuberculosis of hilar lymph nodes (disorder)'),('tuberculosis',1,'74610006',NULL,'Tuberculous erythema nodosum (disorder)'),('tuberculosis',1,'77038006',NULL,'Tuberculosis of peripheral lymph nodes (disorder)'),('tuberculosis',1,'77668003',NULL,'Isolated tracheal tuberculosis (disorder)'),('tuberculosis',1,'78436002',NULL,'Tuberculosis of intrathoracic lymph nodes (disorder)'),('tuberculosis',1,'80003002',NULL,'Tuberculous pneumonia (disorder)'),('tuberculosis',1,'80010008',NULL,'Isolated bronchial tuberculosis (disorder)'),('tuberculosis',1,'80602006',NULL,'Nodular tuberculosis of lung (disorder)'),('tuberculosis',1,'82495004',NULL,'Tuberculosis of mediastinal lymph nodes (disorder)'),('tuberculosis',1,'82796002',NULL,'Scrofuloderma (disorder)'),('tuberculosis',1,'83784000',NULL,'Tuberculosis of mediastinum (disorder)'),('tuberculosis',1,'85692003',NULL,'Tuberculosis of tracheobronchial lymph nodes (disorder)'),('tuberculosis',1,'88356006',NULL,'Primary tuberculous complex (disorder)'),('tuberculosis',1,'9768003',NULL,'Tuberculosis cutis lichenoides (disorder)');
INSERT INTO #codessnomed
VALUES ('alcohol-heavy-drinker',1,'15167005',NULL,'Alcohol abuse (disorder)'),('alcohol-heavy-drinker',1,'160592001',NULL,'Alcohol intake above recommended sensible limits (finding)'),('alcohol-heavy-drinker',1,'198421000000108',NULL,'Hazardous alcohol use (observable entity)'),('alcohol-heavy-drinker',1,'198431000000105',NULL,'Harmful alcohol use (observable entity)'),('alcohol-heavy-drinker',1,'228279004',NULL,'Very heavy drinker (life style)'),('alcohol-heavy-drinker',1,'228310006',NULL,'Drinks in morning to get rid of hangover (finding)'),('alcohol-heavy-drinker',1,'228315001',NULL,'Binge drinker (finding)'),('alcohol-heavy-drinker',1,'228362008',NULL,'Feels should cut down drinking (finding)'),('alcohol-heavy-drinker',1,'7200002',NULL,'Alcoholism (disorder)'),('alcohol-heavy-drinker',1,'777651000000101',NULL,'Higher risk alcohol drinking (finding)'),('alcohol-heavy-drinker',1,'86933000',NULL,'Heavy drinker (life style)');
INSERT INTO #codessnomed
VALUES ('alcohol-light-drinker',1,'228276006',NULL,'Occasional drinker (life style)'),('alcohol-light-drinker',1,'228277002',NULL,'Light drinker (life style)'),('alcohol-light-drinker',1,'266917007',NULL,'Trivial drinker - <1u/day (life style)'),('alcohol-light-drinker',1,'777671000000105',NULL,'Lower risk alcohol drinking (finding)');
INSERT INTO #codessnomed
VALUES ('alcohol-moderate-drinker',1,'160588008',NULL,'Spirit drinker (life style)'),('alcohol-moderate-drinker',1,'160589000',NULL,'Beer drinker (life style)'),('alcohol-moderate-drinker',1,'160590009',NULL,'Drinks beer and spirits (life style)'),('alcohol-moderate-drinker',1,'160591008',NULL,'Drinks wine (life style)'),('alcohol-moderate-drinker',1,'160593006',NULL,'Alcohol intake within recommended sensible limits (finding)'),('alcohol-moderate-drinker',1,'28127009',NULL,'Social drinker (life style)'),('alcohol-moderate-drinker',1,'43783005',NULL,'Moderate drinker (life style)');
INSERT INTO #codessnomed
VALUES ('alcohol-non-drinker',1,'105542008',NULL,'Teetotaller (life style)');
INSERT INTO #codessnomed
VALUES ('alcohol-weekly-intake',1,'160573003',NULL,'Alcohol intake (observable entity)'),('alcohol-weekly-intake',1,'228958009',NULL,'alcohol units/week (qualifier value)');
INSERT INTO #codessnomed
VALUES ('bmi',2,'301331008',NULL,'Finding of body mass index (finding)'),('bmi',2,'60621009',NULL,'Body mass index (observable entity)'),('bmi',2,'846931000000101',NULL,'Baseline body mass index (observable entity)');
INSERT INTO #codessnomed
VALUES ('smoking-status-current',1,'266929003',NULL,'Smoking started (life style)'),('smoking-status-current',1,'836001000000109',NULL,'Waterpipe tobacco consumption (observable entity)'),('smoking-status-current',1,'77176002',NULL,'Smoker (life style)'),('smoking-status-current',1,'65568007',NULL,'Cigarette smoker (life style)'),('smoking-status-current',1,'394873005',NULL,'Not interested in stopping smoking (finding)'),('smoking-status-current',1,'394872000',NULL,'Ready to stop smoking (finding)'),('smoking-status-current',1,'394871007',NULL,'Thinking about stopping smoking (observable entity)'),('smoking-status-current',1,'230057008',NULL,'Cigar consumption (observable entity)'),('smoking-status-current',1,'230056004',NULL,'Cigarette consumption (observable entity)'),('smoking-status-current',1,'160623006',NULL,'Smoking: [started] or [restarted]'),('smoking-status-current',1,'160622001',NULL,'Smoker (& cigarette)'),('smoking-status-current',1,'160619003',NULL,'Rolls own cigarettes (finding)'),('smoking-status-current',1,'160616005',NULL,'Trying to give up smoking (finding)'),('smoking-status-current',1,'160612007',NULL,'Keeps trying to stop smoking (finding)'),('smoking-status-current',1,'160606002',NULL,'Very heavy cigarette smoker (40+ cigs/day) (life style)'),('smoking-status-current',1,'160605003',NULL,'Heavy cigarette smoker (20-39 cigs/day) (life style)'),('smoking-status-current',1,'160604004',NULL,'Moderate cigarette smoker (10-19 cigs/day) (life style)'),('smoking-status-current',1,'160603005',NULL,'Light cigarette smoker (1-9 cigs/day) (life style)'),('smoking-status-current',1,'59978006',NULL,'Cigar smoker (life style)'),('smoking-status-current',1,'446172000',NULL,'Failed attempt to stop smoking (finding)'),('smoking-status-current',1,'413173009',NULL,'Minutes from waking to first tobacco consumption (observable entity)'),('smoking-status-current',1,'401201003',NULL,'Cigarette pack-years (observable entity)'),('smoking-status-current',1,'401159003',NULL,'Reason for restarting smoking (observable entity)'),('smoking-status-current',1,'308438006',NULL,'Smoking restarted (life style)'),('smoking-status-current',1,'230058003',NULL,'Pipe tobacco consumption (observable entity)'),('smoking-status-current',1,'134406006',NULL,'Smoking reduced (observable entity)'),('smoking-status-current',1,'82302008',NULL,'Pipe smoker (life style)'),('smoking-status-current',1,'56578002',NULL,'Moderate smoker (20 or less per day) (finding)'),('smoking-status-current',1,'56771006',NULL,'Heavy smoker (over 20 per day) (finding)'),('smoking-status-current',1,'160613002',NULL,'Admitted tobacco consumption possibly untrue'),('smoking-status-current',1,'230060001',NULL,'Light cigarette smoker (finding)'),('smoking-status-current',1,'230062009',NULL,'Moderate cigarette smoker (finding)'),('smoking-status-current',1,'230063004',NULL,'Heavy cigarette smoker (finding)'),('smoking-status-current',1,'230064005',NULL,'Very heavy cigarette smoker (finding)'),('smoking-status-current',1,'230065006',NULL,'Chain smoker (finding)'),('smoking-status-current',1,'449868002',NULL,'Smokes tobacco daily (finding)'),('smoking-status-current',1,'203191000000107',NULL,'Wants to stop smoking'),('smoking-status-current',1,'228487000',NULL,'Total time smoked (observable entity)'),('smoking-status-current',1,'228488005',NULL,'Age at starting smoking (observable entity)'),('smoking-status-current',1,'864091000000103',NULL,'Number of previous attempts to stop smoking'),('smoking-status-current',1,'1092481000000104',NULL,'Number of calculated smoking pack years (observable entity)'),('smoking-status-current',1,'26663004',NULL,'Cigar smoking tobacco (substance)'),('smoking-status-current',1,'66562002',NULL,'Cigarette smoking tobacco (substance)'),('smoking-status-current',1,'84498003',NULL,'Pipe smoking tobacco (substance)'),('smoking-status-current',1,'698289004',NULL,'Hookah pipe smoker (finding)');
INSERT INTO #codessnomed
VALUES ('smoking-status-currently-not',1,'160618006',NULL,'Current non-smoker (life style)'),('smoking-status-currently-not',1,'8392000',NULL,'Non-smoker (life style)'),('smoking-status-currently-not',1,'87739003',NULL,'Tolerant non-smoker (finding)'),('smoking-status-currently-not',1,'105539002',NULL,'Non-smoker for personal reasons (finding)'),('smoking-status-currently-not',1,'105540000',NULL,'Non-smoker for religious reasons (finding)'),('smoking-status-currently-not',1,'105541001',NULL,'Non-smoker for medical reasons (finding)'),('smoking-status-currently-not',1,'360918006',NULL,'Aggressive non-smoker (finding)'),('smoking-status-currently-not',1,'360929005',NULL,'Intolerant non-smoker (finding)'),('smoking-status-currently-not',1,'405746006',NULL,'Current non smoker but past smoking history unknown');
INSERT INTO #codessnomed
VALUES ('smoking-status-ex',1,'160617001',NULL,'Stopped smoking (life style)'),('smoking-status-ex',1,'160620009',NULL,'Ex-pipe smoker (life style)'),('smoking-status-ex',1,'160621008',NULL,'Ex-cigar smoker (life style)'),('smoking-status-ex',1,'160625004',NULL,'Date ceased smoking (observable entity)'),('smoking-status-ex',1,'266922007',NULL,'Ex-light cigarette smoker (1-9/day) (life style)'),('smoking-status-ex',1,'266923002',NULL,'Ex-moderate cigarette smoker (10-19/day) (life style)'),('smoking-status-ex',1,'266924008',NULL,'Ex-heavy cigarette smoker (20-39/day) (life style)'),('smoking-status-ex',1,'266925009',NULL,'Ex-very heavy cigarette smoker (40+/day) (life style)'),('smoking-status-ex',1,'281018007',NULL,'Ex-cigarette smoker (life style)'),('smoking-status-ex',1,'395177003',NULL,'Smoking free weeks (observable entity)'),('smoking-status-ex',1,'492191000000103',NULL,'Ex roll-up cigarette smoker (finding)'),('smoking-status-ex',1,'517211000000106',NULL,'Recently stopped smoking (finding)'),('smoking-status-ex',1,'8517006',NULL,'Ex-smoker (life style)'),('smoking-status-ex',1,'53896009',NULL,'Tolerant ex-smoker (finding)'),('smoking-status-ex',1,'266928006',NULL,'Ex-cigarette smoker amount unknown (finding)'),('smoking-status-ex',1,'360890004',NULL,'Intolerant ex-smoker (finding)'),('smoking-status-ex',1,'360900008',NULL,'Aggressive ex-smoker (finding)'),('smoking-status-ex',1,'735128000',NULL,'Ex-smoker for less than 1 year'),('smoking-status-ex',1,'1092031000000108',NULL,'Ex-smoker amount unknown (finding)'),('smoking-status-ex',1,'1092041000000104',NULL,'Ex-very heavy smoker (40+/day) (finding)'),('smoking-status-ex',1,'1092071000000105',NULL,'Ex-heavy smoker (20-39/day) (finding)'),('smoking-status-ex',1,'1092091000000109',NULL,'Ex-moderate smoker (10-19/day) (finding)'),('smoking-status-ex',1,'1092111000000104',NULL,'Ex-light smoker (1-9/day) (finding)'),('smoking-status-ex',1,'48031000119106',NULL,'Ex-smoker for more than 1 year'),('smoking-status-ex',1,'449369001',NULL,'Stopped smoking before pregnancy'),('smoking-status-ex',1,'228486009',NULL,'Time since stopped smoking (observable entity)');
INSERT INTO #codessnomed
VALUES ('smoking-status-ex-trivial',1,'266921000',NULL,'Ex-trivial cigarette smoker (<1/day) (life style)'),('smoking-status-ex-trivial',1,'1092131000000107',NULL,'Ex-trivial smoker (<1/day) (finding)');
INSERT INTO #codessnomed
VALUES ('smoking-status-never',1,'160601007',NULL,'Non-smoker (& [never smoked tobacco])'),('smoking-status-never',1,'266919005',NULL,'Never smoked tobacco (life style)'),('smoking-status-never',1,'221000119102',NULL,'Never smoked any substance (finding)');
INSERT INTO #codessnomed
VALUES ('smoking-status-passive',1,'43381005',NULL,'Passive smoker (finding)'),('smoking-status-passive',1,'161080002',NULL,'Passive smoking risk (environment)'),('smoking-status-passive',1,'228523000',NULL,'Exposed to tobacco smoke at work (finding)'),('smoking-status-passive',1,'228524006',NULL,'Exposed to tobacco smoke at home (finding)'),('smoking-status-passive',1,'228525007',NULL,'Exposed to tobacco smoke in public places (finding)'),('smoking-status-passive',1,'713142003',NULL,'At risk from passive smoking (finding)'),('smoking-status-passive',1,'722451000000101',NULL,'Passive smoking (qualifier value)'),('smoking-status-passive',1,'1104241000000108',NULL,'Ex-smoker in household (situation)'),('smoking-status-passive',1,'94151000119101',NULL,'Smoker in home environment');
INSERT INTO #codessnomed
VALUES ('smoking-status-trivial',1,'266920004',NULL,'Trivial cigarette smoker (less than one cigarette/day) (life style)'),('smoking-status-trivial',1,'428041000124106',NULL,'Occasional tobacco smoker (finding)'),('smoking-status-trivial',1,'230059006',NULL,'Occasional cigarette smoker (finding)');
INSERT INTO #codessnomed
VALUES ('creatinine',1,'1000731000000107',NULL,'Serum creatinine level (observable entity)'),('creatinine',1,'1106601000000100',NULL,'Substance concentration of creatinine in plasma (observable entity)'),('creatinine',1,'1109421000000104',NULL,'Substance concentration of creatinine in plasma using colorimetric analysis (observable entity)'),('creatinine',1,'1109431000000102',NULL,'Substance concentration of creatinine in plasma using enzymatic analysis (observable entity)'),('creatinine',1,'1109441000000106',NULL,'Substance concentration of creatinine in serum using colorimetric analysis (observable entity)'),('creatinine',1,'1000981000000109',NULL,'Corrected plasma creatinine level (observable entity)'),('creatinine',1,'1000991000000106',NULL,'Corrected serum creatinine level (observable entity)'),('creatinine',1,'1001011000000107',NULL,'Plasma creatinine level (observable entity)'),('creatinine',1,'1107001000000108',NULL,'Substance concentration of creatinine in serum (observable entity)'),('creatinine',1,'1109451000000109',NULL,'Substance concentration of creatinine in serum using enzymatic analysis (observable entity)'),('creatinine',1,'53641000237107',NULL,'Corrected mass concentration of creatinine in plasma (observable entity)');
INSERT INTO #codessnomed
VALUES ('egfr',1,'1011481000000105',NULL,'eGFR (estimated glomerular filtration rate) using creatinine Chronic Kidney Disease Epidemiology Collaboration equation per 1.73 square metres'),('egfr',1,'1011491000000107',NULL,'eGFR (estimated glomerular filtration rate) using cystatin C Chronic Kidney Disease Epidemiology Collaboration equation per 1.73 square metres'),('egfr',1,'1020291000000106',NULL,'GFR (glomerular filtration rate) calculated by abbreviated Modification of Diet in Renal Disease Study Group calculation'),('egfr',1,'1107411000000104',NULL,'eGFR (estimated glomerular filtration rate) by laboratory calculation'),('egfr',1,'241373003',NULL,'Technetium-99m-diethylenetriamine pentaacetic acid clearance - glomerular filtration rate (procedure)'),('egfr',1,'262300005',NULL,'With glomerular filtration rate'),('egfr',1,'737105002',NULL,'GFR (glomerular filtration rate) calculation technique'),('egfr',1,'80274001',NULL,'Glomerular filtration rate (observable entity)'),('egfr',1,'996231000000108',NULL,'GFR (glomerular filtration rate) calculated by abbreviated Modification of Diet in Renal Disease Study Group calculation adjusted for African American origin'),('egfr',1,'857971000000104',NULL,'Estimated glomerular filtration rate using Chronic Kidney Disease Epidemiology Collaboration formula (observable entity)'),('egfr',1,'963601000000106',NULL,'Estimated glomerular filtration rate using cystatin C Chronic Kidney Disease Epidemiology Collaboration equation (observable entity)'),('egfr',1,'963611000000108',NULL,'Estimated glomerular filtration rate using cystatin C per 1.73 square metres'),('egfr',1,'963621000000102',NULL,'Estimated glomerular filtration rate using creatinine Chronic Kidney Disease Epidemiology Collaboration equation (observable entity)'),('egfr',1,'963631000000100',NULL,'Estimated glomerular filtration rate using serum creatinine per 1.73 square metres'),('egfr',1,'857981000000102',NULL,'Estimated glomerular filtration rate using Chronic Kidney Disease Epidemiology Collaboration formula per 1.73 square metres');
INSERT INTO #codessnomed
VALUES ('hdl-cholesterol',1,'1005681000000107',NULL,'Serum high density lipoprotein cholesterol level (observable entity)'),('hdl-cholesterol',1,'1010581000000101',NULL,'Plasma high density lipoprotein cholesterol level (observable entity)'),('hdl-cholesterol',1,'1026461000000104',NULL,'Serum random high density lipoprotein cholesterol level (observable entity)'),('hdl-cholesterol',1,'1107661000000104',NULL,'Substance concentration of high density lipoprotein cholesterol in plasma (observable entity)'),('hdl-cholesterol',1,'1028831000000106',NULL,'Plasma random high density lipoprotein cholesterol level (observable entity)'),('hdl-cholesterol',1,'1107681000000108',NULL,'Substance concentration of high density lipoprotein cholesterol in serum (observable entity)'),('hdl-cholesterol',1,'1026451000000102',NULL,'Serum fasting high density lipoprotein cholesterol level (observable entity)'),('hdl-cholesterol',1,'1028841000000102',NULL,'Plasma fasting high density lipoprotein cholesterol level (observable entity)');
INSERT INTO #codessnomed
VALUES ('ldl-cholesterol',1,'1010591000000104',NULL,'Plasma low density lipoprotein cholesterol level (observable entity)'),('ldl-cholesterol',1,'1014501000000104',NULL,'Calculated low density lipoprotein cholesterol level (observable entity)'),('ldl-cholesterol',1,'1022191000000100',NULL,'Serum low density lipoprotein cholesterol level (observable entity)'),('ldl-cholesterol',1,'1026471000000106',NULL,'Serum fasting low density lipoprotein cholesterol level (observable entity)'),('ldl-cholesterol',1,'1026481000000108',NULL,'Serum random low density lipoprotein cholesterol level (observable entity)'),('ldl-cholesterol',1,'53981000237105',NULL,'Substance concentration of low density lipoprotein cholesterol in plasma (observable entity)'),('ldl-cholesterol',1,'1108541000000100',NULL,'Substance concentration of low density lipoprotein cholesterol in plasma (observable entity)'),('ldl-cholesterol',1,'1108551000000102',NULL,'Substance concentration of low density lipoprotein cholesterol in serum (observable entity)'),('ldl-cholesterol',1,'1028861000000101',NULL,'Plasma fasting low density lipoprotein cholesterol level (observable entity)'),('ldl-cholesterol',1,'1028851000000104',NULL,'Plasma random low density lipoprotein cholesterol level (observable entity)'),('ldl-cholesterol',1,'55621000237101',NULL,'Substance concentration of low density lipoprotein cholesterol in serum (observable entity)');
INSERT INTO #codessnomed
VALUES ('triglycerides',1,'1028871000000108',NULL,'Plasma random triglyceride level (observable entity)'),('triglycerides',1,'1031321000000109',NULL,'Plasma fasting triglyceride level (observable entity)'),('triglycerides',1,'850991000000104',NULL,'Triglyceride level (observable entity)'),('triglycerides',1,'1005691000000109',NULL,'Serum triglycerides level (observable entity)'),('triglycerides',1,'1109831000000104',NULL,'Substance concentration of triglyceride in serum (observable entity)'),('triglycerides',1,'1026491000000105',NULL,'Serum fasting triglyceride level (observable entity)'),('triglycerides',1,'1010601000000105',NULL,'Plasma triglyceride level (observable entity)'),('triglycerides',1,'1461000237101',NULL,'Substance concentration of triglyceride in serum (observable entity)'),('triglycerides',1,'1026501000000104',NULL,'Serum random triglyceride level (observable entity)'),('triglycerides',1,'1109821000000101',NULL,'Substance concentration of triglyceride in plasma (observable entity)'),('triglycerides',1,'365796000',NULL,'Finding of serum triglyceride levels (finding)'),('triglycerides',1,'271245006',NULL,'Measurement of serum triglyceride level (procedure)')

INSERT INTO #AllCodes
SELECT [concept], [version], [code], [description] from #codessnomed;

IF OBJECT_ID('tempdb..#codesemis') IS NOT NULL DROP TABLE #codesemis;
CREATE TABLE #codesemis (
  [concept] [varchar](255) NOT NULL,
  [version] INT NOT NULL,
	[code] [varchar](20) COLLATE Latin1_General_CS_AS NOT NULL,
	[term] [varchar](20) COLLATE Latin1_General_CS_AS NULL,
	[description] [varchar](255) NULL
) ON [PRIMARY];

INSERT INTO #codesemis
VALUES ('chronic-kidney-disease',1,'EMISNQCH20',NULL,'Chronic kidney disease stage 3'),('chronic-kidney-disease',1,'EMISNQCH17',NULL,'Chronic kidney disease stage');
INSERT INTO #codesemis
VALUES ('ckd-stage-3',1,'^ESCTAN821240',NULL,'Anaemia co-occurrent and due to chronic kidney disease stage 3'),('ckd-stage-3',1,'^ESCTAN821241',NULL,'Anemia co-occurrent and due to chronic kidney disease stage 3'),('ckd-stage-3',1,'^ESCTCH796669',NULL,'Chronic kidney disease stage 3 due to type 2 diabetes mellitus'),('ckd-stage-3',1,'^ESCTCH796671',NULL,'Chronic kidney disease stage 3 due to type II diabetes mellitus'),('ckd-stage-3',1,'^ESCTCH802745',NULL,'Chronic kidney disease stage 3 due to type 1 diabetes mellitus'),('ckd-stage-3',1,'^ESCTCH802746',NULL,'Chronic kidney disease stage 3 due to type I diabetes mellitus'),('ckd-stage-3',1,'^ESCTCH804068',NULL,'Chronic kidney disease stage 3 due to hypertension'),('ckd-stage-3',1,'^ESCTCH808707',NULL,'Chronic kidney disease stage 3 due to benign hypertension'),('ckd-stage-3',1,'^ESCTCH834588',NULL,'Chronic kidney disease with glomerular filtration rate category G3a and albuminuria category A1'),('ckd-stage-3',1,'^ESCTCH834590',NULL,'Chronic kidney disease with glomerular filtration rate category G3a and albuminuria category A2'),('ckd-stage-3',1,'^ESCTCH834593',NULL,'Chronic kidney disease with glomerular filtration rate category G3a and albuminuria category A3'),('ckd-stage-3',1,'^ESCTCH834600',NULL,'Chronic kidney disease with glomerular filtration rate category G3b and albuminuria category A1'),('ckd-stage-3',1,'^ESCTCH834602',NULL,'Chronic kidney disease with glomerular filtration rate category G3b and albuminuria category A2'),('ckd-stage-3',1,'^ESCTCH834604',NULL,'Chronic kidney disease with glomerular filtration rate category G3b and albuminuria category A3'),('ckd-stage-3',1,'^ESCTCK717479',NULL,'CKD stage 3'),('ckd-stage-3',1,'^ESCTCK810423',NULL,'CKD (chronic kidney disease) stage 3 with proteinuria'),('ckd-stage-3',1,'^ESCTCK810426',NULL,'CKD (chronic kidney disease) stage 3 without proteinuria'),('ckd-stage-3',1,'^ESCTCK810430',NULL,'CKD (chronic kidney disease) stage 3A with proteinuria'),('ckd-stage-3',1,'^ESCTCK810435',NULL,'CKD (chronic kidney disease) stage 3A without proteinuria'),('ckd-stage-3',1,'^ESCTCK810438',NULL,'CKD (chronic kidney disease) stage 3B with proteinuria'),('ckd-stage-3',1,'^ESCTCK810441',NULL,'CKD (chronic kidney disease) stage 3B without proteinuria'),('ckd-stage-3',1,'^ESCTDI796670',NULL,'Diabetic stage 3 chronic renal impairment due to type 2 diabetes mellitus'),('ckd-stage-3',1,'^ESCTHY803043',NULL,'Hypertensive heart AND chronic kidney disease stage 3'),('ckd-stage-3',1,'^ESCTHY804406',NULL,'Hypertension in chronic kidney disease stage 3 due to type 2 diabetes mellitus'),('ckd-stage-3',1,'^ESCTHY804407',NULL,'Hypertension in chronic kidney disease stage 3 due to type II diabetes mellitus'),('ckd-stage-3',1,'^ESCTMA808769',NULL,'Malignant hypertensive chronic kidney disease stage 3');
INSERT INTO #codesemis
VALUES ('ckd-stage-4',1,'^ESCTAN821231',NULL,'Anaemia in chronic kidney disease stage 4'),('ckd-stage-4',1,'^ESCTAN821232',NULL,'Anemia co-occurrent and due to chronic kidney disease stage 4'),('ckd-stage-4',1,'^ESCTAN821233',NULL,'Anemia in chronic kidney disease stage 4'),('ckd-stage-4',1,'^ESCTAN821234',NULL,'Anaemia co-occurrent and due to chronic kidney disease stage 4'),('ckd-stage-4',1,'^ESCTCH796664',NULL,'Chronic kidney disease stage 4 due to type 2 diabetes mellitus'),('ckd-stage-4',1,'^ESCTCH796666',NULL,'Chronic kidney disease stage 4 due to type II diabetes mellitus'),('ckd-stage-4',1,'^ESCTCH802747',NULL,'Chronic kidney disease stage 4 due to type 1 diabetes mellitus'),('ckd-stage-4',1,'^ESCTCH802748',NULL,'Chronic kidney disease stage 4 due to type I diabetes mellitus'),('ckd-stage-4',1,'^ESCTCH804066',NULL,'Chronic kidney disease stage 4 due to hypertension'),('ckd-stage-4',1,'^ESCTCH808708',NULL,'Chronic kidney disease stage 4 due to benign hypertension'),('ckd-stage-4',1,'^ESCTCH834610',NULL,'Chronic kidney disease with glomerular filtration rate category G4 and albuminuria category A1'),('ckd-stage-4',1,'^ESCTCH834612',NULL,'Chronic kidney disease with glomerular filtration rate category G4 and albuminuria category A2'),('ckd-stage-4',1,'^ESCTCH834615',NULL,'Chronic kidney disease with glomerular filtration rate category G4 and albuminuria category A3'),('ckd-stage-4',1,'^ESCTCK714778',NULL,'CKD stage 4'),('ckd-stage-4',1,'^ESCTCK810445',NULL,'CKD (chronic kidney disease) stage 4 with proteinuria'),('ckd-stage-4',1,'^ESCTCK810448',NULL,'CKD (chronic kidney disease) stage 4 without proteinuria'),('ckd-stage-4',1,'^ESCTDI796665',NULL,'Diabetic stage 4 chronic renal impairment due to type 2 diabetes mellitus'),('ckd-stage-4',1,'^ESCTHY803042',NULL,'Hypertensive heart AND chronic kidney disease stage 4'),('ckd-stage-4',1,'^ESCTHY804404',NULL,'Hypertension in chronic kidney disease stage 4 due to type 2 diabetes mellitus'),('ckd-stage-4',1,'^ESCTHY804405',NULL,'Hypertension in chronic kidney disease stage 4 due to type II diabetes mellitus'),('ckd-stage-4',1,'^ESCTMA808770',NULL,'Malignant hypertensive chronic kidney disease stage 4');
INSERT INTO #codesemis
VALUES ('ckd-stage-5',1,'^ESCT1192455',NULL,'End-stage renal disease'),('ckd-stage-5',1,'^ESCT1270447',NULL,'End-stage renal disease'),('ckd-stage-5',1,'^ESCT1371635',NULL,'Dependence on continuous ambulatory peritoneal dialysis due to end stage renal disease'),('ckd-stage-5',1,'^ESCTAN761537',NULL,'Anaemia in end stage renal disease'),('ckd-stage-5',1,'^ESCTAN761538',NULL,'Anemia in end stage renal disease'),('ckd-stage-5',1,'^ESCTAN761539',NULL,'Anemia co-occurrent and due to end stage renal disease'),('ckd-stage-5',1,'^ESCTAN761540',NULL,'Anaemia co-occurrent and due to end stage renal disease'),('ckd-stage-5',1,'^ESCTAN821236',NULL,'Anaemia in chronic kidney disease stage 5'),('ckd-stage-5',1,'^ESCTAN821237',NULL,'Anemia co-occurrent and due to chronic kidney disease stage 5'),('ckd-stage-5',1,'^ESCTAN821238',NULL,'Anaemia co-occurrent and due to chronic kidney disease stage 5'),('ckd-stage-5',1,'^ESCTAN821239',NULL,'Anemia in chronic kidney disease stage 5'),('ckd-stage-5',1,'^ESCTCH771489',NULL,'Chronic kidney disease stage 5 on dialysis'),('ckd-stage-5',1,'^ESCTCH771490',NULL,'Chronic kidney disease 5d'),('ckd-stage-5',1,'^ESCTCH771492',NULL,'Chronic kidney disease stage 5 with transplant'),('ckd-stage-5',1,'^ESCTCH771493',NULL,'Chronic kidney disease 5t'),('ckd-stage-5',1,'^ESCTCH796661',NULL,'Chronic kidney disease stage 5 due to type 2 diabetes mellitus'),('ckd-stage-5',1,'^ESCTCH796663',NULL,'Chronic kidney disease stage 5 due to type II diabetes mellitus'),('ckd-stage-5',1,'^ESCTCH802749',NULL,'Chronic kidney disease stage 5 due to type 1 diabetes mellitus'),('ckd-stage-5',1,'^ESCTCH802750',NULL,'Chronic kidney disease stage 5 due to type I diabetes mellitus'),('ckd-stage-5',1,'^ESCTCH804067',NULL,'Chronic kidney disease stage 5 due to hypertension'),('ckd-stage-5',1,'^ESCTCH808709',NULL,'Chronic kidney disease stage 5 due to benign hypertension'),('ckd-stage-5',1,'^ESCTCH834617',NULL,'Chronic kidney disease with glomerular filtration rate category G5 and albuminuria category A1'),('ckd-stage-5',1,'^ESCTCH834620',NULL,'Chronic kidney disease with glomerular filtration rate category G5 and albuminuria category A2'),('ckd-stage-5',1,'^ESCTCH834622',NULL,'Chronic kidney disease with glomerular filtration rate category G5 and albuminuria category A3'),('ckd-stage-5',1,'^ESCTCK717485',NULL,'CKD stage 5'),('ckd-stage-5',1,'^ESCTCK771491',NULL,'CKD (chronic kidney disease) stage 5d'),('ckd-stage-5',1,'^ESCTCK771494',NULL,'CKD (chronic kidney disease) stage 5t'),('ckd-stage-5',1,'^ESCTCK810451',NULL,'CKD (chronic kidney disease) stage 5 with proteinuria'),('ckd-stage-5',1,'^ESCTCK810455',NULL,'CKD (chronic kidney disease) stage 5 without proteinuria'),('ckd-stage-5',1,'^ESCTDE709585',NULL,'Dependence on peritoneal dialysis due to end stage renal disease'),('ckd-stage-5',1,'^ESCTDE709652',NULL,'Dependence on haemodialysis due to end stage renal disease'),('ckd-stage-5',1,'^ESCTDE709653',NULL,'Dependence on hemodialysis due to end stage renal disease'),('ckd-stage-5',1,'^ESCTDE709794',NULL,'Dependence on dialysis due to end stage renal disease'),('ckd-stage-5',1,'^ESCTDI796662',NULL,'Diabetic stage 5 chronic renal impairment due to type 2 diabetes mellitus'),('ckd-stage-5',1,'^ESCTEN324584',NULL,'End stage kidney disease'),('ckd-stage-5',1,'^ESCTEN324588',NULL,'End stage chronic renal failure'),('ckd-stage-5',1,'^ESCTEN509415',NULL,'End stage renal failure untreated by renal replacement therapy'),('ckd-stage-5',1,'^ESCTEN509416',NULL,'End stage renal failure on dialysis'),('ckd-stage-5',1,'^ESCTEN509417',NULL,'End stage renal failure with renal transplant'),('ckd-stage-5',1,'^ESCTEN769149',NULL,'End stage renal disease due to benign hypertension'),('ckd-stage-5',1,'^ESCTEN803525',NULL,'End stage renal disease due to hypertension'),('ckd-stage-5',1,'^ESCTEN804800',NULL,'End stage renal disease on dialysis due to hypertension'),('ckd-stage-5',1,'^ESCTES324585',NULL,'ESRF - End stage renal failure'),('ckd-stage-5',1,'^ESCTES324586',NULL,'ESCRF - End stage chronic renal failure'),('ckd-stage-5',1,'^ESCTES324587',NULL,'ESRD - End stage renal disease'),('ckd-stage-5',1,'^ESCTES769150',NULL,'ESRD (End stage renal disease) due to benign hypertension'),('ckd-stage-5',1,'^ESCTES803526',NULL,'ESRD (End stage renal disease) due to hypertension'),('ckd-stage-5',1,'^ESCTHY803041',NULL,'Hypertensive heart AND chronic kidney disease stage 5'),('ckd-stage-5',1,'^ESCTHY804401',NULL,'Hypertension in chronic kidney disease stage 5 due to type 2 diabetes mellitus'),('ckd-stage-5',1,'^ESCTHY804402',NULL,'Hypertension in chronic kidney disease stage 5 due to type II diabetes mellitus'),('ckd-stage-5',1,'^ESCTMA804797',NULL,'Malignant hypertensive chronic kidney disease stage 5'),('ckd-stage-5',1,'^ESCTMA808765',NULL,'Malignant hypertensive end stage renal disease'),('ckd-stage-5',1,'^ESCTMA808813',NULL,'Malignant hypertensive end stage renal disease on dialysis');
INSERT INTO #codesemis
VALUES ('sle',1,'^ESCTBU514089',NULL,'Bullous systemic lupus erythematosus'),('sle',1,'^ESCTCD512809',NULL,'CDLE - Chronic discoid lupus erythematosus'),('sle',1,'^ESCTCE406029',NULL,'Cerebral systemic lupus erythematosus'),('sle',1,'^ESCTCH512808',NULL,'Chronic discoid lupus erythematosus'),('sle',1,'^ESCTCH512810',NULL,'Chilblain lupus erythematosus'),('sle',1,'^ESCTDI378949',NULL,'Discoid lupus erythematosus of eyelid'),('sle',1,'^ESCTDI378950',NULL,'Discoid lupus erythematosus eyelid'),('sle',1,'^ESCTDI378951',NULL,'Discoid lupus eyelid'),('sle',1,'^ESCTDL480563',NULL,'DLE - Discoid lupus erythematosus'),('sle',1,'^ESCTLE480559',NULL,'LE - Lupus erythematosus'),('sle',1,'^ESCTLE480564',NULL,'LE - Discoid lupus erythematosus'),('sle',1,'^ESCTLI514085',NULL,'Limited lupus erythematosus'),('sle',1,'^ESCTLU257360',NULL,'Lupus nephritis - WHO Class II'),('sle',1,'^ESCTLU267516',NULL,'Lupus with glomerular sclerosis'),('sle',1,'^ESCTLU267517',NULL,'Lupus nephritis - WHO Class VI'),('sle',1,'^ESCTLU273907',NULL,'Lupus profundus'),('sle',1,'^ESCTLU308669',NULL,'Lupus nephritis - WHO Class IV'),('sle',1,'^ESCTLU334360',NULL,'Lupus nephritis - WHO Class V'),('sle',1,'^ESCTLU369178',NULL,'Lupus nephritis - WHO Class I'),('sle',1,'^ESCTLU374466',NULL,'Lupus nephritis - WHO Class III'),('sle',1,'^ESCTLU406027',NULL,'Lupus encephalopathy'),('sle',1,'^ESCTLU480560',NULL,'Lupus'),('sle',1,'^ESCTLU512806',NULL,'Lupus erythematosus and erythema multiforme-like syndrome'),('sle',1,'^ESCTLU514088',NULL,'Lupus panniculitis'),('sle',1,'^ESCTME334359',NULL,'Membranous lupus glomerulonephritis'),('sle',1,'^ESCTNE405966',NULL,'Neonatal lupus'),('sle',1,'^ESCTRO512807',NULL,'Rowells syndrome'),('sle',1,'^ESCTSA514093',NULL,'SACLE - Subacute cutaneous lupus erythematosus'),('sle',1,'^ESCTSC514092',NULL,'SCLE - Subacute cutaneous lupus erythematosus'),('sle',1,'^ESCTSK514086',NULL,'Skin and joint lupus'),('sle',1,'^ESCTSL257358',NULL,'SLE glomerulonephritis syndrome, WHO class II'),('sle',1,'^ESCTSL257359',NULL,'SLE with mesangial proliferative glomerulonephritis'),('sle',1,'^ESCTSL267514',NULL,'SLE glomerulonephritis syndrome, WHO class VI'),('sle',1,'^ESCTSL267515',NULL,'SLE with advanced sclerosing glomerulonephritis'),('sle',1,'^ESCTSL308667',NULL,'SLE glomerulonephritis syndrome, WHO class IV'),('sle',1,'^ESCTSL308668',NULL,'SLE with diffuse proliferative glomerulonephritis'),('sle',1,'^ESCTSL334357',NULL,'SLE glomerulonephritis syndrome, WHO class V'),('sle',1,'^ESCTSL334358',NULL,'SLE with membranous glomerulonephritis'),('sle',1,'^ESCTSL340060',NULL,'SLE - Systemic lupus erythematosus'),('sle',1,'^ESCTSL361922',NULL,'SLE glomerulonephritis syndrome'),('sle',1,'^ESCTSL369176',NULL,'SLE glomerulonephritis syndrome, WHO class I'),('sle',1,'^ESCTSL369177',NULL,'SLE with normal kidneys'),('sle',1,'^ESCTSL374464',NULL,'SLE glomerulonephritis syndrome, WHO class III'),('sle',1,'^ESCTSL374465',NULL,'SLE with focal AND segmental proliferative glomerulonephritis'),('sle',1,'^ESCTSY257361',NULL,'Systemic lupus erythematosus glomerulonephritis syndrome, World Health Organisation (WHO) class II'),('sle',1,'^ESCTSY257362',NULL,'Systemic lupus erythematosus glomerulonephritis syndrome, World Health Organization (WHO) class II'),('sle',1,'^ESCTSY257363',NULL,'Systemic lupus erythematosus glomerulonephritis syndrome, World Health Organization class II'),('sle',1,'^ESCTSY267518',NULL,'Systemic lupus erythematosus glomerulonephritis syndrome, World Health Organisation (WHO) class VI'),('sle',1,'^ESCTSY267519',NULL,'Systemic lupus erythematosus glomerulonephritis syndrome, World Health Organization (WHO) class VI'),('sle',1,'^ESCTSY267520',NULL,'Systemic lupus erythematosus glomerulonephritis syndrome, World Health Organization class VI'),('sle',1,'^ESCTSY308670',NULL,'Systemic lupus erythematosus glomerulonephritis syndrome, World Health Organisation (WHO) class IV'),('sle',1,'^ESCTSY308671',NULL,'Systemic lupus erythematosus glomerulonephritis syndrome, World Health Organization (WHO) class IV'),('sle',1,'^ESCTSY308672',NULL,'Systemic lupus erythematosus glomerulonephritis syndrome, World Health Organization class IV'),('sle',1,'^ESCTSY334361',NULL,'Systemic lupus erythematosus glomerulonephritis syndrome, World Health Organisation (WHO) class V'),('sle',1,'^ESCTSY334362',NULL,'Systemic lupus erythematosus glomerulonephritis syndrome, World Health Organization (WHO) class V'),('sle',1,'^ESCTSY334363',NULL,'Systemic lupus erythematosus glomerulonephritis syndrome, World Health Organization class V'),('sle',1,'^ESCTSY361924',NULL,'Systemic lupus erythematosus glomerulonephritis syndrome'),('sle',1,'^ESCTSY369179',NULL,'Systemic lupus erythematosus glomerulonephritis syndrome, World Health Organisation (WHO) class I'),('sle',1,'^ESCTSY369180',NULL,'Systemic lupus erythematosus glomerulonephritis syndrome, World Health Organization (WHO) class I'),('sle',1,'^ESCTSY369181',NULL,'Systemic lupus erythematosus glomerulonephritis syndrome, World Health Organization class I'),('sle',1,'^ESCTSY374467',NULL,'Systemic lupus erythematosus glomerulonephritis syndrome, World Health Organization (WHO) class III'),('sle',1,'^ESCTSY374468',NULL,'Systemic lupus erythematosus glomerulonephritis syndrome, World Health Organisation (WHO) class III'),('sle',1,'^ESCTSY374469',NULL,'Systemic lupus erythematosus glomerulonephritis syndrome, World Health Organization class III'),('sle',1,'^ESCTSY514090',NULL,'Systemic lupus erythematosus with multisystem involvement'),('sle',1,'EMISNQSY6',NULL,'Systemic lupus erythematosus encephalitis'),('sle',1,'^ESCT1185132',NULL,'Pericarditis co-occurrent and due to systemic lupus erythematosus'),('sle',1,'^ESCT1352191',NULL,'Autosomal systemic lupus erythematosus'),('sle',1,'^ESCT1352192',NULL,'Autosomal SLE (systemic lupus erythematosus)'),('sle',1,'^ESCT1352193',NULL,'Familial systemic lupus erythematosus'),('sle',1,'^ESCT1406104',NULL,'Lupus-like syndrome'),('sle',1,'^ESCTAC668182',NULL,'Acute systemic lupus erythematosus'),('sle',1,'^ESCTAN668204',NULL,'Anetoderma secondary to lupus erythematosus'),('sle',1,'^ESCTBU405493',NULL,'Butterfly rash associated with systemic lupus'),('sle',1,'^ESCTCA668207',NULL,'Calcinosis secondary to lupus erythematosus'),('sle',1,'^ESCTCH500611',NULL,'Chorea in systemic lupus erythematosus'),('sle',1,'^ESCTCH786098',NULL,'Chorea co-occurrent and due to systemic lupus erythematosus'),('sle',1,'^ESCTCH786099',NULL,'Chorea with systemic lupus erythematosus'),('sle',1,'^ESCTCH815523',NULL,'Cheilitis due to lupus erythematosus'),('sle',1,'^ESCTDE786120',NULL,'Demyelination of central nervous system co-occurrent and due to systemic lupus erythematosus'),('sle',1,'^ESCTDE786121',NULL,'Demyelination with systemic lupus erythematosus'),('sle',1,'^ESCTDI308784',NULL,'Dilated cardiomyopathy secondary to systemic lupus erythematosus'),('sle',1,'^ESCTDR380552',NULL,'Drug-induced lupus erythematosus'),('sle',1,'^ESCTEN802262',NULL,'Endocarditis due to systemic lupus erythematosus'),('sle',1,'^ESCTFU668183',NULL,'Fulminating systemic lupus erythematosus'),('sle',1,'^ESCTGI770137',NULL,'Gingival disease co-occurrent and due to lupus erythematosus'),('sle',1,'^ESCTGL809990',NULL,'Glomerular disease due to systemic lupus erythematosus'),('sle',1,'^ESCTGL809991',NULL,'Glomerular disease due to SLE (systemic lupus erythematosus)'),('sle',1,'^ESCTHA795184',NULL,'Haemolytic anaemia associated with systemic lupus erythematosus'),('sle',1,'^ESCTHE795185',NULL,'Hemolytic anemia associated with systemic lupus erythematosus'),('sle',1,'^ESCTHY668210',NULL,'Hypermelanosis due to lupus erythematosus'),('sle',1,'^ESCTLU281251',NULL,'Lupus hepatitis'),('sle',1,'^ESCTLU281252',NULL,'Lupoid hepatitis'),('sle',1,'^ESCTLU376503',NULL,'Lupus disease of the lung'),('sle',1,'^ESCTLU505500',NULL,'Lupus pneumonia'),('sle',1,'^ESCTLU505501',NULL,'Lupoid pneumonia'),('sle',1,'^ESCTLU514173',NULL,'Lupus vasculitis'),('sle',1,'^ESCTLU514175',NULL,'Lupus erythematosus-associated vasculitis'),('sle',1,'^ESCTLU666906',NULL,'Lupus erythematosus overlap syndrome'),('sle',1,'^ESCTLU668203',NULL,'Lupus erythematosus-associated anetoderma'),('sle',1,'^ESCTLU668206',NULL,'Lupus erythematosus-associated calcinosis'),('sle',1,'^ESCTLU668208',NULL,'Lupus erythematosus-associated papulonodular mucinosis'),('sle',1,'^ESCTLU668209',NULL,'Lupus erythematosus-associated hypermelanosis'),('sle',1,'^ESCTLU668211',NULL,'Lupus erythematosus-associated nailfold telangiectasia'),('sle',1,'^ESCTLU668213',NULL,'Lupus erythematosus-associated urticarial vasculitis'),('sle',1,'^ESCTLU668215',NULL,'Lupus erythematosus-associated necrotising vasculitis'),('sle',1,'^ESCTLU668216',NULL,'Lupus erythematosus-associated necrotizing vasculitis'),('sle',1,'^ESCTLU668219',NULL,'Lupus erythematosus-associated poikiloderma'),('sle',1,'^ESCTLU668221',NULL,'Lupus erythematosus-associated nail dystrophy'),('sle',1,'^ESCTLU761502',NULL,'Lupus erythematosus of oral mucous membrane'),('sle',1,'^ESCTLU761503',NULL,'Lupus erythematosus of oral mucosa'),('sle',1,'^ESCTLU815524',NULL,'Lupus cheilitis'),('sle',1,'^ESCTNA668222',NULL,'Nail dystrophy due to lupus erythematosus'),('sle',1,'^ESCTNE668217',NULL,'Necrotising vasculitis due to lupus erythematosus'),('sle',1,'^ESCTNE668218',NULL,'Necrotizing vasculitis due to lupus erythematosus'),('sle',1,'^ESCTNE809113',NULL,'Nephropathy co-occurrent and due to systemic lupus erythematosus'),('sle',1,'^ESCTNE809115',NULL,'Nephrotic syndrome co-occurrent and due to systemic lupus erythematosus'),('sle',1,'^ESCTNE809116',NULL,'Nephrosis co-occurrent and due to systemic lupus erythematosus'),('sle',1,'^ESCTNE809117',NULL,'Nephrosis with systemic lupus erythematosus'),('sle',1,'^ESCTPE290594',NULL,'Pericarditis secondary to systemic lupus erythematosus'),('sle',1,'^ESCTPO668220',NULL,'Poikiloderma due to lupus erythematosus'),('sle',1,'^ESCTRA405492',NULL,'Rash of systemic lupus erythematosus'),
('sle',1,'^ESCTRE690505',NULL,'Retinal vasculitis due to systemic lupus erythematosus'),('sle',1,'^ESCTSE795182',NULL,'Secondary autoimmune haemolytic anaemia co-occurrent and due to systemic lupus erythematosus'),('sle',1,'^ESCTSE795183',NULL,'Secondary autoimmune hemolytic anemia co-occurrent and due to systemic lupus erythematosus'),('sle',1,'^ESCTSL659382',NULL,'SLE - Systemic lupus erythematosus-related syndrome'),('sle',1,'^ESCTSY405618',NULL,'Systemic lupus erythematosus arthritis'),('sle',1,'^ESCTSY659381',NULL,'Systemic lupus erythematosus-related syndrome'),('sle',1,'^ESCTSY667099',NULL,'Systemic lupus erythematosus-associated antiphospholipid syndrome'),('sle',1,'^ESCTSY668184',NULL,'Systemic lupus erythematosus of childhood'),('sle',1,'^ESCTSY751150',NULL,'Systemic lupus erythematosus in remission'),('sle',1,'^ESCTSY832077',NULL,'Systemic lupus erythematosus/Sjogrens overlap syndrome'),('sle',1,'^ESCTTE668212',NULL,'Telangiectasia of nailfolds due to lupus erythematosus'),('sle',1,'^ESCTUR668214',NULL,'Urticarial vasculitis due to lupus erythematosus'),('sle',1,'^ESCTVA514174',NULL,'Vasculitis due to lupus erythematosus');
INSERT INTO #codesemis
VALUES ('tuberculosis',1,'^ESCTAR475938',NULL,'Arthritis caused by Mycobacterium tuberculosis'),('tuberculosis',1,'^ESCTCE337727',NULL,'Cervical tuberculous lymphadenitis'),('tuberculosis',1,'^ESCTCO311162',NULL,'Concato disease'),('tuberculosis',1,'^ESCTGH393589',NULL,'Ghon tubercle'),('tuberculosis',1,'^ESCTGH393590',NULL,'Ghon complex'),('tuberculosis',1,'^ESCTIN474101',NULL,'Infiltrative tuberculosis of lung'),('tuberculosis',1,'^ESCTLA364390',NULL,'Laryngeal tuberculosis'),('tuberculosis',1,'^ESCTLI265565',NULL,'Lichen scrofulosorum'),('tuberculosis',1,'^ESCTLU266735',NULL,'Lupus exedens'),('tuberculosis',1,'^ESCTLV266737',NULL,'LV - Lupus vulgaris'),('tuberculosis',1,'^ESCTMT326982',NULL,'MTB - Miliary tuberculosis'),('tuberculosis',1,'^ESCTNO381104',NULL,'Nodular tuberculosis of lung'),('tuberculosis',1,'^ESCTOC329457',NULL,'Ocular tuberculosis'),('tuberculosis',1,'^ESCTPA316295',NULL,'Papulonecrotic tuberculid'),('tuberculosis',1,'^ESCTPA316296',NULL,'Papulonecrotic tuberculide'),('tuberculosis',1,'^ESCTPO286704',NULL,'Post-tuberculous bronchiectasis'),('tuberculosis',1,'^ESCTPR304534',NULL,'Prosectors wart'),('tuberculosis',1,'^ESCTPR311161',NULL,'Progressive malignant polyserositis'),('tuberculosis',1,'^ESCTPR352961',NULL,'Primary tuberculosis'),('tuberculosis',1,'^ESCTPR352963',NULL,'Primary (TB) tuberculosis'),('tuberculosis',1,'^ESCTPR474099',NULL,'Primary progressive tuberculosis with tuberculous pleurisy'),('tuberculosis',1,'^ESCTPT451460',NULL,'PTB - Pulmonary tuberculosis'),('tuberculosis',1,'^ESCTRE276024',NULL,'Retroperitoneal tuberculosis'),('tuberculosis',1,'^ESCTSC337728',NULL,'Scrofula'),('tuberculosis',1,'^ESCTSC384703',NULL,'Scrofuloderma'),('tuberculosis',1,'^ESCTTB256970',NULL,'TB - Urogenital tuberculosis'),('tuberculosis',1,'^ESCTTB342137',NULL,'TB - Tuberculosis'),('tuberculosis',1,'^ESCTTB420023',NULL,'TB - Urinary tuberculosis'),('tuberculosis',1,'^ESCTTB451461',NULL,'TB - Pulmonary tuberculosis'),('tuberculosis',1,'^ESCTTU256969',NULL,'Tuberculosis of genitourinary system'),('tuberculosis',1,'^ESCTTU265564',NULL,'Tuberculosis cutis lichenoides'),('tuberculosis',1,'^ESCTTU266736',NULL,'Tuberculosis cutis luposa'),('tuberculosis',1,'^ESCTTU266738',NULL,'Tuberculosis lupus exedens'),('tuberculosis',1,'^ESCTTU266739',NULL,'Tuberculosis luposa cutis'),('tuberculosis',1,'^ESCTTU273007',NULL,'Tuberculous pleural empyema'),('tuberculosis',1,'^ESCTTU278008',NULL,'Tuberculosis of bones and/or joints'),('tuberculosis',1,'^ESCTTU337729',NULL,'Tuberculosis of cervical lymph nodes'),('tuberculosis',1,'^ESCTTU345467',NULL,'Tuberculous osteomyelitis'),('tuberculosis',1,'^ESCTTU364389',NULL,'Tuberculosis of larynx'),('tuberculosis',1,'^ESCTTU364391',NULL,'Tuberculosis (TB) with laryngitis'),('tuberculosis',1,'^ESCTTU371263',NULL,'Tuberculosis with erythema nodosum AND hypersensitivity reaction'),('tuberculosis',1,'^ESCTTU371264',NULL,'Tuberculosis (TB) with erythema nodosum'),('tuberculosis',1,'^ESCTTU376360',NULL,'Tuberculosis of trachea'),('tuberculosis',1,'^ESCTTU384705',NULL,'Tuberculosis colliquativa cutis'),('tuberculosis',1,'^ESCTTU389296',NULL,'Tuberculous tracheobronchial adenopathy'),('tuberculosis',1,'^ESCTTU474106',NULL,'Tuberculous pleuritis'),('tuberculosis',1,'^ESCTTU475936',NULL,'Tuberculous arthropathy'),('tuberculosis',1,'^ESCTTU475937',NULL,'Tuberculous rheumatism'),('tuberculosis',1,'^ESCTUR256971',NULL,'Urogenital tuberculosis'),('tuberculosis',1,'^ESCTUR420022',NULL,'Urinary tuberculosis'),('tuberculosis',1,'^ESCTVE304532',NULL,'Verruca necrogenica'),('tuberculosis',1,'^ESCTWA304533',NULL,'Warty tuberculosis'),('tuberculosis',1,'EMISNQTU1',NULL,'Tuberculosis of urinary tract');
INSERT INTO #codesemis
VALUES ('alcohol-heavy-drinker',1,'^ESCTAA274036',NULL,'AA - Alcohol abuse'),('alcohol-heavy-drinker',1,'^ESCTAL261465',NULL,'Alcoholism'),('alcohol-heavy-drinker',1,'^ESCTBO497845',NULL,'Bout drinker'),('alcohol-heavy-drinker',1,'^ESCTDR391332',NULL,'Drinks heavily'),('alcohol-heavy-drinker',1,'^ESCTEP497846',NULL,'Episodic drinker'),('alcohol-heavy-drinker',1,'^ESCTET274035',NULL,'Ethanol abuse'),('alcohol-heavy-drinker',1,'^ESCTEX453343',NULL,'Excessive ethanol consumption'),('alcohol-heavy-drinker',1,'^ESCTEX453345',NULL,'Excessive alcohol consumption'),('alcohol-heavy-drinker',1,'^ESCTEX453346',NULL,'Excessive alcohol use'),('alcohol-heavy-drinker',1,'^ESCTXS453342',NULL,'XS - Excessive ethanol consumption'),('alcohol-heavy-drinker',1,'^ESCTXS453344',NULL,'XS - Excessive alcohol consumption');
INSERT INTO #codesemis
VALUES ('alcohol-light-drinker',1,'^ESCTDR497797',NULL,'Drinks on special occasions');
INSERT INTO #codesemis
VALUES ('alcohol-moderate-drinker',1,'^ESCTDR453336',NULL,'Drinker of hard liquor'),('alcohol-moderate-drinker',1,'^ESCTDR453339',NULL,'Drinks beer and hard liquor');
INSERT INTO #codesemis
VALUES ('alcohol-non-drinker',1,'^ESCTAB412032',NULL,'Abstinent'),('alcohol-non-drinker',1,'^ESCTCU412038',NULL,'Current non-drinker of alcohol'),('alcohol-non-drinker',1,'^ESCTDO412035',NULL,'Does not drink alcohol'),('alcohol-non-drinker',1,'^ESCTNE412034',NULL,'Never drinks'),('alcohol-non-drinker',1,'^ESCTNO412037',NULL,'Non - drinker alcohol');
INSERT INTO #codesemis
VALUES ('alcohol-weekly-intake',1,'^ESCT1192867',NULL,'Alcohol units per week'),('alcohol-weekly-intake',1,'^ESCTAI453315',NULL,'AI - Alcohol intake'),('alcohol-weekly-intake',1,'^ESCTAL453314',NULL,'Alcohol intake'),('alcohol-weekly-intake',1,'^ESCTAL453319',NULL,'Alcoholic drink intake'),('alcohol-weekly-intake',1,'^ESCTAL498716',NULL,'alcohol units/week'),('alcohol-weekly-intake',1,'^ESCTET453316',NULL,'Ethanol intake'),('alcohol-weekly-intake',1,'^ESCTET453317',NULL,'ETOH - Alcohol intake'),('alcohol-weekly-intake',1,'EGTON418',NULL,'Alcohol intake');
INSERT INTO #codesemis
VALUES ('bmi',2,'^ESCT1192336',NULL,'Finding of body mass index'),('bmi',2,'^ESCTBA828699',NULL,'Baseline BMI (body mass index)'),('bmi',2,'^ESCTBM348480',NULL,'BMI - Body mass index'),('bmi',2,'^ESCTBO348478',NULL,'Body mass index'),('bmi',2,'^ESCTFI589221',NULL,'Finding of BMI (body mass index)'),('bmi',2,'^ESCTOB589220',NULL,'Observation of body mass index'),('bmi',2,'^ESCTQU348481',NULL,'Quetelet index');
INSERT INTO #codesemis
VALUES ('smoking-status-current',1,'^ESCT1172093',NULL,'Number of calculated smoking pack years'),('smoking-status-current',1,'^ESCT1248230',NULL,'Admitted tobacco cons untrue ?'),('smoking-status-current',1,'^ESCTAD453353',NULL,'Admitted tobacco consumption possibly untrue'),('smoking-status-current',1,'^ESCTAG498058',NULL,'Age at starting smoking'),('smoking-status-current',1,'^ESCTCH500319',NULL,'Chain smoker'),('smoking-status-current',1,'^ESCTCI292703',NULL,'Cigar smoking tobacco'),('smoking-status-current',1,'^ESCTCI358245',NULL,'Cigarette smoking tobacco'),('smoking-status-current',1,'^ESCTHE342222',NULL,'Heavy smoker (over 20 per day)'),('smoking-status-current',1,'^ESCTHE500317',NULL,'Heavy cigarette smoker'),('smoking-status-current',1,'^ESCTHO750718',NULL,'Hookah pipe smoker'),('smoking-status-current',1,'^ESCTLI500315',NULL,'Light cigarette smoker'),('smoking-status-current',1,'^ESCTMO341910',NULL,'Moderate smoker (20 or less per day)'),('smoking-status-current',1,'^ESCTMO500316',NULL,'Moderate cigarette smoker'),('smoking-status-current',1,'^ESCTNU829927',NULL,'Number of previous attempts to stop smoking'),('smoking-status-current',1,'^ESCTPI387464',NULL,'Pipe smoking tobacco'),('smoking-status-current',1,'^ESCTSM737599',NULL,'Smokes tobacco daily'),('smoking-status-current',1,'^ESCTVE500318',NULL,'Very heavy cigarette smoker'),('smoking-status-current',1,'^ESCTWA750719',NULL,'Water pipe smoker'),('smoking-status-current',1,'^ESCTWA806318',NULL,'Wants to stop smoking'),('smoking-status-current',1,'EGTON1025',NULL,'Current Smoker NOS'),('smoking-status-current',1,'EMISNQSM14',NULL,'Smoking increased'),('smoking-status-current',1,'EMISQNO1',NULL,'Not interested in stopping smoking'),('smoking-status-current',1,'EMISQRE12',NULL,'Ready to stop smoking'),('smoking-status-current',1,'EMISSMRE1',NULL,'Smoker (Read codes)');
INSERT INTO #codesemis
VALUES ('smoking-status-currently-not',1,'^ESCTAG621746',NULL,'Aggressive non-smoker'),('smoking-status-currently-not',1,'^ESCTCU671807',NULL,'Current non smoker but past smoking history unknown'),('smoking-status-currently-not',1,'^ESCTIN621756',NULL,'Intolerant non-smoker'),('smoking-status-currently-not',1,'^ESCTNO412028',NULL,'Non-smoker for personal reasons'),('smoking-status-currently-not',1,'^ESCTNO412029',NULL,'Non-smoker for religious reasons'),('smoking-status-currently-not',1,'^ESCTNO412030',NULL,'Non-smoker for medical reasons'),('smoking-status-currently-not',1,'^ESCTTO392605',NULL,'Tolerant non-smoker');
INSERT INTO #codesemis
VALUES ('smoking-status-ex',1,'^ESCT1165113',NULL,'Ex-smoker for less than 1 year'),('smoking-status-ex',1,'^ESCT1172035',NULL,'Ex-smoker amount unknown'),('smoking-status-ex',1,'^ESCT1172036',NULL,'Ex-very heavy smoker (40+/day)'),('smoking-status-ex',1,'^ESCT1172039',NULL,'Ex-heavy smoker (20-39/day)'),('smoking-status-ex',1,'^ESCT1172042',NULL,'Ex-moderate smoker (10-19/day)'),('smoking-status-ex',1,'^ESCT1172045',NULL,'Ex-light smoker (1-9/day)'),('smoking-status-ex',1,'^ESCTAG621728',NULL,'Aggressive ex-smoker'),('smoking-status-ex',1,'^ESCTCE263604',NULL,'Cessation of smoking'),('smoking-status-ex',1,'^ESCTEX549603',NULL,'Ex-cigarette smoker amount unknown'),('smoking-status-ex',1,'^ESCTEX801757',NULL,'Ex-smoker for more than 1 year'),('smoking-status-ex',1,'^ESCTIN621715',NULL,'Intolerant ex-smoker'),('smoking-status-ex',1,'^ESCTST736897',NULL,'Stopped smoking before pregnancy'),('smoking-status-ex',1,'^ESCTTI498056',NULL,'Time since stopped smoking'),('smoking-status-ex',1,'^ESCTTO337414',NULL,'Tolerant ex-smoker'),('smoking-status-ex',1,'EGTON1026',NULL,'Ex-cigar smoker'),('smoking-status-ex',1,'EGTON1027',NULL,'Ex- Rolled Tobacco Smoker'),('smoking-status-ex',1,'EGTON322',NULL,'Ex-Cigarette Smoker');
INSERT INTO #codesemis
VALUES ('smoking-status-ex-trivial',1,'^ESCT1172048',NULL,'Ex-trivial smoker (<1/day)');
INSERT INTO #codesemis
VALUES ('smoking-status-never',1,'^ESCTNE549592',NULL,'Never smoked'),('smoking-status-never',1,'^ESCTNE796504',NULL,'Never smoked any substance');
INSERT INTO #codesemis
VALUES ('smoking-status-passive',1,'^ESCT1261859',NULL,'Ex-smoker in household'),('smoking-status-passive',1,'^ESCTAT770016',NULL,'At risk from passive smoking'),('smoking-status-passive',1,'^ESCTET319901',NULL,'ETS - Exposed to tobacco smoke'),('smoking-status-passive',1,'^ESCTEX319902',NULL,'Exposed to environmental tobacco smoke'),('smoking-status-passive',1,'^ESCTEX319903',NULL,'Exposed to tobacco smoke'),('smoking-status-passive',1,'^ESCTEX319905',NULL,'Exposed to second hand tobacco smoke'),('smoking-status-passive',1,'^ESCTEX498098',NULL,'Exposed to tobacco smoke at work'),('smoking-status-passive',1,'^ESCTEX498100',NULL,'Exposed to tobacco smoke in public places'),('smoking-status-passive',1,'^ESCTIN319904',NULL,'Involuntary smoker'),('smoking-status-passive',1,'^ESCTPA822363',NULL,'Passive smoking'),('smoking-status-passive',1,'^ESCTSM802991',NULL,'Smoker in home'),('smoking-status-passive',1,'^ESCTSM802992',NULL,'Smoker in household'),('smoking-status-passive',1,'^ESCTSM802993',NULL,'Smoker in home environment');
INSERT INTO #codesemis
VALUES ('creatinine',1,'^ESCT1262086',NULL,'Creatinine substance concentration in plasma'),('creatinine',1,'^ESCT1262087',NULL,'Creatinine molar concentration in plasma'),('creatinine',1,'^ESCT1262136',NULL,'Creatinine substance concentration in serum'),('creatinine',1,'^ESCT1262137',NULL,'Creatinine molar concentration in serum'),('creatinine',1,'^ESCT1262444',NULL,'Creatinine substance concentration in plasma by colorimetric method'),('creatinine',1,'^ESCT1262445',NULL,'Creatinine molar concentration in plasma by colorimetric method'),('creatinine',1,'^ESCT1262446',NULL,'Creatinine substance concentration in plasma by enzymatic method'),('creatinine',1,'^ESCT1262447',NULL,'Creatinine molar concentration in plasma by enzymatic method'),('creatinine',1,'^ESCT1262448',NULL,'Creatinine substance concentration in serum by colorimetric method'),('creatinine',1,'^ESCT1262449',NULL,'Creatinine molar concentration in serum by colorimetric method'),('creatinine',1,'^ESCT1262450',NULL,'Creatinine substance concentration in serum by enzymatic method'),('creatinine',1,'^ESCT1262451',NULL,'Creatinine molar concentration in serum by enzymatic method');
INSERT INTO #codesemis
VALUES ('egfr',1,'^ESCT1167392',NULL,'Glomerular filtration rate calculation technique'),('egfr',1,'^ESCT1167393',NULL,'GFR - Glomerular filtration rate calculation technique'),('egfr',1,'^ESCT1237005',NULL,'GFR (glomerular filtration rate) calculation technique'),('egfr',1,'^ESCT1249126',NULL,'eGFR (estimated glomerular filtration rate) using CKD-Epi (Chronic Kidney Disease Epidemiology Collaboration) formula per 1.73 square metres'),('egfr',1,'^ESCT1262192',NULL,'Estimated glomerular filtration rate by laboratory calculation'),('egfr',1,'^ESCT1262193',NULL,'eGFR (estimated glomerular filtration rate) by laboratory calculation'),('egfr',1,'^ESCT1268044',NULL,'GFR - glomerular filtration rate'),('egfr',1,'^ESCT1437095',NULL,'Glomerular filtration rate calculated by abbreviated Modification of Diet in Renal Disease Study Group calculation adjusted for African American origin'),('egfr',1,'^ESCT1437099',NULL,'Estimated glomerular filtration rate using creatinine Chronic Kidney Disease Epidemiology Collaboration equation per 1.73 square metres'),('egfr',1,'^ESCT1437100',NULL,'Estimated glomerular filtration rate using cystatin C Chronic Kidney Disease Epidemiology Collaboration equation per 1.73 square metres'),('egfr',1,'^ESCTEG829482',NULL,'eGFR (estimated glomerular filtration rate) using CKD-Epi (Chronic Kidney Disease Epidemiology Collaboration) formula'),('egfr',1,'^ESCTEG835295',NULL,'eGFR (estimated glomerular filtration rate) using cystatin C CKD-EPI (Chronic Kidney Disease Epidemiology Collaboration) equation'),('egfr',1,'^ESCTEG835298',NULL,'eGFR (estimated glomerular filtration rate) using creatinine CKD-EPI (Chronic Kidney Disease Epidemiology Collaboration) equation'),('egfr',1,'^ESCTES829480',NULL,'Estimated glomerular filtration rate using Chronic Kidney Disease Epidemiology Collaboration formula'),('egfr',1,'^ESCTES835294',NULL,'Estimated glomerular filtration rate using cystatin C Chronic Kidney Disease Epidemiology Collaboration equation'),('egfr',1,'^ESCTES835297',NULL,'Estimated glomerular filtration rate using creatinine Chronic Kidney Disease Epidemiology Collaboration equation'),('egfr',1,'^ESCTTC515939',NULL,'Tc99m-DTPA clearance - GFR'),('egfr',1,'^ESCTTE515940',NULL,'Technetium-99m-diethylenetriamine pentaacetic acid clearance - glomerular filtration rate'),('egfr',1,'^ESCTWI545152',NULL,'With GFR'),('egfr',1,'^ESCTWI545153',NULL,'With glomerular filtration rate');
INSERT INTO #codesemis
VALUES ('hdl-cholesterol',1,'^ESCT1262229',NULL,'HDL (high density lipoprotein) cholesterol substance concentration in plasma'),('hdl-cholesterol',1,'^ESCT1262230',NULL,'HDL (high density lipoprotein) cholesterol molar concentration in plasma'),('hdl-cholesterol',1,'^ESCT1262232',NULL,'HDL (high density lipoprotein) cholesterol substance concentration in serum'),('hdl-cholesterol',1,'^ESCT1262233',NULL,'HDL (high density lipoprotein) cholesterol molar concentration in serum'),('hdl-cholesterol',1,'^ESCTSE838573',NULL,'Serum HDL (high density lipoprotein) cholesterol level');
INSERT INTO #codesemis
VALUES ('ldl-cholesterol',1,'^ESCT1262339',NULL,'LDL-C (low density lipoprotein cholesterol) substance concentration in plasma'),('ldl-cholesterol',1,'^ESCT1262340',NULL,'LDL-C (low density lipoprotein cholesterol) molar concentration in plasma'),('ldl-cholesterol',1,'^ESCT1262341',NULL,'LDL-C (low density lipoprotein cholesterol) substance concentration in serum'),('ldl-cholesterol',1,'^ESCT1262342',NULL,'LDL-C (low density lipoprotein cholesterol) molar concentration in serum'),('ldl-cholesterol',1,'^ESCTSE840392',NULL,'Serum LDL (low density lipoprotein) cholesterol level');
INSERT INTO #codesemis
VALUES ('triglycerides',1,'^ESCT1262496',NULL,'Triglyceride substance concentration in plasma'),('triglycerides',1,'^ESCT1262497',NULL,'Triglyceride molar concentration in plasma'),('triglycerides',1,'^ESCT1262498',NULL,'Triglyceride substance concentration in serum'),('triglycerides',1,'^ESCT1262499',NULL,'Triglyceride molar concentration in serum'),('triglycerides',1,'^ESCTFI627911',NULL,'Finding of serum triglyceride levels'),('triglycerides',1,'^ESCTSE627910',NULL,'Serum triglyceride levels'),('triglycerides',1,'^ESCTME552241',NULL,'Measurement of serum triglyceride level'),('triglycerides',1,'^ESCTSE552242',NULL,'Serum triglyceride levels')

INSERT INTO #AllCodes
SELECT [concept], [version], [code], [description] from #codesemis;


IF OBJECT_ID('tempdb..#TempRefCodes') IS NOT NULL DROP TABLE #TempRefCodes;
CREATE TABLE #TempRefCodes (FK_Reference_Coding_ID BIGINT NOT NULL, concept VARCHAR(255) NOT NULL, version INT NOT NULL, [description] VARCHAR(255));

-- Read v2 codes
INSERT INTO #TempRefCodes
SELECT PK_Reference_Coding_ID, dcr.concept, dcr.[version], dcr.[description]
FROM [SharedCare].[Reference_Coding] rc
INNER JOIN #codesreadv2 dcr on dcr.code = rc.MainCode
WHERE CodingType='ReadCodeV2'
AND (dcr.term IS NULL OR dcr.term = rc.Term)
and PK_Reference_Coding_ID != -1;

-- CTV3 codes
INSERT INTO #TempRefCodes
SELECT PK_Reference_Coding_ID, dcc.concept, dcc.[version], dcc.[description]
FROM [SharedCare].[Reference_Coding] rc
INNER JOIN #codesctv3 dcc on dcc.code = rc.MainCode
WHERE CodingType='CTV3'
and PK_Reference_Coding_ID != -1;

-- EMIS codes with a FK Reference Coding ID
INSERT INTO #TempRefCodes
SELECT FK_Reference_Coding_ID, ce.concept, ce.[version], ce.[description]
FROM [SharedCare].[Reference_Local_Code] rlc
INNER JOIN #codesemis ce on ce.code = rlc.LocalCode
WHERE FK_Reference_Coding_ID != -1;

IF OBJECT_ID('tempdb..#TempSNOMEDRefCodes') IS NOT NULL DROP TABLE #TempSNOMEDRefCodes;
CREATE TABLE #TempSNOMEDRefCodes (FK_Reference_SnomedCT_ID BIGINT NOT NULL, concept VARCHAR(255) NOT NULL, [version] INT NOT NULL, [description] VARCHAR(255));

-- SNOMED codes
INSERT INTO #TempSNOMEDRefCodes
SELECT PK_Reference_SnomedCT_ID, dcs.concept, dcs.[version], dcs.[description]
FROM SharedCare.Reference_SnomedCT rs
INNER JOIN #codessnomed dcs on dcs.code = rs.ConceptID;

-- EMIS codes with a FK SNOMED ID but without a FK Reference Coding ID
INSERT INTO #TempSNOMEDRefCodes
SELECT FK_Reference_SnomedCT_ID, ce.concept, ce.[version], ce.[description]
FROM [SharedCare].[Reference_Local_Code] rlc
INNER JOIN #codesemis ce on ce.code = rlc.LocalCode
WHERE FK_Reference_Coding_ID = -1
AND FK_Reference_SnomedCT_ID != -1;

-- De-duped tables
IF OBJECT_ID('tempdb..#CodeSets') IS NOT NULL DROP TABLE #CodeSets;
CREATE TABLE #CodeSets (FK_Reference_Coding_ID BIGINT NOT NULL, concept VARCHAR(255) NOT NULL, [description] VARCHAR(255));

IF OBJECT_ID('tempdb..#SnomedSets') IS NOT NULL DROP TABLE #SnomedSets;
CREATE TABLE #SnomedSets (FK_Reference_SnomedCT_ID BIGINT NOT NULL, concept VARCHAR(255) NOT NULL, [description] VARCHAR(255));

IF OBJECT_ID('tempdb..#VersionedCodeSets') IS NOT NULL DROP TABLE #VersionedCodeSets;
CREATE TABLE #VersionedCodeSets (FK_Reference_Coding_ID BIGINT NOT NULL, Concept VARCHAR(255), [Version] INT, [description] VARCHAR(255));

IF OBJECT_ID('tempdb..#VersionedSnomedSets') IS NOT NULL DROP TABLE #VersionedSnomedSets;
CREATE TABLE #VersionedSnomedSets (FK_Reference_SnomedCT_ID BIGINT NOT NULL, Concept VARCHAR(255), [Version] INT, [description] VARCHAR(255));

INSERT INTO #VersionedCodeSets
SELECT DISTINCT * FROM #TempRefCodes;

INSERT INTO #VersionedSnomedSets
SELECT DISTINCT * FROM #TempSNOMEDRefCodes;

INSERT INTO #CodeSets
SELECT FK_Reference_Coding_ID, c.concept, [description]
FROM #VersionedCodeSets c
INNER JOIN (
  SELECT concept, MAX(version) AS maxVersion FROM #VersionedCodeSets
  GROUP BY concept)
sub ON sub.concept = c.concept AND c.version = sub.maxVersion;

INSERT INTO #SnomedSets
SELECT FK_Reference_SnomedCT_ID, c.concept, [description]
FROM #VersionedSnomedSets c
INNER JOIN (
  SELECT concept, MAX(version) AS maxVersion FROM #VersionedSnomedSets
  GROUP BY concept)
sub ON sub.concept = c.concept AND c.version = sub.maxVersion;

--#endregion

-- >>> Following code sets injected: sle v1

------- EXCLUSIONS: PI wants to exclude the following: lupus pernio, neonatal lupus, drug-induced lupus, tuberculosis, cutaneous lupus without a corresponding 
------- systemic diagnosis, codes relating to a diagnostic test

------- lupus pernio, drug-induced lupus, and neonatal lupus code sets have been created - but prevalence suggests they are unused


-- >>> Following code sets injected: tuberculosis v1

-- table of sle coding events

IF OBJECT_ID('tempdb..#SLECodes') IS NOT NULL DROP TABLE #SLECodes;
SELECT FK_Patient_Link_ID, EventDate
INTO #SLECodes
FROM SharedCare.[GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'sle' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'sle' AND Version = 1)
)
GROUP BY FK_Patient_Link_ID, EventDate

-- table of patients that meet the exclusion criteria: turberculosis, lupus pernio, drug-induced lupus, neonatal lupus

IF OBJECT_ID('tempdb..#Exclusions') IS NOT NULL DROP TABLE #Exclusions;
SELECT FK_Patient_Link_ID AS PatientId, EventDate
INTO #Exclusions
FROM SharedCare.[GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'tuberculosis' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'tuberculosis' AND Version = 1)
)
GROUP BY FK_Patient_Link_ID, EventDate


-- create cohort of patients with an SLE diagnosis in the study period

IF OBJECT_ID('tempdb..#Cohort') IS NOT NULL DROP TABLE #Cohort;
SELECT
	 p.FK_Patient_Link_ID
	,yob.YearOfBirth
	,p.EthnicGroupDescription
	,p.DeathDate
INTO #Cohort
FROM #Patients p
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE 
	p.FK_Patient_Link_ID IN (SELECT DISTINCT FK_Patient_Link_ID FROM #SLECodes)
	AND p.FK_Patient_Link_ID NOT IN (SELECT DISTINCT p.FK_Patient_Link_ID FROM #Exclusions)
AND YEAR(@StartDate) - YearOfBirth > 18

---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------

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
--┌────────────────────────────┐
--│ Index Multiple Deprivation │
--└────────────────────────────┘

-- OBJECTIVE: To get the 2019 Index of Multiple Deprivation (IMD) decile for each patient.

-- INPUT: Assumes there exists a temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: A temp table as follows:
-- #PatientIMDDecile (FK_Patient_Link_ID, IMD2019Decile1IsMostDeprived10IsLeastDeprived)
-- 	- FK_Patient_Link_ID - unique patient id
--	- IMD2019Decile1IsMostDeprived10IsLeastDeprived - number 1 to 10 inclusive

-- Get all patients IMD_Score (which is a rank) for the cohort and map to decile
-- (Data on mapping thresholds at: https://www.gov.uk/government/statistics/english-indices-of-deprivation-2019
IF OBJECT_ID('tempdb..#AllPatientIMDDeciles') IS NOT NULL DROP TABLE #AllPatientIMDDeciles;
SELECT 
	FK_Patient_Link_ID,
	FK_Reference_Tenancy_ID,
	HDMModifDate,
	CASE 
		WHEN IMD_Score <= 3284 THEN 1
		WHEN IMD_Score <= 6568 THEN 2
		WHEN IMD_Score <= 9853 THEN 3
		WHEN IMD_Score <= 13137 THEN 4
		WHEN IMD_Score <= 16422 THEN 5
		WHEN IMD_Score <= 19706 THEN 6
		WHEN IMD_Score <= 22990 THEN 7
		WHEN IMD_Score <= 26275 THEN 8
		WHEN IMD_Score <= 29559 THEN 9
		ELSE 10
	END AS IMD2019Decile1IsMostDeprived10IsLeastDeprived 
INTO #AllPatientIMDDeciles
FROM SharedCare.Patient p
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND IMD_Score IS NOT NULL
AND IMD_Score != -1;
-- 972479 rows
-- 00:00:11

-- If patients have a tenancy id of 2 we take this as their most likely IMD_Score
-- as this is the GP data feed and so most likely to be up to date
IF OBJECT_ID('tempdb..#PatientIMDDecile') IS NOT NULL DROP TABLE #PatientIMDDecile;
SELECT FK_Patient_Link_ID, MIN(IMD2019Decile1IsMostDeprived10IsLeastDeprived) as IMD2019Decile1IsMostDeprived10IsLeastDeprived INTO #PatientIMDDecile FROM #AllPatientIMDDeciles
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_Tenancy_ID = 2
GROUP BY FK_Patient_Link_ID;
-- 247377 rows
-- 00:00:00

-- Find the patients who remain unmatched
IF OBJECT_ID('tempdb..#UnmatchedImdPatients') IS NOT NULL DROP TABLE #UnmatchedImdPatients;
SELECT FK_Patient_Link_ID INTO #UnmatchedImdPatients FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientIMDDecile;
-- 38710 rows
-- 00:00:00

-- If every IMD_Score is the same for all their linked patient ids then we use that
INSERT INTO #PatientIMDDecile
SELECT FK_Patient_Link_ID, MIN(IMD2019Decile1IsMostDeprived10IsLeastDeprived) FROM #AllPatientIMDDeciles
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedImdPatients)
GROUP BY FK_Patient_Link_ID
HAVING MIN(IMD2019Decile1IsMostDeprived10IsLeastDeprived) = MAX(IMD2019Decile1IsMostDeprived10IsLeastDeprived);
-- 36656
-- 00:00:00

-- Find any still unmatched patients
TRUNCATE TABLE #UnmatchedImdPatients;
INSERT INTO #UnmatchedImdPatients
SELECT FK_Patient_Link_ID FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientIMDDecile;
-- 2054 rows
-- 00:00:00

-- If there is a unique most recent imd decile then use that
INSERT INTO #PatientIMDDecile
SELECT p.FK_Patient_Link_ID, MIN(p.IMD2019Decile1IsMostDeprived10IsLeastDeprived) FROM #AllPatientIMDDeciles p
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(HDMModifDate) MostRecentDate FROM #AllPatientIMDDeciles
	WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedImdPatients)
	GROUP BY FK_Patient_Link_ID
) sub ON sub.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND sub.MostRecentDate = p.HDMModifDate
GROUP BY p.FK_Patient_Link_ID
HAVING MIN(IMD2019Decile1IsMostDeprived10IsLeastDeprived) = MAX(IMD2019Decile1IsMostDeprived10IsLeastDeprived);
-- 489
-- 00:00:00

-- CREATE COPY OF GP EVENTS TABLE, FILTERED TO COHORT FOR THIS STUDY

IF OBJECT_ID('tempdb..#GPEvents') IS NOT NULL DROP TABLE #GPEvents;
SELECT FK_Patient_Link_ID, EventDate, 
		FK_Reference_Coding_ID, FK_Reference_SnomedCT_ID, SuppliedCode,
		[Value],[Units]
INTO #GPEvents
FROM SharedCare.GP_Events gp
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort)

--┌─────┐
--│ BMI │
--└─────┘

-- OBJECTIVE: To get the BMI for each patient in a cohort.

-- INPUT: Assumes there exists a temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort
-- Also takes one parameter:
--	- gp-events-table: string - (table name) the name of the table containing the GP events. Usually is "RLS.vw_GP_Events" but can be anything with the columns: FK_Patient_Link_ID, EventDate, FK_Reference_Coding_ID, and FK_Reference_SnomedCT_ID
-- Also assumes there is an @IndexDate defined - The index date of the study


-- OUTPUT: A temp table as follows:
-- #PatientBMI (FK_Patient_Link_ID, BMI, DateOfBMIMeasurement)
--	- FK_Patient_Link_ID - unique patient id
--  - BMI
--  - DateOfBMIMeasurement

-- ASSUMPTIONS:
--	- We take the measurement closest to @IndexDate to be correct

-- >>> Following code sets injected: bmi v2

-- Get all BMI measurements 

IF OBJECT_ID('tempdb..#AllPatientBMI') IS NOT NULL DROP TABLE #AllPatientBMI;
SELECT 
	FK_Patient_Link_ID,
	CAST(EventDate AS DATE) AS EventDate,
	FK_Reference_Coding_ID,
	FK_Reference_SnomedCT_ID,
	[Value]
INTO #AllPatientBMI
FROM #GPEvents
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
	AND FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'bmi'AND [Version]=2) 
	AND EventDate <= @IndexDate
	AND TRY_CONVERT(NUMERIC(16,5), [Value]) BETWEEN 5 AND 100

UNION
SELECT 
	FK_Patient_Link_ID,
	CAST(EventDate AS DATE) AS EventDate,
	FK_Reference_Coding_ID,
	FK_Reference_SnomedCT_ID,
	[Value]
FROM #GPEvents
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
	AND FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'bmi' AND [Version]=2)
	AND EventDate <= @IndexDate
	AND TRY_CONVERT(NUMERIC(16,5), [Value]) BETWEEN 5 AND 100


-- For closest BMI prior to index date
IF OBJECT_ID('tempdb..#TempCurrentBMI') IS NOT NULL DROP TABLE #TempCurrentBMI;
SELECT 
	a.FK_Patient_Link_ID, 
	Max([Value]) as [Value],
	Max(EventDate) as EventDate
INTO #TempCurrentBMI
FROM #AllPatientBMI a
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(EventDate) AS MostRecentDate 
	FROM #AllPatientBMI
	GROUP BY FK_Patient_Link_ID
) sub ON sub.MostRecentDate = a.EventDate and sub.FK_Patient_Link_ID = a.FK_Patient_Link_ID
GROUP BY a.FK_Patient_Link_ID;

-- Bring all together in final table
IF OBJECT_ID('tempdb..#PatientBMI') IS NOT NULL DROP TABLE #PatientBMI;
SELECT 
	p.FK_Patient_Link_ID,
	BMI = TRY_CONVERT(NUMERIC(16,5), [Value]),
	EventDate AS DateOfBMIMeasurement
INTO #PatientBMI 
FROM #Patients p
LEFT OUTER JOIN #TempCurrentBMI c on c.FK_Patient_Link_ID = p.FK_Patient_Link_ID
--┌────────────────┐
--│ Alcohol Intake │
--└────────────────┘

-- OBJECTIVE: To get the alcohol status for each patient in a cohort.

-- INPUT: Assumes there exists a temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort
-- Also takes one parameter:
--	- gp-events-table: string - (table name) the name of the table containing the GP events. Usually is "RLS.vw_GP_Events" but can be anything with the columns: FK_Patient_Link_ID, EventDate, FK_Reference_Coding_ID, and FK_Reference_SnomedCT_ID

-- OUTPUT: A temp table as follows:
-- #PatientAlcoholIntake (FK_Patient_Link_ID, CurrentAlcoholIntake)
--	- FK_Patient_Link_ID - unique patient id
--  - WorstAlcoholIntake - [heavy drinker/moderate drinker/light drinker/non-drinker] - worst code
--	- CurrentAlcoholIntake - [heavy drinker/moderate drinker/light drinker/non-drinker] - most recent code

-- ASSUMPTIONS:
--	- We take the most recent alcohol intake code in a patient's record to be correct

-- >>> Following code sets injected: alcohol-non-drinker v1/alcohol-light-drinker v1/alcohol-moderate-drinker v1/alcohol-heavy-drinker v1/alcohol-weekly-intake v1

-- Get all patients year of birth for the cohort
IF OBJECT_ID('tempdb..#AllPatientAlcoholIntakeCodes') IS NOT NULL DROP TABLE #AllPatientAlcoholIntakeCodes;
SELECT 
	FK_Patient_Link_ID,
	CAST(EventDate AS DATE) AS EventDate,
	FK_Reference_Coding_ID,
	FK_Reference_SnomedCT_ID,
	[Value]
INTO #AllPatientAlcoholIntakeCodes
FROM #GPEvents
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_SnomedCT_ID IN (
	SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets 
	WHERE Concept IN (
	'alcohol-non-drinker', 
	'alcohol-light-drinker',
	'alcohol-moderate-drinker',
	'alcohol-heavy-drinker',
	'alcohol-weekly-intake'
	)
	AND [Version]=1
) 
UNION
SELECT 
	FK_Patient_Link_ID,
	CAST(EventDate AS DATE) AS EventDate,
	FK_Reference_Coding_ID,
	FK_Reference_SnomedCT_ID,
	[Value]
FROM #GPEvents
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets 
	WHERE Concept IN (
	'alcohol-non-drinker', 
	'alcohol-light-drinker',
	'alcohol-moderate-drinker',
	'alcohol-heavy-drinker',
	'alcohol-weekly-intake'
	)
	AND [Version]=1
);

IF OBJECT_ID('tempdb..#AllPatientAlcoholIntakeConcept') IS NOT NULL DROP TABLE #AllPatientAlcoholIntakeConcept;
SELECT 
	a.FK_Patient_Link_ID,
	EventDate,
	CASE WHEN c.Concept IS NULL THEN s.Concept ELSE c.Concept END AS Concept,
	-1 AS Severity,
	[Value]
INTO #AllPatientAlcoholIntakeConcept
FROM #AllPatientAlcoholIntakeCodes a
LEFT OUTER JOIN #VersionedCodeSets c on c.FK_Reference_Coding_ID = a.FK_Reference_Coding_ID
LEFT OUTER JOIN #VersionedSnomedSets s on s.FK_Reference_SnomedCT_ID = a.FK_Reference_SnomedCT_ID;

UPDATE #AllPatientAlcoholIntakeConcept
SET Severity = 3
WHERE Concept = 'alcohol-heavy-drinker' OR (Concept = 'alcohol-weekly-intake' AND TRY_CONVERT(NUMERIC(16,5), [Value]) > 14) ;
UPDATE #AllPatientAlcoholIntakeConcept
SET Severity = 2
WHERE Concept = 'alcohol-moderate-drinker' OR (Concept = 'alcohol-weekly-intake' AND TRY_CONVERT(NUMERIC(16,5), [Value]) BETWEEN 7 AND 14);
UPDATE #AllPatientAlcoholIntakeConcept
SET Severity = 1
WHERE Concept = 'alcohol-light-drinker' OR (Concept = 'alcohol-weekly-intake' AND TRY_CONVERT(NUMERIC(16,5), [Value]) BETWEEN 0 AND 7);
UPDATE #AllPatientAlcoholIntakeConcept
SET Severity = 0
WHERE Concept = 'alcohol-non-drinker' OR (Concept = 'alcohol-weekly-intake' AND TRY_CONVERT(NUMERIC(16,5), [Value]) = 0 );

-- For "worst" alcohol intake
IF OBJECT_ID('tempdb..#TempWorstAlc') IS NOT NULL DROP TABLE #TempWorstAlc;
SELECT 
	FK_Patient_Link_ID, 
	CASE 
		WHEN MAX(Severity) = 3 THEN 'heavy drinker'
		WHEN MAX(Severity) = 2 THEN 'moderate drinker'
		WHEN MAX(Severity) = 1 THEN 'light drinker'
		WHEN MAX(Severity) = 0 THEN 'non-drinker'
	END AS [Status]
INTO #TempWorstAlc
FROM #AllPatientAlcoholIntakeConcept
WHERE Severity >= 0
GROUP BY FK_Patient_Link_ID;

-- For "current" alcohol intake
IF OBJECT_ID('tempdb..#TempCurrentAlc') IS NOT NULL DROP TABLE #TempCurrentAlc;
SELECT 
	a.FK_Patient_Link_ID, 
	CASE 
		WHEN MAX(Severity) = 3 THEN 'heavy drinker'
		WHEN MAX(Severity) = 2 THEN 'moderate drinker'
		WHEN MAX(Severity) = 1 THEN 'light drinker'
		WHEN MAX(Severity) = 0 THEN 'non-drinker'
	END AS [Status]
INTO #TempCurrentAlc
FROM #AllPatientAlcoholIntakeConcept a
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(EventDate) AS MostRecentDate FROM #AllPatientAlcoholIntakeConcept
	WHERE Severity >= 0
	GROUP BY FK_Patient_Link_ID
) sub ON sub.MostRecentDate = a.EventDate and sub.FK_Patient_Link_ID = a.FK_Patient_Link_ID
GROUP BY a.FK_Patient_Link_ID;

-- Bring all together in final table
IF OBJECT_ID('tempdb..#PatientAlcoholIntake') IS NOT NULL DROP TABLE #PatientAlcoholIntake;
SELECT 
	p.FK_Patient_Link_ID,
	CASE WHEN w.[Status] IS NULL THEN 'unknown' ELSE w.[Status] END AS WorstAlcoholIntake,
	CASE WHEN c.[Status] IS NULL THEN 'unknown' ELSE c.[Status] END AS CurrentAlcoholIntake
INTO #PatientAlcoholIntake FROM #Patients p
LEFT OUTER JOIN #TempWorstAlc w on w.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #TempCurrentAlc c on c.FK_Patient_Link_ID = p.FK_Patient_Link_ID;
--┌────────────────┐
--│ Smoking status │
--└────────────────┘

-- OBJECTIVE: To get the smoking status for each patient in a cohort.

-- INPUT: Assumes there exists a temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort
-- Also takes one parameter:
--	- gp-events-table: string - (table name) the name of the table containing the GP events. Usually is "RLS.vw_GP_Events" but can be anything with the columns: FK_Patient_Link_ID, EventDate, FK_Reference_Coding_ID, and FK_Reference_SnomedCT_ID

-- OUTPUT: A temp table as follows:
-- #PatientSmokingStatus (FK_Patient_Link_ID, PassiveSmoker, WorstSmokingStatus, CurrentSmokingStatus)
--	- FK_Patient_Link_ID - unique patient id
--	- PassiveSmoker - Y/N (whether a patient has ever had a code for passive smoking)
--	- WorstSmokingStatus - [non-trivial-smoker/trivial-smoker/non-smoker]
--	- CurrentSmokingStatus - [non-trivial-smoker/trivial-smoker/non-smoker]

-- ASSUMPTIONS:
--	- We take the most recent smoking status in a patient's record to be correct
--	- However, there is likely confusion between the "non smoker" and "never smoked" codes. Especially as sometimes the synonyms for these codes overlap. Therefore, a patient wih a most recent smoking status of "never", but who has previous smoking codes, would be classed as WorstSmokingStatus=non-trivial-smoker / CurrentSmokingStatus=non-smoker

-- >>> Following code sets injected: smoking-status-current v1/smoking-status-currently-not v1/smoking-status-ex v1/smoking-status-ex-trivial v1/smoking-status-never v1/smoking-status-passive v1/smoking-status-trivial v1
-- Get all patients year of birth for the cohort
IF OBJECT_ID('tempdb..#AllPatientSmokingStatusCodes') IS NOT NULL DROP TABLE #AllPatientSmokingStatusCodes;
SELECT 
	FK_Patient_Link_ID,
	CAST(EventDate AS DATE) AS EventDate,
	FK_Reference_Coding_ID,
	FK_Reference_SnomedCT_ID
INTO #AllPatientSmokingStatusCodes
FROM #GPEvents
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_SnomedCT_ID IN (
	SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets 
	WHERE Concept IN (
		'smoking-status-current',
		'smoking-status-currently-not',
		'smoking-status-ex',
		'smoking-status-ex-trivial',
		'smoking-status-never',
		'smoking-status-passive',
		'smoking-status-trivial'
	)
	AND [Version]=1
) 
UNION
SELECT 
	FK_Patient_Link_ID,
	CAST(EventDate AS DATE) AS EventDate,
	FK_Reference_Coding_ID,
	FK_Reference_SnomedCT_ID
FROM #GPEvents
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets 
	WHERE Concept IN (
		'smoking-status-current',
		'smoking-status-currently-not',
		'smoking-status-ex',
		'smoking-status-ex-trivial',
		'smoking-status-never',
		'smoking-status-passive',
		'smoking-status-trivial'
	)
	AND [Version]=1
);

IF OBJECT_ID('tempdb..#AllPatientSmokingStatusConcept') IS NOT NULL DROP TABLE #AllPatientSmokingStatusConcept;
SELECT 
	a.FK_Patient_Link_ID,
	EventDate,
	CASE WHEN c.Concept IS NULL THEN s.Concept ELSE c.Concept END AS Concept,
	-1 AS SeverityWorst,
	-1 AS SeverityCurrent
INTO #AllPatientSmokingStatusConcept
FROM #AllPatientSmokingStatusCodes a
LEFT OUTER JOIN #VersionedCodeSets c on c.FK_Reference_Coding_ID = a.FK_Reference_Coding_ID
LEFT OUTER JOIN #VersionedSnomedSets s on s.FK_Reference_SnomedCT_ID = a.FK_Reference_SnomedCT_ID;

UPDATE #AllPatientSmokingStatusConcept
SET SeverityWorst = 2, 
	SeverityCurrent = 2
WHERE Concept IN ('smoking-status-current');
UPDATE #AllPatientSmokingStatusConcept
SET SeverityWorst = 2, 
	SeverityCurrent = 0
WHERE Concept IN ('smoking-status-ex');
UPDATE #AllPatientSmokingStatusConcept
SET SeverityWorst = 1,	
	SeverityCurrent = 0
WHERE Concept IN ('smoking-status-ex-trivial');
UPDATE #AllPatientSmokingStatusConcept
SET SeverityWorst = 1,
	SeverityCurrent = 1
WHERE Concept IN ('smoking-status-trivial');
UPDATE #AllPatientSmokingStatusConcept
SET SeverityWorst = 0,
	SeverityCurrent = 0
WHERE Concept IN ('smoking-status-never');
UPDATE #AllPatientSmokingStatusConcept
SET SeverityWorst = 0,
	SeverityCurrent = 0
WHERE Concept IN ('smoking-status-currently-not');

-- passive smokers
IF OBJECT_ID('tempdb..#TempPassiveSmokers') IS NOT NULL DROP TABLE #TempPassiveSmokers;
select DISTINCT FK_Patient_Link_ID into #TempPassiveSmokers from #AllPatientSmokingStatusConcept
where Concept = 'smoking-status-passive';

-- For "worst" smoking status
IF OBJECT_ID('tempdb..#TempWorst') IS NOT NULL DROP TABLE #TempWorst;
SELECT 
	FK_Patient_Link_ID, 
	CASE 
		WHEN MAX(SeverityWorst) = 2 THEN 'non-trivial-smoker'
		WHEN MAX(SeverityWorst) = 1 THEN 'trivial-smoker'
		WHEN MAX(SeverityWorst) = 0 THEN 'non-smoker'
	END AS [Status]
INTO #TempWorst
FROM #AllPatientSmokingStatusConcept
WHERE SeverityWorst >= 0
GROUP BY FK_Patient_Link_ID;

-- For "current" smoking status
IF OBJECT_ID('tempdb..#TempCurrent') IS NOT NULL DROP TABLE #TempCurrent;
SELECT 
	a.FK_Patient_Link_ID, 
	CASE 
		WHEN MAX(SeverityCurrent) = 2 THEN 'non-trivial-smoker'
		WHEN MAX(SeverityCurrent) = 1 THEN 'trivial-smoker'
		WHEN MAX(SeverityCurrent) = 0 THEN 'non-smoker'
	END AS [Status]
INTO #TempCurrent
FROM #AllPatientSmokingStatusConcept a
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(EventDate) AS MostRecentDate FROM #AllPatientSmokingStatusConcept
	WHERE SeverityCurrent >= 0
	GROUP BY FK_Patient_Link_ID
) sub ON sub.MostRecentDate = a.EventDate and sub.FK_Patient_Link_ID = a.FK_Patient_Link_ID
GROUP BY a.FK_Patient_Link_ID;

-- Bring all together in final table
IF OBJECT_ID('tempdb..#PatientSmokingStatus') IS NOT NULL DROP TABLE #PatientSmokingStatus;
SELECT 
	p.FK_Patient_Link_ID,
	CASE WHEN ps.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PassiveSmoker,
	CASE WHEN w.[Status] IS NULL THEN 'unknown-smoking-status' ELSE w.[Status] END AS WorstSmokingStatus,
	CASE WHEN c.[Status] IS NULL THEN 'unknown-smoking-status' ELSE c.[Status] END AS CurrentSmokingStatus
INTO #PatientSmokingStatus FROM #Patients p
LEFT OUTER JOIN #TempPassiveSmokers ps on ps.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #TempWorst w on w.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #TempCurrent c on c.FK_Patient_Link_ID = p.FK_Patient_Link_ID;
-- >>> Following code sets injected: chronic-kidney-disease v1/ckd-stage-1 v1/ckd-stage-2 v1/ckd-stage-3 v1/ckd-stage-4 v1/ckd-stage-5 v1
-- >>> Following code sets injected: creatinine v1/egfr v1

---------- GET DATE OF FIRST SLE DIAGNOSIS --------------
IF OBJECT_ID('tempdb..#SLEFirstDiagnosis') IS NOT NULL DROP TABLE #SLEFirstDiagnosis;
SELECT FK_Patient_Link_ID, 
	   SLEFirstDiagnosisDate = MIN(CONVERT(DATE,EventDate))
INTO #SLEFirstDiagnosis
FROM #SLECodes
GROUP BY FK_Patient_Link_ID

---------- GET CKD STAGE FOR EACH PATIENT ---------------

-- get all codes for CKD
IF OBJECT_ID('tempdb..#ckd') IS NOT NULL DROP TABLE #ckd;
SELECT 
	gp.FK_Patient_Link_ID,
	EventDate = CONVERT(DATE, gp.EventDate),
	a.Concept
INTO #ckd
FROM #GPEvents gp
INNER JOIN #AllCodes a ON a.Code = gp.SuppliedCode
WHERE Concept IN 
	('chronic-kidney-disease', 'ckd-stage-1', 'ckd-stage-2', 'ckd-stage-3', 'ckd-stage-4', 'ckd-stage-5')

SELECT FK_Patient_Link_ID,
		CKDStage = CASE WHEN concept = 'ckd-stage-1' then 1
			WHEN concept = 'ckd-stage-2' then 2
			WHEN concept = 'ckd-stage-3' then 3
			WHEN concept = 'ckd-stage-4' then 4
			WHEN concept = 'ckd-stage-5' then 5
				ELSE 0 END
INTO #ckd_stages
FROM #ckd

SELECT FK_Patient_Link_ID, 
		CKDStageMax = MAX(CKDStage)
INTO #CKDStage
FROM #ckd_stages
GROUP BY FK_Patient_Link_ID

----------- GET MOST RECENT TEST RESULTS FOR EACH PATIENT


-- >>> Following code sets injected: egfr v1

-- First we get the date of the nearest egfr measurement before/after
-- the index date
IF OBJECT_ID('tempdb..#egfrTEMP1') IS NOT NULL DROP TABLE #egfrTEMP1;
  SELECT FK_Patient_Link_ID, MAX(EventDate) AS EventDate
INTO #egfrTEMP1
FROM #GPEvents
WHERE SuppliedCode IN (SELECT code FROM #AllCodes WHERE Concept = 'egfr' AND Version = 1) 
AND EventDate < '2023-10-31'
AND [Value] IS NOT NULL
AND [Value] != '0'
AND Units LIKE '%'
-- as these are all tests, we can ignore values values outside the specified range
AND TRY_CONVERT(DECIMAL(10,3), [Value]) >= 0
AND TRY_CONVERT(DECIMAL(10,3), [Value]) <= 500
GROUP BY FK_Patient_Link_ID;

-- Then we join to that table in order to get the value of that measurement
IF OBJECT_ID('tempdb..#egfr') IS NOT NULL DROP TABLE #egfr;
SELECT p.FK_Patient_Link_ID, p.EventDate AS DateOfFirstValue, MAX(p.Value) AS [Value]
INTO #egfr
FROM #GPEvents p
INNER JOIN #egfrTEMP1 sub ON sub.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND sub.EventDate = p.EventDate
WHERE SuppliedCode IN (SELECT code FROM #AllCodes WHERE Concept = 'egfr' AND Version = 1) 
GROUP BY p.FK_Patient_Link_ID, p.EventDate;

-- >>> Following code sets injected: creatinine v1

-- First we get the date of the nearest creatinine measurement before/after
-- the index date
IF OBJECT_ID('tempdb..#creatinineTEMP1') IS NOT NULL DROP TABLE #creatinineTEMP1;
  SELECT FK_Patient_Link_ID, MAX(EventDate) AS EventDate
INTO #creatinineTEMP1
FROM #GPEvents
WHERE SuppliedCode IN (SELECT code FROM #AllCodes WHERE Concept = 'creatinine' AND Version = 1) 
AND EventDate < '2023-10-31'
AND [Value] IS NOT NULL
AND [Value] != '0'
AND Units LIKE '%'
-- as these are all tests, we can ignore values values outside the specified range
AND TRY_CONVERT(DECIMAL(10,3), [Value]) >= 0
AND TRY_CONVERT(DECIMAL(10,3), [Value]) <= 500
GROUP BY FK_Patient_Link_ID;

-- Then we join to that table in order to get the value of that measurement
IF OBJECT_ID('tempdb..#creatinine') IS NOT NULL DROP TABLE #creatinine;
SELECT p.FK_Patient_Link_ID, p.EventDate AS DateOfFirstValue, MAX(p.Value) AS [Value]
INTO #creatinine
FROM #GPEvents p
INNER JOIN #creatinineTEMP1 sub ON sub.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND sub.EventDate = p.EventDate
WHERE SuppliedCode IN (SELECT code FROM #AllCodes WHERE Concept = 'creatinine' AND Version = 1) 
GROUP BY p.FK_Patient_Link_ID, p.EventDate;

-- >>> Following code sets injected: hdl-cholesterol v1

-- First we get the date of the nearest hdl-cholesterol measurement before/after
-- the index date
IF OBJECT_ID('tempdb..#hdl_cholesterolTEMP1') IS NOT NULL DROP TABLE #hdl_cholesterolTEMP1;
  SELECT FK_Patient_Link_ID, MAX(EventDate) AS EventDate
INTO #hdl_cholesterolTEMP1
FROM #GPEvents
WHERE SuppliedCode IN (SELECT code FROM #AllCodes WHERE Concept = 'hdl-cholesterol' AND Version = 1) 
AND EventDate < '2023-10-31'
AND [Value] IS NOT NULL
AND [Value] != '0'
AND Units LIKE '%'
-- as these are all tests, we can ignore values values outside the specified range
AND TRY_CONVERT(DECIMAL(10,3), [Value]) >= 0
AND TRY_CONVERT(DECIMAL(10,3), [Value]) <= 500
GROUP BY FK_Patient_Link_ID;

-- Then we join to that table in order to get the value of that measurement
IF OBJECT_ID('tempdb..#hdl_cholesterol') IS NOT NULL DROP TABLE #hdl_cholesterol;
SELECT p.FK_Patient_Link_ID, p.EventDate AS DateOfFirstValue, MAX(p.Value) AS [Value]
INTO #hdl_cholesterol
FROM #GPEvents p
INNER JOIN #hdl_cholesterolTEMP1 sub ON sub.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND sub.EventDate = p.EventDate
WHERE SuppliedCode IN (SELECT code FROM #AllCodes WHERE Concept = 'hdl-cholesterol' AND Version = 1) 
GROUP BY p.FK_Patient_Link_ID, p.EventDate;

-- >>> Following code sets injected: ldl-cholesterol v1

-- First we get the date of the nearest ldl-cholesterol measurement before/after
-- the index date
IF OBJECT_ID('tempdb..#ldl_cholesterolTEMP1') IS NOT NULL DROP TABLE #ldl_cholesterolTEMP1;
  SELECT FK_Patient_Link_ID, MAX(EventDate) AS EventDate
INTO #ldl_cholesterolTEMP1
FROM #GPEvents
WHERE SuppliedCode IN (SELECT code FROM #AllCodes WHERE Concept = 'ldl-cholesterol' AND Version = 1) 
AND EventDate < '2023-10-31'
AND [Value] IS NOT NULL
AND [Value] != '0'
AND Units LIKE '%'
-- as these are all tests, we can ignore values values outside the specified range
AND TRY_CONVERT(DECIMAL(10,3), [Value]) >= 0
AND TRY_CONVERT(DECIMAL(10,3), [Value]) <= 500
GROUP BY FK_Patient_Link_ID;

-- Then we join to that table in order to get the value of that measurement
IF OBJECT_ID('tempdb..#ldl_cholesterol') IS NOT NULL DROP TABLE #ldl_cholesterol;
SELECT p.FK_Patient_Link_ID, p.EventDate AS DateOfFirstValue, MAX(p.Value) AS [Value]
INTO #ldl_cholesterol
FROM #GPEvents p
INNER JOIN #ldl_cholesterolTEMP1 sub ON sub.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND sub.EventDate = p.EventDate
WHERE SuppliedCode IN (SELECT code FROM #AllCodes WHERE Concept = 'ldl-cholesterol' AND Version = 1) 
GROUP BY p.FK_Patient_Link_ID, p.EventDate;

-- >>> Following code sets injected: triglycerides v1

-- First we get the date of the nearest triglycerides measurement before/after
-- the index date
IF OBJECT_ID('tempdb..#triglyceridesTEMP1') IS NOT NULL DROP TABLE #triglyceridesTEMP1;
  SELECT FK_Patient_Link_ID, MAX(EventDate) AS EventDate
INTO #triglyceridesTEMP1
FROM #GPEvents
WHERE SuppliedCode IN (SELECT code FROM #AllCodes WHERE Concept = 'triglycerides' AND Version = 1) 
AND EventDate < '2023-10-31'
AND [Value] IS NOT NULL
AND [Value] != '0'
AND Units LIKE '%'
-- as these are all tests, we can ignore values values outside the specified range
AND TRY_CONVERT(DECIMAL(10,3), [Value]) >= 0
AND TRY_CONVERT(DECIMAL(10,3), [Value]) <= 500
GROUP BY FK_Patient_Link_ID;

-- Then we join to that table in order to get the value of that measurement
IF OBJECT_ID('tempdb..#triglycerides') IS NOT NULL DROP TABLE #triglycerides;
SELECT p.FK_Patient_Link_ID, p.EventDate AS DateOfFirstValue, MAX(p.Value) AS [Value]
INTO #triglycerides
FROM #GPEvents p
INNER JOIN #triglyceridesTEMP1 sub ON sub.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND sub.EventDate = p.EventDate
WHERE SuppliedCode IN (SELECT code FROM #AllCodes WHERE Concept = 'triglycerides' AND Version = 1) 
GROUP BY p.FK_Patient_Link_ID, p.EventDate;

--bring together for final output
SELECT	 PatientId = m.FK_Patient_Link_ID
		,m.YearOfBirth
		,sex.Sex
		,lsoa.LSOA_Code
		,m.EthnicGroupDescription
		,imd.IMD2019Decile1IsMostDeprived10IsLeastDeprived
		,smok.WorstSmokingStatus
		,smok.CurrentSmokingStatus
		,bmi.BMI
		,bmi.DateOfBMIMeasurement
		,alc.WorstAlcoholIntake
		,alc.CurrentAlcoholIntake
		,sle.SLEFirstDiagnosisDate
		,CKDStage = ckd.CKDStageMax
		,Egfr = egf.[Value]
		,Egfr_dt = egf.DateOfFirstValue
		,Creatinine = cre.[Value]
		,Creatinine_dt = cre.DateOfFirstValue
		,HDL_Cholesterol = hdl.[Value]
		,HDL_dt = hdl.DateOfFirstValue
		,LDL_Cholesterol = ldl.[Value]
		,LDL_dt = ldl.DateOfFirstValue
		,Triglycerides = tri.[Value]
		,Triglycerides_dt = tri.DateOfFirstValue
FROM #Cohort m
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientLSOA lsoa ON lsoa.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientIMDDecile imd ON imd.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSmokingStatus smok ON smok.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientBMI bmi ON bmi.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientAlcoholIntake alc ON alc.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #SLEFirstDiagnosis sle ON sle.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #CKDStage ckd ON ckd.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #egfr egf ON egf.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #creatinine cre ON cre.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #hdl_cholesterol hdl ON hdl.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #ldl_cholesterol ldl ON ldl.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #triglycerides tri ON tri.FK_Patient_Link_ID = m.FK_Patient_Link_ID



