--┌──────────────────────────────────────────────┐
--│ Patients with multimorbidity and covid	     │
--└──────────────────────────────────────────────┘

------------- RDE CHECK -----------------
-----------------------------------------	

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

------------------------------------ CREATE COHORT -------------------------------------
	-- REGISTERED WITH A GM GP
	-- OVER  18
	-- DIABETES DIAGNOSIS

--> EXECUTE query-patient-year-of-birth.sql

IF OBJECT_ID('tempdb..#DiabetesT1Patients') IS NOT NULL DROP TABLE #DiabetesT1Patients;
SELECT 
	FK_Patient_Link_ID,
	SuppliedCode,
	EventDate
INTO #DiabetesT1Patients
FROM [RLS].[vw_GP_Events]
WHERE (
    FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('diabetes-type-i') AND Version = 1) OR
    FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('diabetes-type-i') AND Version = 1)
	)
	AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)

SELECT FK_Patient_Link_ID, MIN(EventDate) AS MinDate
INTO #T1Min
FROM #DiabetesT2Patients

IF OBJECT_ID('tempdb..#DiabetesT2Patients') IS NOT NULL DROP TABLE #DiabetesT2Patients;
SELECT 
	FK_Patient_Link_ID,
	SuppliedCode,
	EventDate
INTO #DiabetesT2Patients
FROM [RLS].[vw_GP_Events]
WHERE (
    FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('diabetes-type-ii') AND Version = 1) OR
    FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('diabetes-type-ii') AND Version = 1)
	)
	AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)

SELECT FK_Patient_Link_ID, MIN(EventDate) AS MinDate
INTO #T2Min
FROM #DiabetesT2Patients


IF OBJECT_ID('tempdb..#Cohort') IS NOT NULL DROP TABLE #Cohort;
SELECT p.FK_Patient_Link_ID, 
	EthnicMainGroup,
	DeathDate,
	yob.YearOfBirth,
	DiabetesT1 = CASE WHEN t1.FK_Patient_Link_ID IS NOT NULL THEN 1 ELSE 0 END,
	DiabetesT1_EarliestDiagnosis = CASE WHEN t1.FK_Patient_Link_ID IS NOT NULL THEN MinDate ELSE NULL END,
	DiabetesT2 = CASE WHEN t2.FK_Patient_Link_ID IS NOT NULL THEN 1 ELSE 0 END,
	DiabetesT2_EarliestDiagnosis = CASE WHEN t2.FK_Patient_Link_ID IS NOT NULL THEN MinDate ELSE NULL END
INTO #Cohort
FROM #Patients p
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #T1Min t1 ON t1.FK_Patient_Link_ID = c.FK_Patient_Link_ID 
LEFT OUTER JOIN #T2Min t2 ON t2.FK_Patient_Link_ID = c.FK_Patient_Link_ID
WHERE YEAR(@StartDate) - YearOfBirth >= 19 														 -- Over 18
	AND (
		p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #DiabetesT1Patients)  OR			 -- Diabetes T1 diagnosis
		p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #DiabetesT2Patients) 			     -- Diabetes T2 diagnosis
		)

----------------------------------------------------------------------------------------


-- LOAD ALL MEDICATIONS CODE SETS NEEDED

--> CODESET bnf-gastro-intestinal-meds:1 bnf-cardiovascular-meds:1 bnf-respiratory-meds:1 bnf-cns-meds:1 bnf-infections-meds:1 bnf-endocrine-meds:1
--> CODESET bnf-obstetrics-gynaecology-meds:1 bnf-malignant-disease-immunosuppression-meds:1 bnf-nutrition-bloods-meds:1 bnf-muskuloskeletal-joint-meds:1
--> CODESET bnf-eye-meds:1 bnf-ear-nose-throat-meds:1 bnf-skin-meds:1 bnf-immunological-meds:1 bnf-anaesthesia-meds:1

-- FIX ISSUE WITH DUPLICATE MEDICATIONS, CAUSED BY SOME CODES APPEARING MULTIPLE TIMES IN #VersionedCodeSets and #VersionedSnomedSets

IF OBJECT_ID('tempdb..#VersionedCodeSets_1') IS NOT NULL DROP TABLE #VersionedCodeSets_1;
SELECT DISTINCT FK_Reference_Coding_ID, Concept, [Version] INTO #VersionedCodeSets_1 FROM #VersionedCodeSets

IF OBJECT_ID('tempdb..#VersionedSnomedSets_1') IS NOT NULL DROP TABLE #VersionedSnomedSets_1;
SELECT DISTINCT FK_Reference_SnomedCT_ID, Concept, [Version] INTO #VersionedSnomedSets_1 FROM #VersionedSnomedSets

-- RETRIEVE ALL RELEVANT PRESCRPTIONS FOR THE COHORT

IF OBJECT_ID('tempdb..#medications_rx') IS NOT NULL DROP TABLE #medications_rx;
SELECT 
	 m.FK_Patient_Link_ID,
		CAST(MedicationDate AS DATE) as PrescriptionDate,
		Concept = CASE WHEN c.Concept IS NOT NULL THEN c.Concept ELSE s.Concept END
INTO #medications_rx
FROM RLS.vw_GP_Medications m
LEFT OUTER JOIN #VersionedSnomedSets_1 s ON s.FK_Reference_SnomedCT_ID = m.FK_Reference_SnomedCT_ID
LEFT OUTER JOIN #VersionedCodeSets_1 c ON c.FK_Reference_Coding_ID = m.FK_Reference_Coding_ID
WHERE m.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort)
	AND m.MedicationDate BETWEEN @StartDate AND @EndDate
	AND UPPER(SourceTable) NOT LIKE '%REPMED%'  -- exclude duplicate prescriptions 
	AND RepeatMedicationFlag = 'N' 				-- exclude duplicate prescriptions 
	AND (
		m.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets_1)
		OR
		m.FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets_1)
		);

--  FINAL TABLE: NUMBER OF EACH MEDICATION CATEGORY PRESCRIBED EACH MONTH 

select 
	FK_Patient_Link_ID,
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
