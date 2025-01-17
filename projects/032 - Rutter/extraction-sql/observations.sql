--┌──────────────┐
--│ Observations │
--└──────────────┘

-------- RESEARCH DATA ENGINEER CHECK -------------------------------
-- Richard Williams	2021-11-26	Review complete
-- Richard Williams	2022-08-04	Review complete following changes
---------------------------------------------------------------------

/* Observations including: 
	Systolic blood pressure
	Diastolic blood pressure
	HbA1c
	Total cholesterol
	LDL cholesterol
	HDL Cholesterol
	Triglyceride
	Creatinine
	eGFR
	Urinary albumin creatinine ratio
*/

-- OUTPUT: Data with the following fields
-- 	-   PatientId (int)
--  -   MatchedPatientId (int or NULL)
--	-	ObservationName
--	-	ObservationDateTime (YYYY-MM-DD 00:00:00)
--  -   TestResult 
--  -   TestUnit

------ Find the main cohort and the matched controls ---------

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
VALUES ('height',1,'229..',NULL,'O/E - height'),('height',1,'229..00',NULL,'O/E - height'),('height',1,'229Z.',NULL,'O/E - height NOS'),('height',1,'229Z.00',NULL,'O/E - height NOS');
INSERT INTO #codesreadv2
VALUES ('weight',1,'22A..',NULL,'O/E - weight'),('weight',1,'22A..00',NULL,'O/E - weight'),('weight',1,'22AZ.',NULL,'O/E - weight NOS'),('weight',1,'22AZ.00',NULL,'O/E - weight NOS');
INSERT INTO #codesreadv2
VALUES ('cholesterol',2,'44P..',NULL,'Serum cholesterol'),('cholesterol',2,'44P..00',NULL,'Serum cholesterol'),('cholesterol',2,'44PZ.',NULL,'Serum cholesterol NOS'),('cholesterol',2,'44PZ.00',NULL,'Serum cholesterol NOS'),('cholesterol',2,'44PJ.',NULL,'Serum total cholesterol level'),('cholesterol',2,'44PJ.00',NULL,'Serum total cholesterol level'),('cholesterol',2,'44PH.',NULL,'Total cholesterol measurement'),('cholesterol',2,'44PH.00',NULL,'Total cholesterol measurement');
INSERT INTO #codesreadv2
VALUES ('creatinine',1,'44J3.',NULL,'Serum creatinine'),('creatinine',1,'44J3.00',NULL,'Serum creatinine'),('creatinine',1,'44JC.',NULL,'Corrected plasma creatinine level'),('creatinine',1,'44JC.00',NULL,'Corrected plasma creatinine level'),('creatinine',1,'44JD.',NULL,'Corrected serum creatinine level'),('creatinine',1,'44JD.00',NULL,'Corrected serum creatinine level'),('creatinine',1,'44JF.',NULL,'Plasma creatinine level'),('creatinine',1,'44JF.00',NULL,'Plasma creatinine level'),('creatinine',1,'44J3z',NULL,'Serum creatinine NOS'),('creatinine',1,'44J3z00',NULL,'Serum creatinine NOS');
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
VALUES ('triglycerides',1,'44Q..',NULL,'Serum triglycerides'),('triglycerides',1,'44Q..00',NULL,'Serum triglycerides'),('triglycerides',1,'44Q4.',NULL,'Serum fasting triglyceride level'),('triglycerides',1,'44Q4.00',NULL,'Serum fasting triglyceride level'),('triglycerides',1,'44Q5.',NULL,'Serum random triglyceride level'),('triglycerides',1,'44Q5.00',NULL,'Serum random triglyceride level'),('triglycerides',1,'44QZ.',NULL,'Serum triglycerides NOS'),('triglycerides',1,'44QZ.00',NULL,'Serum triglycerides NOS');
INSERT INTO #codesreadv2
VALUES ('urinary-albumin-creatinine-ratio',1,'46TC.',NULL,'Urine albumin:creatinine ratio'),('urinary-albumin-creatinine-ratio',1,'46TC.00',NULL,'Urine albumin:creatinine ratio')

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
VALUES ('height',1,'229..',NULL,'O/E - height'),('height',1,'229Z.',NULL,'O/E - height NOS');
INSERT INTO #codesctv3
VALUES ('weight',1,'22A..',NULL,'O/E - weight'),('weight',1,'22AZ.',NULL,'O/E - weight NOS');
INSERT INTO #codesctv3
VALUES ('cholesterol',2,'XSK14',NULL,'Total cholesterol measurement'),('cholesterol',2,'44PH.',NULL,'Total cholesterol measurement'),('cholesterol',2,'44PJ.',NULL,'Serum total cholesterol level'),('cholesterol',2,'44P..',NULL,'Serum cholesterol'),('cholesterol',2,'44PZ.',NULL,'Serum cholesterol NOS'),('cholesterol',2,'XE2eD',NULL,'Serum cholesterol'),('cholesterol',2,'XaJe9',NULL,'Serum total cholesterol level');
INSERT INTO #codesctv3
VALUES ('creatinine',1,'XE2q5',NULL,'Serum creatinine'),('creatinine',1,'XE2q5',NULL,'Serum creatinine level'),('creatinine',1,'XaERc',NULL,'Corrected serum creatinine level'),('creatinine',1,'XaERX',NULL,'Corrected plasma creatinine level'),('creatinine',1,'44J3z',NULL,'Serum creatinine NOS');
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
VALUES ('triglycerides',1,'XE2q9',NULL,'Serum triglycerides'),('triglycerides',1,'XE2q9',NULL,'Serum triglyceride levels'),('triglycerides',1,'44Q4.',NULL,'Serum fasting triglyceride level'),('triglycerides',1,'44QZ.',NULL,'Serum triglycerides NOS');
INSERT INTO #codesctv3
VALUES ('urinary-albumin-creatinine-ratio',1,'46TC.',NULL,'Urine albumin:creatinine ratio'),('urinary-albumin-creatinine-ratio',1,'XE2n3',NULL,'Urine albumin:creatinine ratio')

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
VALUES ('height',1,'14456009',NULL,'Measuring height of patient'),('height',1,'50373000',NULL,'Body height measure'),('height',1,'139977008',NULL,'O/E - height'),('height',1,'162755006',NULL,'On examination - height'),('height',1,'248327008',NULL,'General finding of height'),('height',1,'248333004',NULL,'Standing height');
INSERT INTO #codessnomed
VALUES ('weight',1,'27113001',NULL,'Body weight'),('weight',1,'139985004',NULL,'O/E - weight'),('weight',1,'162763007',NULL,'On examination - weight'),('weight',1,'248341004',NULL,'General weight finding'),('weight',1,'248345008',NULL,'Body weight'),('weight',1,'271604008',NULL,'Weight finding'),('weight',1,'301333006',NULL,'Finding of measures of body weight'),('weight',1,'363808001',NULL,'Measured body weight'),('weight',1,'424927000',NULL,'Body weight with shoes'),('weight',1,'425024002',NULL,'Body weight without shoes'),('weight',1,'735395000',NULL,'Current body weight'),('weight',1,'784399000',NULL,'Self reported body weight');
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
VALUES ('systolic-blood-pressure',1,'72313002',NULL,'Systolic arterial pressure (observable entity)'),('systolic-blood-pressure',1,'251070002',NULL,'Non-invasive systolic blood pressure'),('systolic-blood-pressure',1,'251071003',NULL,'Invasive systolic blood pressure'),('systolic-blood-pressure',1,'271649006',NULL,'SAP - Systolic arterial pressure'),('systolic-blood-pressure',1,'314438006',NULL,'Minimum systolic blood pressure (observable entity)'),('systolic-blood-pressure',1,'314439003',NULL,'Maximum systolic blood pressure (observable entity)'),('systolic-blood-pressure',1,'314440001',NULL,'Average systolic blood pressure (observable entity)'),('systolic-blood-pressure',1,'314441002',NULL,'Minimum day interval systolic blood pressure (observable entity)'),('systolic-blood-pressure',1,'314442009',NULL,'Minimum night interval systolic blood pressure (observable entity)'),('systolic-blood-pressure',1,'314443004',NULL,'Maximum night interval systolic blood pressure (observable entity)'),('systolic-blood-pressure',1,'314444005',NULL,'Maximum day interval systolic blood pressure (observable entity)'),('systolic-blood-pressure',1,'314445006',NULL,'Average night interval systolic blood pressure (observable entity)'),('systolic-blood-pressure',1,'314446007',NULL,'Average day interval systolic blood pressure (observable entity)'),('systolic-blood-pressure',1,'314447003',NULL,'Minimum 24 hour systolic blood pressure (observable entity)'),('systolic-blood-pressure',1,'314448008',NULL,'Maximum 24 hour systolic blood pressure (observable entity)'),('systolic-blood-pressure',1,'314449000',NULL,'Average 24 hour systolic blood pressure (observable entity'),('systolic-blood-pressure',1,'314464000',NULL,'24 hour systolic blood pressure (observable entity)'),('systolic-blood-pressure',1,'399304008',NULL,'Systolic blood pressure on admission'),('systolic-blood-pressure',1,'400974009',NULL,'Standing systolic blood pressure'),('systolic-blood-pressure',1,'407554009',NULL,'Sitting systolic blood pressure'),('systolic-blood-pressure',1,'407556006',NULL,'Lying systolic blood pressure'),('systolic-blood-pressure',1,'413606001',NULL,'Average home systolic blood pressure'),('systolic-blood-pressure',1,'716579001',NULL,'Baseline systolic blood pressure'),('systolic-blood-pressure',1,'198081000000101',NULL,'Ambulatory systolic blood pressure'),('systolic-blood-pressure',1,'814101000000107',NULL,'Systolic blood pressure centile'),('systolic-blood-pressure',1,'1036551000000101',NULL,'Non-invasive central systolic blood pressure'),('systolic-blood-pressure',1,'1087991000000109',NULL,'Level of reduction in systolic blood pressure on standing (observable entity)'),('systolic-blood-pressure',1,'12929001',NULL,'Normal systolic arterial pressure (finding)'),('systolic-blood-pressure',1,'18050000',NULL,'Increased systolic arterial pressure (finding)'),('systolic-blood-pressure',1,'18352002',NULL,'Abnormal systolic arterial pressure (finding)'),('systolic-blood-pressure',1,'81010002',NULL,'Decreased systolic arterial pressure (finding)'),('systolic-blood-pressure',1,'163030003',NULL,'On examination - Systolic blood pressure reading'),('systolic-blood-pressure',1,'707303003',NULL,'Post exercise systolic blood pressure response abnormal'),('systolic-blood-pressure',1,'707304009',NULL,'Post exercise systolic blood pressure response normal (finding)');
INSERT INTO #codessnomed
VALUES ('urinary-albumin-creatinine-ratio',1,'271075006',NULL,'Urine albumin/creatinine ratio measurement')

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

-- >>> Following code sets injected: hba1c v2/cholesterol v2/hdl-cholesterol v1/ldl-cholesterol v1/egfr v1/creatinine v1/triglycerides v1
-- >>> Following code sets injected: systolic-blood-pressure v1/diastolic-blood-pressure v1/urinary-albumin-creatinine-ratio v1
-- >>> Following code sets injected: height v1/weight v1

-- Get observation values for the main and matched cohort
IF OBJECT_ID('tempdb..#observations') IS NOT NULL DROP TABLE #observations;
SELECT 
	FK_Patient_Link_ID,
	CAST(EventDate AS DATE) AS EventDate,
	Concept = CASE WHEN sn.Concept IS NOT NULL THEN sn.Concept ELSE co.Concept END,
	[Version] =  CASE WHEN sn.[Version] IS NOT NULL THEN sn.[Version] ELSE co.[Version] END,
	[Value],
	[Units]
INTO #observations
FROM RLS.vw_GP_Events gp
LEFT JOIN #VersionedSnomedSets sn ON sn.FK_Reference_SnomedCT_ID = gp.FK_Reference_SnomedCT_ID
LEFT JOIN #VersionedCodeSets co ON co.FK_Reference_Coding_ID = gp.FK_Reference_Coding_ID
WHERE
	(gp.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept NOT IN ('polycystic-ovarian-syndrome', 'gestational-diabetes', 'diabetes-type-ii' )) OR
    gp.FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept NOT IN ('polycystic-ovarian-syndrome', 'gestational-diabetes', 'diabetes-type-ii' )) )
AND (gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #MainCohort) OR gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #MatchedCohort))
AND EventDate BETWEEN '2016-04-01' AND @EndDate

-- WHERE CODES EXIST IN BOTH VERSIONS OF THE CODE SET (OR IN OTHER SIMILAR CODE SETS), THERE WILL BE DUPLICATES, SO EXCLUDE THEM FROM THE SETS/VERSIONS THAT WE DON'T WANT 

IF OBJECT_ID('tempdb..#all_observations') IS NOT NULL DROP TABLE #all_observations;
select 
	FK_Patient_Link_ID, CAST(EventDate AS DATE) EventDate, Concept, [Value], [Units], [Version]
into #all_observations
from #observations
except
select FK_Patient_Link_ID, EventDate, Concept, [Value], [Units], [Version] from #observations 
where 
	(Concept = 'cholesterol' and [Version] <> 2) OR -- e.g. serum HDL cholesterol appears in cholesterol v1 code set, which we don't want, but we do want the code as part of the hdl-cholesterol code set.
	(Concept = 'hba1c' and [Version] <> 2) -- e.g. hba1c level appears twice with same value: from version 1 and version 2. We only want version 2 so exclude any others.

-- REMOVE USELESS OBSERVATIONS WITH NO VALUE

IF OBJECT_ID('tempdb..#observations_final') IS NOT NULL DROP TABLE #observations_final;
SELECT FK_Patient_Link_ID,
	EventDate,
	Concept,
	[Value] = TRY_CONVERT(NUMERIC (18,5), [Value]), --convert to numeric
	[Units]
INTO #observations_final
FROM #all_observations
WHERE [Value] IS NOT NULL AND TRY_CONVERT(NUMERIC (18,5), [Value]) <> 0 AND [Value] <> '0' -- REMOVE NULLS AND ZEROES
	AND UPPER([Value]) NOT LIKE '%[A-Z]%'  -- REMOVES ANY TEXT VALUES


-- BRING TOGETHER FOR FINAL OUTPUT

SELECT	 
	PatientId = m.FK_Patient_Link_ID
	,MainCohortMatchedPatientId = NULL
	,TestName = o.Concept
	,TestDate = o.EventDate
	,TestResult =o.[Value]
	,TestUnit = o.[Units]
FROM #MainCohort m
LEFT JOIN #observations_final o ON o.FK_Patient_Link_ID = m.FK_Patient_Link_ID 
 UNION
-- patients in matched cohort
SELECT	 
	PatientId = m.FK_Patient_Link_ID
	,MainCohortMatchedPatientId = m.PatientWhoIsMatched 
	,TestName = o.Concept
	,TestDate = o.EventDate
	,TestResult = o.[Value]
	,TestUnit = o.[Units]
FROM #MatchedCohort m
LEFT JOIN #observations_final o ON o.FK_Patient_Link_ID = m.FK_Patient_Link_ID
