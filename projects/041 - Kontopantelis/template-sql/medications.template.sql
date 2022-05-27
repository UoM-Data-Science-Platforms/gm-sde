--┌─────────────┐
--│ Medications │
--└─────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------
-- 

-- All prescriptions of nephrotoxic medications within __ of study start date (01/03/2018).

-- OUTPUT: Data with the following fields
-- 	-   PatientId (int)
--	-	MedicationCategory
--	-	PrescriptionDate (YYYY-MM-DD)

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
----------------------------------- DEFINE MAIN COHORT -- ----------------------------------------------
--------------------------------------------------------------------------------------------------------

-- LOAD CODESETS FOR CONDITIONS THAT INDICATE RISK OF CKD

--> CODESET hypertension:1 diabetes:1

-- LOAD CODESETS FOR TESTS USED TO INDICATE CKD

--> CODESET egfr:1 urinary-albumin-creatinine-ratio:1


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
	AND [Value] IS NOT NULL AND UPPER([Value]) NOT LIKE '%[A-Z]%' 

-- CREATE TABLE OF EGFR TESTS THAT MEET CKD CRITERIA (VARIOUS STAGEs)

SELECT FK_Patient_Link_ID,
	EventDate,
	egfr_evidence = CASE WHEN egfr_Code = 1 AND [Value] >= 90   THEN 'G1' 
		WHEN egfr_Code = 1 AND [Value] BETWEEN 60 AND 89 		THEN 'G2'
		WHEN egfr_Code = 1 AND [Value] BETWEEN 45 AND 59 		THEN 'G3a'
		WHEN egfr_Code = 1 AND [Value] BETWEEN 30 AND 44 		THEN 'G3b'
		WHEN egfr_Code = 1 AND [Value] BETWEEN 15 AND 29 		THEN 'G4'
		WHEN egfr_Code = 1 AND [Value] BETWEEN  0 AND 15 		THEN 'G5'
			ELSE NULL END
INTO #ckd_stages_egfr
FROM #EGFR_ACR_TESTS

-- FIND EGFR TESTS INDICATIVE OF CKD STAGE 3-5, WITH THE DATES OF THE PREVIOUS TEST

IF OBJECT_ID('tempdb..#egfr_dates') IS NOT NULL DROP TABLE #egfr_dates;
SELECT *, 
	stage_previous_egfr = LAG(egfr_evidence, 1, NULL) OVER (PARTITION BY FK_Patient_Link_ID ORDER BY EventDate),
	date_previous_egfr = LAG(EventDate, 1, NULL) OVER (PARTITION BY FK_Patient_Link_ID ORDER BY EventDate)
INTO #egfr_dates
FROM #ckd_stages_egfr
where egfr_evidence in ('G3a', 'G3b', 'G4', 'G5')
ORDER BY FK_Patient_Link_ID, EventDate

-- CREATE TABLE OF PATIENTS THAT HAD TWO EGFR TESTS INDICATIVE OF CKD STAGE 3-5, WITHIN 3 MONTHS OF EACH OTHER

IF OBJECT_ID('tempdb..#egfr_ckd_evidence') IS NOT NULL DROP TABLE #egfr_ckd_evidence;
SELECT *
INTO #egfr_ckd_evidence
FROM #egfr_dates
WHERE datediff(month, date_previous_egfr, EventDate) <=  3 --only find patients with two tests in three months

-- FIND PATIENTS THAT MEET THE FOLLOWING: "ACR > 3mg/mmol lasting for at least 3 months”

-- CREATE TABLE OF ACR TESTS

SELECT FK_Patient_Link_ID,
	EventDate, 
	acr_evidence = CASE WHEN acr_Code = 1 AND [Value] > 30  	THEN 'A3' 
		WHEN acr_Code = 1 AND [Value] BETWEEN 3 AND 30 			THEN 'A2'
		WHEN acr_Code = 1 AND [Value] BETWEEN  0 AND 3 			THEN 'A1'
			ELSE NULL END 
INTO #ckd_stages_acr
FROM #EGFR_ACR_TESTS

-- FIND TESTS THAT ARE >3mg/mmol AND SHOW DATE OF PREVIOUS TEST

IF OBJECT_ID('tempdb..#acr_dates') IS NOT NULL DROP TABLE #acr_dates;
SELECT *, 
	stage_previous_acr = LAG(acr_evidence, 1, NULL) OVER (PARTITION BY FK_Patient_Link_ID ORDER BY EventDate),
	date_previous_acr = LAG(EventDate, 1, NULL) OVER (PARTITION BY FK_Patient_Link_ID ORDER BY EventDate)
INTO #acr_dates
FROM #ckd_stages_acr
WHERE acr_evidence in ('A3','A2')
ORDER BY FK_Patient_Link_ID, EventDate

IF OBJECT_ID('tempdb..#acr_ckd_evidence') IS NOT NULL DROP TABLE #acr_ckd_evidence;
SELECT *
INTO #acr_ckd_evidence
FROM #acr_dates
WHERE datediff(month, date_previous_acr, EventDate) >=  3 --only find patients with acr stages A1/A2 lasting at least 3 months


-- CREATE TABLE OF PATIENTS AT RISK OF CKD: DIABETES OR HYPERTENSION

IF OBJECT_ID('tempdb..#ckd_risk') IS NOT NULL DROP TABLE #ckd_risk;
SELECT DISTINCT FK_Patient_Link_ID
INTO #ckd_risk
FROM [RLS].[vw_GP_Events] gp
LEFT OUTER JOIN #VersionedSnomedSets s ON s.FK_Reference_SnomedCT_ID = gp.FK_Reference_SnomedCT_ID
LEFT OUTER JOIN #VersionedCodeSets c ON c.FK_Reference_Coding_ID = gp.FK_Reference_Coding_ID
WHERE  gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND (
	gp.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('diabetes', 'hypertension') AND [Version]=1) OR
    gp.FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('diabetes', 'hypertension') AND [Version]=1)
);

-- CREATE TABLE ONLY INCLUDING THE REQUIRED COHORT, WHICH INCLUDES THOSE WITH EVIDENCE OF CKD AND THOSE AT RISK OF CKD

IF OBJECT_ID('tempdb..#Cohort') IS NOT NULL DROP TABLE #Cohort;
SELECT p.FK_Patient_Link_ID,
		p.EthnicMainGroup,
		p.DeathDate,
		EvidenceOfCKD_egfr = CASE WHEN p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #egfr_ckd_evidence) THEN 1 ELSE 0 END,
		EvidenceOfCKD_acr = CASE WHEN p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #acr_ckd_evidence) THEN 1 ELSE 0 END,
		AtRiskOfCKD = CASE WHEN p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #ckd_risk) THEN 1 ELSE 0 END
INTO #Cohort
FROM #Patients p
WHERE p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #egfr_ckd_evidence) 
	OR p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #acr_ckd_evidence) 
	OR p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #ckd_risk) 



-- load codesets needed for retrieving medication prescriptions (only those that weren't loaded at start of script)

--> CODESET aminoglycosides:1 ace-inhibitor:1 bisphosphonates:1 calcineurin-inhibitors:1 diuretic:1 lithium:1 mesalazine:1 nsaids:1
--> CODESET sglt2-inhibitors:1 metformin:1 sulphonylureas:1 glp1-receptor-agonists:1 statins:1 antipsychotics:1
--> CODESET contraceptives-combined-hormonal:1 contraceptives-devices:1 contraceptives-emergency-pills:1 contraceptives-progesterone-only:1


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
		Concept = CASE WHEN s.Concept IS NOT NULL THEN s.Concept ELSE c.Concept END
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

IF OBJECT_ID('tempdb..#meds_wide') IS NOT NULL DROP TABLE #meds_wide;
select 
	FK_Patient_Link_ID,
	PrescriptionDate,
	[ace-inhibitor] = case when Concept = 'ace-inhibitor' then 1 else 0 end,
	aminoglycoside = case when Concept = 'aminoglycosides' then 1 else 0 end,
	bisphosphonate = case when Concept = 'bisphosphonates' then 1 else 0 end,
	[calcineurin-inhibitor] = case when Concept = 'calcineurin-inhibitor' then 1 else 0 end,
	diuretic = case when Concept = 'diuretic' then 1 else 0 end,
	lithium = case when Concept = 'lithium' then 1 else 0 end,
	mesalazine = case when Concept = 'mesalazine' then 1 else 0 end,
	nsaid = case when Concept = 'nsaids' then 1 else 0 end, 
	[sglt2-inhibitor] = case when Concept = 'sglt2-inhibitors' then 1 else 0 end,
	metformin = case when Concept = 'metformin' then 1 else 0 end,
	sulphonylurea = case when Concept = 'sulphonylureas' then 1 else 0 end,
	[glp1-receptor-agonist] = case when Concept = 'glp1-receptor-agonists' then 1 else 0 end,
	statin = case when Concept = 'statins' then 1 else 0 end,
	antipsychotic = case when Concept = 'antipsychotics' then 1 else 0 end,
	contraceptive = case when Concept in ('contraceptives-combined-hormonal','contraceptives-devices','contraceptives-emergency-pills','contraceptives-progesterone-only') then 1 else 0 end
into #meds_wide
from #medications_rx


select 
	FK_Patient_Link_ID, 
	YEAR(PrescriptionDate) as [Year], 
	Month(PrescriptionDate) as [Month], 
	[ace-inhibitor-or-ARB] = sum([ace-inhibitor]),
	aminoglycoside = sum(aminoglycoside),
	bisphosphonate = sum(bisphosphonate),
	[calcineurin-inhibitor] = sum([calcineurin-inhibitor]),
	diuretic = sum(diuretic),
	lithium = sum(lithium),
	mesalazine = sum(mesalazine),
	nsaid = sum(nsaid), 
	[sglt2-inhibitor] = sum([sglt2-inhibitor]),
	metformin = sum(metformin),
	sulphonylurea = sum(sulphonylurea),
	[glp1-receptor-agonist] = sum([glp1-receptor-agonist]),
	statin = sum(statin),
	antipsychotic = sum(antipsychotic),
	contraceptive = sum(contraceptive)
from #meds_wide
group by FK_Patient_Link_ID, YEAR(PrescriptionDate), Month(PrescriptionDate)
order by FK_Patient_Link_ID, YEAR(PrescriptionDate), Month(PrescriptionDate)



