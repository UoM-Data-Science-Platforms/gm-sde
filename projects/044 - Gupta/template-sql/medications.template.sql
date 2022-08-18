--┌──────────────────────────────────────────────┐
--│ Patients with multimorbidity and covid	     │
--└──────────────────────────────────────────────┘

---- RESEARCH DATA ENGINEER CHECK ----
-- 1st July 2022 - Richard Williams --
--------------------------------------

-- OUTPUT: Data with the following fields
-- - PatientID
-- - Year
-- - Month
-- - NumberOfPrescriptions_BNFChap1 .. 20

DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2019-01-01';
SET @EndDate = '2022-05-01';

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

IF OBJECT_ID('tempdb..#PatientsToInclude') IS NOT NULL DROP TABLE #PatientsToInclude;
SELECT FK_Patient_Link_ID INTO #PatientsToInclude
FROM RLS.vw_Patient_GP_History
GROUP BY FK_Patient_Link_ID
HAVING MIN(StartDate) < '2022-06-01';

-- Set the date variables for the LTC code

DECLARE @IndexDate datetime;
DECLARE @MinDate datetime;
SET @IndexDate = '2022-05-01';
SET @MinDate = '1900-01-01';

--> EXECUTE query-patient-ltcs-date-range.sql 
--> EXECUTE query-patient-ltcs-number-of.sql

-- FIND ALL PATIENTS WITH A MENTAL CONDITION

IF OBJECT_ID('tempdb..#PatientsWithMentalCondition') IS NOT NULL DROP TABLE #PatientsWithMentalCondition;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #PatientsWithMentalCondition
FROM #PatientsWithLTCs
WHERE LTC IN ('Anorexia Or Bulimia', 'Anxiety And Other Somatoform Disorders', 'Dementia', 'Depression', 'Schizophrenia Or Bipolar')
	AND FirstDate < '2020-03-01'
--872,174

-- FIND ALL PATIENTS WITH 2 OR MORE CONDITIONS, INCLUDING A MENTAL CONDITION

IF OBJECT_ID('tempdb..#2orMoreLTCsIncludingMental') IS NOT NULL DROP TABLE #2orMoreLTCsIncludingMental;
SELECT DISTINCT FK_Patient_Link_ID
INTO #2orMoreLTCsIncludingMental
FROM #NumLTCs 
WHERE NumberOfLTCs = 2
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsWithMentalCondition)
--677,226


--> EXECUTE query-patient-year-of-birth.sql
--> EXECUTE query-patients-with-covid.sql start-date:2020-01-01 gp-events-table:RLS.vw_GP_Events all-patients:false

------------------------------------ CREATE COHORT -------------------------------------
	-- REGISTERED WITH A GM GP
	-- OVER  18
	-- HAD A COVID19 INFECTION
	-- 2 OR MORE LTCs INCLUDING ONE MENTAL CONDITION

IF OBJECT_ID('tempdb..#Cohort') IS NOT NULL DROP TABLE #Cohort;
SELECT p.FK_Patient_Link_ID, 
	EthnicMainGroup,
	DeathDate,
	yob.YearOfBirth
INTO #Cohort
FROM #Patients p
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE YEAR(@StartDate) - YearOfBirth >= 19 														 -- Over 18
	AND p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #CovidPatientsMultipleDiagnoses) -- had at least one covid19 infection
	AND p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #2orMoreLTCsIncludingMental)     -- at least 2 LTCs including one mental
	AND p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude) 			 -- exclude new patients processed post-COPI notice


-- TABLE OF GP MEDICATIONS FOR COHORT TO SPEED UP REUSABLE QUERIES

IF OBJECT_ID('tempdb..#PatientMedicationData') IS NOT NULL DROP TABLE #PatientMedicationData;
SELECT 
  FK_Patient_Link_ID,
  CAST(MedicationDate AS DATE) AS MedicationDate,
  SuppliedCode,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID
INTO #PatientMedicationData
FROM [RLS].vw_GP_Medications
WHERE 
	UPPER(SourceTable) NOT LIKE '%REPMED%'  -- exclude duplicate prescriptions 
	AND RepeatMedicationFlag = 'N' 			-- exclude duplicate prescriptions 
	AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort)
	AND MedicationDate < '2022-06-01';

-- LOAD ALL MEDICATIONS CODE SETS NEEDED

--> CODESET bnf-gastro-intestinal-meds:1 bnf-cardiovascular-meds:1 bnf-respiratory-meds:1 bnf-cns-meds:1 bnf-infections-meds:1 bnf-endocrine-meds:1
--> CODESET bnf-obstetrics-gynaecology-meds:1 bnf-malignant-disease-immunosuppression-meds:1 bnf-nutrition-bloods-meds:1 bnf-muskuloskeletal-joint-meds:1
--> CODESET bnf-eye-meds:1 bnf-ear-nose-throat-meds:1 bnf-skin-meds:1 bnf-immunological-meds:1 bnf-anaesthesia-meds:1


-- FIX ISSUE WITH DUPLICATE MEDICATIONS, CAUSED BY SOME CODES APPEARING MULTIPLE TIMES IN #AllCodes

IF OBJECT_ID('tempdb..#AllCodes_1') IS NOT NULL DROP TABLE #AllCodes_1;
SELECT DISTINCT Code, Concept, [Version] INTO #AllCodes_1 FROM #AllCodes

-- RETRIEVE ALL RELEVANT PRESCRPTIONS FOR THE COHORT

IF OBJECT_ID('tempdb..#medications_rx') IS NOT NULL DROP TABLE #medications_rx;
SELECT 
	 m.FK_Patient_Link_ID,
		CAST(MedicationDate AS DATE) as PrescriptionDate,
		Concept = s.Concept
INTO #medications_rx
FROM #PatientMedicationData m
LEFT OUTER JOIN #AllCodes_1 s ON s.Code = m.SuppliedCode
WHERE m.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort)
	AND m.MedicationDate BETWEEN @StartDate AND @EndDate
	AND m.SuppliedCode IN (SELECT [Code] FROM #AllCodes_1) -- using Code due to prevalency discrepancy with IDs

--  FINAL TABLE: NUMBER OF EACH MEDICATION CATEGORY PRESCRIBED EACH MONTH 

select 
	PatientId = FK_Patient_Link_ID,
	YEAR(PrescriptionDate) as [Year], 
	Month(PrescriptionDate) as [Month], 
	[bnf-gastro-intestinal] = ISNULL(SUM(CASE WHEN Concept = 'bnf-gastro-intestinal-meds' then 1 else 0 end),0),
	[bnf-cardiovascular] = ISNULL(SUM(CASE WHEN Concept = 'bnf-cardiovascular-meds' then 1 else 0 end),0),
	[bnf-respiratory] = ISNULL(SUM(CASE WHEN Concept = 'bnf-respiratory-meds' then 1 else 0 end),0),
	[bnf-cns] = ISNULL(SUM(CASE WHEN Concept = 'bnf-cns-meds' then 1 else 0 end),0),
	[bnf-infections] = ISNULL(SUM(CASE WHEN Concept = 'bnf-infections-meds' then 1 else 0 end),0),
	[bnf-endocrine] = ISNULL(SUM(CASE WHEN Concept = 'bnf-endocrine-meds' then 1 else 0 end),0),
	[bnf-obstetrics-gynaecology] = ISNULL(SUM(CASE WHEN Concept = 'bnf-obstetrics-gynaecology-meds' then 1 else 0 end),0),
	[bnf-malignant-disease-immunosuppression] = ISNULL(SUM(CASE WHEN Concept = 'bnf-malignant-disease-immunosuppression-meds' then 1 else 0 end),0),
	[bnf-nutrition-bloods] = ISNULL(SUM(CASE WHEN Concept = 'bnf-gastro-intestinal-meds' then 1 else 0 end),0),
	[bnf-muskuloskeletal-joint] = ISNULL(SUM(CASE WHEN Concept = 'bnf-gastro-intestinal-meds' then 1 else 0 end),0),
	[bnf-eye] = ISNULL(SUM(CASE WHEN Concept = 'bnf-eye-meds' then 1 else 0 end),0),
	[bnf-ear-nose-throat] = ISNULL(SUM(CASE WHEN Concept = 'bnf-ear-nose-throat-meds' then 1 else 0 end),0),
	[bnf-skin] = ISNULL(SUM(CASE WHEN Concept = 'bnf-skin-meds' then 1 else 0 end),0),
	[bnf-immunological] = ISNULL(SUM(CASE WHEN Concept = 'bnf-immunological-meds' then 1 else 0 end),0),
	[bnf-anaesthesia] = ISNULL(SUM(CASE WHEN Concept = 'bnf-anaesthesia-meds' then 1 else 0 end),0)
from #medications_rx
group by FK_Patient_Link_ID, YEAR(PrescriptionDate), Month(PrescriptionDate)
order by FK_Patient_Link_ID, YEAR(PrescriptionDate), Month(PrescriptionDate)
