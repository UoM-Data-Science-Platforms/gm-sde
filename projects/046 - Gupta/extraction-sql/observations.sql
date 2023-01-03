--┌──────────────────────────────┐
--│ Patients with diabetes 	     │
--└──────────────────────────────┘

---- RESEARCH DATA ENGINEER CHECK ----
-- 1st July 2022 - Richard Williams --
--------------------------------------	

-- OUTPUT: Data with the following fields


DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2020-01-01';
SET @EndDate = '2022-05-01';

--Just want the output, not the messages
SET NOCOUNT ON;

--┌───────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
--│ Create table of patients who are registered with a GM GP, and haven't joined the database from June 2022 onwards  │
--└───────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

-- INPUT REQUIREMENTS: @StartDate

DECLARE @TempEndDate datetime;
SET @TempEndDate = '2022-06-01'; -- THIS TEMP END DATE IS DUE TO THE POST-COPI GOVERNANCE REQUIREMENTS 

IF OBJECT_ID('tempdb..#PatientsToInclude') IS NOT NULL DROP TABLE #PatientsToInclude;
SELECT FK_Patient_Link_ID INTO #PatientsToInclude
FROM RLS.vw_Patient_GP_History
GROUP BY FK_Patient_Link_ID
HAVING MIN(StartDate) < @TempEndDate; -- ENSURES NO PATIENTS THAT ENTERED THE DATABASE FROM JUNE 2022 ONWARDS ARE INCLUDED

-- Find all patients alive at start date
IF OBJECT_ID('tempdb..#PossiblePatients') IS NOT NULL DROP TABLE #PossiblePatients;
SELECT PK_Patient_Link_ID as FK_Patient_Link_ID, EthnicMainGroup, DeathDate INTO #PossiblePatients FROM [RLS].vw_Patient_Link
WHERE 
	(DeathDate IS NULL OR (DeathDate >= @StartDate AND DeathDate <= @TempEndDate))
	AND PK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

-- Find all patients registered with a GP
IF OBJECT_ID('tempdb..#PatientsWithGP') IS NOT NULL DROP TABLE #PatientsWithGP;
SELECT DISTINCT FK_Patient_Link_ID INTO #PatientsWithGP FROM [RLS].vw_Patient
where FK_Reference_Tenancy_ID = 2;

-- Make cohort from patients alive at start date and registered with a GP
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT pp.* INTO #Patients FROM #PossiblePatients pp
INNER JOIN #PatientsWithGP gp on gp.FK_Patient_Link_ID = pp.FK_Patient_Link_ID;

------------------------------------------

-- OUTPUT: #Patients

------------------------------------ CREATE COHORT -------------------------------------
	-- REGISTERED WITH A GM GP
	-- OVER  18
	-- DIABETES DIAGNOSIS

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
VALUES ('diabetes-type-i',1,'C1000',NULL,'Diabetes mellitus, juvenile type, with no mention of complication'),('diabetes-type-i',1,'C100000',NULL,'Diabetes mellitus, juvenile type, with no mention of complication'),('diabetes-type-i',1,'C1010',NULL,'Diabetes mellitus, juvenile type, with ketoacidosis'),('diabetes-type-i',1,'C101000',NULL,'Diabetes mellitus, juvenile type, with ketoacidosis'),('diabetes-type-i',1,'C1020',NULL,'Diabetes mellitus, juvenile type, with hyperosmolar coma'),('diabetes-type-i',1,'C102000',NULL,'Diabetes mellitus, juvenile type, with hyperosmolar coma'),('diabetes-type-i',1,'C1030',NULL,'Diabetes mellitus, juvenile type, with ketoacidotic coma'),('diabetes-type-i',1,'C103000',NULL,'Diabetes mellitus, juvenile type, with ketoacidotic coma'),('diabetes-type-i',1,'C1040',NULL,'Diabetes mellitus, juvenile type, with renal manifestation'),('diabetes-type-i',1,'C104000',NULL,'Diabetes mellitus, juvenile type, with renal manifestation'),('diabetes-type-i',1,'C1050',NULL,'Diabetes mellitus, juvenile type, with ophthalmic manifestation'),('diabetes-type-i',1,'C105000',NULL,'Diabetes mellitus, juvenile type, with ophthalmic manifestation'),('diabetes-type-i',1,'C1060',NULL,'Diabetes mellitus, juvenile type, with neurological manifestation'),('diabetes-type-i',1,'C106000',NULL,'Diabetes mellitus, juvenile type, with neurological manifestation'),('diabetes-type-i',1,'C1070',NULL,'Diabetes mellitus, juvenile type, with peripheral circulatory disorder'),('diabetes-type-i',1,'C107000',NULL,'Diabetes mellitus, juvenile type, with peripheral circulatory disorder'),('diabetes-type-i',1,'C108.',NULL,'Insulin dependent diabetes mellitus'),('diabetes-type-i',1,'C108.00',NULL,'Insulin dependent diabetes mellitus'),('diabetes-type-i',1,'C1080',NULL,'Insulin-dependent diabetes mellitus with renal complications'),('diabetes-type-i',1,'C108000',NULL,'Insulin-dependent diabetes mellitus with renal complications'),('diabetes-type-i',1,'C1081',NULL,'Insulin-dependent diabetes mellitus with ophthalmic complications'),('diabetes-type-i',1,'C108100',NULL,'Insulin-dependent diabetes mellitus with ophthalmic complications'),('diabetes-type-i',1,'C1082',NULL,'Insulin-dependent diabetes mellitus with neurological complications'),('diabetes-type-i',1,'C108200',NULL,'Insulin-dependent diabetes mellitus with neurological complications'),('diabetes-type-i',1,'C1083',NULL,'Insulin dependent diabetes mellitus with multiple complications'),('diabetes-type-i',1,'C108300',NULL,'Insulin dependent diabetes mellitus with multiple complications'),('diabetes-type-i',1,'C1084',NULL,'Unstable insulin dependent diabetes mellitus'),('diabetes-type-i',1,'C108400',NULL,'Unstable insulin dependent diabetes mellitus'),('diabetes-type-i',1,'C1085',NULL,'Insulin dependent diabetes mellitus with ulcer'),('diabetes-type-i',1,'C108500',NULL,'Insulin dependent diabetes mellitus with ulcer'),('diabetes-type-i',1,'C1086',NULL,'Insulin dependent diabetes mellitus with gangrene'),('diabetes-type-i',1,'C108600',NULL,'Insulin dependent diabetes mellitus with gangrene'),('diabetes-type-i',1,'C1087',NULL,'Insulin dependent diabetes mellitus with retinopathy'),('diabetes-type-i',1,'C108700',NULL,'Insulin dependent diabetes mellitus with retinopathy'),('diabetes-type-i',1,'C1088',NULL,'Insulin dependent diabetes mellitus - poor control'),('diabetes-type-i',1,'C108800',NULL,'Insulin dependent diabetes mellitus - poor control'),('diabetes-type-i',1,'C1089',NULL,'Insulin dependent diabetes maturity onset'),('diabetes-type-i',1,'C108900',NULL,'Insulin dependent diabetes maturity onset'),('diabetes-type-i',1,'C108A',NULL,'Insulin-dependent diabetes without complication'),('diabetes-type-i',1,'C108A00',NULL,'Insulin-dependent diabetes without complication'),('diabetes-type-i',1,'C108B',NULL,'Insulin dependent diabetes mellitus with mononeuropathy'),('diabetes-type-i',1,'C108B00',NULL,'Insulin dependent diabetes mellitus with mononeuropathy'),('diabetes-type-i',1,'C108C',NULL,'Insulin dependent diabetes mellitus with polyneuropathy'),('diabetes-type-i',1,'C108C00',NULL,'Insulin dependent diabetes mellitus with polyneuropathy'),('diabetes-type-i',1,'C108D',NULL,'Insulin dependent diabetes mellitus with nephropathy'),('diabetes-type-i',1,'C108D00',NULL,'Insulin dependent diabetes mellitus with nephropathy'),('diabetes-type-i',1,'C108E',NULL,'Insulin dependent diabetes mellitus with hypoglycaemic coma'),('diabetes-type-i',1,'C108E00',NULL,'Insulin dependent diabetes mellitus with hypoglycaemic coma'),('diabetes-type-i',1,'C108F',NULL,'Insulin dependent diabetes mellitus with diabetic cataract'),('diabetes-type-i',1,'C108F00',NULL,'Insulin dependent diabetes mellitus with diabetic cataract'),('diabetes-type-i',1,'C108G',NULL,'Insulin dependent diabetes mellitus with peripheral angiopathy'),('diabetes-type-i',1,'C108G00',NULL,'Insulin dependent diabetes mellitus with peripheral angiopathy'),('diabetes-type-i',1,'C108H',NULL,'Insulin dependent diabetes mellitus with arthropathy'),('diabetes-type-i',1,'C108H00',NULL,'Insulin dependent diabetes mellitus with arthropathy'),('diabetes-type-i',1,'C108J',NULL,'Insulin dependent diabetes mellitus with neuropathic arthropathy'),('diabetes-type-i',1,'C108J00',NULL,'Insulin dependent diabetes mellitus with neuropathic arthropathy'),('diabetes-type-i',1,'C10E.',NULL,'Type 1 diabetes mellitus'),('diabetes-type-i',1,'C10E.00',NULL,'Type 1 diabetes mellitus'),('diabetes-type-i',1,'C10E0',NULL,'Type 1 diabetes mellitus with renal complications'),('diabetes-type-i',1,'C10E000',NULL,'Type 1 diabetes mellitus with renal complications'),('diabetes-type-i',1,'C10E1',NULL,'Type 1 diabetes mellitus with ophthalmic complications'),('diabetes-type-i',1,'C10E100',NULL,'Type 1 diabetes mellitus with ophthalmic complications'),('diabetes-type-i',1,'C10E2',NULL,'Type 1 diabetes mellitus with neurological complications'),('diabetes-type-i',1,'C10E200',NULL,'Type 1 diabetes mellitus with neurological complications'),('diabetes-type-i',1,'C10E3',NULL,'Type 1 diabetes mellitus with multiple complications'),('diabetes-type-i',1,'C10E300',NULL,'Type 1 diabetes mellitus with multiple complications'),('diabetes-type-i',1,'C10E4',NULL,'Unstable type 1 diabetes mellitus'),('diabetes-type-i',1,'C10E400',NULL,'Unstable type 1 diabetes mellitus'),('diabetes-type-i',1,'C10E5',NULL,'Type 1 diabetes mellitus with ulcer'),('diabetes-type-i',1,'C10E500',NULL,'Type 1 diabetes mellitus with ulcer'),('diabetes-type-i',1,'C10E6',NULL,'Type 1 diabetes mellitus with gangrene'),('diabetes-type-i',1,'C10E600',NULL,'Type 1 diabetes mellitus with gangrene'),('diabetes-type-i',1,'C10E7',NULL,'Type 1 diabetes mellitus with retinopathy'),('diabetes-type-i',1,'C10E700',NULL,'Type 1 diabetes mellitus with retinopathy'),('diabetes-type-i',1,'C10E8',NULL,'Type 1 diabetes mellitus - poor control'),('diabetes-type-i',1,'C10E800',NULL,'Type 1 diabetes mellitus - poor control'),('diabetes-type-i',1,'C10E9',NULL,'Type 1 diabetes mellitus maturity onset'),('diabetes-type-i',1,'C10E900',NULL,'Type 1 diabetes mellitus maturity onset'),('diabetes-type-i',1,'C10EA',NULL,'Type 1 diabetes mellitus without complication'),('diabetes-type-i',1,'C10EA00',NULL,'Type 1 diabetes mellitus without complication'),('diabetes-type-i',1,'C10EB',NULL,'Type 1 diabetes mellitus with mononeuropathy'),('diabetes-type-i',1,'C10EB00',NULL,'Type 1 diabetes mellitus with mononeuropathy'),('diabetes-type-i',1,'C10EC',NULL,'Type 1 diabetes mellitus with polyneuropathy'),('diabetes-type-i',1,'C10EC00',NULL,'Type 1 diabetes mellitus with polyneuropathy'),('diabetes-type-i',1,'C10ED',NULL,'Type 1 diabetes mellitus with nephropathy'),('diabetes-type-i',1,'C10ED00',NULL,'Type 1 diabetes mellitus with nephropathy'),('diabetes-type-i',1,'C10EE',NULL,'Type 1 diabetes mellitus with hypoglycaemic coma'),('diabetes-type-i',1,'C10EE00',NULL,'Type 1 diabetes mellitus with hypoglycaemic coma'),('diabetes-type-i',1,'C10EF',NULL,'Type 1 diabetes mellitus with diabetic cataract'),('diabetes-type-i',1,'C10EF00',NULL,'Type 1 diabetes mellitus with diabetic cataract'),('diabetes-type-i',1,'C10EG',NULL,'Type 1 diabetes mellitus with peripheral angiopathy'),('diabetes-type-i',1,'C10EG00',NULL,'Type 1 diabetes mellitus with peripheral angiopathy'),('diabetes-type-i',1,'C10EH',NULL,'Type 1 diabetes mellitus with arthropathy'),('diabetes-type-i',1,'C10EH00',NULL,'Type 1 diabetes mellitus with arthropathy'),('diabetes-type-i',1,'C10EJ',NULL,'Type 1 diabetes mellitus with neuropathic arthropathy'),('diabetes-type-i',1,'C10EJ00',NULL,'Type 1 diabetes mellitus with neuropathic arthropathy'),('diabetes-type-i',1,'C10EK',NULL,'Type 1 diabetes mellitus with persistent proteinuria'),('diabetes-type-i',1,'C10EK00',NULL,'Type 1 diabetes mellitus with persistent proteinuria'),('diabetes-type-i',1,'C10EL',NULL,'Type 1 diabetes mellitus with persistent microalbuminuria'),('diabetes-type-i',1,'C10EL00',NULL,'Type 1 diabetes mellitus with persistent microalbuminuria'),('diabetes-type-i',1,'C10EM',NULL,'Type 1 diabetes mellitus with ketoacidosis'),('diabetes-type-i',1,'C10EM00',NULL,'Type 1 diabetes mellitus with ketoacidosis'),('diabetes-type-i',1,'C10EN',NULL,'Type 1 diabetes mellitus with ketoacidotic coma'),('diabetes-type-i',1,'C10EN00',NULL,'Type 1 diabetes mellitus with ketoacidotic coma'),('diabetes-type-i',1,'C10EP',NULL,'Type 1 diabetes mellitus with exudative maculopathy'),('diabetes-type-i',1,'C10EP00',NULL,'Type 1 diabetes mellitus with exudative maculopathy'),('diabetes-type-i',1,'C10EQ',NULL,'Type 1 diabetes mellitus with gastroparesis'),('diabetes-type-i',1,'C10EQ00',NULL,'Type 1 diabetes mellitus with gastroparesis'),('diabetes-type-i',1,'C10y0',NULL,'Diabetes mellitus, juvenile type, with other specified manifestation'),('diabetes-type-i',1,'C10y000',NULL,'Diabetes mellitus, juvenile type, with other specified manifestation'),('diabetes-type-i',1,'C10z0',NULL,'Diabetes mellitus, juvenile type, with unspecified complication'),
('diabetes-type-i',1,'C10z000',NULL,'Diabetes mellitus, juvenile type, with unspecified complication');
INSERT INTO #codesreadv2
VALUES ('diabetes-type-ii',1,'C1001',NULL,'Diabetes mellitus, adult onset, with no mention of complication'),('diabetes-type-ii',1,'C100100',NULL,'Diabetes mellitus, adult onset, with no mention of complication'),('diabetes-type-ii',1,'C1011',NULL,'Diabetes mellitus, adult onset, with ketoacidosis'),('diabetes-type-ii',1,'C101100',NULL,'Diabetes mellitus, adult onset, with ketoacidosis'),('diabetes-type-ii',1,'C1021',NULL,'Diabetes mellitus, adult onset, with hyperosmolar coma'),('diabetes-type-ii',1,'C102100',NULL,'Diabetes mellitus, adult onset, with hyperosmolar coma'),('diabetes-type-ii',1,'C1031',NULL,'Diabetes mellitus, adult onset, with ketoacidotic coma'),('diabetes-type-ii',1,'C103100',NULL,'Diabetes mellitus, adult onset, with ketoacidotic coma'),('diabetes-type-ii',1,'C1041',NULL,'Diabetes mellitus, adult onset, with renal manifestation'),('diabetes-type-ii',1,'C104100',NULL,'Diabetes mellitus, adult onset, with renal manifestation'),('diabetes-type-ii',1,'C1051',NULL,'Diabetes mellitus, adult onset, with ophthalmic manifestation'),('diabetes-type-ii',1,'C105100',NULL,'Diabetes mellitus, adult onset, with ophthalmic manifestation'),('diabetes-type-ii',1,'C1061',NULL,'Diabetes mellitus, adult onset, with neurological manifestation'),('diabetes-type-ii',1,'C106100',NULL,'Diabetes mellitus, adult onset, with neurological manifestation'),('diabetes-type-ii',1,'C1071',NULL,'Diabetes mellitus, adult onset, with peripheral circulatory disorder'),('diabetes-type-ii',1,'C107100',NULL,'Diabetes mellitus, adult onset, with peripheral circulatory disorder'),('diabetes-type-ii',1,'C109.',NULL,'Non-insulin dependent diabetes mellitus'),('diabetes-type-ii',1,'C109.00',NULL,'Non-insulin dependent diabetes mellitus'),('diabetes-type-ii',1,'C1090',NULL,'Non-insulin-dependent diabetes mellitus with renal complications'),('diabetes-type-ii',1,'C109000',NULL,'Non-insulin-dependent diabetes mellitus with renal complications'),('diabetes-type-ii',1,'C1091',NULL,'Non-insulin-dependent diabetes mellitus with ophthalmic complications'),('diabetes-type-ii',1,'C109100',NULL,'Non-insulin-dependent diabetes mellitus with ophthalmic complications'),('diabetes-type-ii',1,'C1092',NULL,'Non-insulin-dependent diabetes mellitus with neurological complications'),('diabetes-type-ii',1,'C109200',NULL,'Non-insulin-dependent diabetes mellitus with neurological complications'),('diabetes-type-ii',1,'C1093',NULL,'Non-insulin-dependent diabetes mellitus with multiple complications'),('diabetes-type-ii',1,'C109300',NULL,'Non-insulin-dependent diabetes mellitus with multiple complications'),('diabetes-type-ii',1,'C1094',NULL,'Non-insulin dependent diabetes mellitus with ulcer'),('diabetes-type-ii',1,'C109400',NULL,'Non-insulin dependent diabetes mellitus with ulcer'),('diabetes-type-ii',1,'C1095',NULL,'Non-insulin dependent diabetes mellitus with gangrene'),('diabetes-type-ii',1,'C109500',NULL,'Non-insulin dependent diabetes mellitus with gangrene'),('diabetes-type-ii',1,'C1096',NULL,'Non-insulin-dependent diabetes mellitus with retinopathy'),('diabetes-type-ii',1,'C109600',NULL,'Non-insulin-dependent diabetes mellitus with retinopathy'),('diabetes-type-ii',1,'C1097',NULL,'Non-insulin dependent diabetes mellitus - poor control'),('diabetes-type-ii',1,'C109700',NULL,'Non-insulin dependent diabetes mellitus - poor control'),('diabetes-type-ii',1,'C1099',NULL,'Non-insulin-dependent diabetes mellitus without complication'),('diabetes-type-ii',1,'C109900',NULL,'Non-insulin-dependent diabetes mellitus without complication'),('diabetes-type-ii',1,'C109A',NULL,'Non-insulin dependent diabetes mellitus with mononeuropathy'),('diabetes-type-ii',1,'C109A00',NULL,'Non-insulin dependent diabetes mellitus with mononeuropathy'),('diabetes-type-ii',1,'C109B',NULL,'Non-insulin dependent diabetes mellitus with polyneuropathy'),('diabetes-type-ii',1,'C109B00',NULL,'Non-insulin dependent diabetes mellitus with polyneuropathy'),('diabetes-type-ii',1,'C109C',NULL,'Non-insulin dependent diabetes mellitus with nephropathy'),('diabetes-type-ii',1,'C109C00',NULL,'Non-insulin dependent diabetes mellitus with nephropathy'),('diabetes-type-ii',1,'C109D',NULL,'Non-insulin dependent diabetes mellitus with hypoglycaemic coma'),('diabetes-type-ii',1,'C109D00',NULL,'Non-insulin dependent diabetes mellitus with hypoglycaemic coma'),('diabetes-type-ii',1,'C109E',NULL,'Non-insulin dependent diabetes mellitus with diabetic cataract'),('diabetes-type-ii',1,'C109E00',NULL,'Non-insulin dependent diabetes mellitus with diabetic cataract'),('diabetes-type-ii',1,'C109F',NULL,'Non-insulin-dependent diabetes mellitus with peripheral angiopathy'),('diabetes-type-ii',1,'C109F00',NULL,'Non-insulin-dependent diabetes mellitus with peripheral angiopathy'),('diabetes-type-ii',1,'C109G',NULL,'Non-insulin dependent diabetes mellitus with arthropathy'),('diabetes-type-ii',1,'C109G00',NULL,'Non-insulin dependent diabetes mellitus with arthropathy'),('diabetes-type-ii',1,'C109H',NULL,'Non-insulin dependent diabetes mellitus with neuropathic arthropathy'),('diabetes-type-ii',1,'C109H00',NULL,'Non-insulin dependent diabetes mellitus with neuropathic arthropathy'),('diabetes-type-ii',1,'C109J',NULL,'Insulin treated Type 2 diabetes mellitus'),('diabetes-type-ii',1,'C109J00',NULL,'Insulin treated Type 2 diabetes mellitus'),('diabetes-type-ii',1,'C109K',NULL,'Hyperosmolar non-ketotic state in type 2 diabetes mellitus'),('diabetes-type-ii',1,'C109K00',NULL,'Hyperosmolar non-ketotic state in type 2 diabetes mellitus'),('diabetes-type-ii',1,'C10D.',NULL,'Diabetes mellitus autosomal dominant type 2'),('diabetes-type-ii',1,'C10D.00',NULL,'Diabetes mellitus autosomal dominant type 2'),('diabetes-type-ii',1,'C10F.',NULL,'Type 2 diabetes mellitus'),('diabetes-type-ii',1,'C10F.00',NULL,'Type 2 diabetes mellitus'),('diabetes-type-ii',1,'C10F0',NULL,'Type 2 diabetes mellitus with renal complications'),('diabetes-type-ii',1,'C10F000',NULL,'Type 2 diabetes mellitus with renal complications'),('diabetes-type-ii',1,'C10F1',NULL,'Type 2 diabetes mellitus with ophthalmic complications'),('diabetes-type-ii',1,'C10F100',NULL,'Type 2 diabetes mellitus with ophthalmic complications'),('diabetes-type-ii',1,'C10F2',NULL,'Type 2 diabetes mellitus with neurological complications'),('diabetes-type-ii',1,'C10F200',NULL,'Type 2 diabetes mellitus with neurological complications'),('diabetes-type-ii',1,'C10F3',NULL,'Type 2 diabetes mellitus with multiple complications'),('diabetes-type-ii',1,'C10F300',NULL,'Type 2 diabetes mellitus with multiple complications'),('diabetes-type-ii',1,'C10F4',NULL,'Type 2 diabetes mellitus with ulcer'),('diabetes-type-ii',1,'C10F400',NULL,'Type 2 diabetes mellitus with ulcer'),('diabetes-type-ii',1,'C10F5',NULL,'Type 2 diabetes mellitus with gangrene'),('diabetes-type-ii',1,'C10F500',NULL,'Type 2 diabetes mellitus with gangrene'),('diabetes-type-ii',1,'C10F6',NULL,'Type 2 diabetes mellitus with retinopathy'),('diabetes-type-ii',1,'C10F600',NULL,'Type 2 diabetes mellitus with retinopathy'),('diabetes-type-ii',1,'C10F7',NULL,'Type 2 diabetes mellitus - poor control'),('diabetes-type-ii',1,'C10F700',NULL,'Type 2 diabetes mellitus - poor control'),('diabetes-type-ii',1,'C10F9',NULL,'Type 2 diabetes mellitus without complication'),('diabetes-type-ii',1,'C10F900',NULL,'Type 2 diabetes mellitus without complication'),('diabetes-type-ii',1,'C10FA',NULL,'Type 2 diabetes mellitus with mononeuropathy'),('diabetes-type-ii',1,'C10FA00',NULL,'Type 2 diabetes mellitus with mononeuropathy'),('diabetes-type-ii',1,'C10FB',NULL,'Type 2 diabetes mellitus with polyneuropathy'),('diabetes-type-ii',1,'C10FB00',NULL,'Type 2 diabetes mellitus with polyneuropathy'),('diabetes-type-ii',1,'C10FC',NULL,'Type 2 diabetes mellitus with nephropathy'),('diabetes-type-ii',1,'C10FC00',NULL,'Type 2 diabetes mellitus with nephropathy'),('diabetes-type-ii',1,'C10FD',NULL,'Type 2 diabetes mellitus with hypoglycaemic coma'),('diabetes-type-ii',1,'C10FD00',NULL,'Type 2 diabetes mellitus with hypoglycaemic coma'),('diabetes-type-ii',1,'C10FE',NULL,'Type 2 diabetes mellitus with diabetic cataract'),('diabetes-type-ii',1,'C10FE00',NULL,'Type 2 diabetes mellitus with diabetic cataract'),('diabetes-type-ii',1,'C10FF',NULL,'Type 2 diabetes mellitus with peripheral angiopathy'),('diabetes-type-ii',1,'C10FF00',NULL,'Type 2 diabetes mellitus with peripheral angiopathy'),('diabetes-type-ii',1,'C10FG',NULL,'Type 2 diabetes mellitus with arthropathy'),('diabetes-type-ii',1,'C10FG00',NULL,'Type 2 diabetes mellitus with arthropathy'),('diabetes-type-ii',1,'C10FH',NULL,'Type 2 diabetes mellitus with neuropathic arthropathy'),('diabetes-type-ii',1,'C10FH00',NULL,'Type 2 diabetes mellitus with neuropathic arthropathy'),('diabetes-type-ii',1,'C10FJ',NULL,'Insulin treated Type 2 diabetes mellitus'),('diabetes-type-ii',1,'C10FJ00',NULL,'Insulin treated Type 2 diabetes mellitus'),('diabetes-type-ii',1,'C10FK',NULL,'Hyperosmolar non-ketotic state in type 2 diabetes mellitus'),('diabetes-type-ii',1,'C10FK00',NULL,'Hyperosmolar non-ketotic state in type 2 diabetes mellitus'),('diabetes-type-ii',1,'C10FL',NULL,'Type 2 diabetes mellitus with persistent proteinuria'),('diabetes-type-ii',1,'C10FL00',NULL,'Type 2 diabetes mellitus with persistent proteinuria'),('diabetes-type-ii',1,'C10FM',NULL,'Type 2 diabetes mellitus with persistent microalbuminuria'),('diabetes-type-ii',1,'C10FM00',NULL,'Type 2 diabetes mellitus with persistent microalbuminuria'),('diabetes-type-ii',1,'C10FN',NULL,'Type 2 diabetes mellitus with ketoacidosis'),('diabetes-type-ii',1,'C10FN00',NULL,'Type 2 diabetes mellitus with ketoacidosis'),('diabetes-type-ii',1,'C10FP',NULL,'Type 2 diabetes mellitus with ketoacidotic coma'),('diabetes-type-ii',1,'C10FP00',NULL,'Type 2 diabetes mellitus with ketoacidotic coma'),('diabetes-type-ii',1,'C10FQ',NULL,'Type 2 diabetes mellitus with exudative maculopathy'),('diabetes-type-ii',1,'C10FQ00',NULL,'Type 2 diabetes mellitus with exudative maculopathy'),
('diabetes-type-ii',1,'C10FR',NULL,'Type 2 diabetes mellitus with gastroparesis'),('diabetes-type-ii',1,'C10FR00',NULL,'Type 2 diabetes mellitus with gastroparesis'),('diabetes-type-ii',1,'C10y1',NULL,'Diabetes mellitus, adult onset, with other specified manifestation'),('diabetes-type-ii',1,'C10y100',NULL,'Diabetes mellitus, adult onset, with other specified manifestation'),('diabetes-type-ii',1,'C10z1',NULL,'Diabetes mellitus, adult onset, with unspecified complication'),('diabetes-type-ii',1,'C10z100',NULL,'Diabetes mellitus, adult onset, with unspecified complication');
INSERT INTO #codesreadv2
VALUES ('cholesterol',2,'44P..',NULL,'Serum cholesterol'),('cholesterol',2,'44P..00',NULL,'Serum cholesterol'),('cholesterol',2,'44PZ.',NULL,'Serum cholesterol NOS'),('cholesterol',2,'44PZ.00',NULL,'Serum cholesterol NOS'),('cholesterol',2,'44PJ.',NULL,'Serum total cholesterol level'),('cholesterol',2,'44PJ.00',NULL,'Serum total cholesterol level'),('cholesterol',2,'44PH.',NULL,'Total cholesterol measurement'),('cholesterol',2,'44PH.00',NULL,'Total cholesterol measurement');
INSERT INTO #codesreadv2
VALUES ('diastolic-blood-pressure',1,'246o1',NULL,'Non-invasive central diastolic blood pressure'),('diastolic-blood-pressure',1,'246o100',NULL,'Non-invasive central diastolic blood pressure'),('diastolic-blood-pressure',1,'246n0',NULL,'Baseline diastolic blood pressure'),('diastolic-blood-pressure',1,'246n000',NULL,'Baseline diastolic blood pressure'),('diastolic-blood-pressure',1,'246m.',NULL,'Average diastolic blood pressure'),('diastolic-blood-pressure',1,'246m.00',NULL,'Average diastolic blood pressure'),('diastolic-blood-pressure',1,'246i.',NULL,'Diastolic blood pressure centile'),('diastolic-blood-pressure',1,'246i.00',NULL,'Diastolic blood pressure centile'),('diastolic-blood-pressure',1,'246f.',NULL,'Ambulatory diastolic blood pressure'),('diastolic-blood-pressure',1,'246f.00',NULL,'Ambulatory diastolic blood pressure'),('diastolic-blood-pressure',1,'246c.',NULL,'Average home diastolic blood pressure'),('diastolic-blood-pressure',1,'246c.00',NULL,'Average home diastolic blood pressure'),('diastolic-blood-pressure',1,'246a.',NULL,'Average night interval diastolic blood pressure'),('diastolic-blood-pressure',1,'246a.00',NULL,'Average night interval diastolic blood pressure'),('diastolic-blood-pressure',1,'246X.',NULL,'Average day interval diastolic blood pressure'),('diastolic-blood-pressure',1,'246X.00',NULL,'Average day interval diastolic blood pressure'),('diastolic-blood-pressure',1,'246V.',NULL,'Average 24 hour diastolic blood pressure'),('diastolic-blood-pressure',1,'246V.00',NULL,'Average 24 hour diastolic blood pressure'),('diastolic-blood-pressure',1,'246T.',NULL,'Lying diastolic blood pressure'),('diastolic-blood-pressure',1,'246T.00',NULL,'Lying diastolic blood pressure'),('diastolic-blood-pressure',1,'246R.',NULL,'Sitting diastolic blood pressure'),('diastolic-blood-pressure',1,'246R.00',NULL,'Sitting diastolic blood pressure'),('diastolic-blood-pressure',1,'246P.',NULL,'Standing diastolic blood pressure'),('diastolic-blood-pressure',1,'246P.00',NULL,'Standing diastolic blood pressure'),('diastolic-blood-pressure',1,'246L.',NULL,'Target diastolic blood pressure'),('diastolic-blood-pressure',1,'246L.00',NULL,'Target diastolic blood pressure'),('diastolic-blood-pressure',1,'246A.',NULL,'O/E - Diastolic BP reading'),('diastolic-blood-pressure',1,'246A.00',NULL,'O/E - Diastolic BP reading');
INSERT INTO #codesreadv2
VALUES ('egfr',1,'451E.',NULL,'Glomerular filtration rate calculated by abbreviated Modification of Diet in Renal Disease Study Group calculation'),('egfr',1,'451E.00',NULL,'Glomerular filtration rate calculated by abbreviated Modification of Diet in Renal Disease Study Group calculation'),('egfr',1,'451G.',NULL,'Glomerular filtration rate calculated by abbreviated Modification of Diet in Renal Disease Study Group calculation adjusted for African American origin'),('egfr',1,'451G.00',NULL,'Glomerular filtration rate calculated by abbreviated Modification of Diet in Renal Disease Study Group calculation adjusted for African American origin'),('egfr',1,'451K.',NULL,'Estimated glomerular filtration rate using Chronic Kidney Disease Epidemiology Collaboration formula per 1.73 square metres'),('egfr',1,'451K.00',NULL,'Estimated glomerular filtration rate using Chronic Kidney Disease Epidemiology Collaboration formula per 1.73 square metres'),('egfr',1,'451M.',NULL,'Estimated glomerular filtration rate using cystatin C Chronic Kidney Disease Epidemiology Collaboration equation per 1.73 square metres'),('egfr',1,'451M.00',NULL,'Estimated glomerular filtration rate using cystatin C Chronic Kidney Disease Epidemiology Collaboration equation per 1.73 square metres'),('egfr',1,'451N.',NULL,'Estimated glomerular filtration rate using creatinine Chronic Kidney Disease Epidemiology Collaboration equation per 1.73 square metres'),('egfr',1,'451N.00',NULL,'Estimated glomerular filtration rate using creatinine Chronic Kidney Disease Epidemiology Collaboration equation per 1.73 square metres');
INSERT INTO #codesreadv2
VALUES ('hba1c',2,'42W5.',NULL,'Haemoglobin A1c level - International Federation of Clinical Chemistry and Laboratory Medicine standardised'),('hba1c',2,'42W5.00',NULL,'Haemoglobin A1c level - International Federation of Clinical Chemistry and Laboratory Medicine standardised'),('hba1c',2,'42W4.',NULL,'HbA1c level (DCCT aligned)'),('hba1c',2,'42W4.00',NULL,'HbA1c level (DCCT aligned)');
INSERT INTO #codesreadv2
VALUES ('hdl-cholesterol',1,'44PC.',NULL,'Serum random HDL cholesterol level'),('hdl-cholesterol',1,'44PC.00',NULL,'Serum random HDL cholesterol level'),('hdl-cholesterol',1,'44P5.',NULL,'Serum HDL cholesterol level'),('hdl-cholesterol',1,'44P5.00',NULL,'Serum HDL cholesterol level'),('hdl-cholesterol',1,'44dA.',NULL,'Plasma HDL cholesterol level'),('hdl-cholesterol',1,'44dA.00',NULL,'Plasma HDL cholesterol level');
INSERT INTO #codesreadv2
VALUES ('ldl-cholesterol',1,'44PI.',NULL,'Calculated LDL cholesterol level'),('ldl-cholesterol',1,'44PI.00',NULL,'Calculated LDL cholesterol level'),('ldl-cholesterol',1,'44P6.',NULL,'Serum LDL cholesterol level'),('ldl-cholesterol',1,'44P6.00',NULL,'Serum LDL cholesterol level'),('ldl-cholesterol',1,'44dB.',NULL,'Plasma LDL cholesterol level'),('ldl-cholesterol',1,'44dB.00',NULL,'Plasma LDL cholesterol level');
INSERT INTO #codesreadv2
VALUES ('systolic-blood-pressure',1,'246o0',NULL,'Non-invasive central systolic blood pressure'),('systolic-blood-pressure',1,'246o000',NULL,'Non-invasive central systolic blood pressure'),('systolic-blood-pressure',1,'246n1',NULL,'Baseline systolic blood pressure'),('systolic-blood-pressure',1,'246n100',NULL,'Baseline systolic blood pressure'),('systolic-blood-pressure',1,'246l.',NULL,'Average systolic blood pressure'),('systolic-blood-pressure',1,'246l.00',NULL,'Average systolic blood pressure'),('systolic-blood-pressure',1,'246j.',NULL,'Systolic blood pressure centile'),('systolic-blood-pressure',1,'246j.00',NULL,'Systolic blood pressure centile'),('systolic-blood-pressure',1,'246e.',NULL,'Ambulatory systolic blood pressure'),('systolic-blood-pressure',1,'246e.00',NULL,'Ambulatory systolic blood pressure'),('systolic-blood-pressure',1,'246d.',NULL,'Average home systolic blood pressure'),('systolic-blood-pressure',1,'246d.00',NULL,'Average home systolic blood pressure'),('systolic-blood-pressure',1,'246b.',NULL,'Average night interval systolic blood pressure'),('systolic-blood-pressure',1,'246b.00',NULL,'Average night interval systolic blood pressure'),('systolic-blood-pressure',1,'246Y.',NULL,'Average day interval systolic blood pressure'),('systolic-blood-pressure',1,'246Y.00',NULL,'Average day interval systolic blood pressure'),('systolic-blood-pressure',1,'246W.',NULL,'Average 24 hour systolic blood pressure'),('systolic-blood-pressure',1,'246W.00',NULL,'Average 24 hour systolic blood pressure'),('systolic-blood-pressure',1,'246S.',NULL,'Lying systolic blood pressure'),('systolic-blood-pressure',1,'246S.00',NULL,'Lying systolic blood pressure'),('systolic-blood-pressure',1,'246Q.',NULL,'Sitting systolic blood pressure'),('systolic-blood-pressure',1,'246Q.00',NULL,'Sitting systolic blood pressure'),('systolic-blood-pressure',1,'246N.',NULL,'Standing systolic blood pressure'),('systolic-blood-pressure',1,'246N.00',NULL,'Standing systolic blood pressure'),('systolic-blood-pressure',1,'246K.',NULL,'Target systolic blood pressure'),('systolic-blood-pressure',1,'246K.00',NULL,'Target systolic blood pressure'),('systolic-blood-pressure',1,'2469.',NULL,'O/E - Systolic BP reading'),('systolic-blood-pressure',1,'2469.00',NULL,'O/E - Systolic BP reading');
INSERT INTO #codesreadv2
VALUES ('triglycerides',1,'44Q..',NULL,'Serum triglycerides'),('triglycerides',1,'44Q..00',NULL,'Serum triglycerides'),('triglycerides',1,'44Q4.',NULL,'Serum fasting triglyceride level'),('triglycerides',1,'44Q4.00',NULL,'Serum fasting triglyceride level'),('triglycerides',1,'44Q5.',NULL,'Serum random triglyceride level'),('triglycerides',1,'44Q5.00',NULL,'Serum random triglyceride level'),('triglycerides',1,'44QZ.',NULL,'Serum triglycerides NOS'),('triglycerides',1,'44QZ.00',NULL,'Serum triglycerides NOS')

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
VALUES ('diabetes-type-i',1,'C1000',NULL,'Diabetes mellitus, juvenile type, with no mention of complication'),('diabetes-type-i',1,'C1010',NULL,'Diabetes mellitus, juvenile type, with ketoacidosis'),('diabetes-type-i',1,'C1020',NULL,'Diabetes mellitus, juvenile type, with hyperosmolar coma'),('diabetes-type-i',1,'C1030',NULL,'Diabetes mellitus, juvenile type, with ketoacidotic coma'),('diabetes-type-i',1,'C1040',NULL,'Diabetes mellitus, juvenile type, with renal manifestation'),('diabetes-type-i',1,'C1050',NULL,'Diabetes mellitus, juvenile type, with ophthalmic manifestation'),('diabetes-type-i',1,'C1060',NULL,'Diabetes mellitus, juvenile type, with neurological manifestation'),('diabetes-type-i',1,'C1070',NULL,'Diabetes mellitus, juvenile type, with peripheral circulatory disorder'),('diabetes-type-i',1,'C1080',NULL,'Insulin-dependent diabetes mellitus with renal complications'),('diabetes-type-i',1,'C1081',NULL,'Insulin-dependent diabetes mellitus with ophthalmic complications'),('diabetes-type-i',1,'C1082',NULL,'Insulin-dependent diabetes mellitus with neurological complications'),('diabetes-type-i',1,'C1083',NULL,'Insulin-dependent diabetes mellitus with multiple complications'),('diabetes-type-i',1,'C1085',NULL,'Insulin-dependent diabetes mellitus with ulcer'),('diabetes-type-i',1,'C1086',NULL,'Insulin-dependent diabetes mellitus with gangrene'),('diabetes-type-i',1,'C1087',NULL,'IDDM - Insulin-dependent diabetes mellitus with retinopathy'),('diabetes-type-i',1,'C1088',NULL,'Insulin-dependent diabetes mellitus - poor control'),('diabetes-type-i',1,'C1089',NULL,'Insulin-dependent diabetes maturity onset'),('diabetes-type-i',1,'C10y0',NULL,'Diabetes mellitus, juvenile type, with other specified manifestation'),('diabetes-type-i',1,'C10z0',NULL,'Diabetes mellitus, juvenile type, with unspecified complication'),('diabetes-type-i',1,'X40J4',NULL,'Insulin-dependent diabetes mellitus'),('diabetes-type-i',1,'X40JY',NULL,'Congenital insulin-dependent diabetes mellitus with fatal secretory diarrhoea'),('diabetes-type-i',1,'XE10E',NULL,'Diabetes mellitus, juvenile type, with no mention of complication'),('diabetes-type-i',1,'XE12C',NULL,'Insulin dependent diabetes mel'),('diabetes-type-i',1,'XM19i',NULL,'[EDTA] Diabetes Type I (insulin dependent) associated with renal failure'),('diabetes-type-i',1,'Xa4g7',NULL,'Unstable type 1 diabetes mellitus'),('diabetes-type-i',1,'XaA6b',NULL,'Perceived control of insulin-dependent diabetes'),('diabetes-type-i',1,'XaELP',NULL,'Insulin-dependent diabetes without complication'),('diabetes-type-i',1,'XaEnn',NULL,'Type I diabetes mellitus with mononeuropathy'),('diabetes-type-i',1,'XaEno',NULL,'Insulin dependent diabetes mellitus with polyneuropathy'),('diabetes-type-i',1,'XaF04',NULL,'Type 1 diabetes mellitus with nephropathy'),('diabetes-type-i',1,'XaFWG',NULL,'Type 1 diabetes mellitus with hypoglycaemic coma'),('diabetes-type-i',1,'XaFm8',NULL,'Type 1 diabetes mellitus with diabetic cataract'),('diabetes-type-i',1,'XaFmK',NULL,'Type I diabetes mellitus with peripheral angiopathy'),('diabetes-type-i',1,'XaFmL',NULL,'Type 1 diabetes mellitus with arthropathy'),('diabetes-type-i',1,'XaFmM',NULL,'Type 1 diabetes mellitus with neuropathic arthropathy'),('diabetes-type-i',1,'XaIzM',NULL,'Type 1 diabetes mellitus with persistent proteinuria'),('diabetes-type-i',1,'XaIzN',NULL,'Type 1 diabetes mellitus with persistent microalbuminuria'),('diabetes-type-i',1,'XaJSr',NULL,'Type I diabetes mellitus with exudative maculopathy'),('diabetes-type-i',1,'XaKyW',NULL,'Type I diabetes mellitus with gastroparesis');
INSERT INTO #codesctv3
VALUES ('diabetes-type-ii',1,'C1011',NULL,'Diabetes mellitus, adult onset, with ketoacidosis'),('diabetes-type-ii',1,'C1021',NULL,'Diabetes mellitus, adult onset, with hyperosmolar coma'),('diabetes-type-ii',1,'C1031',NULL,'Diabetes mellitus, adult onset, with ketoacidotic coma'),('diabetes-type-ii',1,'C1041',NULL,'Diabetes mellitus, adult onset, with renal manifestation'),('diabetes-type-ii',1,'C1051',NULL,'Diabetes mellitus, adult onset, with ophthalmic manifestation'),('diabetes-type-ii',1,'C1061',NULL,'Diabetes mellitus, adult onset, with neurological manifestation'),('diabetes-type-ii',1,'C1071',NULL,'Diabetes mellitus, adult onset, with peripheral circulatory disorder'),('diabetes-type-ii',1,'C1090',NULL,'Non-insulin-dependent diabetes mellitus with renal complications'),('diabetes-type-ii',1,'C1091',NULL,'Non-insulin-dependent diabetes mellitus with ophthalmic complications'),('diabetes-type-ii',1,'C1092',NULL,'Non-insulin-dependent diabetes mellitus with neurological complications'),('diabetes-type-ii',1,'C1093',NULL,'Non-insulin-dependent diabetes mellitus with multiple complications'),('diabetes-type-ii',1,'C1094',NULL,'Non-insulin-dependent diabetes mellitus with ulcer'),('diabetes-type-ii',1,'C1095',NULL,'Non-insulin-dependent diabetes mellitus with gangrene'),('diabetes-type-ii',1,'C1096',NULL,'NIDDM - Non-insulin-dependent diabetes mellitus with retinopathy'),('diabetes-type-ii',1,'C1097',NULL,'Non-insulin-dependent diabetes mellitus - poor control'),('diabetes-type-ii',1,'C10y1',NULL,'Diabetes mellitus, adult onset, with other specified manifestation'),('diabetes-type-ii',1,'C10z1',NULL,'Diabetes mellitus, adult onset, with unspecified complication'),('diabetes-type-ii',1,'X40J5',NULL,'Non-insulin-dependent diabetes mellitus'),('diabetes-type-ii',1,'X40J6',NULL,'Insulin treated Type 2 diabetes mellitus'),('diabetes-type-ii',1,'X40JJ',NULL,'Diabetes mellitus autosomal dominant type 2'),('diabetes-type-ii',1,'XE10F',NULL,'Diabetes mellitus, adult onset, with no mention of complication'),('diabetes-type-ii',1,'XM19j',NULL,'[EDTA] Diabetes Type II (non-insulin-dependent) associated with renal failure'),('diabetes-type-ii',1,'XaELQ',NULL,'Non-insulin-dependent diabetes mellitus without complication'),('diabetes-type-ii',1,'XaEnp',NULL,'Type II diabetes mellitus with mononeuropathy'),('diabetes-type-ii',1,'XaEnq',NULL,'Type 2 diabetes mellitus with polyneuropathy'),('diabetes-type-ii',1,'XaF05',NULL,'Type 2 diabetes mellitus with nephropathy'),('diabetes-type-ii',1,'XaFWI',NULL,'Type II diabetes mellitus with hypoglycaemic coma'),('diabetes-type-ii',1,'XaFmA',NULL,'Type II diabetes mellitus with diabetic cataract'),('diabetes-type-ii',1,'XaFn7',NULL,'Non-insulin-dependent diabetes mellitus with peripheral angiopathy'),('diabetes-type-ii',1,'XaFn8',NULL,'Non-insulin dependent diabetes mellitus with arthropathy'),('diabetes-type-ii',1,'XaFn9',NULL,'Non-insulin dependent diabetes mellitus with neuropathic arthropathy'),('diabetes-type-ii',1,'XaIfG',NULL,'Type II diabetes on insulin'),('diabetes-type-ii',1,'XaIfI',NULL,'Type II diabetes on diet only'),('diabetes-type-ii',1,'XaIrf',NULL,'Hyperosmolar non-ketotic state in type II diabetes mellitus'),('diabetes-type-ii',1,'XaIzQ',NULL,'Type 2 diabetes mellitus with persistent proteinuria'),('diabetes-type-ii',1,'XaIzR',NULL,'Type 2 diabetes mellitus with persistent microalbuminuria'),('diabetes-type-ii',1,'XaJQp',NULL,'Type II diabetes mellitus with exudative maculopathy'),('diabetes-type-ii',1,'XaKyX',NULL,'Type II diabetes mellitus with gastroparesis');
INSERT INTO #codesctv3
VALUES ('cholesterol',2,'XSK14',NULL,'Total cholesterol measurement'),('cholesterol',2,'44PH.',NULL,'Total cholesterol measurement'),('cholesterol',2,'44PJ.',NULL,'Serum total cholesterol level'),('cholesterol',2,'44P..',NULL,'Serum cholesterol'),('cholesterol',2,'44PZ.',NULL,'Serum cholesterol NOS'),('cholesterol',2,'XE2eD',NULL,'Serum cholesterol'),('cholesterol',2,'XaJe9',NULL,'Serum total cholesterol level');
INSERT INTO #codesctv3
VALUES ('diastolic-blood-pressure',1,'X779S',NULL,'DAP-Diastolic arterial pressur'),('diastolic-blood-pressure',1,'X779T',NULL,'DAP-Diastolic arterial pressur'),('diastolic-blood-pressure',1,'Xac5K',NULL,'Baseline diastolic BP'),('diastolic-blood-pressure',1,'Xaedp',NULL,'Non-invasive centrl diastlc BP'),('diastolic-blood-pressure',1,'XaF4a',NULL,'Ave day diastol blood pressure'),('diastolic-blood-pressure',1,'XaF4b',NULL,'Ave 24h diastol blood pressure'),('diastolic-blood-pressure',1,'XaF4e',NULL,'24h diastolic blood pressure'),('diastolic-blood-pressure',1,'XaF4Q',NULL,'Min diastolic blood pressure'),('diastolic-blood-pressure',1,'XaF4R',NULL,'Max diastolic blood pressure'),('diastolic-blood-pressure',1,'XaF4S',NULL,'Ave diastolic blood pressure'),('diastolic-blood-pressure',1,'XaF4T',NULL,'Min day diastol blood pressure'),('diastolic-blood-pressure',1,'XaF4U',NULL,'Min night diast blood pressure'),('diastolic-blood-pressure',1,'XaF4V',NULL,'Min 24h diastol blood pressure'),('diastolic-blood-pressure',1,'XaF4W',NULL,'Max night diast blood pressure'),('diastolic-blood-pressure',1,'XaF4X',NULL,'Max day diast blood pressure'),('diastolic-blood-pressure',1,'XaF4Y',NULL,'Max 24h diastol blood pressure'),('diastolic-blood-pressure',1,'XaF4Z',NULL,'Ave night diast blood pressure'),('diastolic-blood-pressure',1,'XaIwk',NULL,'Standing diastolic BP'),('diastolic-blood-pressure',1,'XaJ2F',NULL,'Sitting diastolic BP'),('diastolic-blood-pressure',1,'XaJ2H',NULL,'Lying diastolic blood pressure'),('diastolic-blood-pressure',1,'XaKFw',NULL,'Average home diastolic BP'),('diastolic-blood-pressure',1,'XaKjG',NULL,'Ambulatory diastolic BP'),('diastolic-blood-pressure',1,'XaYg8',NULL,'Diastolic BP centile'),('diastolic-blood-pressure',1,'XM02Y',NULL,'DAP-Diastolic arterial pressur'),('diastolic-blood-pressure',1,'246o1',NULL,'Non-invasive central diastolic blood pressure'),('diastolic-blood-pressure',1,'246n0',NULL,'Baseline diastolic blood pressure'),('diastolic-blood-pressure',1,'246m.',NULL,'Average diastolic blood pressure'),('diastolic-blood-pressure',1,'246i.',NULL,'Diastolic blood pressure centile'),('diastolic-blood-pressure',1,'246f.',NULL,'Ambulatory diastolic blood pressure'),('diastolic-blood-pressure',1,'246c.',NULL,'Average home diastolic blood pressure'),('diastolic-blood-pressure',1,'246a.',NULL,'Average night interval diastolic blood pressure'),('diastolic-blood-pressure',1,'246X.',NULL,'Average day interval diastolic blood pressure'),('diastolic-blood-pressure',1,'246V.',NULL,'Average 24 hour diastolic blood pressure'),('diastolic-blood-pressure',1,'246T.',NULL,'Lying diastolic blood pressure'),('diastolic-blood-pressure',1,'246R.',NULL,'Sitting diastolic blood pressure'),('diastolic-blood-pressure',1,'246P.',NULL,'Standing diastolic blood pressure'),('diastolic-blood-pressure',1,'246L.',NULL,'Target diastolic blood pressure'),('diastolic-blood-pressure',1,'246A.',NULL,'O/E - Diastolic BP reading');
INSERT INTO #codesctv3
VALUES ('egfr',1,'X70kK',NULL,'Tc99m-DTPA clearance - GFR'),('egfr',1,'X70kL',NULL,'Cr51- EDTA clearance - GFR'),('egfr',1,'X90kf',NULL,'With GFR'),('egfr',1,'XaK8y',NULL,'Glomerular filtration rate calculated by abbreviated Modification of Diet in Renal Disease Study Group calculation'),('egfr',1,'XaMDA',NULL,'Glomerular filtration rate calculated by abbreviated Modification of Diet in Renal Disease Study Group calculation adjusted for African American origin'),('egfr',1,'XaZpN',NULL,'Estimated glomerular filtration rate using Chronic Kidney Disease Epidemiology Collaboration formula per 1.73 square metres'),('egfr',1,'XacUJ',NULL,'Estimated glomerular filtration rate using cystatin C Chronic Kidney Disease Epidemiology Collaboration equation per 1.73 square metres'),('egfr',1,'XacUK',NULL,'Estimated glomerular filtration rate using creatinine Chronic Kidney Disease Epidemiology Collaboration equation per 1.73 square metres');
INSERT INTO #codesctv3
VALUES ('hba1c',2,'XaERp',NULL,'HbA1c level (DCCT aligned)'),('hba1c',2,'XaPbt',NULL,'HbA1c levl - IFCC standardised'),('hba1c',2,'42W5.',NULL,'Haemoglobin A1c level - International Federation of Clinical Chemistry and Laboratory Medicine standardised'),('hba1c',2,'42W4.',NULL,'HbA1c level (DCCT aligned)');
INSERT INTO #codesctv3
VALUES ('hdl-cholesterol',1,'44P5.',NULL,'Serum HDL cholesterol level'),('hdl-cholesterol',1,'44PC.',NULL,'Ser random HDL cholesterol lev'),('hdl-cholesterol',1,'XaEVr',NULL,'Plasma HDL cholesterol level');
INSERT INTO #codesctv3
VALUES ('ldl-cholesterol',1,'44P6.',NULL,'Serum LDL cholesterol level'),('ldl-cholesterol',1,'XaIp4',NULL,'Calculated LDL cholesterol lev'),('ldl-cholesterol',1,'XaEVs',NULL,'Plasma LDL cholesterol level');
INSERT INTO #codesctv3
VALUES ('systolic-blood-pressure',1,'X779Q',NULL,'Non-invasive systol art press'),('systolic-blood-pressure',1,'X779R',NULL,'Invasive systol arterial press'),('systolic-blood-pressure',1,'Xac5L',NULL,'Baseline systolic BP'),('systolic-blood-pressure',1,'Xaedo',NULL,'Non-invasive central systlc BP'),('systolic-blood-pressure',1,'XaF4d',NULL,'24h systolic blood pressure'),('systolic-blood-pressure',1,'XaF4D',NULL,'Min systolic blood pressure'),('systolic-blood-pressure',1,'XaF4E',NULL,'Max systolic blood pressure'),('systolic-blood-pressure',1,'XaF4F',NULL,'Ave systolic blood pressure'),('systolic-blood-pressure',1,'XaF4G',NULL,'Min day systol blood pressure'),('systolic-blood-pressure',1,'XaF4H',NULL,'Min night syst blood pressure'),('systolic-blood-pressure',1,'XaF4I',NULL,'Max night syst blood pressure'),('systolic-blood-pressure',1,'XaF4J',NULL,'Max day syst blood pressure'),('systolic-blood-pressure',1,'XaF4K',NULL,'Ave night syst blood pressure'),('systolic-blood-pressure',1,'XaF4L',NULL,'Ave day systol blood pressure'),('systolic-blood-pressure',1,'XaF4M',NULL,'Min 24h systol blood pressure'),('systolic-blood-pressure',1,'XaF4N',NULL,'Max 24h systol blood pressure'),('systolic-blood-pressure',1,'XaF4O',NULL,'Ave 24h systol blood pressure'),('systolic-blood-pressure',1,'XaIwj',NULL,'Standing systolic BP'),('systolic-blood-pressure',1,'XaJ2E',NULL,'Sitting systolic BP'),('systolic-blood-pressure',1,'XaJ2G',NULL,'Lying systolic blood pressure'),('systolic-blood-pressure',1,'XaKFx',NULL,'Average home systolic BP'),('systolic-blood-pressure',1,'XaKjF',NULL,'Ambulatory systolic BP'),('systolic-blood-pressure',1,'XaXfX',NULL,'Post exerc sys BP respons norm'),('systolic-blood-pressure',1,'XaXfY',NULL,'Post exer sys BP respon abnorm'),('systolic-blood-pressure',1,'XaYg9',NULL,'Systolic BP centile'),('systolic-blood-pressure',1,'XM02X',NULL,'SAP - Systol arterial pressure'),('systolic-blood-pressure',1,'246o0',NULL,'Non-invasive central systolic blood pressure'),('systolic-blood-pressure',1,'246n1',NULL,'Baseline systolic blood pressure'),('systolic-blood-pressure',1,'246l.',NULL,'Average systolic blood pressure'),('systolic-blood-pressure',1,'246j.',NULL,'Systolic blood pressure centile'),('systolic-blood-pressure',1,'246e.',NULL,'Ambulatory systolic blood pressure'),('systolic-blood-pressure',1,'246d.',NULL,'Average home systolic blood pressure'),('systolic-blood-pressure',1,'246b.',NULL,'Average night interval systolic blood pressure'),('systolic-blood-pressure',1,'246Y.',NULL,'Average day interval systolic blood pressure'),('systolic-blood-pressure',1,'246W.',NULL,'Average 24 hour systolic blood pressure'),('systolic-blood-pressure',1,'246S.',NULL,'Lying systolic blood pressure'),('systolic-blood-pressure',1,'246Q.',NULL,'Sitting systolic blood pressure'),('systolic-blood-pressure',1,'246N.',NULL,'Standing systolic blood pressure'),('systolic-blood-pressure',1,'246K.',NULL,'Target systolic blood pressure'),('systolic-blood-pressure',1,'2469.',NULL,'O/E - Systolic BP reading');
INSERT INTO #codesctv3
VALUES ('triglycerides',1,'XE2q9',NULL,'Serum triglycerides'),('triglycerides',1,'XE2q9',NULL,'Serum triglyceride levels'),('triglycerides',1,'44Q4.',NULL,'Serum fasting triglyceride level'),('triglycerides',1,'44QZ.',NULL,'Serum triglycerides NOS')

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
VALUES ('cholesterol',2,'1005671000000105',NULL,'Serum cholesterol level'),('cholesterol',2,'412808005',NULL,'Serum total cholesterol level'),('cholesterol',2,'121868005',NULL,'Total cholesterol measurement (procedure)'),('cholesterol',2,'994351000000103',NULL,'Serum total cholesterol level');
INSERT INTO #codessnomed
VALUES ('diastolic-blood-pressure',1,'174255007',NULL,'Non-invasive diastolic blood pressure'),('diastolic-blood-pressure',1,'251073000',NULL,'Invasive diastolic blood pressure'),('diastolic-blood-pressure',1,'271650006',NULL,'Diastolic arterial pressure'),('diastolic-blood-pressure',1,'314451001',NULL,'Minimum diastolic blood pressure (observable entity)'),('diastolic-blood-pressure',1,'314452008',NULL,'Maximum diastolic blood pressure (observable entity)'),('diastolic-blood-pressure',1,'314453003',NULL,'Average diastolic blood pressure (observable entity)'),('diastolic-blood-pressure',1,'314454009',NULL,'Minimum day interval diastolic blood pressure (observable entity)'),('diastolic-blood-pressure',1,'314455005',NULL,'Minimum night interval diastolic blood pressure (observable entity)'),('diastolic-blood-pressure',1,'314456006',NULL,'Minimum 24 hour diastolic blood pressure (observable entity)'),('diastolic-blood-pressure',1,'314457002',NULL,'Maximum night interval diastolic blood pressure (observable entity)'),('diastolic-blood-pressure',1,'314458007',NULL,'Maximum day interval diastolic blood pressure (observable entity)'),('diastolic-blood-pressure',1,'314459004',NULL,'Maximum 24 hour diastolic blood pressure (observable entity)'),('diastolic-blood-pressure',1,'314460009',NULL,'Average night interval diastolic blood pressure (observable entity)'),('diastolic-blood-pressure',1,'314461008',NULL,'Average day interval diastolic blood pressure (observable entity)'),('diastolic-blood-pressure',1,'314462001',NULL,'Average 24 hour diastolic blood pressure (observable entity)'),('diastolic-blood-pressure',1,'314465004',NULL,'24 hour diastolic blood pressure (observable entity)'),('diastolic-blood-pressure',1,'400975005',NULL,'Standing diastolic blood pressure'),('diastolic-blood-pressure',1,'407555005',NULL,'Sitting diastolic blood pressure'),('diastolic-blood-pressure',1,'407557002',NULL,'Lying diastolic blood pressure'),('diastolic-blood-pressure',1,'413605002',NULL,'Average home diastolic blood pressure'),('diastolic-blood-pressure',1,'446226005',NULL,'Diastolic blood pressure on admission'),('diastolic-blood-pressure',1,'716632005',NULL,'Baseline diastolic blood pressure'),('diastolic-blood-pressure',1,'198091000000104',NULL,'Ambulatory diastolic blood pressure'),('diastolic-blood-pressure',1,'814081000000101',NULL,'Diastolic blood pressure centile'),('diastolic-blood-pressure',1,'1091811000000102',NULL,'Diastolic arterial pressure (observable entity)'),('diastolic-blood-pressure',1,'1036571000000105',NULL,'Non-invasive central diastolic blood pressure'),('diastolic-blood-pressure',1,'23154005',NULL,'Increased diastolic arterial pressure (finding)'),('diastolic-blood-pressure',1,'42689008',NULL,'Decreased diastolic arterial pressure (finding)'),('diastolic-blood-pressure',1,'49844009',NULL,'Abnormal diastolic arterial pressure (finding)'),('diastolic-blood-pressure',1,'53813002',NULL,'Normal diastolic arterial pressure (finding)'),('diastolic-blood-pressure',1,'163031004',NULL,'On examination - Diastolic BP reading');
INSERT INTO #codessnomed
VALUES ('egfr',1,'1011481000000105',NULL,'eGFR (estimated glomerular filtration rate) using creatinine Chronic Kidney Disease Epidemiology Collaboration equation per 1.73 square metres'),('egfr',1,'1011491000000107',NULL,'eGFR (estimated glomerular filtration rate) using cystatin C Chronic Kidney Disease Epidemiology Collaboration equation per 1.73 square metres'),('egfr',1,'1020291000000106',NULL,'GFR (glomerular filtration rate) calculated by abbreviated Modification of Diet in Renal Disease Study Group calculation'),('egfr',1,'1107411000000104',NULL,'eGFR (estimated glomerular filtration rate) by laboratory calculation'),('egfr',1,'241373003',NULL,'Technetium-99m-diethylenetriamine pentaacetic acid clearance - glomerular filtration rate (procedure)'),('egfr',1,'262300005',NULL,'With glomerular filtration rate'),('egfr',1,'737105002',NULL,'GFR (glomerular filtration rate) calculation technique'),('egfr',1,'80274001',NULL,'Glomerular filtration rate (observable entity)'),('egfr',1,'996231000000108',NULL,'GFR (glomerular filtration rate) calculated by abbreviated Modification of Diet in Renal Disease Study Group calculation adjusted for African American origin');
INSERT INTO #codessnomed
VALUES ('hba1c',2,'1019431000000105',NULL,'HbA1c level (Diabetes Control and Complications Trial aligned)'),('hba1c',2,'999791000000106',NULL,'Haemoglobin A1c level - International Federation of Clinical Chemistry and Laboratory Medicine standardised');
INSERT INTO #codessnomed
VALUES ('hdl-cholesterol',1,'1005681000000107',NULL,'Serum high density lipoprotein cholesterol level (observable entity)'),('hdl-cholesterol',1,'1010581000000101',NULL,'Plasma high density lipoprotein cholesterol level (observable entity)'),('hdl-cholesterol',1,'1026461000000104',NULL,'Serum random high density lipoprotein cholesterol level (observable entity)');
INSERT INTO #codessnomed
VALUES ('ldl-cholesterol',1,'1010591000000104',NULL,'Plasma low density lipoprotein cholesterol level (observable entity)'),('ldl-cholesterol',1,'1014501000000104',NULL,'Calculated low density lipoprotein cholesterol level (observable entity)'),('ldl-cholesterol',1,'1022191000000100',NULL,'Serum low density lipoprotein cholesterol level (observable entity)');
INSERT INTO #codessnomed
VALUES ('systolic-blood-pressure',1,'72313002',NULL,'Systolic arterial pressure (observable entity)'),('systolic-blood-pressure',1,'251070002',NULL,'Non-invasive systolic blood pressure'),('systolic-blood-pressure',1,'251071003',NULL,'Invasive systolic blood pressure'),('systolic-blood-pressure',1,'271649006',NULL,'SAP - Systolic arterial pressure'),('systolic-blood-pressure',1,'314438006',NULL,'Minimum systolic blood pressure (observable entity)'),('systolic-blood-pressure',1,'314439003',NULL,'Maximum systolic blood pressure (observable entity)'),('systolic-blood-pressure',1,'314440001',NULL,'Average systolic blood pressure (observable entity)'),('systolic-blood-pressure',1,'314441002',NULL,'Minimum day interval systolic blood pressure (observable entity)'),('systolic-blood-pressure',1,'314442009',NULL,'Minimum night interval systolic blood pressure (observable entity)'),('systolic-blood-pressure',1,'314443004',NULL,'Maximum night interval systolic blood pressure (observable entity)'),('systolic-blood-pressure',1,'314444005',NULL,'Maximum day interval systolic blood pressure (observable entity)'),('systolic-blood-pressure',1,'314445006',NULL,'Average night interval systolic blood pressure (observable entity)'),('systolic-blood-pressure',1,'314446007',NULL,'Average day interval systolic blood pressure (observable entity)'),('systolic-blood-pressure',1,'314447003',NULL,'Minimum 24 hour systolic blood pressure (observable entity)'),('systolic-blood-pressure',1,'314448008',NULL,'Maximum 24 hour systolic blood pressure (observable entity)'),('systolic-blood-pressure',1,'314449000',NULL,'Average 24 hour systolic blood pressure (observable entity'),('systolic-blood-pressure',1,'314464000',NULL,'24 hour systolic blood pressure (observable entity)'),('systolic-blood-pressure',1,'399304008',NULL,'Systolic blood pressure on admission'),('systolic-blood-pressure',1,'400974009',NULL,'Standing systolic blood pressure'),('systolic-blood-pressure',1,'407554009',NULL,'Sitting systolic blood pressure'),('systolic-blood-pressure',1,'407556006',NULL,'Lying systolic blood pressure'),('systolic-blood-pressure',1,'413606001',NULL,'Average home systolic blood pressure'),('systolic-blood-pressure',1,'716579001',NULL,'Baseline systolic blood pressure'),('systolic-blood-pressure',1,'198081000000101',NULL,'Ambulatory systolic blood pressure'),('systolic-blood-pressure',1,'814101000000107',NULL,'Systolic blood pressure centile'),('systolic-blood-pressure',1,'1036551000000101',NULL,'Non-invasive central systolic blood pressure'),('systolic-blood-pressure',1,'1087991000000109',NULL,'Level of reduction in systolic blood pressure on standing (observable entity)'),('systolic-blood-pressure',1,'12929001',NULL,'Normal systolic arterial pressure (finding)'),('systolic-blood-pressure',1,'18050000',NULL,'Increased systolic arterial pressure (finding)'),('systolic-blood-pressure',1,'18352002',NULL,'Abnormal systolic arterial pressure (finding)'),('systolic-blood-pressure',1,'81010002',NULL,'Decreased systolic arterial pressure (finding)'),('systolic-blood-pressure',1,'163030003',NULL,'On examination - Systolic blood pressure reading'),('systolic-blood-pressure',1,'707303003',NULL,'Post exercise systolic blood pressure response abnormal'),('systolic-blood-pressure',1,'707304009',NULL,'Post exercise systolic blood pressure response normal (finding)')

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
VALUES ('diastolic-blood-pressure',1,'EMISNQDI86',NULL,'Diastolic blood pressure - left arm'),('diastolic-blood-pressure',1,'EMISNQDI87',NULL,'Diastolic blood pressure - right arm');
INSERT INTO #codesemis
VALUES ('systolic-blood-pressure',1,'EMISNQSY8',NULL,'Systolic blood pressure - left arm'),('systolic-blood-pressure',1,'EMISNQSY9',NULL,'Systolic blood pressure - right arm')

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

-- >>> Following code sets injected: diabetes-type-i v1/diabetes-type-ii v1

-- FIND ALL DIAGNOSES OF TYPE 1 DIABETES

IF OBJECT_ID('tempdb..#DiabetesT1Patients') IS NOT NULL DROP TABLE #DiabetesT1Patients;
SELECT 
	FK_Patient_Link_ID,
	SuppliedCode,
	CAST(EventDate AS DATE) AS EventDate
INTO #DiabetesT1Patients
FROM [RLS].[vw_GP_Events]
WHERE (SuppliedCode IN (SELECT [Code] FROM #AllCodes WHERE [Concept] IN ('diabetes-type-i') AND [Version] = 1))
	AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
	AND EventDate <= @StartDate

-- FIND EARLIEST DIAGNOSIS OF TYPE 1 DIABETES FOR EACH PATIENT

IF OBJECT_ID('tempdb..#T1Min') IS NOT NULL DROP TABLE #T1Min;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS MinDate
INTO #T1Min
FROM #DiabetesT1Patients
GROUP BY FK_Patient_Link_ID

-- FIND ALL DIAGNOSES OF TYPE 2 DIABETES

IF OBJECT_ID('tempdb..#DiabetesT2Patients') IS NOT NULL DROP TABLE #DiabetesT2Patients;
SELECT 
	FK_Patient_Link_ID,
	SuppliedCode,
	CAST(EventDate AS DATE) AS EventDate
INTO #DiabetesT2Patients
FROM [RLS].[vw_GP_Events]
WHERE (SuppliedCode IN (SELECT [Code] FROM #AllCodes WHERE [Concept] IN ('diabetes-type-ii') AND [Version] = 1))
	AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
	AND EventDate <= @StartDate

-- FIND EARLIEST DIAGNOSIS OF TYPE 2 DIABETES FOR EACH PATIENT

IF OBJECT_ID('tempdb..#T2Min') IS NOT NULL DROP TABLE #T2Min;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS MinDate
INTO #T2Min
FROM #DiabetesT2Patients
GROUP BY FK_Patient_Link_ID

-- CREATE COHORT OF DIABETES PATIENTS

IF OBJECT_ID('tempdb..#Cohort') IS NOT NULL DROP TABLE #Cohort;
SELECT p.FK_Patient_Link_ID, 
	EthnicMainGroup,
	DeathDate,
	yob.YearOfBirth,
	DiabetesT1 = CASE WHEN t1.FK_Patient_Link_ID IS NOT NULL THEN 1 ELSE 0 END,
	DiabetesT1_EarliestDiagnosis = CASE WHEN t1.FK_Patient_Link_ID IS NOT NULL THEN t1.MinDate ELSE NULL END,
	DiabetesT2 = CASE WHEN t2.FK_Patient_Link_ID IS NOT NULL THEN 1 ELSE 0 END,
	DiabetesT2_EarliestDiagnosis = CASE WHEN t2.FK_Patient_Link_ID IS NOT NULL THEN t2.MinDate ELSE NULL END
INTO #Cohort
FROM #Patients p
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #T1Min t1 ON t1.FK_Patient_Link_ID = p.FK_Patient_Link_ID 
LEFT OUTER JOIN #T2Min t2 ON t2.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE YEAR(@StartDate) - YearOfBirth >= 19 														 -- Over 18
	AND (
		p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #DiabetesT1Patients)  OR			 -- Diabetes T1 diagnosis
		p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #DiabetesT2Patients) 			     -- Diabetes T2 diagnosis
		)
	AND p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude) 			 -- exclude new patients processed post-COPI notice


----------------------------------------------------------------------------------------

-- TABLE OF GP EVENTS FOR COHORT TO SPEED UP REUSABLE QUERIES

IF OBJECT_ID('tempdb..#PatientEventData') IS NOT NULL DROP TABLE #PatientEventData;
SELECT 
  FK_Patient_Link_ID,
  CAST(EventDate AS DATE) AS EventDate,
  SuppliedCode,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID,
  [Value],
  Units
INTO #PatientEventData
FROM [RLS].vw_GP_Events
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort)
	AND EventDate < '2022-06-01';

------------------------------- OBSERVATIONS -------------------------------------

-- >>> Following code sets injected: systolic-blood-pressure v1/diastolic-blood-pressure v1/hba1c v2
-- >>> Following code sets injected: cholesterol v2/ldl-cholesterol v1/hdl-cholesterol v1/triglycerides v1/egfr v1

-- CREATE TABLE OF OBSERVATIONS REQUESTED BY THE PI

IF OBJECT_ID('tempdb..#observations') IS NOT NULL DROP TABLE #observations;
SELECT 
	FK_Patient_Link_ID,
	CAST(EventDate AS DATE) AS EventDate,
	Concept = CASE WHEN sn.Concept IS NOT NULL THEN sn.Concept ELSE co.Concept END,
	[Version] =  CASE WHEN sn.[Version] IS NOT NULL THEN sn.[Version] ELSE co.[Version] END,
	[Value] = TRY_CONVERT(NUMERIC (18,5), [Value]),
	Units
INTO #observations
FROM #PatientEventData gp
LEFT JOIN #VersionedSnomedSets sn ON sn.FK_Reference_SnomedCT_ID = gp.FK_Reference_SnomedCT_ID
LEFT JOIN #VersionedCodeSets co ON co.FK_Reference_Coding_ID = gp.FK_Reference_Coding_ID
WHERE
	((gp.FK_Reference_SnomedCT_ID IN (
		SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets sn WHERE sn.Concept In ('systolic-blood-pressure', 'diastolic-blood-pressure', 'ldl-cholesterol', 'hdl-cholesterol', 'triglycerides', 'egfr') AND [Version] = 1) 
			OR sn.Concept IN ('hba1c', 'cholesterol') AND sn.[Version] = 2 )
		OR (gp.FK_Reference_Coding_ID   IN (
		SELECT FK_Reference_Coding_ID   FROM #VersionedCodeSets co WHERE co.Concept In ('systolic-blood-pressure', 'diastolic-blood-pressure', 'ldl-cholesterol', 'hdl-cholesterol', 'triglycerides', 'egfr') AND [Version] = 1) 
			OR co.Concept IN ('hba1c', 'cholesterol') AND co.[Version] = 2 ))
	AND [Value] IS NOT NULL AND [Value] != '0' AND UPPER([Value]) NOT LIKE '%[A-Z]%'  -- CHECKS IN CASE ANY ZERO, NULL OR TEXT VALUES REMAINED

-- WHERE CODES EXIST IN BOTH VERSIONS OF THE CODE SET (OR IN OTHER SIMILAR CODE SETS), THERE WILL BE DUPLICATES, SO EXCLUDE THEM FROM THE SETS/VERSIONS THAT WE DON'T WANT 

IF OBJECT_ID('tempdb..#all_observations') IS NOT NULL DROP TABLE #all_observations;
select 
	FK_Patient_Link_ID, CAST(EventDate AS DATE) EventDate, Concept, [Value], Units
into #all_observations
from #observations
WHERE 
	((Concept in ('systolic-blood-pressure', 'diastolic-blood-pressure', 'ldl-cholesterol', 'hdl-cholesterol', 'triglycerides', 'egfr') AND [Version] = 1) OR
	(Concept IN ('cholesterol', 'hba1c') AND [Version] = 2)) -- e.g. hba1c level appears twice with same value: from version 1 and version 2. We only want version 2 so exclude any others.
	AND [Value] > 0 AND [Value] <> '0.00000' 


-- FIND CLOSEST OBSERVATIONS BEFORE AND AFTER PANDEMIC STARTED

IF OBJECT_ID('tempdb..#most_recent_date_before_covid') IS NOT NULL DROP TABLE #most_recent_date_before_covid;
SELECT o.FK_Patient_Link_ID, Concept, MAX(EventDate) as MostRecentDate
INTO #most_recent_date_before_covid
FROM #all_observations o
WHERE EventDate < '2020-03-01'
GROUP BY o.FK_Patient_Link_ID, Concept

IF OBJECT_ID('tempdb..#most_recent_date_after_covid') IS NOT NULL DROP TABLE #most_recent_date_after_covid;
SELECT o.FK_Patient_Link_ID, Concept, MIN(EventDate) as MostRecentDate
INTO #most_recent_date_after_covid
FROM #all_observations o
WHERE EventDate >= '2020-03-01'
GROUP BY o.FK_Patient_Link_ID, Concept

IF OBJECT_ID('tempdb..#closest_observations') IS NOT NULL DROP TABLE #closest_observations;
SELECT o.FK_Patient_Link_ID, 
	o.EventDate, 
	o.Concept, 
	o.[Value],
	Units,
	BeforeOrAfterCovid = CASE WHEN bef.MostRecentDate = o.EventDate THEN 'before' WHEN aft.MostRecentDate = o.EventDate THEN 'after' ELSE 'check' END,
	ROW_NUM = ROW_NUMBER () OVER (PARTITION BY o.FK_Patient_Link_ID, o.EventDate, o.Concept ORDER BY [Value] DESC) -- THIS WILL BE USED IN NEXT QUERY TO TAKE THE MAX VALUE WHERE THERE ARE MULTIPLE
INTO #closest_observations
FROM #all_observations o
LEFT JOIN #most_recent_date_before_covid bef ON bef.FK_Patient_Link_ID = o.FK_Patient_Link_ID AND bef.MostRecentDate = o.EventDate and bef.Concept = o.Concept
LEFT JOIN #most_recent_date_after_covid aft ON aft.FK_Patient_Link_ID = o.FK_Patient_Link_ID AND aft.MostRecentDate = o.EventDate and aft.Concept = o.Concept
WHERE bef.MostRecentDate = o.EventDate OR aft.MostRecentDate = o.EventDate

-- CREATE WIDE TABLE WITH CLOSEST OBSERVATIONS BEFORE AND AFTER COVID POSITIVE DATE

IF OBJECT_ID('tempdb..#observations_wide') IS NOT NULL DROP TABLE #observations_wide;
SELECT
	 FK_Patient_Link_ID
	,SystolicBP_1 = MAX(CASE WHEN [Concept] = 'systolic-blood-pressure' AND BeforeOrAfterCovid = 'before' THEN [Value] ELSE NULL END)
	,SystolicBP_1_dt = MAX(CASE WHEN [Concept] = 'systolic-blood-pressure' AND BeforeOrAfterCovid = 'before' THEN EventDate ELSE NULL END)
	,SystolicBP_1_unit = MAX(CASE WHEN [Concept] = 'systolic-blood-pressure' AND BeforeOrAfterCovid = 'before' THEN Units ELSE NULL END)
	,SystolicBP_2 = MAX(CASE WHEN [Concept] = 'systolic-blood-pressure' AND BeforeOrAfterCovid = 'after' THEN [Value] ELSE NULL END)
	,SystolicBP_2_dt = MAX(CASE WHEN [Concept] = 'systolic-blood-pressure' AND BeforeOrAfterCovid = 'after' THEN EventDate ELSE NULL END)
	,SystolicBP_2_unit = MAX(CASE WHEN [Concept] = 'systolic-blood-pressure' AND BeforeOrAfterCovid = 'after' THEN Units ELSE NULL END)
	,diastolicBP_1 = MAX(CASE WHEN [Concept] = 'diastolic-blood-pressure' AND BeforeOrAfterCovid = 'before' THEN [Value] ELSE NULL END)
	,diastolicBP_1_dt = MAX(CASE WHEN [Concept] = 'diastolic-blood-pressure' AND BeforeOrAfterCovid = 'before' THEN EventDate ELSE NULL END)
	,diastolicBP_1_unit = MAX(CASE WHEN [Concept] = 'diastolic-blood-pressure' AND BeforeOrAfterCovid = 'before' THEN Units ELSE NULL END)
	,diastolicBP_2 = MAX(CASE WHEN [Concept] = 'diastolic-blood-pressure' AND BeforeOrAfterCovid = 'after' THEN [Value] ELSE NULL END)
	,diastolicBP_2_dt = MAX(CASE WHEN [Concept] = 'diastolic-blood-pressure' AND BeforeOrAfterCovid = 'after' THEN EventDate ELSE NULL END)
	,diastolicBP_2_unit = MAX(CASE WHEN [Concept] = 'diastolic-blood-pressure' AND BeforeOrAfterCovid = 'after' THEN Units ELSE NULL END)
	,cholesterol_1 = MAX(CASE WHEN [Concept] = 'cholesterol' AND BeforeOrAfterCovid = 'before' THEN [Value] ELSE NULL END)
	,cholesterol_1_dt = MAX(CASE WHEN [Concept] = 'cholesterol' AND BeforeOrAfterCovid = 'before' THEN EventDate ELSE NULL END)
	,cholesterol_1_unit = MAX(CASE WHEN [Concept] = 'cholesterol' AND BeforeOrAfterCovid = 'before' THEN Units ELSE NULL END)
	,cholesterol_2 = MAX(CASE WHEN [Concept] = 'cholesterol' AND BeforeOrAfterCovid = 'after' THEN [Value] ELSE NULL END)
	,cholesterol_2_dt = MAX(CASE WHEN [Concept] = 'cholesterol' AND BeforeOrAfterCovid = 'after' THEN EventDate ELSE NULL END)
	,cholesterol_2_unit = MAX(CASE WHEN [Concept] = 'cholesterol' AND BeforeOrAfterCovid = 'after' THEN Units ELSE NULL END)
	,HDLcholesterol_1 = MAX(CASE WHEN [Concept] = 'hdl-cholesterol' AND BeforeOrAfterCovid = 'before' THEN [Value] ELSE NULL END)
	,HDLcholesterol_1_dt = MAX(CASE WHEN [Concept] = 'hdl-cholesterol' AND BeforeOrAfterCovid = 'before' THEN EventDate ELSE NULL END)
	,HDLcholesterol_1_unit = MAX(CASE WHEN [Concept] = 'hdl-cholesterol' AND BeforeOrAfterCovid = 'before' THEN Units ELSE NULL END)
	,HDLcholesterol_2 = MAX(CASE WHEN [Concept] = 'hdl-cholesterol' AND BeforeOrAfterCovid = 'after' THEN [Value] ELSE NULL END)
	,HDLcholesterol_2_dt = MAX(CASE WHEN [Concept] = 'hdl-cholesterol' AND BeforeOrAfterCovid = 'after' THEN EventDate ELSE NULL END)
	,HDLcholesterol_2_unit = MAX(CASE WHEN [Concept] = 'hdl-cholesterol' AND BeforeOrAfterCovid = 'after' THEN Units ELSE NULL END)
	,LDL_cholesterol_1 = MAX(CASE WHEN [Concept] = 'ldl-cholesterol' AND BeforeOrAfterCovid = 'before' THEN [Value] ELSE NULL END)
	,LDL_cholesterol_1_dt = MAX(CASE WHEN [Concept] = 'ldl-cholesterol' AND BeforeOrAfterCovid = 'before' THEN EventDate ELSE NULL END)
	,LDL_cholesterol_1_unit = MAX(CASE WHEN [Concept] = 'ldl-cholesterol' AND BeforeOrAfterCovid = 'before' THEN Units ELSE NULL END)
	,LDL_cholesterol_2 = MAX(CASE WHEN [Concept] = 'ldl-cholesterol' AND BeforeOrAfterCovid = 'after' THEN [Value] ELSE NULL END)
	,LDL_cholesterol_2_dt = MAX(CASE WHEN [Concept] = 'ldl-cholesterol' AND BeforeOrAfterCovid = 'after' THEN EventDate ELSE NULL END)
	,LDL_cholesterol_2_unit = MAX(CASE WHEN [Concept] = 'ldl-cholesterol' AND BeforeOrAfterCovid = 'after' THEN Units ELSE NULL END)
	,Triglyceride_1 = MAX(CASE WHEN [Concept] = 'triglycerides' AND BeforeOrAfterCovid = 'before' THEN [Value] ELSE NULL END)
	,Triglyceride_1_dt = MAX(CASE WHEN [Concept] = 'triglycerides' AND BeforeOrAfterCovid = 'before' THEN EventDate ELSE NULL END)
	,Triglyceride_1_unit = MAX(CASE WHEN [Concept] = 'triglycerides' AND BeforeOrAfterCovid = 'before' THEN Units ELSE NULL END)
	,Triglyceride_2 = MAX(CASE WHEN [Concept] = 'triglycerides' AND BeforeOrAfterCovid = 'after' THEN [Value] ELSE NULL END)
	,Triglyceride_2_dt = MAX(CASE WHEN [Concept] = 'triglycerides' AND BeforeOrAfterCovid = 'after' THEN EventDate ELSE NULL END)
	,Triglyceride_2_unit = MAX(CASE WHEN [Concept] = 'triglycerides' AND BeforeOrAfterCovid = 'after' THEN Units ELSE NULL END)
	,egfr_1 = MAX(CASE WHEN [Concept] = 'egfr' AND BeforeOrAfterCovid = 'before' THEN [Value] ELSE NULL END)
	,egfr_1_dt = MAX(CASE WHEN [Concept] = 'egfr' AND BeforeOrAfterCovid = 'before' THEN EventDate ELSE NULL END)
	,egfr_1_unit = MAX(CASE WHEN [Concept] = 'egfr' AND BeforeOrAfterCovid = 'before' THEN Units ELSE NULL END)
	,egfr_2 = MAX(CASE WHEN [Concept] = 'egfr' AND BeforeOrAfterCovid = 'after' THEN [Value] ELSE NULL END)
	,egfr_2_dt = MAX(CASE WHEN [Concept] = 'egfr' AND BeforeOrAfterCovid = 'after' THEN EventDate ELSE NULL END)
	,egfr_2_unit = MAX(CASE WHEN [Concept] = 'egfr' AND BeforeOrAfterCovid = 'after' THEN Units ELSE NULL END)
	,hba1c_1 = MAX(CASE WHEN [Concept] = 'hba1c' AND BeforeOrAfterCovid = 'before' THEN [Value] ELSE NULL END)
	,hba1c_1_dt = MAX(CASE WHEN [Concept] = 'hba1c' AND BeforeOrAfterCovid = 'before' THEN EventDate ELSE NULL END)
	,hba1c_1_unit = MAX(CASE WHEN [Concept] = 'hba1c' AND BeforeOrAfterCovid = 'before' THEN Units ELSE NULL END)
	,hba1c_2 = MAX(CASE WHEN [Concept] = 'hba1c' AND BeforeOrAfterCovid = 'after' THEN [Value] ELSE NULL END)
	,hba1c_2_dt = MAX(CASE WHEN [Concept] = 'hba1c' AND BeforeOrAfterCovid = 'after' THEN EventDate ELSE NULL END)
	,hba1c_2_unit = MAX(CASE WHEN [Concept] = 'hba1c' AND BeforeOrAfterCovid = 'after' THEN Units ELSE NULL END)
INTO #observations_wide
FROM #closest_observations
WHERE ROW_NUM = 1
GROUP BY FK_Patient_Link_ID
-- BRING TOGETHER FOR FINAL DATA EXTRACT

SELECT  
	PatientId = p.FK_Patient_Link_ID
	,SystolicBP_1
	,SystolicBP_1_dt 
	,SystolicBP_1_unit
	,SystolicBP_2
	,SystolicBP_2_dt 
	,SystolicBP_2_unit
	,diastolicBP_1
	,diastolicBP_1_dt
	,diastolicBP_1_unit
	,diastolicBP_2
	,diastolicBP_2_dt
	,diastolicBP_2_unit
	,cholesterol_1
	,cholesterol_1_dt
	,cholesterol_1_unit
	,cholesterol_2
	,cholesterol_2_dt
	,cholesterol_2_unit
	,HDLcholesterol_1
	,HDLcholesterol_1_dt 
	,HDLcholesterol_1_unit
	,HDLcholesterol_2
	,HDLcholesterol_2_dt 
	,HDLcholesterol_2_unit
	,LDL_cholesterol_1
	,LDL_cholesterol_1_dt
	,LDL_cholesterol_1_unit
	,LDL_cholesterol_2
	,LDL_cholesterol_2_dt
	,LDL_cholesterol_2_unit
	,Triglyceride_1
	,Triglyceride_1_dt
	,Triglyceride_1_unit
	,Triglyceride_2
	,Triglyceride_2_dt
	,Triglyceride_2_unit
	,egfr_1
	,egfr_1_dt 
	,egfr_1_unit
	,egfr_2
	,egfr_2_dt 
	,egfr_2_unit
	,hba1c_1
	,hba1c_1_dt
	,hba1c_1_unit
	,hba1c_2
	,hba1c_2_dt
	,hba1c_2_unit
FROM #Cohort p 
INNER JOIN #observations_wide obs on obs.FK_Patient_Link_ID = p.FK_Patient_Link_ID