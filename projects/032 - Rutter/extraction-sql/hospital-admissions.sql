--┌───────────────────────────────────────────────────────────────────────────┐
--│ Hospital stay information for T2D intervention cohort and T2D controls    │
--└───────────────────────────────────────────────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK -------------------------------
-- Richard Williams	2021-11-26	Review complete
-- Richard Williams	2022-08-04	Review complete following changes
---------------------------------------------------------------------

-- OUTPUT: Data with the following fields
-- Patient Id
-- AdmissionDate (DD-MM-YYYY)
-- DischargeDate (DD-MM-YYYY)
-- AdmissionType

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2019-07-09';
DECLARE @EndDate datetime;
SET @EndDate = '2022-03-31';

--Just want the output, not the messages
SET NOCOUNT ON;

-- Find all patients alive at start date
IF OBJECT_ID('tempdb..#PossiblePatients') IS NOT NULL DROP TABLE #PossiblePatients;
SELECT PK_Patient_Link_ID as FK_Patient_Link_ID, EthnicMainGroup, DeathDate INTO #PossiblePatients FROM [RLS].vw_Patient_Link
WHERE (DeathDate IS NULL OR DeathDate >= @StartDate);

-- Find all patients registered with a GP
IF OBJECT_ID('tempdb..#PatientsWithGP') IS NOT NULL DROP TABLE #PatientsWithGP;
SELECT DISTINCT FK_Patient_Link_ID INTO #PatientsWithGP FROM [RLS].vw_Patient
where FK_Reference_Tenancy_ID = 2;

-- Make cohort from patients alive at start date and registered with a GP
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT pp.* INTO #Patients FROM #PossiblePatients pp
INNER JOIN #PatientsWithGP gp on gp.FK_Patient_Link_ID = pp.FK_Patient_Link_ID;

------------------------------------------------------------------------------
--┌────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
--│ Define Cohort for RQ032: patients that had a diabetes intervention and are included in the MyWay Dataset   │
--└────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

-- OBJECTIVE: To build the cohort of patients needed for RQ032. This reduces duplication of code in the template scripts.

-- COHORT: Any patient in the DiabetesMyWay data, with 20:1 matched controls that have Type 2 Diabetes. More detail in the comments throughout this script.

-- INPUT: assumes there exists one temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: Temp tables as follows:
-- #MainCohort
-- #MatchedCohort
-- #PatientEventData

------------------------------------------------------------------------------------------------------------------------------------------------------------

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
VALUES ('diabetes-type-ii',1,'C1001',NULL,'Diabetes mellitus, adult onset, with no mention of complication'),('diabetes-type-ii',1,'C100100',NULL,'Diabetes mellitus, adult onset, with no mention of complication'),('diabetes-type-ii',1,'C1011',NULL,'Diabetes mellitus, adult onset, with ketoacidosis'),('diabetes-type-ii',1,'C101100',NULL,'Diabetes mellitus, adult onset, with ketoacidosis'),('diabetes-type-ii',1,'C1021',NULL,'Diabetes mellitus, adult onset, with hyperosmolar coma'),('diabetes-type-ii',1,'C102100',NULL,'Diabetes mellitus, adult onset, with hyperosmolar coma'),('diabetes-type-ii',1,'C1031',NULL,'Diabetes mellitus, adult onset, with ketoacidotic coma'),('diabetes-type-ii',1,'C103100',NULL,'Diabetes mellitus, adult onset, with ketoacidotic coma'),('diabetes-type-ii',1,'C1041',NULL,'Diabetes mellitus, adult onset, with renal manifestation'),('diabetes-type-ii',1,'C104100',NULL,'Diabetes mellitus, adult onset, with renal manifestation'),('diabetes-type-ii',1,'C1051',NULL,'Diabetes mellitus, adult onset, with ophthalmic manifestation'),('diabetes-type-ii',1,'C105100',NULL,'Diabetes mellitus, adult onset, with ophthalmic manifestation'),('diabetes-type-ii',1,'C1061',NULL,'Diabetes mellitus, adult onset, with neurological manifestation'),('diabetes-type-ii',1,'C106100',NULL,'Diabetes mellitus, adult onset, with neurological manifestation'),('diabetes-type-ii',1,'C1071',NULL,'Diabetes mellitus, adult onset, with peripheral circulatory disorder'),('diabetes-type-ii',1,'C107100',NULL,'Diabetes mellitus, adult onset, with peripheral circulatory disorder'),('diabetes-type-ii',1,'C109.',NULL,'Non-insulin dependent diabetes mellitus'),('diabetes-type-ii',1,'C109.00',NULL,'Non-insulin dependent diabetes mellitus'),('diabetes-type-ii',1,'C1090',NULL,'Non-insulin-dependent diabetes mellitus with renal complications'),('diabetes-type-ii',1,'C109000',NULL,'Non-insulin-dependent diabetes mellitus with renal complications'),('diabetes-type-ii',1,'C1091',NULL,'Non-insulin-dependent diabetes mellitus with ophthalmic complications'),('diabetes-type-ii',1,'C109100',NULL,'Non-insulin-dependent diabetes mellitus with ophthalmic complications'),('diabetes-type-ii',1,'C1092',NULL,'Non-insulin-dependent diabetes mellitus with neurological complications'),('diabetes-type-ii',1,'C109200',NULL,'Non-insulin-dependent diabetes mellitus with neurological complications'),('diabetes-type-ii',1,'C1093',NULL,'Non-insulin-dependent diabetes mellitus with multiple complications'),('diabetes-type-ii',1,'C109300',NULL,'Non-insulin-dependent diabetes mellitus with multiple complications'),('diabetes-type-ii',1,'C1094',NULL,'Non-insulin dependent diabetes mellitus with ulcer'),('diabetes-type-ii',1,'C109400',NULL,'Non-insulin dependent diabetes mellitus with ulcer'),('diabetes-type-ii',1,'C1095',NULL,'Non-insulin dependent diabetes mellitus with gangrene'),('diabetes-type-ii',1,'C109500',NULL,'Non-insulin dependent diabetes mellitus with gangrene'),('diabetes-type-ii',1,'C1096',NULL,'Non-insulin-dependent diabetes mellitus with retinopathy'),('diabetes-type-ii',1,'C109600',NULL,'Non-insulin-dependent diabetes mellitus with retinopathy'),('diabetes-type-ii',1,'C1097',NULL,'Non-insulin dependent diabetes mellitus - poor control'),('diabetes-type-ii',1,'C109700',NULL,'Non-insulin dependent diabetes mellitus - poor control'),('diabetes-type-ii',1,'C1099',NULL,'Non-insulin-dependent diabetes mellitus without complication'),('diabetes-type-ii',1,'C109900',NULL,'Non-insulin-dependent diabetes mellitus without complication'),('diabetes-type-ii',1,'C109A',NULL,'Non-insulin dependent diabetes mellitus with mononeuropathy'),('diabetes-type-ii',1,'C109A00',NULL,'Non-insulin dependent diabetes mellitus with mononeuropathy'),('diabetes-type-ii',1,'C109B',NULL,'Non-insulin dependent diabetes mellitus with polyneuropathy'),('diabetes-type-ii',1,'C109B00',NULL,'Non-insulin dependent diabetes mellitus with polyneuropathy'),('diabetes-type-ii',1,'C109C',NULL,'Non-insulin dependent diabetes mellitus with nephropathy'),('diabetes-type-ii',1,'C109C00',NULL,'Non-insulin dependent diabetes mellitus with nephropathy'),('diabetes-type-ii',1,'C109D',NULL,'Non-insulin dependent diabetes mellitus with hypoglycaemic coma'),('diabetes-type-ii',1,'C109D00',NULL,'Non-insulin dependent diabetes mellitus with hypoglycaemic coma'),('diabetes-type-ii',1,'C109E',NULL,'Non-insulin dependent diabetes mellitus with diabetic cataract'),('diabetes-type-ii',1,'C109E00',NULL,'Non-insulin dependent diabetes mellitus with diabetic cataract'),('diabetes-type-ii',1,'C109F',NULL,'Non-insulin-dependent diabetes mellitus with peripheral angiopathy'),('diabetes-type-ii',1,'C109F00',NULL,'Non-insulin-dependent diabetes mellitus with peripheral angiopathy'),('diabetes-type-ii',1,'C109G',NULL,'Non-insulin dependent diabetes mellitus with arthropathy'),('diabetes-type-ii',1,'C109G00',NULL,'Non-insulin dependent diabetes mellitus with arthropathy'),('diabetes-type-ii',1,'C109H',NULL,'Non-insulin dependent diabetes mellitus with neuropathic arthropathy'),('diabetes-type-ii',1,'C109H00',NULL,'Non-insulin dependent diabetes mellitus with neuropathic arthropathy'),('diabetes-type-ii',1,'C109J',NULL,'Insulin treated Type 2 diabetes mellitus'),('diabetes-type-ii',1,'C109J00',NULL,'Insulin treated Type 2 diabetes mellitus'),('diabetes-type-ii',1,'C109K',NULL,'Hyperosmolar non-ketotic state in type 2 diabetes mellitus'),('diabetes-type-ii',1,'C109K00',NULL,'Hyperosmolar non-ketotic state in type 2 diabetes mellitus'),('diabetes-type-ii',1,'C10D.',NULL,'Diabetes mellitus autosomal dominant type 2'),('diabetes-type-ii',1,'C10D.00',NULL,'Diabetes mellitus autosomal dominant type 2'),('diabetes-type-ii',1,'C10F.',NULL,'Type 2 diabetes mellitus'),('diabetes-type-ii',1,'C10F.00',NULL,'Type 2 diabetes mellitus'),('diabetes-type-ii',1,'C10F0',NULL,'Type 2 diabetes mellitus with renal complications'),('diabetes-type-ii',1,'C10F000',NULL,'Type 2 diabetes mellitus with renal complications'),('diabetes-type-ii',1,'C10F1',NULL,'Type 2 diabetes mellitus with ophthalmic complications'),('diabetes-type-ii',1,'C10F100',NULL,'Type 2 diabetes mellitus with ophthalmic complications'),('diabetes-type-ii',1,'C10F2',NULL,'Type 2 diabetes mellitus with neurological complications'),('diabetes-type-ii',1,'C10F200',NULL,'Type 2 diabetes mellitus with neurological complications'),('diabetes-type-ii',1,'C10F3',NULL,'Type 2 diabetes mellitus with multiple complications'),('diabetes-type-ii',1,'C10F300',NULL,'Type 2 diabetes mellitus with multiple complications'),('diabetes-type-ii',1,'C10F4',NULL,'Type 2 diabetes mellitus with ulcer'),('diabetes-type-ii',1,'C10F400',NULL,'Type 2 diabetes mellitus with ulcer'),('diabetes-type-ii',1,'C10F5',NULL,'Type 2 diabetes mellitus with gangrene'),('diabetes-type-ii',1,'C10F500',NULL,'Type 2 diabetes mellitus with gangrene'),('diabetes-type-ii',1,'C10F6',NULL,'Type 2 diabetes mellitus with retinopathy'),('diabetes-type-ii',1,'C10F600',NULL,'Type 2 diabetes mellitus with retinopathy'),('diabetes-type-ii',1,'C10F7',NULL,'Type 2 diabetes mellitus - poor control'),('diabetes-type-ii',1,'C10F700',NULL,'Type 2 diabetes mellitus - poor control'),('diabetes-type-ii',1,'C10F9',NULL,'Type 2 diabetes mellitus without complication'),('diabetes-type-ii',1,'C10F900',NULL,'Type 2 diabetes mellitus without complication'),('diabetes-type-ii',1,'C10FA',NULL,'Type 2 diabetes mellitus with mononeuropathy'),('diabetes-type-ii',1,'C10FA00',NULL,'Type 2 diabetes mellitus with mononeuropathy'),('diabetes-type-ii',1,'C10FB',NULL,'Type 2 diabetes mellitus with polyneuropathy'),('diabetes-type-ii',1,'C10FB00',NULL,'Type 2 diabetes mellitus with polyneuropathy'),('diabetes-type-ii',1,'C10FC',NULL,'Type 2 diabetes mellitus with nephropathy'),('diabetes-type-ii',1,'C10FC00',NULL,'Type 2 diabetes mellitus with nephropathy'),('diabetes-type-ii',1,'C10FD',NULL,'Type 2 diabetes mellitus with hypoglycaemic coma'),('diabetes-type-ii',1,'C10FD00',NULL,'Type 2 diabetes mellitus with hypoglycaemic coma'),('diabetes-type-ii',1,'C10FE',NULL,'Type 2 diabetes mellitus with diabetic cataract'),('diabetes-type-ii',1,'C10FE00',NULL,'Type 2 diabetes mellitus with diabetic cataract'),('diabetes-type-ii',1,'C10FF',NULL,'Type 2 diabetes mellitus with peripheral angiopathy'),('diabetes-type-ii',1,'C10FF00',NULL,'Type 2 diabetes mellitus with peripheral angiopathy'),('diabetes-type-ii',1,'C10FG',NULL,'Type 2 diabetes mellitus with arthropathy'),('diabetes-type-ii',1,'C10FG00',NULL,'Type 2 diabetes mellitus with arthropathy'),('diabetes-type-ii',1,'C10FH',NULL,'Type 2 diabetes mellitus with neuropathic arthropathy'),('diabetes-type-ii',1,'C10FH00',NULL,'Type 2 diabetes mellitus with neuropathic arthropathy'),('diabetes-type-ii',1,'C10FJ',NULL,'Insulin treated Type 2 diabetes mellitus'),('diabetes-type-ii',1,'C10FJ00',NULL,'Insulin treated Type 2 diabetes mellitus'),('diabetes-type-ii',1,'C10FK',NULL,'Hyperosmolar non-ketotic state in type 2 diabetes mellitus'),('diabetes-type-ii',1,'C10FK00',NULL,'Hyperosmolar non-ketotic state in type 2 diabetes mellitus'),('diabetes-type-ii',1,'C10FL',NULL,'Type 2 diabetes mellitus with persistent proteinuria'),('diabetes-type-ii',1,'C10FL00',NULL,'Type 2 diabetes mellitus with persistent proteinuria'),('diabetes-type-ii',1,'C10FM',NULL,'Type 2 diabetes mellitus with persistent microalbuminuria'),('diabetes-type-ii',1,'C10FM00',NULL,'Type 2 diabetes mellitus with persistent microalbuminuria'),('diabetes-type-ii',1,'C10FN',NULL,'Type 2 diabetes mellitus with ketoacidosis'),('diabetes-type-ii',1,'C10FN00',NULL,'Type 2 diabetes mellitus with ketoacidosis'),('diabetes-type-ii',1,'C10FP',NULL,'Type 2 diabetes mellitus with ketoacidotic coma'),('diabetes-type-ii',1,'C10FP00',NULL,'Type 2 diabetes mellitus with ketoacidotic coma'),('diabetes-type-ii',1,'C10FQ',NULL,'Type 2 diabetes mellitus with exudative maculopathy'),('diabetes-type-ii',1,'C10FQ00',NULL,'Type 2 diabetes mellitus with exudative maculopathy'),
('diabetes-type-ii',1,'C10FR',NULL,'Type 2 diabetes mellitus with gastroparesis'),('diabetes-type-ii',1,'C10FR00',NULL,'Type 2 diabetes mellitus with gastroparesis'),('diabetes-type-ii',1,'C10y1',NULL,'Diabetes mellitus, adult onset, with other specified manifestation'),('diabetes-type-ii',1,'C10y100',NULL,'Diabetes mellitus, adult onset, with other specified manifestation'),('diabetes-type-ii',1,'C10z1',NULL,'Diabetes mellitus, adult onset, with unspecified complication'),('diabetes-type-ii',1,'C10z100',NULL,'Diabetes mellitus, adult onset, with unspecified complication');
INSERT INTO #codesreadv2
VALUES ('gestational-diabetes',1,'L1808',NULL,'Gestational diabetes mellitus'),('gestational-diabetes',1,'L180800',NULL,'Gestational diabetes mellitus'),('gestational-diabetes',1,'L1809',NULL,'Gestational diabetes mellitus'),('gestational-diabetes',1,'L180900',NULL,'Gestational diabetes mellitus');
INSERT INTO #codesreadv2
VALUES ('polycystic-ovarian-syndrome',1,'12FA.',NULL,'FH: Polycystic ovaries'),('polycystic-ovarian-syndrome',1,'12FA.00',NULL,'FH: Polycystic ovaries'),('polycystic-ovarian-syndrome',1,'C164.',NULL,'Polycystic ovaries'),('polycystic-ovarian-syndrome',1,'C164.00',NULL,'Polycystic ovaries'),('polycystic-ovarian-syndrome',1,'C165.',NULL,'Polycystic ovarian syndrome'),('polycystic-ovarian-syndrome',1,'C165.00',NULL,'Polycystic ovarian syndrome');
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
VALUES ('diabetes-type-ii',1,'C1011',NULL,'Diabetes mellitus, adult onset, with ketoacidosis'),('diabetes-type-ii',1,'C1021',NULL,'Diabetes mellitus, adult onset, with hyperosmolar coma'),('diabetes-type-ii',1,'C1031',NULL,'Diabetes mellitus, adult onset, with ketoacidotic coma'),('diabetes-type-ii',1,'C1041',NULL,'Diabetes mellitus, adult onset, with renal manifestation'),('diabetes-type-ii',1,'C1051',NULL,'Diabetes mellitus, adult onset, with ophthalmic manifestation'),('diabetes-type-ii',1,'C1061',NULL,'Diabetes mellitus, adult onset, with neurological manifestation'),('diabetes-type-ii',1,'C1071',NULL,'Diabetes mellitus, adult onset, with peripheral circulatory disorder'),('diabetes-type-ii',1,'C1090',NULL,'Non-insulin-dependent diabetes mellitus with renal complications'),('diabetes-type-ii',1,'C1091',NULL,'Non-insulin-dependent diabetes mellitus with ophthalmic complications'),('diabetes-type-ii',1,'C1092',NULL,'Non-insulin-dependent diabetes mellitus with neurological complications'),('diabetes-type-ii',1,'C1093',NULL,'Non-insulin-dependent diabetes mellitus with multiple complications'),('diabetes-type-ii',1,'C1094',NULL,'Non-insulin-dependent diabetes mellitus with ulcer'),('diabetes-type-ii',1,'C1095',NULL,'Non-insulin-dependent diabetes mellitus with gangrene'),('diabetes-type-ii',1,'C1096',NULL,'NIDDM - Non-insulin-dependent diabetes mellitus with retinopathy'),('diabetes-type-ii',1,'C1097',NULL,'Non-insulin-dependent diabetes mellitus - poor control'),('diabetes-type-ii',1,'C10y1',NULL,'Diabetes mellitus, adult onset, with other specified manifestation'),('diabetes-type-ii',1,'C10z1',NULL,'Diabetes mellitus, adult onset, with unspecified complication'),('diabetes-type-ii',1,'X40J5',NULL,'Non-insulin-dependent diabetes mellitus'),('diabetes-type-ii',1,'X40J6',NULL,'Insulin treated Type 2 diabetes mellitus'),('diabetes-type-ii',1,'X40JJ',NULL,'Diabetes mellitus autosomal dominant type 2'),('diabetes-type-ii',1,'XE10F',NULL,'Diabetes mellitus, adult onset, with no mention of complication'),('diabetes-type-ii',1,'XM19j',NULL,'[EDTA] Diabetes Type II (non-insulin-dependent) associated with renal failure'),('diabetes-type-ii',1,'XaELQ',NULL,'Non-insulin-dependent diabetes mellitus without complication'),('diabetes-type-ii',1,'XaEnp',NULL,'Type II diabetes mellitus with mononeuropathy'),('diabetes-type-ii',1,'XaEnq',NULL,'Type 2 diabetes mellitus with polyneuropathy'),('diabetes-type-ii',1,'XaF05',NULL,'Type 2 diabetes mellitus with nephropathy'),('diabetes-type-ii',1,'XaFWI',NULL,'Type II diabetes mellitus with hypoglycaemic coma'),('diabetes-type-ii',1,'XaFmA',NULL,'Type II diabetes mellitus with diabetic cataract'),('diabetes-type-ii',1,'XaFn7',NULL,'Non-insulin-dependent diabetes mellitus with peripheral angiopathy'),('diabetes-type-ii',1,'XaFn8',NULL,'Non-insulin dependent diabetes mellitus with arthropathy'),('diabetes-type-ii',1,'XaFn9',NULL,'Non-insulin dependent diabetes mellitus with neuropathic arthropathy'),('diabetes-type-ii',1,'XaIfG',NULL,'Type II diabetes on insulin'),('diabetes-type-ii',1,'XaIfI',NULL,'Type II diabetes on diet only'),('diabetes-type-ii',1,'XaIrf',NULL,'Hyperosmolar non-ketotic state in type II diabetes mellitus'),('diabetes-type-ii',1,'XaIzQ',NULL,'Type 2 diabetes mellitus with persistent proteinuria'),('diabetes-type-ii',1,'XaIzR',NULL,'Type 2 diabetes mellitus with persistent microalbuminuria'),('diabetes-type-ii',1,'XaJQp',NULL,'Type II diabetes mellitus with exudative maculopathy'),('diabetes-type-ii',1,'XaKyX',NULL,'Type II diabetes mellitus with gastroparesis');
INSERT INTO #codesctv3
VALUES ('gestational-diabetes',1,'L1808',NULL,'Gestational diabetes');
INSERT INTO #codesctv3
VALUES ('polycystic-ovarian-syndrome',1,'X406n',NULL,'Polycystic ovarian syndrome'),('polycystic-ovarian-syndrome',1,'X406n',NULL,'Polycystic ovary syndrome'),('polycystic-ovarian-syndrome',1,'XE10l',NULL,'PCO - Polycystic ovaries'),('polycystic-ovarian-syndrome',1,'XE2p5',NULL,'(Polycystic ovaries) or (Stein-Leventhal syndrome)'),('polycystic-ovarian-syndrome',1,'XaJZG',NULL,'FH: Polycystic ovaries'),('polycystic-ovarian-syndrome',1,'C164.',NULL,'Polycystic ovaries'),('polycystic-ovarian-syndrome',1,'X406n',NULL,'PCOD - Polycystic ovarian disease'),('polycystic-ovarian-syndrome',1,'XE10l',NULL,'Polycystic ovaries'),('polycystic-ovarian-syndrome',1,'X406n',NULL,'PCOS - Polycystic ovarian syndrome'),('polycystic-ovarian-syndrome',1,'XE2p5',NULL,'Polycystic ovaries'),('polycystic-ovarian-syndrome',1,'C164.',NULL,'(Polycystic ovaries) or (isosexual virilisation) or (Stein-Leventhal syndrome) or (multicystic ovaries)'),('polycystic-ovarian-syndrome',1,'X406n',NULL,'Polycystic ovarian disease');
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
VALUES ('gestational-diabetes',1,'^ESCTGE801661',NULL,'Gestational diabetes, delivered'),('gestational-diabetes',1,'^ESCTGE801662',NULL,'Gestational diabetes mellitus complicating pregnancy');
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

-- >>> Following code sets injected: diabetes-type-ii v1/polycystic-ovarian-syndrome v1/gestational-diabetes v1
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

-- FIND PATIENTS WITH A DIAGNOSIS OF POLYCYSTIC OVARY SYNDROME OR GESTATIONAL DIABETES, TO EXCLUDE

IF OBJECT_ID('tempdb..#exclusions') IS NOT NULL DROP TABLE #exclusions;
SELECT DISTINCT gp.FK_Patient_Link_ID
INTO #exclusions
FROM [RLS].[vw_GP_Events] gp
WHERE SuppliedCode IN 
	(SELECT [Code] FROM #AllCodes WHERE [Concept] IN 
		('polycystic-ovarian-syndrome', 'gestational-diabetes') AND [Version] = 1)
			AND EventDate BETWEEN '2018-07-09' AND '2022-03-31'

-- CREATE TABLE OF ALL PATIENTS THAT HAVE ANY LIFETIME DIAGNOSES OF T2D AS OF 2019-07-09
-- THIS TABLE WILL BE JOINED TO IN FINAL TABLE TO PROVIDE ADDITIONAL DIABETES INFO FOR THE MYWAY PATIENTS
-- THIS TABLE WILL ALSO BE USED TO FIND CONTROL PATIENTS WHO HAVE T2D BUT DIDN'T HAVE INTERVENTION

IF OBJECT_ID('tempdb..#diabetes2_diagnoses') IS NOT NULL DROP TABLE #diabetes2_diagnoses;
SELECT gp.FK_Patient_Link_ID, 
	YearOfBirth, 
	Sex,
	EventDate
INTO #diabetes2_diagnoses
FROM [RLS].[vw_GP_Events] gp
LEFT OUTER JOIN #Patients p ON p.FK_Patient_Link_ID = gp.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE (SuppliedCode IN (SELECT [Code] FROM #AllCodes WHERE [Concept] IN ('diabetes-type-ii') AND [Version] = 1)) AND 
	gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
    AND gp.FK_Patient_Link_ID NOT IN (SELECT FK_Patient_Link_ID FROM #exclusions)
	AND (gp.EventDate) <= @StartDate

-- Find earliest diagnosis of T2D for each patient

IF OBJECT_ID('tempdb..#EarliestDiagnosis_T2D') IS NOT NULL DROP TABLE #EarliestDiagnosis_T2D;
SELECT FK_Patient_Link_ID
	,EarliestDiagnosis_T2D = MIN(CAST(EventDate AS DATE))
INTO #EarliestDiagnosis_T2D
FROM #diabetes2_diagnoses
GROUP BY FK_Patient_Link_ID

-- DEFINE MAIN COHORT: PATIENTS IN THE MYWAY DATA

IF OBJECT_ID('tempdb..#MainCohort') IS NOT NULL DROP TABLE #MainCohort;
SELECT DISTINCT
	p.FK_Patient_Link_ID,
	YearOfBirth, 
	Sex,
	EthnicMainGroup
INTO #MainCohort
FROM #Patients p
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE 
	p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM MWDH.Live_Header) 		-- My Way Diabetes Patients
	AND p.FK_Patient_Link_ID NOT IN (SELECT FK_Patient_Link_ID FROM #exclusions)   -- Exclude pts with gestational diabetes
	AND YEAR(@StartDate) - yob.YearOfBirth >= 19									-- Over 18s only
	AND p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude) -- exclude new patients processed post-COPI notice


-- Define the population of potential matches for the cohort
IF OBJECT_ID('tempdb..#PotentialMatches') IS NOT NULL DROP TABLE #PotentialMatches;
SELECT DISTINCT FK_Patient_Link_ID, Sex, YearOfBirth
INTO #PotentialMatches
FROM #diabetes2_diagnoses
WHERE FK_Patient_Link_ID NOT IN (SELECT FK_Patient_Link_ID FROM #MainCohort)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude) -- exclude new patients processed post-COPI notice


--┌────────────────────────────────────────────────────┐
--│ Cohort matching on year of birth / sex 					   │
--└────────────────────────────────────────────────────┘

-- OBJECTIVE: To take a primary cohort and find a 1:n matched cohort based on year of birth and sex.

-- INPUT: Takes two parameters
--  - yob-flex: integer - number of years each way that still allow a year of birth match
--  - num-matches: integer - number of matches for each patient in the cohort
-- Requires two temp tables to exist as follows:
-- #MainCohort (FK_Patient_Link_ID, Sex, YearOfBirth)
-- 	- FK_Patient_Link_ID - unique patient id
--	- Sex - M/F
--	- YearOfBirth - Integer
-- #PotentialMatches (FK_Patient_Link_ID, Sex, YearOfBirth)
-- 	- FK_Patient_Link_ID - unique patient id
--	- Sex - M/F
--	- YearOfBirth - Integer

-- OUTPUT: A temp table as follows:
-- #CohortStore (FK_Patient_Link_ID, YearOfBirth, Sex, MatchingPatientId, MatchingYearOfBirth)
--  - FK_Patient_Link_ID - unique patient id for primary cohort patient
--  - YearOfBirth - of the primary cohort patient
--  - Sex - of the primary cohort patient
--  - MatchingPatientId - id of the matched patient
--  - MatchingYearOfBirth - year of birth of the matched patient

-- TODO 
-- A few things to consider when doing matching:
--  - Consider removing "ghost patients" e.g. people without a primary care record
--  - Consider matching on practice. Patients in different locations might have different outcomes. Also
--    for primary care based diagnosing, practices might have different thoughts on severity, timing etc.
--  - For instances where lots of cases have no matches, consider allowing matching to occur with replacement.
--    I.e. a patient can match more than one person in the main cohort.

-- First we extend the #PrimaryCohort table to give each age-sex combo a unique number
-- and to avoid polluting the #MainCohort table
IF OBJECT_ID('tempdb..#Cases') IS NOT NULL DROP TABLE #Cases;
SELECT FK_Patient_Link_ID AS PatientId, YearOfBirth, Sex, Row_Number() OVER(PARTITION BY YearOfBirth, Sex ORDER BY FK_Patient_Link_ID) AS CaseRowNumber
INTO #Cases FROM #MainCohort;

-- Then we do the same with the #PotentialMatches
IF OBJECT_ID('tempdb..#Matches') IS NOT NULL DROP TABLE #Matches;
SELECT FK_Patient_Link_ID AS PatientId, YearOfBirth, Sex, Row_Number() OVER(PARTITION BY YearOfBirth, Sex ORDER BY FK_Patient_Link_ID) AS AssignedPersonNumber
INTO #Matches FROM #PotentialMatches;

-- Find the number of people with each characteristic in the main cohort
IF OBJECT_ID('tempdb..#CharacteristicCount') IS NOT NULL DROP TABLE #CharacteristicCount;
SELECT YearOfBirth, Sex, COUNT(*) AS [Count] INTO #CharacteristicCount FROM #Cases GROUP BY YearOfBirth, Sex;

-- Find the number of potential matches for each Age/Sex combination
-- The output of this is useful for seeing how many matches you can get
-- SELECT A.YearOfBirth, A.Sex, B.Count / A.Count AS NumberOfPotentialMatchesPerCohortPatient FROM (SELECT * FROM #CharacteristicCount) A LEFT OUTER JOIN (SELECT YearOfBirth, Sex, COUNT(*) AS [Count] FROM #Matches GROUP BY YearOfBirth, Sex) B ON B.YearOfBirth = A.YearOfBirth AND B.Sex = A.Sex ORDER BY NumberOfPotentialMatches,A.YearOfBirth,A.Sex;

-- The final table contains a row for each match, so e.g. if patient 1 has 4
-- matches then there will be 4 rows in the table for this.
IF OBJECT_ID('tempdb..#CohortStore') IS NOT NULL DROP TABLE #CohortStore;
CREATE TABLE #CohortStore(
  PatientId BIGINT, 
  YearOfBirth INT, 
  Sex nchar(1), 
  MatchingPatientId BIGINT,
  MatchingYearOfBirth INT
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
WHILE ( @Counter1 <= 20)
BEGIN
  INSERT INTO #CohortStore
  SELECT c.PatientId, c.YearOfBirth, c.Sex, p.PatientId AS MatchedPatientId, c.YearOfBirth
  FROM #Cases c
    INNER JOIN #CharacteristicCount cc on cc.YearOfBirth = c.YearOfBirth and cc.Sex = c.Sex
    INNER JOIN #Matches p 
      ON p.Sex = c.Sex 
      AND p.YearOfBirth = c.YearOfBirth 
      -- This next line is the trick to only matching each person once
      AND p.AssignedPersonNumber = CaseRowNumber + (@counter1 - 1) * cc.[Count];

  -- We might not need this, but to be extra sure let's delete any patients who 
  -- we're already using to match people
  DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #CohortStore);

  SET @Counter1  = @Counter1  + 1
END

--2. Now relax the yob restriction to get extra matches for people with no matches
DECLARE @LastRowInsert1 INT;
SET @LastRowInsert1=1;
WHILE ( @LastRowInsert1 > 0)
BEGIN
  INSERT INTO #CohortStore
  SELECT sub.PatientId, sub.YearOfBirth, sub.Sex, MatchedPatientId, MAX(m.YearOfBirth) FROM (
  SELECT c.PatientId, c.YearOfBirth, c.Sex, MAX(p.PatientId) AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(p.PatientId) ORDER BY p.PatientId) AS AssignedPersonNumber
  FROM #Cases c
  INNER JOIN #Matches p 
    ON p.Sex = c.Sex 
    AND p.YearOfBirth >= c.YearOfBirth - 1
    AND p.YearOfBirth <= c.YearOfBirth + 1
  WHERE c.PatientId in (
    -- find patients who aren't currently matched
    select PatientId from #Cases except select PatientId from #CohortStore
  )
  GROUP BY c.PatientId, c.YearOfBirth, c.Sex, p.PatientId) sub
  INNER JOIN #Matches m 
    ON m.Sex = sub.Sex 
    AND m.PatientId = sub.MatchedPatientId
    AND m.YearOfBirth >= sub.YearOfBirth - 1
    AND m.YearOfBirth <= sub.YearOfBirth + 1
  WHERE sub.AssignedPersonNumber = 1
  GROUP BY sub.PatientId, sub.YearOfBirth, sub.Sex, MatchedPatientId;
  SELECT @LastRowInsert1=@@ROWCOUNT;

  DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #CohortStore);
END

--3. Now relax the yob restriction to get extra matches for people with only 1, 2, 3, ... n-1 matches
DECLARE @Counter2 INT; 
SET @Counter2=1;
WHILE (@Counter2 < 20)
BEGIN
  DECLARE @LastRowInsert INT;
  SET @LastRowInsert=1;
  WHILE ( @LastRowInsert > 0)
  BEGIN

    IF OBJECT_ID('tempdb..#CohortPatientForEachMatchingPatient') IS NOT NULL DROP TABLE #CohortPatientForEachMatchingPatient;
    SELECT p.PatientId AS MatchedPatientId, c.PatientId, Row_Number() OVER(PARTITION BY p.PatientId ORDER BY p.PatientId) AS MatchedPatientNumber
    INTO #CohortPatientForEachMatchingPatient
    FROM #Matches p
    INNER JOIN #Cases c
      ON p.Sex = c.Sex 
      AND p.YearOfBirth >= c.YearOfBirth - 1
      AND p.YearOfBirth <= c.YearOfBirth + 1
    WHERE c.PatientId IN (
      -- find patients who only have @Counter2 matches
      SELECT PatientId FROM #CohortStore GROUP BY PatientId HAVING count(*) = @Counter2
    );

    IF OBJECT_ID('tempdb..#CohortPatientForEachMatchingPatientWithCohortNumbered') IS NOT NULL DROP TABLE #CohortPatientForEachMatchingPatientWithCohortNumbered;
    SELECT PatientId, MatchedPatientId, Row_Number() OVER(PARTITION BY PatientId ORDER BY MatchedPatientId) AS PatientNumber
    INTO #CohortPatientForEachMatchingPatientWithCohortNumbered
    FROM #CohortPatientForEachMatchingPatient
    WHERE MatchedPatientNumber = 1;

    INSERT INTO #CohortStore
    SELECT s.PatientId, c.YearOfBirth, c.Sex, MatchedPatientId, m.YearOfBirth FROM #CohortPatientForEachMatchingPatientWithCohortNumbered s
    LEFT OUTER JOIN #Cases c ON c.PatientId = s.PatientId
    LEFT OUTER JOIN #Matches m ON m.PatientId = MatchedPatientId
    WHERE PatientNumber = 1;

    SELECT @LastRowInsert=@@ROWCOUNT;

    DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #CohortStore);
  END
  
  SET @Counter2  = @Counter2  + 1
END


-- Get the matched cohort detail - same as main cohort
IF OBJECT_ID('tempdb..#MatchedCohort') IS NOT NULL DROP TABLE #MatchedCohort;
SELECT 
  c.MatchingPatientId AS FK_Patient_Link_ID,
  Sex,
  MatchingYearOfBirth,
  EthnicMainGroup,
  PatientId AS PatientWhoIsMatched
INTO #MatchedCohort
FROM #CohortStore c
LEFT OUTER JOIN #Patients p ON p.FK_Patient_Link_ID = c.MatchingPatientId

-- Define a table with all the patient ids for the main cohort and the matched cohort
IF OBJECT_ID('tempdb..#PatientIds') IS NOT NULL DROP TABLE #PatientIds;
SELECT PatientId AS FK_Patient_Link_ID INTO #PatientIds FROM #CohortStore
UNION
SELECT MatchingPatientId FROM #CohortStore;


-- CREATE TABLE OF ALL GP EVENTS FOR MAIN AND MATCHED COHORTS - TO SPEED UP FUTURE QUERIES

IF OBJECT_ID('tempdb..#PatientEventData') IS NOT NULL DROP TABLE #PatientEventData;
SELECT 
  FK_Patient_Link_ID,
  CAST(EventDate AS DATE) AS EventDate,
  SuppliedCode,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID,
  [Value],
  [Units]
INTO #PatientEventData
FROM [RLS].vw_GP_Events
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientIds)
		AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude) -- exclude new patients processed post-COPI notice

--Outputs from this reusable query:
-- #MainCohort
-- #MatchedCohort
-- #PatientEventData

---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------

------------------------------------------------------------------------------

-- REDUCE THE #Patients TABLE SO THAT IT ONLY INCLUDES THE MAIN AND MATCHED COHORT
-- REUSABLE QUERIES CAN USE IT TO RUN QUICKER 

DELETE FROM #Patients
WHERE FK_Patient_Link_ID NOT IN (SELECT FK_Patient_Link_ID FROM #PatientIds)

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

--┌────────────────────────────────────┐
--│ COVID-related secondary admissions │
--└────────────────────────────────────┘

-- OBJECTIVE: To classify every admission to secondary care based on whether it is a COVID or non-COVID related.
--						A COVID-related admission is classed as an admission within 4 weeks after, or up to 2 weeks before
--						a positive test.

-- INPUT: Takes one parameter
--  - start-date: string - (YYYY-MM-DD) the date to count diagnoses from. Usually this should be 2020-01-01.
--	-	all-patients: boolean - (true/false) if true, then all patients are included, otherwise only those in the pre-existing #Patients table.
--	- gp-events-table: string - (table name) the name of the table containing the GP events. Usually is "RLS.vw_GP_Events" but can be anything with the columns: FK_Patient_Link_ID, EventDate, and SuppliedCode
-- And assumes there exists two temp tables as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort
-- #Admissions (FK_Patient_Link_ID, AdmissionDate, AcuteProvider)
--  A distinct list of the admissions for each patient in the cohort

-- OUTPUT: A temp table as follows:
-- #COVIDUtilisationAdmissions (FK_Patient_Link_ID, AdmissionDate, AcuteProvider, CovidHealthcareUtilisation)
--	- FK_Patient_Link_ID - unique patient id
--	- AdmissionDate - date of admission (YYYY-MM-DD)
--	- AcuteProvider - Bolton, SRFT, Stockport etc..
--	- CovidHealthcareUtilisation - 'TRUE' if admission within 4 weeks after, or up to 14 days before, a positive test

-- Get first positive covid test for each patient
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
AND EventDate > '2019-07-09'
AND EventDate <= @TEMPWithCovidEndDate
--AND EventDate <= GETDATE()
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

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
FROM #PatientEventData
WHERE SuppliedCode IN (
	select Code from #AllCodes 
	where Concept in ('covid-positive-antigen-test','covid-positive-pcr-test','covid-positive-test-other') 
	AND Version = 1
)
AND EventDate <= @TEMPWithCovidEndDate
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

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

IF OBJECT_ID('tempdb..#COVIDUtilisationAdmissions') IS NOT NULL DROP TABLE #COVIDUtilisationAdmissions;
SELECT 
	a.*, 
	CASE
		WHEN c.FK_Patient_Link_ID IS NOT NULL THEN 'TRUE'
		ELSE 'FALSE'
	END AS CovidHealthcareUtilisation
INTO #COVIDUtilisationAdmissions 
FROM #Admissions a
LEFT OUTER join #CovidPatients c ON 
	a.FK_Patient_Link_ID = c.FK_Patient_Link_ID 
	AND a.AdmissionDate <= DATEADD(WEEK, 4, c.FirstCovidPositiveDate)
	AND a.AdmissionDate >= DATEADD(DAY, -14, c.FirstCovidPositiveDate);
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

--bring together for final output
--patients in main cohort
SELECT 
	PatientId = m.FK_Patient_Link_ID,
	NULL AS MainCohortMatchedPatientId,
	l.AdmissionDate,
	l.DischargeDate,
	ty.AdmissionType,
	c.CovidHealthcareUtilisation
FROM #MainCohort m 
INNER JOIN #LengthOfStay l ON m.FK_Patient_Link_ID = l.FK_Patient_Link_ID
INNER JOIN #COVIDUtilisationAdmissions c ON c.FK_Patient_Link_ID = l.FK_Patient_Link_ID AND c.AdmissionDate = l.AdmissionDate AND c.AcuteProvider = l.AcuteProvider
INNER JOIN #AdmissionTypes ty ON ty.FK_Patient_Link_ID = m.FK_Patient_Link_ID AND ty.AdmissionDate = l.AdmissionDate
WHERE l.AdmissionDate BETWEEN @StartDate AND @EndDate
--patients in matched cohort
UNION
SELECT 
	PatientId = m.FK_Patient_Link_ID,
	PatientWhoIsMatched AS MainCohortMatchedPatientId,
	l.AdmissionDate,
	DischargeDate,
	ty.AdmissionType,
    c.CovidHealthcareUtilisation
FROM #MatchedCohort m 
INNER JOIN #LengthOfStay l ON m.FK_Patient_Link_ID = l.FK_Patient_Link_ID
INNER JOIN #COVIDUtilisationAdmissions c ON c.FK_Patient_Link_ID = l.FK_Patient_Link_ID AND c.AdmissionDate = l.AdmissionDate AND c.AcuteProvider = l.AcuteProvider
INNER JOIN #AdmissionTypes ty ON ty.FK_Patient_Link_ID = m.FK_Patient_Link_ID AND ty.AdmissionDate = l.AdmissionDate
WHERE l.AdmissionDate BETWEEN @StartDate AND @EndDate