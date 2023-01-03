--┌──────────────────────────────────────────────┐
--│ Meds - Patients with diabetes and covid	     │
--└──────────────────────────────────────────────┘

---- RESEARCH DATA ENGINEER CHECK ----
-- 1st July 2022 - Richard Williams --
--------------------------------------

-- OUTPUT: Data with the following fields
-- - PatientID
-- - Year
-- - Month
-- - NumberOfPrescriptions_BNFChap1 .. 15

DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2019-01-01';
SET @EndDate = '2022-05-01';

--Just want the output, not the messages
SET NOCOUNT ON;

--> EXECUTE query-get-possible-patients.sql

------------------------------------ CREATE COHORT -------------------------------------
	-- REGISTERED WITH A GM GP
	-- OVER  18
	-- DIABETES DIAGNOSIS

--> EXECUTE query-patient-year-of-birth.sql

--> CODESET diabetes-type-i:1 diabetes-type-ii:1

-- FIND ALL DIAGNOSES OF TYPE 1 DIABETES

IF OBJECT_ID('tempdb..#DiabetesT1Patients') IS NOT NULL DROP TABLE #DiabetesT1Patients;
SELECT 
	FK_Patient_Link_ID,
	SuppliedCode,
	EventDate
INTO #DiabetesT1Patients
FROM [RLS].[vw_GP_Events]
WHERE (SuppliedCode IN (SELECT [Code] FROM #AllCodes WHERE [Concept] IN ('diabetes-type-i') AND [Version] = 1))
	AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
	AND EventDate <= @StartDate

-- FIND ALL DIAGNOSES OF TYPE 2 DIABETES

IF OBJECT_ID('tempdb..#DiabetesT2Patients') IS NOT NULL DROP TABLE #DiabetesT2Patients;
SELECT 
	FK_Patient_Link_ID,
	SuppliedCode,
	EventDate
INTO #DiabetesT2Patients
FROM [RLS].[vw_GP_Events]
WHERE (SuppliedCode IN (SELECT [Code] FROM #AllCodes WHERE [Concept] IN ('diabetes-type-ii') AND [Version] = 1))
	AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
	AND EventDate <= @StartDate

-- CREATE COHORT OF DIABETES PATIENTS

IF OBJECT_ID('tempdb..#Cohort') IS NOT NULL DROP TABLE #Cohort;
SELECT p.FK_Patient_Link_ID, 
	EthnicMainGroup,
	DeathDate,
	yob.YearOfBirth
INTO #Cohort
FROM #Patients p
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE YEAR(@StartDate) - YearOfBirth >= 19 														 -- Over 18
	AND (
		p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #DiabetesT1Patients)  OR			 -- Diabetes T1 diagnosis
		p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #DiabetesT2Patients) 			     -- Diabetes T2 diagnosis
		)
	AND p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude) 			 -- exclude new patients processed post-COPI notice

----------------------------------------------------------------------------------------

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

--> CODESET sglt2-inhibitors:1 metformin:1 insulin:1 ace-inhibitor:2 angiotensin-receptor-blockers:1 aspirin:1 clopidogrel:1

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
	[sglt2-inhibitors] = ISNULL(SUM(CASE WHEN Concept = 'sglt2-inhibitors' then 1 else 0 end),0),
	[metformin] = ISNULL(SUM(CASE WHEN Concept = 'metformin' then 1 else 0 end),0),
	[insulin] = ISNULL(SUM(CASE WHEN Concept = 'insulin' then 1 else 0 end),0),
	[ace-inhibitor] = ISNULL(SUM(CASE WHEN Concept = 'ace-inhibitor' then 1 else 0 end),0),
	[angiotensin-receptor-blockers] = ISNULL(SUM(CASE WHEN Concept = 'angiotensin-receptor-blockers' then 1 else 0 end),0),
	[aspirin] = ISNULL(SUM(CASE WHEN Concept = 'aspirin' then 1 else 0 end),0),
	[clopidogrel] = ISNULL(SUM(CASE WHEN Concept = 'clopidogrel' then 1 else 0 end),0),
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
