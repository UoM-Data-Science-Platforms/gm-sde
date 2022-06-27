--┌─────────────┐
--│ Medications │
--└─────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------
-- 

-- All prescriptions of the following medications during the study period:
	-- aminoglycosides
	-- [ace-inhibitor-or-ARB],
	-- bisphosphonate,
	-- [calcineurin-inhibitor],
	-- diuretic,
	-- lithium ,
	-- mesalazine ,
	-- nsaid, 
	-- [sglt2-inhibitor] ,
	-- metformin,
	-- sulphonylurea,
	-- [glp1-receptor-agonist],
	-- statin,
	-- antipsychotic,
	-- [oestrogens-and-hrt]
	-- contraceptive

-- OUTPUT: Data with the following fields
-- 	-   PatientId (int)
--  -   Year
--  -   Month
--	-	MedicationCategory - number of prescriptions for given medication category

--Just want the output, not the messages
SET NOCOUNT ON;

DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2018-03-01';
SET @EndDate = '2022-03-01';


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



--------------------------------------------------------------------------------------------------------
----------------------------------- DEFINE MAIN COHORT -----------------------------------------------
--------------------------------------------------------------------------------------------------------
-- COHORT WILL BE ANY PATIENT WITH BIOCHEMICAL EVIDENCE OF CKD


-- LOAD CODESETS NEEDED FOR DEFINING COHORT

--> CODESET hypertension:1 diabetes:1
--> CODESET egfr:1 urinary-albumin-creatinine-ratio:1 glomerulonephritis:1 kidney-transplant:1 kidney-stones:1 vasculitis:1


---- FIND PATIENTS WITH BIOCHEMICAL EVIDENCE OF CKD

---- find all eGFR and ACR tests

IF OBJECT_ID('tempdb..#EGFR_ACR_TESTS') IS NOT NULL DROP TABLE #EGFR_ACR_TESTS;
SELECT gp.FK_Patient_Link_ID, 
	CAST(GP.EventDate AS DATE) AS EventDate, 
	SuppliedCode, 
	[value] = TRY_CONVERT(NUMERIC (18,5), [Value]),  
	[Units],
	egfr_Code = CASE WHEN SuppliedCode IN (
		SELECT [Code] FROM #AllCodes WHERE [Concept] IN ('egfr') AND [Version] = 1 ) THEN 1 ELSE 0 END,
	acr_Code = CASE WHEN SuppliedCode IN (
		SELECT [Code] FROM #AllCodes WHERE [Concept] IN ('urinary-albumin-creatinine-ratio') AND [Version] = 1 ) THEN 1 ELSE 0 END
INTO #EGFR_ACR_TESTS
FROM [RLS].[vw_GP_Events] gp
WHERE (
		gp.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('egfr', 'urinary-albumin-creatinine-ratio')  AND [Version]=1) OR
		gp.FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('egfr', 'urinary-albumin-creatinine-ratio')  AND [Version]=1)
	  )
	AND gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
	AND (gp.EventDate) BETWEEN '2016-01-01' and @EndDate
	AND [Value] IS NOT NULL AND UPPER([Value]) NOT LIKE '%[A-Z]%' -- REMOVE RECORDS WITH NO VALUE OR TEXT 

-- CATEGORISE EGFR AND ACR TESTS INTO CKD STAGES

IF OBJECT_ID('tempdb..#ckd_stages') IS NOT NULL DROP TABLE #ckd_stages;
SELECT FK_Patient_Link_ID,
	EventDate,
	egfr_evidence = CASE WHEN egfr_Code = 1 AND [Value] >= 90   THEN 'G1' 
		WHEN egfr_Code = 1 AND [Value] BETWEEN 60 AND 89 		THEN 'G2'
		WHEN egfr_Code = 1 AND [Value] BETWEEN 45 AND 59 		THEN 'G3a'
		WHEN egfr_Code = 1 AND [Value] BETWEEN 30 AND 44 		THEN 'G3b'
		WHEN egfr_Code = 1 AND [Value] BETWEEN 15 AND 29 		THEN 'G4'
		WHEN egfr_Code = 1 AND [Value] BETWEEN  0 AND 15 		THEN 'G5'
			ELSE NULL END,
	acr_evidence = CASE WHEN acr_Code = 1 AND [Value] > 30  	THEN 'A3' 
		WHEN acr_Code = 1 AND [Value] BETWEEN 3 AND 30 			THEN 'A2'
		WHEN acr_Code = 1 AND [Value] BETWEEN  0 AND 3 			THEN 'A1'
			ELSE NULL END 
INTO #ckd_stages
FROM #EGFR_ACR_TESTS

-- FIND EGFR TESTS INDICATIVE OF CKD STAGE 3-5, WITH THE DATES OF THE PREVIOUS TEST

IF OBJECT_ID('tempdb..#egfr_dates') IS NOT NULL DROP TABLE #egfr_dates;
SELECT *, 
	stage_previous_egfr = LAG(egfr_evidence, 1, NULL) OVER (PARTITION BY FK_Patient_Link_ID ORDER BY EventDate),
	date_previous_egfr = LAG(EventDate, 1, NULL) OVER (PARTITION BY FK_Patient_Link_ID ORDER BY EventDate)
INTO #egfr_dates
FROM #ckd_stages
ORDER BY FK_Patient_Link_ID, EventDate

-- CREATE TABLE OF PATIENTS THAT HAD TWO EGFR TESTS INDICATIVE OF CKD STAGE 3-5, WITHIN 3 MONTHS OF EACH OTHER

IF OBJECT_ID('tempdb..#egfr_ckd_evidence') IS NOT NULL DROP TABLE #egfr_ckd_evidence;
SELECT *
INTO #egfr_ckd_evidence
FROM #egfr_dates
WHERE datediff(month, date_previous_egfr, EventDate) <=  3 --only find patients with two tests in three months

-- CREATE TABLE OF PATIENTS THAT HAVE A HISTORY OF KIDNEY DAMAGE (TO BE USED AS EXTRA CRITERIA FOR FINDING CKD STAGE 1 AND 2)

IF OBJECT_ID('tempdb..#kidney_damage') IS NOT NULL DROP TABLE #kidney_damage;
SELECT DISTINCT FK_Patient_Link_ID
INTO #kidney_damage
FROM [RLS].[vw_GP_Events] gp
WHERE  gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #egfr_ckd_evidence)
AND (
	gp.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('glomerulonephritis', 'kidney-transplant', 'kidney-stones', 'vasculitis') AND [Version]=1) OR
    gp.FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('glomerulonephritis', 'kidney-transplant', 'kidney-stones', 'vasculitis') AND [Version]=1)
	)
	AND EventDate <= @StartDate


-- FIND PATIENTS THAT MEET THE FOLLOWING: "ACR > 3mg/mmol lasting for at least 3 months”

-- FIND ACR TESTS THAT ARE >3mg/mmol AND SHOW DATE OF PREVIOUS TEST

IF OBJECT_ID('tempdb..#acr_dates') IS NOT NULL DROP TABLE #acr_dates;
SELECT *, 
	stage_previous_acr = LAG(acr_evidence, 1, NULL) OVER (PARTITION BY FK_Patient_Link_ID ORDER BY EventDate),
	date_previous_acr = LAG(EventDate, 1, NULL) OVER (PARTITION BY FK_Patient_Link_ID ORDER BY EventDate)
INTO #acr_dates
FROM #ckd_stages
WHERE acr_evidence in ('A3','A2')
ORDER BY FK_Patient_Link_ID, EventDate

IF OBJECT_ID('tempdb..#acr_ckd_evidence') IS NOT NULL DROP TABLE #acr_ckd_evidence;
SELECT *
INTO #acr_ckd_evidence
FROM #acr_dates
WHERE datediff(month, date_previous_acr, EventDate) >=  3 --only find patients with acr stages A1/A2 lasting at least 3 months

--> EXECUTE query-patient-year-of-birth.sql

---- CREATE COHORT:
	-- 1. PATIENTS WITH EGFR TESTS INDICATIVE OF CKD STAGES 1-2, PLUS RAISED ACR OR HISTORY OF KIDNEY DAMAGE
	-- 2. PATIENTS WITH EGFR TESTS INDICATIVE OF CKD STAGES 3-5
	-- 3. PATIENTS WITH ACR TESTS INDICATIVE OF CKD (A3 AND A2)

IF OBJECT_ID('tempdb..#Cohort') IS NOT NULL DROP TABLE #Cohort;
SELECT p.FK_Patient_Link_ID,
		p.EthnicMainGroup,
		p.DeathDate,
		EvidenceOfCKD_egfr = CASE 
		WHEN p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #egfr_ckd_evidence where egfr_evidence in ('G3a', 'G3b', 'G4', 'G5')) -- egfr indicating stages 3-5
			OR (p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #egfr_ckd_evidence where egfr_evidence in ('G1', 'G2')) 
				AND ((p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #acr_dates)) 
					OR p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #kidney_damage))) 											THEN 1 ELSE 0 END,
		EvidenceOfCKD_acr = CASE WHEN p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #acr_ckd_evidence) 							THEN 1 ELSE 0 END
INTO #Cohort
FROM #Patients p
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE (YEAR(@StartDate) - YearOfBirth > 18) AND ( -- OVER 18s ONLY
 	p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #egfr_ckd_evidence where egfr_evidence in ('G3a', 'G3b', 'G4', 'G5')) -- egfr indicating stages 3-5
		OR (
		p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #egfr_ckd_evidence where egfr_evidence in ('G1', 'G2')) 
			AND ((p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #acr_dates)) OR p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #kidney_damage))
			) -- egfr stages 1-2 and (ACR evidence or kidney damage) 
		OR p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #acr_ckd_evidence) -- ACR evidence
		)
-- TABLE OF GP EVENTS FOR COHORT TO SPEED UP REUSABLE QUERIES

IF OBJECT_ID('tempdb..#PatientEventData') IS NOT NULL DROP TABLE #PatientEventData;
SELECT 
  FK_Patient_Link_ID,
  CAST(EventDate AS DATE) AS EventDate,
  SuppliedCode,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID,
  [Value]
INTO #PatientEventData
FROM [RLS].vw_GP_Events
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort);

---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------


-- load codesets needed for retrieving medication prescriptions

----- UNUSED CURRENTLY
-- CODESET aminoglycosides:1 ace-inhibitor:1 bisphosphonates:1 calcineurin-inhibitors:1 diuretic:1 lithium:1 mesalazine:1 nsaids:1
-- CODESET sglt2-inhibitors:1 metformin:1 sulphonylureas:1 glp1-receptor-agonists:1 statins:1 antipsychotics:1 oestrogens-and-hrt:1 hormone-replacement-therapy:1
-- CODESET contraceptives-combined-hormonal:1 contraceptives-devices:1 contraceptives-emergency-pills:1 contraceptives-progesterone-only:1

--> CODESET statins:1 ace-inhibitor:1 aspirin:1 clopidogrel:1 sglt2-inhibitors:1 oestrogens-and-hrt:1 nsaids:1


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
		Concept = --'oestrgogens-and-hrt'
		CASE WHEN s.Concept IS NOT NULL THEN s.Concept ELSE c.Concept END
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

IF OBJECT_ID('tempdb..#meds_wide') IS NOT NULL DROP TABLE #meds_wide;
select 
	FK_Patient_Link_ID,
	YEAR(PrescriptionDate) as [Year], 
	Month(PrescriptionDate) as [Month], 
	statin = ISNULL(SUM(CASE WHEN Concept = 'statins' then 1 else 0 end),0),
	[ace-inhibitor-or-arb] = ISNULL(SUM(CASE WHEN Concept = 'ace-inhibitor' then 1 else 0 end),0),
	aspirin = ISNULL(SUM(CASE WHEN Concept = 'aspirin' then 1 else 0 end),0),
	clopidogrel = ISNULL(SUM(CASE WHEN Concept = 'clopidogrel' then 1 else 0 end),0),
	[sglt2-inhibitor] = ISNULL(SUM(CASE WHEN Concept = 'sglt2-inhibitors' then 1 else 0 end),0),
    nsaid = ISNULL(SUM(CASE WHEN Concept = 'nsaids' then 1 else 0 end),0), 
	[hormone-replacement-therapy] = ISNULL(SUM(CASE WHEN Concept = 'hormone-replacement-therapy' then 1 else 0 end),0)
	-- aminoglycoside = ISNULL(SUM(CASE WHEN Concept = 'aminoglycosides' then 1 else 0 end),0),
	-- bisphosphonate = ISNULL(SUM(CASE WHEN Concept = 'bisphosphonates' then 1 else 0 end),0),
	-- [calcineurin-inhibitor] = ISNULL(SUM(CASE WHEN Concept = 'calcineurin-inhibitor' then 1 else 0 end),0),
	-- diuretic = ISNULL(SUM(CASE WHEN Concept = 'diuretic' then 1 else 0 end),0),
	-- lithium = ISNULL(SUM(CASE WHEN Concept = 'lithium' then 1 else 0 end),0),
	-- mesalazine = ISNULL(SUM(CASE WHEN Concept = 'mesalazine' then 1 else 0 end),0),
	-- metformin = ISNULL(SUM(CASE WHEN Concept = 'metformin' then 1 else 0 end),0),
	-- sulphonylurea = ISNULL(SUM(CASE WHEN Concept = 'sulphonylureas' then 1 else 0 end),0),
	-- [glp1-receptor-agonist] = ISNULL(SUM(CASE WHEN Concept = 'glp1-receptor-agonists' then 1 else 0 end),0),
	-- antipsychotic = ISNULL(SUM(CASE WHEN Concept = 'antipsychotics' then 1 else 0 end),0),
	-- contraceptive = ISNULL(SUM(CASE WHEN Concept in ('contraceptives-combined-hormonal','contraceptives-devices','contraceptives-emergency-pills','contraceptives-progesterone-only') then 1 else 0 end),0)
from #medications_rx
group by FK_Patient_Link_ID, YEAR(PrescriptionDate), Month(PrescriptionDate)
order by FK_Patient_Link_ID, YEAR(PrescriptionDate), Month(PrescriptionDate)
