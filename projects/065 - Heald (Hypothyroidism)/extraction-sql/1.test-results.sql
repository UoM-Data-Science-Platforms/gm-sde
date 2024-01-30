--┌───────────────────────────┐
--│ Longitudinal test results │
--└───────────────────────────┘

-- Get every thyroid function test (TFT) results and BMI results for each member of the cohort
-- OUTPUT:
--   Patient ID
--   Date of test results
--   Type of test (TSH/FT4/FT3) + TPO Antibody titre (ie we do not need anyone without a TFT result)
--   Test Result Value
--   Measurement Units

-- Just want the output, not the messages
SET NOCOUNT ON;

-- Get the cohort of patients
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
-- 33s

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
-- 41s

-- Now restrict to those >=18
TRUNCATE TABLE #Patients;
INSERT INTO #Patients
SELECT FK_Patient_Link_ID FROM #PatientYearOfBirth
WHERE YearOfBirth <= YEAR(GETDATE()) - 18;
-- 3s

-- NB get-first-diagnosis is fine even though T4 level is not a diagnosis as both codes appear in the Events table

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
VALUES ('bmi',2,'22K..',NULL,'Body Mass Index'),('bmi',2,'22K..00',NULL,'Body Mass Index'),('bmi',2,'22KB.',NULL,'Baseline body mass index'),('bmi',2,'22KB.00',NULL,'Baseline body mass index');
INSERT INTO #codesreadv2
VALUES ('t3',1,'4424.',NULL,'Serum T3 level'),('t3',1,'4424.00',NULL,'Serum T3 level'),('t3',1,'4425.',NULL,'Free T3 level'),('t3',1,'4425.00',NULL,'Free T3 level'),('t3',1,'442U.',NULL,'Serum free triiodothyronine level'),('t3',1,'442U.00',NULL,'Serum free triiodothyronine level'),('t3',1,'442Y.',NULL,'Plasma free triiodothyronine level'),('t3',1,'442Y.00',NULL,'Plasma free triiodothyronine level'),('t3',1,'442f.',NULL,'Serum total T3 level'),('t3',1,'442f.00',NULL,'Serum total T3 level');
INSERT INTO #codesreadv2
VALUES ('t4',1,'4426.',NULL,'Serum T4 level'),('t4',1,'4426.00',NULL,'Serum T4 level'),('t4',1,'4427.',NULL,'Free T4 level'),('t4',1,'4427.00',NULL,'Free T4 level'),('t4',1,'442a.',NULL,'Plasma total T4 level'),('t4',1,'442a.00',NULL,'Plasma total T4 level'),('t4',1,'442b.',NULL,'Serum total T4 level'),('t4',1,'442b.00',NULL,'Serum total T4 level'),('t4',1,'442c.',NULL,'Plasma free T4 level'),('t4',1,'442c.00',NULL,'Plasma free T4 level'),('t4',1,'442V.',NULL,'Serum free T4 level'),('t4',1,'442V.00',NULL,'Serum free T4 level');
INSERT INTO #codesreadv2
VALUES ('tpo-antibody',1,'43Gd.',NULL,'Thyroid peroxidase antibody level'),('tpo-antibody',1,'43Gd.00',NULL,'Thyroid peroxidase antibody level'),('tpo-antibody',1,'43Gd0',NULL,'Serum thyroid peroxidase antibody concentration'),('tpo-antibody',1,'43Gd000',NULL,'Serum thyroid peroxidase antibody concentration');
INSERT INTO #codesreadv2
VALUES ('tsh',1,'442A.',NULL,'TSH - thyroid stim. hormone'),('tsh',1,'442A.00',NULL,'TSH - thyroid stim. hormone'),('tsh',1,'442W.',NULL,'Serum TSH level'),('tsh',1,'442W.00',NULL,'Serum TSH level'),('tsh',1,'442X.',NULL,'Plasma TSH level'),('tsh',1,'442X.00',NULL,'Plasma TSH level')

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
VALUES ('bmi',2,'22K..',NULL,'Body Mass Index'),('bmi',2,'X76CO',NULL,'Quetelet index'),('bmi',2,'Xa7wG',NULL,'Observation of body mass index'),('bmi',2,'XaZcl',NULL,'Baseline body mass index');
INSERT INTO #codesctv3
VALUES ('t3',1,'4424.',NULL,'Serum T3 level'),('t3',1,'4425.',NULL,'Free triiodothyronine level'),('t3',1,'XaERq',NULL,'Serum free T3 level'),('t3',1,'XaERt',NULL,'Plasma free T3 level'),('t3',1,'XaIzH',NULL,'Serum total T3 level');
INSERT INTO #codesctv3
VALUES ('t4',1,'4426.',NULL,'Serum T4 level'),('t4',1,'XaERr',NULL,'Serum free T4 level'),('t4',1,'XaERs',NULL,'Plasma free T4 level'),('t4',1,'XaESF',NULL,'Plasma total T4 level'),('t4',1,'XaESG',NULL,'Serum total T4 level'),('t4',1,'4427.',NULL,'Free thyroxine level');
INSERT INTO #codesctv3
VALUES ('tpo-antibody',1,'XabCy',NULL,'Serum thyroid peroxidase antibody concentration'),('tpo-antibody',1,'XaDvU',NULL,'Thyroid peroxidase antibody level');
INSERT INTO #codesctv3
VALUES ('tsh',1,'442A.',NULL,'TSH - thyroid stimulating hormone (& level)'),('tsh',1,'XaELV',NULL,'Serum TSH level'),('tsh',1,'XaELW',NULL,'Plasma TSH level'),('tsh',1,'XE2wy',NULL,'Thyroid stimulating hormone level')

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
VALUES ('bmi',2,'301331008',NULL,'Finding of body mass index (finding)'),('bmi',2,'60621009',NULL,'Body mass index (observable entity)'),('bmi',2,'846931000000101',NULL,'Baseline body mass index (observable entity)');
INSERT INTO #codessnomed
VALUES ('t3',1,'996771000000104',NULL,'Serum total T3 level (observable entity)'),('t3',1,'1010501000000106',NULL,'Serum T3 level (observable entity)'),('t3',1,'1016961000000104',NULL,'Serum free triiodothyronine level (observable entity)'),('t3',1,'1022811000000100',NULL,'Plasma free triiodothyronine level (observable entity)'),('t3',1,'1027141000000107',NULL,'Free triiodothyronine level (observable entity)'),('t3',1,'1109521000000103',NULL,'Substance concentration of free triiodothyronine in plasma (observable entity)'),('t3',1,'1109471000000100',NULL,'Mass concentration of free triiodothyronine in plasma (observable entity)'),('t3',1,'1109481000000103',NULL,'Mass concentration of free triiodothyronine in serum (observable entity)'),('t3',1,'1109551000000108',NULL,'Substance concentration of free triiodothyronine in serum (observable entity)'),('t3',1,'1110261000000103',NULL,'Mass concentration of total triiodothyronine in serum (observable entity)');
INSERT INTO #codessnomed
VALUES ('t4',1,'1016971000000106',NULL,'Serum free T4 level (observable entity)'),('t4',1,'1010511000000108',NULL,'Serum T4 level (observable entity)'),('t4',1,'1022821000000106',NULL,'Plasma total T4 level (observable entity)'),('t4',1,'1022831000000108',NULL,'Serum total T4 level (observable entity)'),('t4',1,'1022841000000104',NULL,'Plasma free T4 level (observable entity)'),('t4',1,'1030801000000101',NULL,'Free thyroxine level (observable entity)'),('t4',1,'1109391000000105',NULL,'ass concentration of free thyroxine in plasma (observable entity)'),('t4',1,'1109401000000108',NULL,'Mass concentration of free thyroxine in serum (observable entity)'),('t4',1,'1110251000000101',NULL,'Mass concentration of total thyroxine in serum (observable entity)'),('t4',1,'1621000237109',NULL,'Substance concentration of thyroxine in serum (observable entity)');
INSERT INTO #codessnomed
VALUES ('tpo-antibody',1,'54421000237102',NULL,'Arbitrary concentration of thyroperoxidase antibody in plasma (observable entity)'),('tpo-antibody',1,'1030111000000108',NULL,'Thyroid peroxidase antibody level (observable entity)'),('tpo-antibody',1,'1004401000000101',NULL,'Serum thyroid peroxidase antibody concentration (observable entity)'),('tpo-antibody',1,'57721000237103',NULL,'Arbitrary concentration of thyroperoxidase antibody in serum (observable entity)');
INSERT INTO #codessnomed
VALUES ('tsh',1,'1022791000000101',NULL,'Serum thyroid stimulating hormone level (observable entity)'),('tsh',1,'1027151000000105',NULL,'Thyroid stimulating hormone level (observable entity)'),('tsh',1,'1022801000000102',NULL,'Plasma thyroid stimulating hormone level (observable entity)'),('tsh',1,'61167004',NULL,'Thyroid stimulating hormone measurement'),('tsh',1,'143692004',NULL,'Thyroid stimulating hormone (& level)'),('tsh',1,'166335005',NULL,'TSH - thyroid stimulating hormone (& level)'),('tsh',1,'269980001',NULL,'Thyroid stimulating hormone (& level)'),('tsh',1,'313440008',NULL,'Measurement of serum thyroid stimulating hormone'),('tsh',1,'313441007',NULL,'Measurement of plasma thyroid stimulating hormone')

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
VALUES ('bmi',2,'^ESCT1192336',NULL,'Finding of body mass index'),('bmi',2,'^ESCTBA828699',NULL,'Baseline BMI (body mass index)'),('bmi',2,'^ESCTBM348480',NULL,'BMI - Body mass index'),('bmi',2,'^ESCTBO348478',NULL,'Body mass index'),('bmi',2,'^ESCTFI589221',NULL,'Finding of BMI (body mass index)'),('bmi',2,'^ESCTOB589220',NULL,'Observation of body mass index'),('bmi',2,'^ESCTQU348481',NULL,'Quetelet index');
INSERT INTO #codesemis
VALUES ('t3',1,'^ESCTFR840810',NULL,'Free T3 (triiodothyronine) level'),('t3',1,'^ESCT1262452',NULL,'Free T3 (triiodothyronine) mass concentration in plasma'),('t3',1,'^ESCT1262453',NULL,'Free T3 (triiodothyronine) mass concentration in serum'),('t3',1,'^ESCT1262455',NULL,'Free T3 (triiodothyronine) substance concentration in plasma'),('t3',1,'^ESCT1262456',NULL,'Free T3 (triiodothyronine) molar concentration in plasma'),('t3',1,'^ESCT1262459',NULL,'Free T3 (triiodothyronine) substance concentration in serum'),('t3',1,'^ESCT1262460',NULL,'Free T3 (triiodothyronine) molar concentration in serum'),('t3',1,'^ESCT1262550',NULL,'Total T3 (triiodothyronine) mass concentration in serum');
INSERT INTO #codesemis
VALUES ('t4',1,'^ESCTFR841185',NULL,'Free T4 level'),('t4',1,'^ESCTFR841186',NULL,'Free T4'),('t4',1,'^ESCTFT841184',NULL,'FT4 - Free thyroxine level'),('t4',1,'^ESCT1262441',NULL,'Free T4 (thyroxine) mass concentration in plasma'),('t4',1,'^ESCT1262442',NULL,'Free T4 (thyroxine) mass concentration in serum'),('t4',1,'^ESCT1262549',NULL,'Total T4 (thyroxine) mass concentration in serum');
INSERT INTO #codesemis
VALUES ('tsh',1,'^ESCTME603010',NULL,'Measurement of serum thyroid stimulating hormone'),('tsh',1,'^ESCTME603014',NULL,'Measurement of plasma thyroid stimulating hormone'),('tsh',1,'^ESCTPL603012',NULL,'Plasma TSH measurement'),('tsh',1,'^ESCTPL603013',NULL,'Plasma TSH level'),('tsh',1,'^ESCTPL603015',NULL,'Plasma thyroid stimulating hormone measurement'),('tsh',1,'^ESCTSE603008',NULL,'Serum TSH measurement'),('tsh',1,'^ESCTSE603009',NULL,'Serum TSH level'),('tsh',1,'^ESCTSE603011',NULL,'Serum thyroid stimulating hormone measurement'),('tsh',1,'^ESCTTH349400',NULL,'Thyroid stimulating hormone measurement'),('tsh',1,'^ESCTTH349402',NULL,'Thyrotropin measurement'),('tsh',1,'^ESCTTH349403',NULL,'Thyrotropin stimulating hormone measurement'),('tsh',1,'^ESCTTH349405',NULL,'Thyroid stimulating hormone level'),('tsh',1,'^ESCTTS349401',NULL,'TSH measurement'),('tsh',1,'^ESCTTS349404',NULL,'TSH - Thyroid stimulating hormone level'),('tsh',1,'^ESCTTS349406',NULL,'TSH level')

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

-- >>> Following code sets injected: t4 v1
-- We find the first occurrence of the relevant code for each patient. For performance reasons
-- we first search by FK_Reference_Coding_ID, and then later, separately, for FK_Reference_SnomedCT_ID.
-- Combining these into an OR statement in a WHERE clause in a single query is substantially slower than
-- searching for each individually and then combining.
IF OBJECT_ID('tempdb..#FirstT4Leveltemppart1') IS NOT NULL DROP TABLE #FirstT4Leveltemppart1;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS DateOfFirstDiagnosis
INTO #FirstT4Leveltemppart1
FROM SharedCare.GP_Events
WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 't4' AND Version = 1)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
GROUP BY FK_Patient_Link_ID;

-- As per above now we find the first instance of the code based on the FK_Reference_SnomedCT_ID
IF OBJECT_ID('tempdb..#FirstT4Leveltemppart2') IS NOT NULL DROP TABLE #FirstT4Leveltemppart2;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS DateOfFirstDiagnosis
INTO #FirstT4Leveltemppart2
FROM SharedCare.GP_Events
WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 't4' AND Version = 1)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
GROUP BY FK_Patient_Link_ID;

-- We now join the two tables above. By doing a FULL JOIN we include all records from both tables.
-- In each row, at least one of the DateOfFirstDiagnosis will be non NULL. Therefore if one field
-- is NULL, then we use the other. If both are non NULL, then we take the earliest as the goal is
-- to get the first occurrence of the code for each patient.
IF OBJECT_ID('tempdb..#FirstT4Level') IS NOT NULL DROP TABLE #FirstT4Level;
SELECT
	CASE WHEN p1.FK_Patient_Link_ID IS NULL THEN p2.FK_Patient_Link_ID ELSE p1.FK_Patient_Link_ID END AS FK_Patient_Link_ID,
	CASE
		WHEN p1.DateOfFirstDiagnosis IS NULL THEN p2.DateOfFirstDiagnosis
		WHEN p2.DateOfFirstDiagnosis IS NULL THEN p1.DateOfFirstDiagnosis
		WHEN p1.DateOfFirstDiagnosis < p2.DateOfFirstDiagnosis THEN p1.DateOfFirstDiagnosis
		ELSE p2.DateOfFirstDiagnosis
	END AS DateOfFirstDiagnosis
INTO #FirstT4Level
FROM #FirstT4Leveltemppart1 p1
FULL JOIN #FirstT4Leveltemppart2 p2 on p1.FK_Patient_Link_ID = p2.FK_Patient_Link_ID

-- 1m26

-- Now restrict patients to just those with a T4 level
TRUNCATE TABLE #Patients;
INSERT INTO #Patients
SELECT FK_Patient_Link_ID FROM #FirstT4Level;
-- 0s
-- 1,133,737 patients
-- 2m43
--┌───────────────────────────────────┐
--│ Get all events for RQ065 cohort   │
--└───────────────────────────────────┘

------------------------------------------------------------------------------

-- Create a table of events for all the people in our cohort.
-- We do this for Ref_Coding_ID and SNOMED_ID separately for performance reasons.
-- 1. Patients with a FK_Reference_Coding_ID
IF OBJECT_ID('tempdb..#PatientEventData1') IS NOT NULL DROP TABLE #PatientEventData1;
SELECT 
  FK_Patient_Link_ID,
  CAST(EventDate AS DATE) AS EventDate,
  CASE WHEN ISNUMERIC([Value]) = 1 THEN CAST([Value] AS float) ELSE NULL END AS [Value],
  Units,
  SuppliedCode,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID
INTO #PatientEventData1
FROM [SharedCare].GP_Events
WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);
--23s

-- 2. Patients with a FK_Reference_SnomedCT_ID
IF OBJECT_ID('tempdb..#PatientEventData2') IS NOT NULL DROP TABLE #PatientEventData2;
SELECT 
  FK_Patient_Link_ID,
  CAST(EventDate AS DATE) AS EventDate,
  CASE WHEN ISNUMERIC([Value]) = 1 THEN CAST([Value] AS float) ELSE NULL END AS [Value],
  Units,
  SuppliedCode,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID
INTO #PatientEventData2
FROM [SharedCare].GP_Events
WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);
--23s

-- 3. Merge the 2 tables together
IF OBJECT_ID('tempdb..#PatientEventData') IS NOT NULL DROP TABLE #PatientEventData;
SELECT * INTO #PatientEventData FROM #PatientEventData1
UNION
SELECT * FROM #PatientEventData2;
--6s

-- 4. Add indexes for future speed increase
DROP INDEX IF EXISTS eventFKData1 ON #PatientEventData;
CREATE INDEX eventFKData1 ON #PatientEventData (FK_Reference_Coding_ID) INCLUDE (FK_Patient_Link_ID, EventDate, [Value], Units);
DROP INDEX IF EXISTS eventFKData2 ON #PatientEventData;
CREATE INDEX eventFKData2 ON #PatientEventData (FK_Reference_SnomedCT_ID) INCLUDE (FK_Patient_Link_ID, EventDate, [Value], Units);
DROP INDEX IF EXISTS eventFKData3 ON #PatientEventData;
CREATE INDEX eventFKData3 ON #PatientEventData (SuppliedCode) INCLUDE (FK_Patient_Link_ID, EventDate, [Value], Units);
--5s for both
-- 4m25

-- >>> Following code sets injected: tsh v1/t3 v1/t4 v1/tpo-antibody v1/bmi v2

IF OBJECT_ID('tempdb..#Measurements') IS NOT NULL DROP TABLE #Measurements;
CREATE TABLE #Measurements (
	FK_Patient_Link_ID bigint,
	MeasurementDate DATE,
	MeasurementLabel VARCHAR(50),
	MeasurementValue FLOAT,
	MeasurementUnit NVARCHAR(64)
);

-- tsh
INSERT INTO #Measurements
SELECT FK_Patient_Link_ID, EventDate AS MeasurementDate, 'tsh' AS MeasurementLabel, [Value] AS MeasurementValue, Units AS MeasurementUnit
FROM #PatientEventData
WHERE SuppliedCode IN (SELECT [Code] FROM #AllCodes WHERE [Concept] = 'tsh' AND [Version] = 1)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND [Value] IS NOT NULL
AND [Value] != 0;
-- 10s

-- t3
INSERT INTO #Measurements
SELECT FK_Patient_Link_ID, EventDate AS MeasurementDate, 't3' AS MeasurementLabel, [Value] AS MeasurementValue, Units AS MeasurementUnit
FROM #PatientEventData
WHERE SuppliedCode IN (SELECT [Code] FROM #AllCodes WHERE [Concept] = 't3' AND [Version] = 1)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND [Value] IS NOT NULL
AND [Value] != 0;
-- 0s

-- t4
INSERT INTO #Measurements
SELECT FK_Patient_Link_ID, EventDate AS MeasurementDate, 't4' AS MeasurementLabel, [Value] AS MeasurementValue, Units AS MeasurementUnit
FROM #PatientEventData
WHERE SuppliedCode IN (SELECT [Code] FROM #AllCodes WHERE [Concept] = 't4' AND [Version] = 1)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND [Value] IS NOT NULL
AND [Value] != 0;
-- 18s

-- tpo-antibody
INSERT INTO #Measurements
SELECT FK_Patient_Link_ID, EventDate AS MeasurementDate, 'tpo-antibody' AS MeasurementLabel, [Value] AS MeasurementValue, Units AS MeasurementUnit
FROM #PatientEventData
WHERE SuppliedCode IN (SELECT [Code] FROM #AllCodes WHERE [Concept] = 'tpo-antibody' AND [Version] = 1)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND [Value] IS NOT NULL
AND [Value] != 0;
-- 0s

-- bmi
INSERT INTO #Measurements
SELECT FK_Patient_Link_ID, EventDate AS MeasurementDate, 'bmi' AS MeasurementLabel, [Value] AS MeasurementValue, Units AS MeasurementUnit
FROM #PatientEventData
WHERE SuppliedCode IN (SELECT [Code] FROM #AllCodes WHERE [Concept] = 'bmi' AND [Version] = 2)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND [Value] IS NOT NULL
AND [Value] != 0;
-- 14s

SELECT 
  FK_Patient_Link_ID AS PatientId,
  MeasurementDate,
  MeasurementLabel,
  MeasurementValue,
  MeasurementUnit
FROM #Measurements;