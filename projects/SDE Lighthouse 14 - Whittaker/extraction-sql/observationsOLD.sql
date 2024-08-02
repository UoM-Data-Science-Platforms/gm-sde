--┌──────────────┐
--│ Observations │
--└──────────────┘

-------- RESEARCH DATA ENGINEER CHECK ---------


-- OUTPUT: Data with the following fields
-- 	-   PatientId (int)
--	-	ObservationName
--	-	ObservationDateTime (YYYY-MM-DD 00:00:00)
--  -   TestResult 
--  -   TestUnit

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2018-01-01'; -- CHECK
DECLARE @EndDate datetime;
SET @EndDate = '2023-10-31'; ---CHECK

DECLARE @MinDate datetime;
SET @MinDate = '1900-01-01';
DECLARE @IndexDate datetime;
SET @IndexDate = '2023-10-31';

--Just want the output, not the messages
SET NOCOUNT ON;

--┌───────────────────────────────────────────────────────────────┐
--│ Define Cohort for LH004: patients that had an SLE diagnosis   │
--└───────────────────────────────────────────────────────────────┘

-- OBJECTIVE: To build the cohort of patients needed for LH003. This reduces duplication of code in the template scripts.

-- COHORT: Any patient with a SLE diagnosis between start and end date.

-- INPUT: assumes there exists one temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: Temp tables as follows:
-- #Cohort

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
VALUES ('sle',1,'F3710',NULL,'Polyneuropathy in disseminated lupus erythematosus'),('sle',1,'F371000',NULL,'Polyneuropathy in disseminated lupus erythematosus'),('sle',1,'F3961',NULL,'Myopathy due to disseminated lupus erythematosus'),('sle',1,'F396100',NULL,'Myopathy due to disseminated lupus erythematosus'),('sle',1,'F4D33',NULL,'Eyelid discoid lupus erythematosus'),('sle',1,'F4D3300',NULL,'Eyelid discoid lupus erythematosus'),('sle',1,'H57y4',NULL,'Lung disease with systemic lupus erythematosus'),('sle',1,'H57y400',NULL,'Lung disease with systemic lupus erythematosus'),('sle',1,'K01x4',NULL,'Nephrotic syndrome in systemic lupus erythematosus'),('sle',1,'K01x400',NULL,'Nephrotic syndrome in systemic lupus erythematosus'),('sle',1,'M154.',NULL,'Lupus erythematosus'),('sle',1,'M154.00',NULL,'Lupus erythematosus'),('sle',1,'M1540',NULL,'Lupus erythematosus chronicus'),('sle',1,'M154000',NULL,'Lupus erythematosus chronicus'),('sle',1,'M1541',NULL,'Discoid lupus erythematosus'),('sle',1,'M154100',NULL,'Discoid lupus erythematosus'),('sle',1,'M1542',NULL,'Lupus erythematosus migrans'),('sle',1,'M154200',NULL,'Lupus erythematosus migrans'),('sle',1,'M1543',NULL,'Lupus erythematosus nodularis'),('sle',1,'M154300',NULL,'Lupus erythematosus nodularis'),('sle',1,'M1544',NULL,'Lupus erythematosus profundus'),('sle',1,'M154400',NULL,'Lupus erythematosus profundus'),('sle',1,'M1545',NULL,'Lupus erythematosus tumidus'),('sle',1,'M154500',NULL,'Lupus erythematosus tumidus'),('sle',1,'M1546',NULL,'Lupus erythematosus unguium mutilans'),('sle',1,'M154600',NULL,'Lupus erythematosus unguium mutilans'),('sle',1,'M154z',NULL,'Lupus erythematosus NOS'),('sle',1,'M154z00',NULL,'Lupus erythematosus NOS'),('sle',1,'Myu78',NULL,'[X]Other local lupus erythematosus'),('sle',1,'Myu7800',NULL,'[X]Other local lupus erythematosus'),('sle',1,'N000.',NULL,'Systemic lupus erythematosus'),('sle',1,'N000.00',NULL,'Systemic lupus erythematosus'),('sle',1,'N0002',NULL,'Drug-induced systemic lupus erythematosus'),('sle',1,'N000200',NULL,'Drug-induced systemic lupus erythematosus'),('sle',1,'N000z',NULL,'Systemic lupus erythematosus NOS'),('sle',1,'N000z00',NULL,'Systemic lupus erythematosus NOS'),('sle',1,'Nyu43',NULL,'[X]Other forms of systemic lupus erythematosus'),('sle',1,'Nyu4300',NULL,'[X]Other forms of systemic lupus erythematosus');
INSERT INTO #codesreadv2
VALUES ('creatinine',1,'44J3.',NULL,'Serum creatinine'),('creatinine',1,'44J3.00',NULL,'Serum creatinine'),('creatinine',1,'44JC.',NULL,'Corrected plasma creatinine level'),('creatinine',1,'44JC.00',NULL,'Corrected plasma creatinine level'),('creatinine',1,'44JD.',NULL,'Corrected serum creatinine level'),('creatinine',1,'44JD.00',NULL,'Corrected serum creatinine level'),('creatinine',1,'44JF.',NULL,'Plasma creatinine level'),('creatinine',1,'44JF.00',NULL,'Plasma creatinine level'),('creatinine',1,'44J3z',NULL,'Serum creatinine NOS'),('creatinine',1,'44J3z00',NULL,'Serum creatinine NOS');
INSERT INTO #codesreadv2
VALUES ('egfr',1,'451E.',NULL,'Glomerular filtration rate calculated by abbreviated Modification of Diet in Renal Disease Study Group calculation'),('egfr',1,'451E.00',NULL,'Glomerular filtration rate calculated by abbreviated Modification of Diet in Renal Disease Study Group calculation'),('egfr',1,'451G.',NULL,'Glomerular filtration rate calculated by abbreviated Modification of Diet in Renal Disease Study Group calculation adjusted for African American origin'),('egfr',1,'451G.00',NULL,'Glomerular filtration rate calculated by abbreviated Modification of Diet in Renal Disease Study Group calculation adjusted for African American origin'),('egfr',1,'451K.',NULL,'Estimated glomerular filtration rate using Chronic Kidney Disease Epidemiology Collaboration formula per 1.73 square metres'),('egfr',1,'451K.00',NULL,'Estimated glomerular filtration rate using Chronic Kidney Disease Epidemiology Collaboration formula per 1.73 square metres'),('egfr',1,'451M.',NULL,'Estimated glomerular filtration rate using cystatin C Chronic Kidney Disease Epidemiology Collaboration equation per 1.73 square metres'),('egfr',1,'451M.00',NULL,'Estimated glomerular filtration rate using cystatin C Chronic Kidney Disease Epidemiology Collaboration equation per 1.73 square metres'),('egfr',1,'451N.',NULL,'Estimated glomerular filtration rate using creatinine Chronic Kidney Disease Epidemiology Collaboration equation per 1.73 square metres'),('egfr',1,'451N.00',NULL,'Estimated glomerular filtration rate using creatinine Chronic Kidney Disease Epidemiology Collaboration equation per 1.73 square metres'),('egfr',1,'451F.',NULL,'Glomerular filtration rate'),('egfr',1,'451F.00',NULL,'Glomerular filtration rate')

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
VALUES ('sle',1,'F3710',NULL,'Polyneuropathy in disseminated lupus erythematosus'),('sle',1,'F3961',NULL,'Myopathy due to disseminated lupus erythematosus'),('sle',1,'F4D33',NULL,'Discoid lupus eyelid'),('sle',1,'H57y4',NULL,'Lung disease with systemic lupus erythematosus'),('sle',1,'K01x4',NULL,'(Nephr synd in system lupus erythemat) or (lupus nephritis]'),('sle',1,'M154.',NULL,'Lupus erythematosus'),('sle',1,'M1540',NULL,'Lupus erythematosus chronicus'),('sle',1,'M1541',NULL,'Discoid lupus erythematosus'),('sle',1,'M1542',NULL,'Lupus erythematosus migrans'),('sle',1,'M1543',NULL,'Lupus erythematosus nodularis'),('sle',1,'M1544',NULL,'Lupus erythematosus profundus'),('sle',1,'M1545',NULL,'Lupus erythematosus tumidus'),('sle',1,'M1546',NULL,'Lupus erythematosus unguium mutilans'),('sle',1,'M154z',NULL,'Lupus erythematosus NOS'),('sle',1,'Myu78',NULL,'[X]Other local lupus erythematosus'),('sle',1,'N000.',NULL,'Systemic lupus erythematosus'),('sle',1,'N0002',NULL,'Drug-induced systemic lupus erythematosus'),('sle',1,'N000z',NULL,'Systemic lupus erythematosus NOS'),('sle',1,'Nyu43',NULL,'[X]Other forms of systemic lupus erythematosus'),('sle',1,'X00Dx',NULL,'Cerebral lupus'),('sle',1,'X30Kn',NULL,'Lupus nephritis - WHO Class I'),('sle',1,'X30Ko',NULL,'Lupus nephritis - WHO Class II'),('sle',1,'X30Kp',NULL,'Lupus nephritis - WHO Class III'),('sle',1,'X30Kq',NULL,'Lupus nephritis - WHO Class IV'),('sle',1,'X30Kr',NULL,'Lupus nephritis - WHO Class V'),('sle',1,'X30Ks',NULL,'Lupus nephritis - WHO Class VI'),('sle',1,'X50Ew',NULL,'Lupus erythematosus and erythema multiforme-like syndrome'),('sle',1,'X50Ex',NULL,'Chronic discoid lupus erythematosus'),('sle',1,'X50Ez',NULL,'Chilblain lupus erythematosus'),('sle',1,'X704W',NULL,'Limited lupus erythematosus'),('sle',1,'X704X',NULL,'Systemic lupus erythematosus with organ/system involvement'),('sle',1,'X704a',NULL,'Lupus panniculitis'),('sle',1,'X704b',NULL,'Bullous systemic lupus erythematosus'),('sle',1,'X704c',NULL,'Systemic lupus erythematosus with multisystem involvement'),('sle',1,'X704d',NULL,'Cutaneous lupus erythematosus'),('sle',1,'X704g',NULL,'Neonatal lupus erythematosus'),('sle',1,'X704h',NULL,'Subacute cutaneous lupus erythematosus'),('sle',1,'XE0da',NULL,'Lupus nephritis'),('sle',1,'XM197',NULL,'[EDTA] Lupus erythematosus associated with renal failure'),('sle',1,'XaBE1',NULL,'Renal tubulo-interstitial disord in systemic lupus erythemat'),('sle',1,'XaC1J',NULL,'Systemic lupus erythematosus with pericarditis');
INSERT INTO #codesctv3
VALUES ('creatinine',1,'XE2q5',NULL,'Serum creatinine'),('creatinine',1,'XE2q5',NULL,'Serum creatinine level'),('creatinine',1,'XaERc',NULL,'Corrected serum creatinine level'),('creatinine',1,'XaERX',NULL,'Corrected plasma creatinine level'),('creatinine',1,'44J3z',NULL,'Serum creatinine NOS'),('creatinine',1,'XaETQ',NULL,'Plasma creatinine level');
INSERT INTO #codesctv3
VALUES ('egfr',1,'X70kK',NULL,'Tc99m-DTPA clearance - GFR'),('egfr',1,'X70kL',NULL,'Cr51- EDTA clearance - GFR'),('egfr',1,'X90kf',NULL,'With GFR'),('egfr',1,'XaK8y',NULL,'Glomerular filtration rate calculated by abbreviated Modification of Diet in Renal Disease Study Group calculation'),('egfr',1,'XaMDA',NULL,'Glomerular filtration rate calculated by abbreviated Modification of Diet in Renal Disease Study Group calculation adjusted for African American origin'),('egfr',1,'XaZpN',NULL,'Estimated glomerular filtration rate using Chronic Kidney Disease Epidemiology Collaboration formula per 1.73 square metres'),('egfr',1,'XacUJ',NULL,'Estimated glomerular filtration rate using cystatin C Chronic Kidney Disease Epidemiology Collaboration equation per 1.73 square metres'),('egfr',1,'XacUK',NULL,'Estimated glomerular filtration rate using creatinine Chronic Kidney Disease Epidemiology Collaboration equation per 1.73 square metres'),('egfr',1,'XSFyN',NULL,'Glomerular filtration rate')

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
VALUES ('sle',1,'11013005',NULL,'SLE glomerulonephritis syndrome, WHO class VI (disorder)'),('sle',1,'15084002',NULL,'Lupus erythematosus profundus (disorder)'),('sle',1,'193178008',NULL,'Polyneuropathy in disseminated lupus erythematosus (disorder)'),('sle',1,'193248005',NULL,'Myopathy due to disseminated lupus erythematosus (disorder)'),('sle',1,'196138005',NULL,'Lung disease with systemic lupus erythematosus (disorder)'),('sle',1,'200936003',NULL,'Lupus erythematosus (disorder)'),('sle',1,'200937007',NULL,'Lupus erythematosus chronicus (disorder)'),('sle',1,'200938002',NULL,'Discoid lupus erythematosus (disorder)'),('sle',1,'200939005',NULL,'Lupus erythematosus migrans (disorder)'),('sle',1,'200940007',NULL,'Lupus erythematosus nodularis (disorder)'),('sle',1,'200941006',NULL,'Lupus erythematosus tumidus (disorder)'),('sle',1,'200942004',NULL,'Lupus erythematosus unguium mutilans (disorder)'),('sle',1,'201436003',NULL,'Drug-induced systemic lupus erythematosus (disorder)'),('sle',1,'238926009',NULL,'Lupus erythematosus and erythema multiforme-like syndrome (disorder)'),('sle',1,'238927000',NULL,'Chronic discoid lupus erythematosus (disorder)'),('sle',1,'238928005',NULL,'Chilblain lupus erythematosus (disorder)'),('sle',1,'239886003',NULL,'Limited lupus erythematosus (disorder)'),('sle',1,'239887007',NULL,'Systemic lupus erythematosus with organ/system involvement (disorder)'),('sle',1,'239888002',NULL,'Lupus panniculitis (disorder)'),('sle',1,'239889005',NULL,'Bullous systemic lupus erythematosus (disorder)'),('sle',1,'239890001',NULL,'Systemic lupus erythematosus with multisystem involvement (disorder)'),('sle',1,'239891002',NULL,'Subacute cutaneous lupus erythematosus (disorder)'),('sle',1,'307755009',NULL,'Renal tubulo-interstitial disorder in systemic lupus erythematosus (disorder)'),('sle',1,'309762007',NULL,'Systemic lupus erythematosus with pericarditis (disorder)'),('sle',1,'36402006',NULL,'SLE glomerulonephritis syndrome, WHO class IV (disorder)'),('sle',1,'4676006',NULL,'SLE glomerulonephritis syndrome, WHO class II (disorder)'),('sle',1,'52042003',NULL,'SLE glomerulonephritis syndrome, WHO class V (disorder)'),('sle',1,'55464009',NULL,'Systemic lupus erythematosus (disorder)'),('sle',1,'68815009',NULL,'SLE glomerulonephritis syndrome (disorder)'),('sle',1,'7119001',NULL,'Cutaneous lupus erythematosus (disorder)'),('sle',1,'73286009',NULL,'SLE glomerulonephritis syndrome, WHO class I (disorder)'),('sle',1,'76521009',NULL,'SLE glomerulonephritis syndrome, WHO class III (disorder)'),('sle',1,'79291003',NULL,'Discoid lupus erythematosus of eyelid (disorder)'),('sle',1,'95609003',NULL,'Neonatal lupus erythematosus (disorder)'),('sle',1,'95644001',NULL,'Systemic lupus erythematosus encephalitis (disorder)');
INSERT INTO #codessnomed
VALUES ('creatinine',1,'1000731000000107',NULL,'Serum creatinine level (observable entity)'),('creatinine',1,'1106601000000100',NULL,'Substance concentration of creatinine in plasma (observable entity)'),('creatinine',1,'1109421000000104',NULL,'Substance concentration of creatinine in plasma using colorimetric analysis (observable entity)'),('creatinine',1,'1109431000000102',NULL,'Substance concentration of creatinine in plasma using enzymatic analysis (observable entity)'),('creatinine',1,'1109441000000106',NULL,'Substance concentration of creatinine in serum using colorimetric analysis (observable entity)'),('creatinine',1,'1000981000000109',NULL,'Corrected plasma creatinine level (observable entity)'),('creatinine',1,'1000991000000106',NULL,'Corrected serum creatinine level (observable entity)'),('creatinine',1,'1001011000000107',NULL,'Plasma creatinine level (observable entity)'),('creatinine',1,'1107001000000108',NULL,'Substance concentration of creatinine in serum (observable entity)'),('creatinine',1,'1109451000000109',NULL,'Substance concentration of creatinine in serum using enzymatic analysis (observable entity)'),('creatinine',1,'53641000237107',NULL,'Corrected mass concentration of creatinine in plasma (observable entity)');
INSERT INTO #codessnomed
VALUES ('egfr',1,'1011481000000105',NULL,'eGFR (estimated glomerular filtration rate) using creatinine Chronic Kidney Disease Epidemiology Collaboration equation per 1.73 square metres'),('egfr',1,'1011491000000107',NULL,'eGFR (estimated glomerular filtration rate) using cystatin C Chronic Kidney Disease Epidemiology Collaboration equation per 1.73 square metres'),('egfr',1,'1020291000000106',NULL,'GFR (glomerular filtration rate) calculated by abbreviated Modification of Diet in Renal Disease Study Group calculation'),('egfr',1,'1107411000000104',NULL,'eGFR (estimated glomerular filtration rate) by laboratory calculation'),('egfr',1,'241373003',NULL,'Technetium-99m-diethylenetriamine pentaacetic acid clearance - glomerular filtration rate (procedure)'),('egfr',1,'262300005',NULL,'With glomerular filtration rate'),('egfr',1,'737105002',NULL,'GFR (glomerular filtration rate) calculation technique'),('egfr',1,'80274001',NULL,'Glomerular filtration rate (observable entity)'),('egfr',1,'996231000000108',NULL,'GFR (glomerular filtration rate) calculated by abbreviated Modification of Diet in Renal Disease Study Group calculation adjusted for African American origin'),('egfr',1,'857971000000104',NULL,'Estimated glomerular filtration rate using Chronic Kidney Disease Epidemiology Collaboration formula (observable entity)'),('egfr',1,'963601000000106',NULL,'Estimated glomerular filtration rate using cystatin C Chronic Kidney Disease Epidemiology Collaboration equation (observable entity)'),('egfr',1,'963611000000108',NULL,'Estimated glomerular filtration rate using cystatin C per 1.73 square metres'),('egfr',1,'963621000000102',NULL,'Estimated glomerular filtration rate using creatinine Chronic Kidney Disease Epidemiology Collaboration equation (observable entity)'),('egfr',1,'963631000000100',NULL,'Estimated glomerular filtration rate using serum creatinine per 1.73 square metres'),('egfr',1,'857981000000102',NULL,'Estimated glomerular filtration rate using Chronic Kidney Disease Epidemiology Collaboration formula per 1.73 square metres')

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
VALUES ('sle',1,'^ESCTBU514089',NULL,'Bullous systemic lupus erythematosus'),('sle',1,'^ESCTCD512809',NULL,'CDLE - Chronic discoid lupus erythematosus'),('sle',1,'^ESCTCE406029',NULL,'Cerebral systemic lupus erythematosus'),('sle',1,'^ESCTCH512808',NULL,'Chronic discoid lupus erythematosus'),('sle',1,'^ESCTCH512810',NULL,'Chilblain lupus erythematosus'),('sle',1,'^ESCTCR397384',NULL,'CRF - Chronic renal failure'),('sle',1,'^ESCTDI378949',NULL,'Discoid lupus erythematosus of eyelid'),('sle',1,'^ESCTDI378950',NULL,'Discoid lupus erythematosus eyelid'),('sle',1,'^ESCTDI378951',NULL,'Discoid lupus eyelid'),('sle',1,'^ESCTDL480563',NULL,'DLE - Discoid lupus erythematosus'),('sle',1,'^ESCTLE480559',NULL,'LE - Lupus erythematosus'),('sle',1,'^ESCTLE480564',NULL,'LE - Discoid lupus erythematosus'),('sle',1,'^ESCTLI514085',NULL,'Limited lupus erythematosus'),('sle',1,'^ESCTLU257360',NULL,'Lupus nephritis - WHO Class II'),('sle',1,'^ESCTLU267516',NULL,'Lupus with glomerular sclerosis'),('sle',1,'^ESCTLU267517',NULL,'Lupus nephritis - WHO Class VI'),('sle',1,'^ESCTLU273907',NULL,'Lupus profundus'),('sle',1,'^ESCTLU308669',NULL,'Lupus nephritis - WHO Class IV'),('sle',1,'^ESCTLU334360',NULL,'Lupus nephritis - WHO Class V'),('sle',1,'^ESCTLU369178',NULL,'Lupus nephritis - WHO Class I'),('sle',1,'^ESCTLU374466',NULL,'Lupus nephritis - WHO Class III'),('sle',1,'^ESCTLU406027',NULL,'Lupus encephalopathy'),('sle',1,'^ESCTLU480560',NULL,'Lupus'),('sle',1,'^ESCTLU512806',NULL,'Lupus erythematosus and erythema multiforme-like syndrome'),('sle',1,'^ESCTLU514088',NULL,'Lupus panniculitis'),('sle',1,'^ESCTME334359',NULL,'Membranous lupus glomerulonephritis'),('sle',1,'^ESCTNE405966',NULL,'Neonatal lupus'),('sle',1,'^ESCTRO512807',NULL,'Rowells syndrome'),('sle',1,'^ESCTSA514093',NULL,'SACLE - Subacute cutaneous lupus erythematosus'),('sle',1,'^ESCTSC514092',NULL,'SCLE - Subacute cutaneous lupus erythematosus'),('sle',1,'^ESCTSK514086',NULL,'Skin and joint lupus'),('sle',1,'^ESCTSL257358',NULL,'SLE glomerulonephritis syndrome, WHO class II'),('sle',1,'^ESCTSL257359',NULL,'SLE with mesangial proliferative glomerulonephritis'),('sle',1,'^ESCTSL267514',NULL,'SLE glomerulonephritis syndrome, WHO class VI'),('sle',1,'^ESCTSL267515',NULL,'SLE with advanced sclerosing glomerulonephritis'),('sle',1,'^ESCTSL308667',NULL,'SLE glomerulonephritis syndrome, WHO class IV'),('sle',1,'^ESCTSL308668',NULL,'SLE with diffuse proliferative glomerulonephritis'),('sle',1,'^ESCTSL334357',NULL,'SLE glomerulonephritis syndrome, WHO class V'),('sle',1,'^ESCTSL334358',NULL,'SLE with membranous glomerulonephritis'),('sle',1,'^ESCTSL340060',NULL,'SLE - Systemic lupus erythematosus'),('sle',1,'^ESCTSL361922',NULL,'SLE glomerulonephritis syndrome'),('sle',1,'^ESCTSL369176',NULL,'SLE glomerulonephritis syndrome, WHO class I'),('sle',1,'^ESCTSL369177',NULL,'SLE with normal kidneys'),('sle',1,'^ESCTSL374464',NULL,'SLE glomerulonephritis syndrome, WHO class III'),('sle',1,'^ESCTSL374465',NULL,'SLE with focal AND segmental proliferative glomerulonephritis'),('sle',1,'^ESCTSY257361',NULL,'Systemic lupus erythematosus glomerulonephritis syndrome, World Health Organisation (WHO) class II'),('sle',1,'^ESCTSY257362',NULL,'Systemic lupus erythematosus glomerulonephritis syndrome, World Health Organization (WHO) class II'),('sle',1,'^ESCTSY257363',NULL,'Systemic lupus erythematosus glomerulonephritis syndrome, World Health Organization class II'),('sle',1,'^ESCTSY267518',NULL,'Systemic lupus erythematosus glomerulonephritis syndrome, World Health Organisation (WHO) class VI'),('sle',1,'^ESCTSY267519',NULL,'Systemic lupus erythematosus glomerulonephritis syndrome, World Health Organization (WHO) class VI'),('sle',1,'^ESCTSY267520',NULL,'Systemic lupus erythematosus glomerulonephritis syndrome, World Health Organization class VI'),('sle',1,'^ESCTSY308670',NULL,'Systemic lupus erythematosus glomerulonephritis syndrome, World Health Organisation (WHO) class IV'),('sle',1,'^ESCTSY308671',NULL,'Systemic lupus erythematosus glomerulonephritis syndrome, World Health Organization (WHO) class IV'),('sle',1,'^ESCTSY308672',NULL,'Systemic lupus erythematosus glomerulonephritis syndrome, World Health Organization class IV'),('sle',1,'^ESCTSY334361',NULL,'Systemic lupus erythematosus glomerulonephritis syndrome, World Health Organisation (WHO) class V'),('sle',1,'^ESCTSY334362',NULL,'Systemic lupus erythematosus glomerulonephritis syndrome, World Health Organization (WHO) class V'),('sle',1,'^ESCTSY334363',NULL,'Systemic lupus erythematosus glomerulonephritis syndrome, World Health Organization class V'),('sle',1,'^ESCTSY361924',NULL,'Systemic lupus erythematosus glomerulonephritis syndrome'),('sle',1,'^ESCTSY369179',NULL,'Systemic lupus erythematosus glomerulonephritis syndrome, World Health Organisation (WHO) class I'),('sle',1,'^ESCTSY369180',NULL,'Systemic lupus erythematosus glomerulonephritis syndrome, World Health Organization (WHO) class I'),('sle',1,'^ESCTSY369181',NULL,'Systemic lupus erythematosus glomerulonephritis syndrome, World Health Organization class I'),('sle',1,'^ESCTSY374467',NULL,'Systemic lupus erythematosus glomerulonephritis syndrome, World Health Organization (WHO) class III'),('sle',1,'^ESCTSY374468',NULL,'Systemic lupus erythematosus glomerulonephritis syndrome, World Health Organisation (WHO) class III'),('sle',1,'^ESCTSY374469',NULL,'Systemic lupus erythematosus glomerulonephritis syndrome, World Health Organization class III'),('sle',1,'^ESCTSY514090',NULL,'Systemic lupus erythematosus with multisystem involvement'),('sle',1,'EMISNQSY6',NULL,'Systemic lupus erythematosus encephalitis');
INSERT INTO #codesemis
VALUES ('creatinine',1,'^ESCT1262086',NULL,'Creatinine substance concentration in plasma'),('creatinine',1,'^ESCT1262087',NULL,'Creatinine molar concentration in plasma'),('creatinine',1,'^ESCT1262136',NULL,'Creatinine substance concentration in serum'),('creatinine',1,'^ESCT1262137',NULL,'Creatinine molar concentration in serum'),('creatinine',1,'^ESCT1262444',NULL,'Creatinine substance concentration in plasma by colorimetric method'),('creatinine',1,'^ESCT1262445',NULL,'Creatinine molar concentration in plasma by colorimetric method'),('creatinine',1,'^ESCT1262446',NULL,'Creatinine substance concentration in plasma by enzymatic method'),('creatinine',1,'^ESCT1262447',NULL,'Creatinine molar concentration in plasma by enzymatic method'),('creatinine',1,'^ESCT1262448',NULL,'Creatinine substance concentration in serum by colorimetric method'),('creatinine',1,'^ESCT1262449',NULL,'Creatinine molar concentration in serum by colorimetric method'),('creatinine',1,'^ESCT1262450',NULL,'Creatinine substance concentration in serum by enzymatic method'),('creatinine',1,'^ESCT1262451',NULL,'Creatinine molar concentration in serum by enzymatic method');
INSERT INTO #codesemis
VALUES ('egfr',1,'^ESCT1167392',NULL,'Glomerular filtration rate calculation technique'),('egfr',1,'^ESCT1167393',NULL,'GFR - Glomerular filtration rate calculation technique'),('egfr',1,'^ESCT1237005',NULL,'GFR (glomerular filtration rate) calculation technique'),('egfr',1,'^ESCT1249126',NULL,'eGFR (estimated glomerular filtration rate) using CKD-Epi (Chronic Kidney Disease Epidemiology Collaboration) formula per 1.73 square metres'),('egfr',1,'^ESCT1262192',NULL,'Estimated glomerular filtration rate by laboratory calculation'),('egfr',1,'^ESCT1262193',NULL,'eGFR (estimated glomerular filtration rate) by laboratory calculation'),('egfr',1,'^ESCT1268044',NULL,'GFR - glomerular filtration rate'),('egfr',1,'^ESCT1437095',NULL,'Glomerular filtration rate calculated by abbreviated Modification of Diet in Renal Disease Study Group calculation adjusted for African American origin'),('egfr',1,'^ESCT1437099',NULL,'Estimated glomerular filtration rate using creatinine Chronic Kidney Disease Epidemiology Collaboration equation per 1.73 square metres'),('egfr',1,'^ESCT1437100',NULL,'Estimated glomerular filtration rate using cystatin C Chronic Kidney Disease Epidemiology Collaboration equation per 1.73 square metres'),('egfr',1,'^ESCTEG829482',NULL,'eGFR (estimated glomerular filtration rate) using CKD-Epi (Chronic Kidney Disease Epidemiology Collaboration) formula'),('egfr',1,'^ESCTEG835295',NULL,'eGFR (estimated glomerular filtration rate) using cystatin C CKD-EPI (Chronic Kidney Disease Epidemiology Collaboration) equation'),('egfr',1,'^ESCTEG835298',NULL,'eGFR (estimated glomerular filtration rate) using creatinine CKD-EPI (Chronic Kidney Disease Epidemiology Collaboration) equation'),('egfr',1,'^ESCTES829480',NULL,'Estimated glomerular filtration rate using Chronic Kidney Disease Epidemiology Collaboration formula'),('egfr',1,'^ESCTES835294',NULL,'Estimated glomerular filtration rate using cystatin C Chronic Kidney Disease Epidemiology Collaboration equation'),('egfr',1,'^ESCTES835297',NULL,'Estimated glomerular filtration rate using creatinine Chronic Kidney Disease Epidemiology Collaboration equation'),('egfr',1,'^ESCTTC515939',NULL,'Tc99m-DTPA clearance - GFR'),('egfr',1,'^ESCTTE515940',NULL,'Technetium-99m-diethylenetriamine pentaacetic acid clearance - glomerular filtration rate'),('egfr',1,'^ESCTWI545152',NULL,'With GFR'),('egfr',1,'^ESCTWI545153',NULL,'With glomerular filtration rate')

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

----
-- TO DO: CODESETS for exclusion conditions ------
----

-- table of sle coding events

IF OBJECT_ID('tempdb..#SLECodes') IS NOT NULL DROP TABLE #SLECodes;
SELECT FK_Patient_Link_ID, EventDate, COUNT(*) AS NumberOfSLECodes
INTO #SLECodes
FROM SharedCare.[GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'sle' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'sle' AND Version = 1)
)
GROUP BY FK_Patient_Link_ID, EventDate


-- table of patients that meet the exclusion criteria: turberculosis, lupus pernio, drug-induced lupus, neonatal lupus
/*
IF OBJECT_ID('tempdb..#Exclusions') IS NOT NULL DROP TABLE #Exclusions;
SELECT FK_Patient_Link_ID AS PatientId, EventDate
INTO #Exclusions
FROM SharedCare.[GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept in () AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept in () AND Version = 1)
)
GROUP BY FK_Patient_Link_ID, EventDate
*/


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
	p.FK_Patient_Link_ID IN (SELECT DISTINCT FK_Patient_Link_ID FROM #SLECodes WHERE NumberOfSLECodes >= 1)
	--AND 
	--p.FK_Patient_Link_ID NOT IN (SELECT DISTINCT FK_Patient_Link_ID FROM #Exclusions)
AND YEAR(@StartDate) - YearOfBirth > 18


---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------


---------------------------------------------------------------------------------------------------------
---------------------------------------- OBSERVATIONS/MEASUREMENTS --------------------------------------
---------------------------------------------------------------------------------------------------------

-- LOAD CODESETS FOR OBSERVATIONS

-- >>> Following code sets injected: creatinine v1/egfr v1

-- GET VALUES FOR ALL OBSERVATIONS OF INTEREST

IF OBJECT_ID('tempdb..#egfr_creat') IS NOT NULL DROP TABLE #egfr_creat;
SELECT 
	FK_Patient_Link_ID,
	CAST(EventDate AS DATE) AS EventDate,
	Concept = CASE WHEN sn.Concept IS NOT NULL THEN sn.Concept ELSE co.Concept END,
	[Version] =  CASE WHEN sn.[Version] IS NOT NULL THEN sn.[Version] ELSE co.[Version] END,
	[Value],
	[Units]
INTO #egfr_creat
FROM SharedCare.GP_Events gp
LEFT JOIN #VersionedSnomedSets sn ON sn.FK_Reference_SnomedCT_ID = gp.FK_Reference_SnomedCT_ID
LEFT JOIN #VersionedCodeSets co ON co.FK_Reference_Coding_ID = gp.FK_Reference_Coding_ID
WHERE
	(
	 gp.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('egfr', 'creatinine')) ) OR
     gp.FK_Reference_Coding_ID   IN (SELECT FK_Reference_Coding_ID   FROM #VersionedCodeSets WHERE (Concept IN ('egfr', 'creatinine'))  ) 
	 )
AND gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort)
AND EventDate BETWEEN @MinDate and @IndexDate
AND Value <> ''

-- For Egfr and Creatinine we want closest prior to index date
IF OBJECT_ID('tempdb..#TempCurrentEgfr') IS NOT NULL DROP TABLE #TempCurrentEgfr;
SELECT 
	a.FK_Patient_Link_ID, 
	a.Concept,
	Max([Value]) as [Value],
	Max(EventDate) as EventDate
INTO #TempCurrentEgfr
FROM #egfr_creat a
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(EventDate) AS MostRecentDate 
	FROM #egfr_creat
	WHERE Concept = 'egfr'
	GROUP BY FK_Patient_Link_ID
) sub ON sub.MostRecentDate = a.EventDate and sub.FK_Patient_Link_ID = a.FK_Patient_Link_ID
GROUP BY a.FK_Patient_Link_ID, a.Concept;

-- For Egfr and Creatinine we want closest prior to index date
IF OBJECT_ID('tempdb..#TempCurrentCreatinine') IS NOT NULL DROP TABLE #TempCurrentCreatinine;
SELECT 
	a.FK_Patient_Link_ID, 
	a.Concept,
	Max([Value]) as [Value],
	Max(EventDate) as EventDate
INTO #TempCurrentCreatinine
FROM #egfr_creat a
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(EventDate) AS MostRecentDate 
	FROM #egfr_creat
	WHERE Concept = 'creatinine'
	GROUP BY FK_Patient_Link_ID
) sub ON sub.MostRecentDate = a.EventDate and sub.FK_Patient_Link_ID = a.FK_Patient_Link_ID
GROUP BY a.FK_Patient_Link_ID, a.Concept;

-- bring together in a table that can be joined to
IF OBJECT_ID('tempdb..#PatientEgfrCreatinine') IS NOT NULL DROP TABLE #PatientEgfrCreatinine;
SELECT 
	p.FK_Patient_Link_ID,
	Egfr = MAX(CASE WHEN e.Concept = 'Egfr' THEN TRY_CONVERT(NUMERIC(16,5), [Value]) ELSE NULL END),
	Egfr_dt = MAX(CASE WHEN e.Concept = 'Egfr' THEN EventDate ELSE NULL END),
	Creatinine = MAX(CASE WHEN c.Concept = 'Creatinine' THEN TRY_CONVERT(NUMERIC(16,5), [Value]) ELSE NULL END),
	Creatinine_dt = MAX(CASE WHEN c.Concept = 'Creatinine' THEN EventDate ELSE NULL END)
INTO #PatientEgfrCreatinine
FROM #Cohort p
LEFT OUTER JOIN #TempCurrentEgfr e on e.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #TempCurrentCreatinine c on c.FK_Patient_Link_ID = p.FK_Patient_Link_ID
GROUP BY p.FK_Patient_Link_ID



