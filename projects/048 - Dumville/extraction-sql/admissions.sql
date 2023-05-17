--┌────────────┐
--│ Admissions │
--└────────────┘

--------------------- RDE CHECK ---------------------
-- Le Mai Parkes  - 25 May 2022 - via pull request --
-----------------------------------------------------

-- OUTPUT: Data with the following fields
--  - PatientId (int)
--  - AdmissionDate (YYYYMMDD)
--  - DischargeDate (YYYYMMDD)
--  - Status (planned/unplanned/maternity/transfer/other)

--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2020-01-01';

-- Set the end date
DECLARE @EndDate datetime;
SET @EndDate = '2022-07-01';

--┌──────────────────────────────────────────┐
--│ Define Cohort for RQ048: Oximetry@Home   │
--└──────────────────────────────────────────┘

-- OBJECTIVE: To build the cohort of patients needed for RQ048. This reduces
--						duplication of code in the template scripts. The cohort is any
--						patient who was recruited into the Oximetry@Home programme. This
--            script also builds the matched cohort.
-- INPUT: None

-- OUTPUT: Temp tables as follows:
-- #Patients - list of patient ids of the cohort and matched cohort
-- #MainCohort - patient attributes for the ox@home patients
-- #CohortStore - output from the cohort matching
-- #OximmetryPatients - deduplicated version of the oximetry@home patients

------------------------------------------------------------------------------

-- Assume temp table #OxAtHome (FK_Patient_Link_ID, AdmissionDate, DischargeDate)

-- Remove admissions ahead of our cut-off date
DELETE FROM #OxAtHome WHERE AdmissionDate > '2022-06-01';

-- Censor discharges after cut-off to appear as NULL
UPDATE #OxAtHome SET DischargeDate = NULL WHERE DischargeDate > '2022-06-01';

-- Assume max discharge date in the case of multiple admission dates
IF OBJECT_ID('tempdb..#OximmetryPatients') IS NOT NULL DROP TABLE #OximmetryPatients;
SELECT FK_Patient_Link_ID, MAX(DischargeDate) AS DischargeDate, AdmissionDate
INTO #OximmetryPatients
FROM #OxAtHome
GROUP BY FK_Patient_Link_ID, AdmissionDate;

-- Only include patients who were first registered at a GP practice prior
-- to June 2022. This is 1 month before COPI expired and so acts as a buffer.
-- If we only looked at patients who first registered before July 2022, then
-- there is a chance that their data was processed after COPI expired.
IF OBJECT_ID('tempdb..#PatientsToInclude') IS NOT NULL DROP TABLE #PatientsToInclude;
SELECT FK_Patient_Link_ID INTO #PatientsToInclude
FROM SharedCare.Patient_GP_History
GROUP BY FK_Patient_Link_ID
HAVING MIN(StartDate) < '2022-06-01';

-- Table of all patients with a GP record
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT DISTINCT FK_Patient_Link_ID
INTO #Patients
FROM SharedCare.Patient
WHERE FK_Reference_Tenancy_ID=2
AND GPPracticeCode NOT LIKE 'ZZZ%'
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

--┌─────────────────────┐
--│ Patients with COVID │
--└─────────────────────┘

-- OBJECTIVE: To get tables of all patients with a COVID diagnosis in their record. This now includes a table
-- that has reinfections. This uses a 90 day cut-off to rule out patients that get multiple tests for
-- a single infection. This 90 day cut-off is also used in the government COVID dashboard. In the first wave,
-- prior to widespread COVID testing, and prior to the correct clinical codes being	available to clinicians,
-- infections were recorded in a variety of ways. We therefore take the first diagnosis from any code indicative
-- of COVID. However, for subsequent infections we insist on the presence of a positive COVID test (PCR or antigen)
-- as opposed to simply a diagnosis code. This is to avoid the situation where a hospital diagnosis code gets 
-- entered into the primary care record several months after the actual infection.

-- INPUT: Takes three parameters
--  - start-date: string - (YYYY-MM-DD) the date to count diagnoses from. Usually this should be 2020-01-01.
--	-	all-patients: boolean - (true/false) if true, then all patients are included, otherwise only those in the pre-existing #Patients table.
--	- gp-events-table: string - (table name) the name of the table containing the GP events. Usually is "SharedCare.GP_Events" but can be anything with the columns: FK_Patient_Link_ID, EventDate, and SuppliedCode

-- OUTPUT: Three temp tables as follows:
-- #CovidPatients (FK_Patient_Link_ID, FirstCovidPositiveDate)
-- 	- FK_Patient_Link_ID - unique patient id
--	- FirstCovidPositiveDate - earliest COVID diagnosis
-- #CovidPatientsAllDiagnoses (FK_Patient_Link_ID, CovidPositiveDate)
-- 	- FK_Patient_Link_ID - unique patient id
--	- CovidPositiveDate - any COVID diagnosis
-- #CovidPatientsMultipleDiagnoses
--	-	FK_Patient_Link_ID - unique patient id
--	-	FirstCovidPositiveDate - date of first COVID diagnosis
--	-	SecondCovidPositiveDate - date of second COVID diagnosis
--	-	ThirdCovidPositiveDate - date of third COVID diagnosis
--	-	FourthCovidPositiveDate - date of fourth COVID diagnosis
--	-	FifthCovidPositiveDate - date of fifth COVID diagnosis

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
VALUES ('covid-positive-antigen-test',1,'43kB1',NULL,'SARS-CoV-2 antigen positive'),('covid-positive-antigen-test',1,'43kB100',NULL,'SARS-CoV-2 antigen positive');
INSERT INTO #codesreadv2
VALUES ('covid-positive-pcr-test',1,'4J3R6',NULL,'SARS-CoV-2 RNA pos lim detect'),('covid-positive-pcr-test',1,'4J3R600',NULL,'SARS-CoV-2 RNA pos lim detect'),('covid-positive-pcr-test',1,'A7952',NULL,'COVID-19 confirmed by laboratory test'),('covid-positive-pcr-test',1,'A795200',NULL,'COVID-19 confirmed by laboratory test'),('covid-positive-pcr-test',1,'43hF.',NULL,'Detection of SARS-CoV-2 by PCR'),('covid-positive-pcr-test',1,'43hF.00',NULL,'Detection of SARS-CoV-2 by PCR');
INSERT INTO #codesreadv2
VALUES ('covid-positive-test-other',1,'4J3R1',NULL,'2019-nCoV (novel coronavirus) detected'),('covid-positive-test-other',1,'4J3R100',NULL,'2019-nCoV (novel coronavirus) detected')

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
VALUES ('covid-positive-antigen-test',1,'Y269d',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) antigen detection result positive'),('covid-positive-antigen-test',1,'43kB1',NULL,'SARS-CoV-2 antigen positive');
INSERT INTO #codesctv3
VALUES ('covid-positive-pcr-test',1,'4J3R6',NULL,'SARS-CoV-2 RNA pos lim detect'),('covid-positive-pcr-test',1,'Y240b',NULL,'Severe acute respiratory syndrome coronavirus 2 qualitative existence in specimen (observable entity)'),('covid-positive-pcr-test',1,'Y2a3b',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) RNA (ribonucleic acid) detection result positive'),('covid-positive-pcr-test',1,'A7952',NULL,'COVID-19 confirmed by laboratory test'),('covid-positive-pcr-test',1,'Y228d',NULL,'Coronavirus disease 19 caused by severe acute respiratory syndrome coronavirus 2 confirmed by laboratory test (situation)'),('covid-positive-pcr-test',1,'Y210e',NULL,'Detection of 2019-nCoV (novel coronavirus) using polymerase chain reaction technique'),('covid-positive-pcr-test',1,'43hF.',NULL,'Detection of SARS-CoV-2 by PCR'),('covid-positive-pcr-test',1,'Y2a3d',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) RNA (ribonucleic acid) detection result positive at the limit of detection');
INSERT INTO #codesctv3
VALUES ('covid-positive-test-other',1,'4J3R1',NULL,'2019-nCoV (novel coronavirus) detected'),('covid-positive-test-other',1,'Y20d1',NULL,'Confirmed 2019-nCov (Wuhan) infection'),('covid-positive-test-other',1,'Y23f7',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) detection result positive')

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
VALUES ('covid-positive-antigen-test',1,'^ESCT1305304',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) antigen detection result positive'),('covid-positive-antigen-test',1,'^ESCT1348538',NULL,'Detection of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) antigen');
INSERT INTO #codesemis
VALUES ('covid-positive-pcr-test',1,'^ESCT1305238',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) RNA (ribonucleic acid) qualitative existence in specimen'),('covid-positive-pcr-test',1,'^ESCT1348314',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) RNA (ribonucleic acid) detection result positive'),('covid-positive-pcr-test',1,'^ESCT1305235',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) RNA (ribonucleic acid) detection result positive'),('covid-positive-pcr-test',1,'^ESCT1300228',NULL,'COVID-19 confirmed by laboratory test GP COVID-19'),('covid-positive-pcr-test',1,'^ESCT1348316',NULL,'2019-nCoV (novel coronavirus) ribonucleic acid detected'),('covid-positive-pcr-test',1,'^ESCT1301223',NULL,'Detection of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) using polymerase chain reaction technique'),('covid-positive-pcr-test',1,'^ESCT1348359',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) RNA (ribonucleic acid) detection result positive at the limit of detection'),('covid-positive-pcr-test',1,'^ESCT1299053',NULL,'Detection of 2019-nCoV (novel coronavirus) using polymerase chain reaction technique'),('covid-positive-pcr-test',1,'^ESCT1300228',NULL,'COVID-19 confirmed by laboratory test'),('covid-positive-pcr-test',1,'^ESCT1348359',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) RNA (ribonucleic acid) detection result positive at the limit of detection');
INSERT INTO #codesemis
VALUES ('covid-positive-test-other',1,'^ESCT1303928',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) detection result positive'),('covid-positive-test-other',1,'^ESCT1299074',NULL,'2019-nCoV (novel coronavirus) detected'),('covid-positive-test-other',1,'^ESCT1301230',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) detected'),('covid-positive-test-other',1,'EMISNQCO303',NULL,'Confirmed 2019-nCoV (Wuhan) infectio'),('covid-positive-test-other',1,'^ESCT1299075',NULL,'Wuhan 2019-nCoV (novel coronavirus) detected'),('covid-positive-test-other',1,'^ESCT1300229',NULL,'COVID-19 confirmed using clinical diagnostic criteria'),('covid-positive-test-other',1,'^ESCT1348575',NULL,'Detection of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2)'),('covid-positive-test-other',1,'^ESCT1299074',NULL,'2019-nCoV (novel coronavirus) detected'),('covid-positive-test-other',1,'^ESCT1300229',NULL,'COVID-19 confirmed using clinical diagnostic criteria'),('covid-positive-test-other',1,'EMISNQCO303',NULL,'Confirmed 2019-nCoV (novel coronavirus) infection'),('covid-positive-test-other',1,'EMISNQCO303',NULL,'Confirmed 2019-nCoV (novel coronavirus) infection'),('covid-positive-test-other',1,'^ESCT1348575',NULL,'Detection of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2)')

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

-- >>> Following code sets injected: covid-positive-antigen-test v1/covid-positive-pcr-test v1/covid-positive-test-other v1


-- Set the temp end date until new legal basis
DECLARE @TEMPWithCovidEndDate datetime;
SET @TEMPWithCovidEndDate = '2022-06-01';

IF OBJECT_ID('tempdb..#CovidPatientsAllDiagnoses') IS NOT NULL DROP TABLE #CovidPatientsAllDiagnoses;
CREATE TABLE #CovidPatientsAllDiagnoses (
	FK_Patient_Link_ID BIGINT,
	CovidPositiveDate DATE
);

INSERT INTO #CovidPatientsAllDiagnoses
SELECT DISTINCT FK_Patient_Link_ID, CONVERT(DATE, [EventDate]) AS CovidPositiveDate
FROM [SharedCare].[COVID19]
WHERE (
	(GroupDescription = 'Confirmed' AND SubGroupDescription != 'Negative') OR
	(GroupDescription = 'Tested' AND SubGroupDescription = 'Positive')
)
AND EventDate > '2020-01-01'
AND EventDate <= @TEMPWithCovidEndDate
--AND EventDate <= GETDATE()
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);

-- We can rely on the GraphNet table for first diagnosis.
IF OBJECT_ID('tempdb..#CovidPatients') IS NOT NULL DROP TABLE #CovidPatients;
SELECT FK_Patient_Link_ID, MIN(CovidPositiveDate) AS FirstCovidPositiveDate INTO #CovidPatients
FROM #CovidPatientsAllDiagnoses
GROUP BY FK_Patient_Link_ID;

-- Now let's get the dates of any positive test (i.e. not things like suspected, or historic)
IF OBJECT_ID('tempdb..#AllPositiveTestsTemp') IS NOT NULL DROP TABLE #AllPositiveTestsTemp;
CREATE TABLE #AllPositiveTestsTemp (
	FK_Patient_Link_ID BIGINT,
	TestDate DATE
);

INSERT INTO #AllPositiveTestsTemp
SELECT DISTINCT FK_Patient_Link_ID, CAST(EventDate AS DATE) AS TestDate
FROM SharedCare.GP_Events
WHERE SuppliedCode IN (
	select Code from #AllCodes 
	where Concept in ('covid-positive-antigen-test','covid-positive-pcr-test','covid-positive-test-other') 
	AND Version = 1
)
AND EventDate <= @TEMPWithCovidEndDate
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);

IF OBJECT_ID('tempdb..#CovidPatientsMultipleDiagnoses') IS NOT NULL DROP TABLE #CovidPatientsMultipleDiagnoses;
CREATE TABLE #CovidPatientsMultipleDiagnoses (
	FK_Patient_Link_ID BIGINT,
	FirstCovidPositiveDate DATE,
	SecondCovidPositiveDate DATE,
	ThirdCovidPositiveDate DATE,
	FourthCovidPositiveDate DATE,
	FifthCovidPositiveDate DATE
);

-- Populate first diagnosis
INSERT INTO #CovidPatientsMultipleDiagnoses (FK_Patient_Link_ID, FirstCovidPositiveDate)
SELECT FK_Patient_Link_ID, MIN(FirstCovidPositiveDate) FROM
(
	SELECT * FROM #CovidPatients
	UNION
	SELECT * FROM #AllPositiveTestsTemp
) sub
GROUP BY FK_Patient_Link_ID;

-- Now let's get second tests.
UPDATE t1
SET t1.SecondCovidPositiveDate = NextTestDate
FROM #CovidPatientsMultipleDiagnoses AS t1
INNER JOIN (
SELECT cp.FK_Patient_Link_ID, MIN(apt.TestDate) AS NextTestDate FROM #CovidPatients cp
INNER JOIN #AllPositiveTestsTemp apt ON cp.FK_Patient_Link_ID = apt.FK_Patient_Link_ID AND apt.TestDate >= DATEADD(day, 90, FirstCovidPositiveDate)
GROUP BY cp.FK_Patient_Link_ID) AS sub ON sub.FK_Patient_Link_ID = t1.FK_Patient_Link_ID;

-- Now let's get third tests.
UPDATE t1
SET t1.ThirdCovidPositiveDate = NextTestDate
FROM #CovidPatientsMultipleDiagnoses AS t1
INNER JOIN (
SELECT cp.FK_Patient_Link_ID, MIN(apt.TestDate) AS NextTestDate FROM #CovidPatientsMultipleDiagnoses cp
INNER JOIN #AllPositiveTestsTemp apt ON cp.FK_Patient_Link_ID = apt.FK_Patient_Link_ID AND apt.TestDate >= DATEADD(day, 90, SecondCovidPositiveDate)
GROUP BY cp.FK_Patient_Link_ID) AS sub ON sub.FK_Patient_Link_ID = t1.FK_Patient_Link_ID;

-- Now let's get fourth tests.
UPDATE t1
SET t1.FourthCovidPositiveDate = NextTestDate
FROM #CovidPatientsMultipleDiagnoses AS t1
INNER JOIN (
SELECT cp.FK_Patient_Link_ID, MIN(apt.TestDate) AS NextTestDate FROM #CovidPatientsMultipleDiagnoses cp
INNER JOIN #AllPositiveTestsTemp apt ON cp.FK_Patient_Link_ID = apt.FK_Patient_Link_ID AND apt.TestDate >= DATEADD(day, 90, ThirdCovidPositiveDate)
GROUP BY cp.FK_Patient_Link_ID) AS sub ON sub.FK_Patient_Link_ID = t1.FK_Patient_Link_ID;

-- Now let's get fifth tests.
UPDATE t1
SET t1.FifthCovidPositiveDate = NextTestDate
FROM #CovidPatientsMultipleDiagnoses AS t1
INNER JOIN (
SELECT cp.FK_Patient_Link_ID, MIN(apt.TestDate) AS NextTestDate FROM #CovidPatientsMultipleDiagnoses cp
INNER JOIN #AllPositiveTestsTemp apt ON cp.FK_Patient_Link_ID = apt.FK_Patient_Link_ID AND apt.TestDate >= DATEADD(day, 90, FourthCovidPositiveDate)
GROUP BY cp.FK_Patient_Link_ID) AS sub ON sub.FK_Patient_Link_ID = t1.FK_Patient_Link_ID;
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

-- define the main cohort and the factors that will be matched
IF OBJECT_ID('tempdb..#MainCohort') IS NOT NULL DROP TABLE #MainCohort;
SELECT 
  o.FK_Patient_Link_ID,
  AdmissionDate AS IndexDate,
  Sex,
  YearOfBirth, 
  CASE
		WHEN imd.IMD2019Decile1IsMostDeprived10IsLeastDeprived BETWEEN 1 AND 2 THEN 1
		WHEN imd.IMD2019Decile1IsMostDeprived10IsLeastDeprived BETWEEN 3 AND 4 THEN 2
		WHEN imd.IMD2019Decile1IsMostDeprived10IsLeastDeprived BETWEEN 5 AND 6 THEN 3
		WHEN imd.IMD2019Decile1IsMostDeprived10IsLeastDeprived BETWEEN 7 AND 8 THEN 4
		WHEN imd.IMD2019Decile1IsMostDeprived10IsLeastDeprived BETWEEN 9 AND 10 THEN 5
	END AS IMD2019Quintile1IsMostDeprived5IsLeastDeprived
INTO #MainCohort
FROM #Patients pat
INNER JOIN #OximmetryPatients o ON o.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientIMDDecile imd ON imd.FK_Patient_Link_ID = pat.FK_Patient_Link_ID;

-- define the pool of people from whom the matches can be extracted
IF OBJECT_ID('tempdb..#PotentialMatches') IS NOT NULL DROP TABLE #PotentialMatches;
SELECT 
  o.FK_Patient_Link_ID,
  FirstCovidPositiveDate AS IndexDate,
  Sex,
  YearOfBirth, 
  CASE
		WHEN imd.IMD2019Decile1IsMostDeprived10IsLeastDeprived BETWEEN 1 AND 2 THEN 1
		WHEN imd.IMD2019Decile1IsMostDeprived10IsLeastDeprived BETWEEN 3 AND 4 THEN 2
		WHEN imd.IMD2019Decile1IsMostDeprived10IsLeastDeprived BETWEEN 5 AND 6 THEN 3
		WHEN imd.IMD2019Decile1IsMostDeprived10IsLeastDeprived BETWEEN 7 AND 8 THEN 4
		WHEN imd.IMD2019Decile1IsMostDeprived10IsLeastDeprived BETWEEN 9 AND 10 THEN 5
	END AS IMD2019Quintile1IsMostDeprived5IsLeastDeprived
INTO #PotentialMatches
FROM #CovidPatientsMultipleDiagnoses o
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = o.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = o.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientIMDDecile imd ON imd.FK_Patient_Link_ID = o.FK_Patient_Link_ID
WHERE o.FK_Patient_Link_ID NOT IN (SELECT FK_Patient_Link_ID FROM #OximmetryPatients);



--┌──────────────────────────────────────────────────────────────────┐
--│ Cohort matching on year of birth / sex / imd / and an index date │
--└──────────────────────────────────────────────────────────────────┘

-- OBJECTIVE: To take a primary cohort and find a 1:n matched cohort based on year of birth,
--            sex, imd, and an index date of an event.

-- INPUT: Takes two parameters
--  - yob-flex: integer - number of years each way that still allow a year of birth match
--  - index-date-flex: integer - number of days either side of the index date that we allow matching
--  - num-matches: integer - number of matches for each patient in the cohort
-- Requires two temp tables to exist as follows:
-- #MainCohort (FK_Patient_Link_ID, IndexDate, Sex, YearOfBirth,IMD2019Quintile1IsMostDeprived5IsLeastDeprived)
-- 	- FK_Patient_Link_ID - unique patient id
--	- IndexDate - date of event of interest (YYYY-MM-DD)
--	- Sex - M/F
--	- YearOfBirth - Integer
--  - IMD2019Quintile1IsMostDeprived5IsLeastDeprived - Integer 1-5
-- #PotentialMatches (FK_Patient_Link_ID, IndexDate, Sex, YearOfBirth, IMD2019Quintile1IsMostDeprived5IsLeastDeprived)
-- 	- FK_Patient_Link_ID - unique patient id
--	- IndexDate - date of event of interest (YYYY-MM-DD)
--	- Sex - M/F
--	- YearOfBirth - Integer
--  - IMD2019Quintile1IsMostDeprived5IsLeastDeprived - Integer 1-5

-- OUTPUT: A temp table as follows:
-- #CohortStore (FK_Patient_Link_ID, YearOfBirth, Sex, IMD2019Quintile1IsMostDeprived5IsLeastDeprived, IndexDate, MatchingPatientId, MatchingYearOfBirth, MatchingIndexDate)
--  - FK_Patient_Link_ID - unique patient id for primary cohort patient
--  - YearOfBirth - of the primary cohort patient
--  - Sex - of the primary cohort patient
--  - IMD2019Quintile1IsMostDeprived5IsLeastDeprived - of the primary cohort patient
--  - IndexDate - date of event of interest (YYYY-MM-DD)
--  - MatchingPatientId - id of the matched patient
--  - MatchingYearOfBirth - year of birth of the matched patient
--  - MatchingIndexDate - index date for the matched patient

-- First we extend the #PrimaryCohort table to give each age-sex combo a unique number
-- and to avoid polluting the #MainCohort table
IF OBJECT_ID('tempdb..#Cases') IS NOT NULL DROP TABLE #Cases;
SELECT FK_Patient_Link_ID AS PatientId, YearOfBirth, Sex, IMD2019Quintile1IsMostDeprived5IsLeastDeprived, IndexDate, Row_Number() OVER(PARTITION BY YearOfBirth, Sex, IMD2019Quintile1IsMostDeprived5IsLeastDeprived, IndexDate ORDER BY FK_Patient_Link_ID) AS CaseRowNumber
INTO #Cases FROM #MainCohort;

-- Then we do the same with the #PotentialMatches
IF OBJECT_ID('tempdb..#Matches') IS NOT NULL DROP TABLE #Matches;
SELECT FK_Patient_Link_ID AS PatientId, YearOfBirth, Sex, IMD2019Quintile1IsMostDeprived5IsLeastDeprived, IndexDate, Row_Number() OVER(PARTITION BY YearOfBirth, Sex, IMD2019Quintile1IsMostDeprived5IsLeastDeprived, IndexDate ORDER BY FK_Patient_Link_ID) AS AssignedPersonNumber
INTO #Matches FROM #PotentialMatches;

-- Find the number of people with each characteristic in the main cohort
IF OBJECT_ID('tempdb..#CharacteristicCount') IS NOT NULL DROP TABLE #CharacteristicCount;
SELECT YearOfBirth, Sex, IMD2019Quintile1IsMostDeprived5IsLeastDeprived, IndexDate, COUNT(*) AS [Count] INTO #CharacteristicCount FROM #Cases GROUP BY YearOfBirth, Sex, IMD2019Quintile1IsMostDeprived5IsLeastDeprived, IndexDate;

-- Find the number of potential matches for each combination
-- The output of this is useful for seeing how many matches you can get
-- SELECT A.YearOfBirth, A.Sex, A.IMD2019Quintile1IsMostDeprived5IsLeastDeprived, A.IndexDate,  B.Count / A.Count AS NumberOfPotentialMatchesPerCohortPatient FROM (SELECT * FROM #CharacteristicCount) A LEFT OUTER JOIN (	SELECT YearOfBirth, Sex, IMD2019Quintile1IsMostDeprived5IsLeastDeprived, IndexDate,  COUNT(*) AS [Count] FROM #Matches GROUP BY YearOfBirth, Sex, IMD2019Quintile1IsMostDeprived5IsLeastDeprived, IndexDate) B ON B.YearOfBirth = A.YearOfBirth AND B.Sex = A.Sex AND B.IndexDate = A.IndexDate AND B.IMD2019Quintile1IsMostDeprived5IsLeastDeprived = A.IMD2019Quintile1IsMostDeprived5IsLeastDeprived ORDER BY NumberOfPotentialMatchesPerCohortPatient,A.YearOfBirth,A.Sex,A.IMD2019Quintile1IsMostDeprived5IsLeastDeprived, A.IndexDate;

-- The final table contains a row for each match, so e.g. if patient 1 has 4
-- matches then there will be 4 rows in the table for this.
IF OBJECT_ID('tempdb..#CohortStore') IS NOT NULL DROP TABLE #CohortStore;
CREATE TABLE #CohortStore(
  PatientId BIGINT, 
  YearOfBirth INT, 
  Sex nchar(1), 
  IMD2019Quintile1IsMostDeprived5IsLeastDeprived INT,
  IndexDate DATE, 
  MatchingPatientId BIGINT,
  MatchingYearOfBirth INT,
  MatchingIndexDate DATE
) ON [PRIMARY];

--1. First match try to match people exactly. We do this as follows:
--    - For each YOB/Sex combination we find all potential matches. E.g. all patients
--      in the potential matches with sex='F' and yob=1957
--    - We then try to assign a single match to all cohort members with sex='F' and yob=1957
--    - If there are still matches unused, we then assign a second match to all cohort members
--    - This continues until we either run out of matches, or successfully match everyone with
--      the desired number of matches.
DECLARE @Counter1 INT; 
SET @Counter1=1;
-- In this loop we find one match at a time for each patient in the cohort
WHILE ( @Counter1 <= 15)
BEGIN
  INSERT INTO #CohortStore
  SELECT c.PatientId, c.YearOfBirth, c.Sex, c.IMD2019Quintile1IsMostDeprived5IsLeastDeprived, c.IndexDate, p.PatientId AS MatchedPatientId, c.YearOfBirth, c.IndexDate
  FROM #Cases c
    INNER JOIN #CharacteristicCount cc on cc.YearOfBirth = c.YearOfBirth and cc.Sex = c.Sex and cc.IMD2019Quintile1IsMostDeprived5IsLeastDeprived = c.IMD2019Quintile1IsMostDeprived5IsLeastDeprived and cc.IndexDate = c.IndexDate
    INNER JOIN #Matches p 
      ON p.Sex = c.Sex 
      AND p.YearOfBirth = c.YearOfBirth 
      AND p.IMD2019Quintile1IsMostDeprived5IsLeastDeprived = c.IMD2019Quintile1IsMostDeprived5IsLeastDeprived 
      AND p.IndexDate = c.IndexDate 
      -- This next line is the trick to only matching each person once
      AND p.AssignedPersonNumber = CaseRowNumber + (@counter1 - 1) * cc.[Count];

  -- We might not need this, but to be extra sure let's delete any patients who 
  -- we're already using to match people
  DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #CohortStore);

  SET @Counter1  = @Counter1  + 1
END

--2. Now relax the yob and index date restriction to get extra matches for people. Loop round starting with
--   those with 0 matches, then 1 match, then 2 matches etc.
DECLARE @Counter2 INT; 
SET @Counter2=0;
WHILE (@Counter2 <= 15)
BEGIN
	DECLARE @LastRowInsert1 INT;
	SET @LastRowInsert1=1;
	WHILE ( @LastRowInsert1 > 0)
	BEGIN
	  INSERT INTO #CohortStore
	  SELECT PatientId, YearOfBirth, Sex, IMD2019Quintile1IsMostDeprived5IsLeastDeprived, IndexDate, MatchedPatientId, MatchedYOB, MatchedIndexDate FROM (
	  SELECT sub.PatientId, sub.YearOfBirth, sub.Sex, sub.IMD2019Quintile1IsMostDeprived5IsLeastDeprived, sub.IndexDate, MatchedPatientId, MAX(m.YearOfBirth) AS MatchedYOB, MAX(m.IndexDate) AS MatchedIndexDate, Row_Number() OVER(PARTITION BY sub.PatientId ORDER BY sub.PatientId) AS NthMatch FROM (
	  SELECT c.PatientId, c.YearOfBirth, c.Sex, c.IMD2019Quintile1IsMostDeprived5IsLeastDeprived, c.IndexDate, MAX(p.PatientId) AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(p.PatientId) ORDER BY p.PatientId) AS AssignedPersonNumber
	  FROM #Cases c
	  INNER JOIN #Matches p 
		ON p.Sex = c.Sex 
		AND p.IMD2019Quintile1IsMostDeprived5IsLeastDeprived = c.IMD2019Quintile1IsMostDeprived5IsLeastDeprived 
		AND p.YearOfBirth >= c.YearOfBirth - 1
		AND p.YearOfBirth <= c.YearOfBirth + 1
		AND p.IndexDate between DATEADD(day,-30,c.IndexDate) and DATEADD(day,30,c.IndexDate)
	  WHERE c.PatientId in (
		-- find patients who aren't currently matched
		select PatientId from #Cases except (select PatientId from #CohortStore group by PatientId having count(*) >= @Counter2)
	  )
	  GROUP BY c.PatientId, c.YearOfBirth, c.Sex, c.IMD2019Quintile1IsMostDeprived5IsLeastDeprived, c.IndexDate, p.PatientId) sub
	  INNER JOIN #Matches m 
		ON m.Sex = sub.Sex 
		AND m.IMD2019Quintile1IsMostDeprived5IsLeastDeprived = sub.IMD2019Quintile1IsMostDeprived5IsLeastDeprived 
		AND m.PatientId = sub.MatchedPatientId
		AND m.YearOfBirth >= sub.YearOfBirth - 1
		AND m.YearOfBirth <= sub.YearOfBirth + 1
		AND m.IndexDate between DATEADD(day,-30,sub.IndexDate) and DATEADD(day,30,sub.IndexDate)
	  WHERE sub.AssignedPersonNumber = 1
	  GROUP BY sub.PatientId, sub.YearOfBirth, sub.Sex, sub.IMD2019Quintile1IsMostDeprived5IsLeastDeprived, sub.IndexDate, MatchedPatientId) sub2
	  WHERE NthMatch = 1
	  ORDER BY PatientId;
	  SELECT @LastRowInsert1=@@ROWCOUNT;

	  DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #CohortStore);
	END
	SET @Counter2  = @Counter2  + 1
END
--select count(*) from #CohortStore;
--select count(distinct MatchingPatientId) from #CohortStore;
--SELECT Num, COUNT(*) FROM ( SELECT PatientId, COUNT(*) AS Num FROM #CohortStore GROUP BY PatientId) sub GROUP BY Num UNION SELECT 0, x FROM (SELECT COUNT(*) AS x FROM (SELECT PatientId FROM #Cases EXCEPT SELECT PatientId FROM #CohortStore) sub1) sub ORDER BY Num;


-- Reduce #Patients table to just ox patients and the matching cohort
TRUNCATE TABLE #Patients;
INSERT INTO #Patients
SELECT PatientId FROM #CohortStore
UNION
SELECT MatchingPatientId FROM #CohortStore;

--┌───────────────────────────────┐
--│ Classify secondary admissions │
--└───────────────────────────────┘

-- OBJECTIVE: To categorise admissions to secondary care into 5 categories: Maternity, 
--						Unplanned, Planned, Transfer and Unknown.

-- ASSUMPTIONS:
--	-	We assume patients can only have one admission per day. This is probably not true, but 
--		where we see multiple admissions it is more likely to be data duplication, or internal
--		admissions, than an admission, discharge and another admission in the same day.
--	-	Where patients have multiple admissions we choose the "highest" category for admission
--		with the categories ranked as follows: Maternity > Unplanned > Planned > Transfer > Unknown
--	-	We have used the following classifications based on the AdmissionTypeCode:
--			- PLANNED: PL (ELECTIVE PLANNED), 11 (Elective - Waiting List), WL (ELECTIVE WL), 13 (Elective - Planned), 12 (Elective - Booked), BL (ELECTIVE BOOKED), D (NULL), Endoscopy (Endoscopy), OP (DIRECT OUTPAT CLINIC), Venesection (X36.2 Venesection), Colonoscopy (H22.9 Colonoscopy), Medical (Medical)
--			-	UNPLANNED: AE (AE.DEPT.OF PROVIDER), 21 (Emergency - Local A&E), I (NULL), GP (GP OR LOCUM GP), 22 (Emergency - GP), 23 (Emergency - Bed Bureau), 28 (Emergency - Other (inc other provider A&E)), 2D (Emergency - Other), 24 (Emergency - Clinic), EM (EMERGENCY OTHER), AI (ACUTE TO INTMED CARE), BB (EMERGENCY BED BUREAU), DO (EMERGENCY DOMICILE), 2A (A+E Department of another provider where the Patient has not been admitted), A+E (Admission	 A+E Admission), Emerg (GP	Emergency GP Patient)
--			-	MATERNITY: 31 (Maternity ante-partum), BH (BABY BORN IN HOSP), AN (MATERNITY ANTENATAL), 82 (Birth in this Health Care Provider), PN (MATERNITY POST NATAL), B (NULL), 32 (Maternity post-partum), BHOSP (Birth in this Health Care Provider)
--			-	TRANSFER: 81 (Transfer from other hosp (not A&E)), TR (PLAN TRANS TO TRUST), ET (EM TRAN (OTHER PROV)), HospTran (Transfer from other NHS Hospital), T (TRANSFER), CentTrans (Transfer from CEN Site)
--			-	OTHER: Anything else not previously classified

-- INPUT: No pre-requisites

-- OUTPUT: A temp table as follows:
-- #AdmissionTypes (FK_Patient_Link_ID, AdmissionDate, AcuteProvider, AdmissionType)
-- 	- FK_Patient_Link_ID - unique patient id
--	- AdmissionDate - date of admission (YYYY-MM-DD)
--	- AcuteProvider - Bolton, SRFT, Stockport etc..
--	- AdmissionType - One of: Maternity/Unplanned/Planned/Transfer/Unknown

-- For each acute admission we find the type. If multiple admissions on same day
-- we group and take the 'highest' category e.g.
-- choose Unplanned, then Planned, then Maternity, then Transfer, then Unknown
IF OBJECT_ID('tempdb..#AdmissionTypes') IS NOT NULL DROP TABLE #AdmissionTypes;
SELECT 
	FK_Patient_Link_ID, AdmissionDate, 
	CASE 
		WHEN AdmissionId = 5 THEN 'Maternity' 
		WHEN AdmissionId = 4 THEN 'Unplanned' 
		WHEN AdmissionId = 3 THEN 'Planned' 
		WHEN AdmissionId = 2 THEN 'Transfer' 
		WHEN AdmissionId = 1 THEN 'Unknown' 
	END as AdmissionType,
	AcuteProvider 
INTO #AdmissionTypes FROM (
	SELECT 
		FK_Patient_Link_ID, CONVERT(DATE, AdmissionDate) as AdmissionDate, 
		MAX(
			CASE 
				WHEN AdmissionTypeCode IN ('PL','11','WL','13','12','BL','D','Endoscopy','OP','Venesection','Colonoscopy','Flex sigmoidosco','Infliximab','IPPlannedAd','S.I. joint inj','Daycase','Extraction Multi','Chemotherapy','Total knee rep c','Total rep hip ce') THEN 3 --'Planned'
				WHEN AdmissionTypeCode IN ('AE','21','I','GP','22','23','EM','28','2D','24','AI','BB','DO','2A','A+E Admission','Emerg GP') THEN 4 --'Unplanned'
				WHEN AdmissionTypeCode IN ('31','BH','AN','82','PN','B','32','BHOSP') THEN 5 --'Maternity'
				WHEN AdmissionTypeCode IN ('81','TR','ET','HospTran','T','CentTrans') THEN 2 --'Transfer'
				WHEN AdmissionTypeCode IN ('Blood test','Blood transfusio','Medical') AND ReasonForAdmissionDescription LIKE ('Elective%') THEN 3 --'Planned'
				WHEN AdmissionTypeCode IN ('Blood test','Blood transfusio','Medical') AND ReasonForAdmissionDescription LIKE ('Emergency%') THEN 4 --'Unplanned'
				ELSE 1 --'Unknown'
			END
		)	AS AdmissionId,
		t.TenancyName AS AcuteProvider
	FROM SharedCare.Acute_Inpatients i
	LEFT OUTER JOIN SharedCare.Reference_Tenancy t ON t.PK_Reference_Tenancy_ID = i.FK_Reference_Tenancy_ID
	WHERE EventType = 'Admission'
	AND AdmissionDate >= @StartDate
	GROUP BY FK_Patient_Link_ID, CONVERT(DATE, AdmissionDate), t.TenancyName
) sub;
-- 523477 rows	523477 rows
-- 00:00:16		00:00:45
--┌─────────────────────────────────────────┐
--│ Secondary admissions and length of stay │
--└─────────────────────────────────────────┘

-- OBJECTIVE: To obtain a table with every secondary care admission, along with the acute provider,
--						the date of admission, the date of discharge, and the length of stay.

-- INPUT: One parameter
--	-	all-patients: boolean - (true/false) if true, then all patients are included, otherwise only those in the pre-existing #Patients table.

-- OUTPUT: Two temp table as follows:
-- #Admissions (FK_Patient_Link_ID, AdmissionDate, AcuteProvider)
-- 	- FK_Patient_Link_ID - unique patient id
--	- AdmissionDate - date of admission (YYYY-MM-DD)
--	- AcuteProvider - Bolton, SRFT, Stockport etc..
--  (Limited to one admission per person per hospital per day, because if a patient has 2 admissions 
--   on the same day to the same hopsital then it's most likely data duplication rather than two short
--   hospital stays)
-- #LengthOfStay (FK_Patient_Link_ID, AdmissionDate)
-- 	- FK_Patient_Link_ID - unique patient id
--	- AdmissionDate - date of admission (YYYY-MM-DD)
--	- AcuteProvider - Bolton, SRFT, Stockport etc..
--	- DischargeDate - date of discharge (YYYY-MM-DD)
--	- LengthOfStay - Number of days between admission and discharge. 1 = [0,1) days, 2 = [1,2) days, etc.

-- Set the temp end date until new legal basis
DECLARE @TEMPAdmissionsEndDate datetime;
SET @TEMPAdmissionsEndDate = '2022-06-01';

-- Populate temporary table with admissions
-- Convert AdmissionDate to a date to avoid issues where a person has two admissions
-- on the same day (but only one discharge)
IF OBJECT_ID('tempdb..#Admissions') IS NOT NULL DROP TABLE #Admissions;
CREATE TABLE #Admissions (
	FK_Patient_Link_ID BIGINT,
	AdmissionDate DATE,
	AcuteProvider NVARCHAR(150)
);
BEGIN
	IF 'false'='true'
		INSERT INTO #Admissions
		SELECT DISTINCT FK_Patient_Link_ID, CONVERT(DATE, AdmissionDate) AS AdmissionDate, t.TenancyName AS AcuteProvider
		FROM [SharedCare].[Acute_Inpatients] i
		LEFT OUTER JOIN SharedCare.Reference_Tenancy t ON t.PK_Reference_Tenancy_ID = i.FK_Reference_Tenancy_ID
		WHERE EventType = 'Admission'
		AND AdmissionDate >= @StartDate
		AND AdmissionDate <= @TEMPAdmissionsEndDate;
	ELSE
		INSERT INTO #Admissions
		SELECT DISTINCT FK_Patient_Link_ID, CONVERT(DATE, AdmissionDate) AS AdmissionDate, t.TenancyName AS AcuteProvider
		FROM [SharedCare].[Acute_Inpatients] i
		LEFT OUTER JOIN SharedCare.Reference_Tenancy t ON t.PK_Reference_Tenancy_ID = i.FK_Reference_Tenancy_ID
		WHERE EventType = 'Admission'
		AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
		AND AdmissionDate >= @StartDate
		AND AdmissionDate <= @TEMPAdmissionsEndDate;
END

--┌──────────────────────┐
--│ Secondary discharges │
--└──────────────────────┘

-- OBJECTIVE: To obtain a table with every secondary care discharge, along with the acute provider,
--						and the date of discharge.

-- INPUT: One parameter
--	-	all-patients: boolean - (true/false) if true, then all patients are included, otherwise only those in the pre-existing #Patients table.

-- OUTPUT: A temp table as follows:
-- #Discharges (FK_Patient_Link_ID, DischargeDate, AcuteProvider)
-- 	- FK_Patient_Link_ID - unique patient id
--	- DischargeDate - date of discharge (YYYY-MM-DD)
--	- AcuteProvider - Bolton, SRFT, Stockport etc..
--  (Limited to one discharge per person per hospital per day, because if a patient has 2 discharges 
--   on the same day to the same hopsital then it's most likely data duplication rather than two short
--   hospital stays)

-- Set the temp end date until new legal basis
DECLARE @TEMPDischargesEndDate datetime;
SET @TEMPDischargesEndDate = '2022-06-01';

-- Populate temporary table with discharges
IF OBJECT_ID('tempdb..#Discharges') IS NOT NULL DROP TABLE #Discharges;
CREATE TABLE #Discharges (
	FK_Patient_Link_ID BIGINT,
	DischargeDate DATE,
	AcuteProvider NVARCHAR(150)
);
BEGIN
	IF 'false'='true'
		INSERT INTO #Discharges
    SELECT DISTINCT FK_Patient_Link_ID, CONVERT(DATE, DischargeDate) AS DischargeDate, t.TenancyName AS AcuteProvider 
    FROM [SharedCare].[Acute_Inpatients] i
    LEFT OUTER JOIN SharedCare.Reference_Tenancy t ON t.PK_Reference_Tenancy_ID = i.FK_Reference_Tenancy_ID
    WHERE EventType = 'Discharge'
    AND DischargeDate >= @StartDate
    AND DischargeDate <= @TEMPDischargesEndDate;
  ELSE
		INSERT INTO #Discharges
    SELECT DISTINCT FK_Patient_Link_ID, CONVERT(DATE, DischargeDate) AS DischargeDate, t.TenancyName AS AcuteProvider 
    FROM [SharedCare].[Acute_Inpatients] i
    LEFT OUTER JOIN SharedCare.Reference_Tenancy t ON t.PK_Reference_Tenancy_ID = i.FK_Reference_Tenancy_ID
    WHERE EventType = 'Discharge'
		AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
    AND DischargeDate >= @StartDate
    AND DischargeDate <= @TEMPDischargesEndDate;;
END
-- 535285 rows	535285 rows
-- 00:00:28		00:00:14


-- Link admission with discharge to get length of stay
-- Length of stay is zero-indexed e.g. 
-- 1 = [0,1) days
-- 2 = [1,2) days
IF OBJECT_ID('tempdb..#LengthOfStay') IS NOT NULL DROP TABLE #LengthOfStay;
SELECT 
	a.FK_Patient_Link_ID, a.AdmissionDate, a.AcuteProvider, 
	MIN(d.DischargeDate) AS DischargeDate, 
	1 + DATEDIFF(day,a.AdmissionDate, MIN(d.DischargeDate)) AS LengthOfStay
	INTO #LengthOfStay
FROM #Admissions a
INNER JOIN #Discharges d ON d.FK_Patient_Link_ID = a.FK_Patient_Link_ID AND d.DischargeDate >= a.AdmissionDate AND d.AcuteProvider = a.AcuteProvider
GROUP BY a.FK_Patient_Link_ID, a.AdmissionDate, a.AcuteProvider
ORDER BY a.FK_Patient_Link_ID, a.AdmissionDate, a.AcuteProvider;
-- 511740 rows	511740 rows	
-- 00:00:04		00:00:05


SELECT 
  o.FK_Patient_Link_ID AS PatientId,
  admit.AdmissionDate,
  los.DischargeDate,
  admit.AdmissionType AS [Status],
  admit.AcuteProvider
FROM #Patients o
LEFT OUTER JOIN #AdmissionTypes admit ON admit.FK_Patient_Link_ID = o.FK_Patient_Link_ID
LEFT OUTER JOIN #LengthOfStay los 
  ON los.FK_Patient_Link_ID = o.FK_Patient_Link_ID
  AND los.AdmissionDate = admit.AdmissionDate
WHERE admit.AdmissionDate < @EndDate
AND (los.DischargeDate IS NULL OR los.DischargeDate < @EndDate);