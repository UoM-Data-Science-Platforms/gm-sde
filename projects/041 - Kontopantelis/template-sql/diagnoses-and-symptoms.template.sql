--┌─────────────────────────────────────┐
--│ Diagnoses and symptoms for cohort   │
--└─────────────────────────────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------

------------------------------------------------------

-- PatientID


-- Set the start date
DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2018-03-01';
SET @EndDate = '2022-03-01';

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


--------------------------------------------------------------------------------------------------------
----------------------------------- DEFINE MAIN COHORT -- ----------------------------------------------
--------------------------------------------------------------------------------------------------------

-- LOAD CODESETS FOR CONDITIONS THAT INDICATE RISK OF CKD

--> CODESET hypertension:1 diabetes:1

-- LOAD CODESETS FOR TESTS USED TO INDICATE CKD

--> CODESET egfr:1 urinary-albumin-creatinine-ratio:1


---- FIND PATIENTS WITH BIOCHEMICAL EVIDENCE OF CKD

---- find all eGFR and ACR tests

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
WHERE SuppliedCode IN (
	SELECT [Code] 
	FROM #AllCodes 
	WHERE [Concept] IN ('egfr', 'urinary-albumin-creatinine-ratio') 
		AND [Version] = 1 
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

-- IF OBJECT_ID('tempdb..#ckd_risk') IS NOT NULL DROP TABLE #ckd_risk;
-- SELECT DISTINCT FK_Patient_Link_ID
-- INTO #ckd_risk
-- FROM [RLS].[vw_GP_Events] gp
-- LEFT OUTER JOIN #VersionedSnomedSets s ON s.FK_Reference_SnomedCT_ID = gp.FK_Reference_SnomedCT_ID
-- LEFT OUTER JOIN #VersionedCodeSets c ON c.FK_Reference_Coding_ID = gp.FK_Reference_Coding_ID
-- WHERE  gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
-- AND (
-- 	gp.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('diabetes', 'hypertension') AND [Version]=1) OR
--     gp.FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('diabetes', 'hypertension') AND [Version]=1)
-- );

-- CREATE TABLE ONLY INCLUDING THE REQUIRED COHORT, WHICH INCLUDES THOSE WITH EVIDENCE OF CKD AND THOSE AT RISK OF CKD

IF OBJECT_ID('tempdb..#Cohort') IS NOT NULL DROP TABLE #Cohort;
SELECT p.FK_Patient_Link_ID,
		p.EthnicMainGroup,
		p.DeathDate,
		EvidenceOfCKD_egfr = CASE WHEN p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #egfr_ckd_evidence) THEN 1 ELSE 0 END,
		EvidenceOfCKD_acr = CASE WHEN p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #acr_ckd_evidence) THEN 1 ELSE 0 END
		--,AtRiskOfCKD = CASE WHEN p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #ckd_risk) THEN 1 ELSE 0 END
INTO #Cohort
FROM #Patients p
WHERE p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #egfr_ckd_evidence) 
	OR p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #acr_ckd_evidence) 
	--OR p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #ckd_risk) 



-----------------------------------------------------------------------------------------------------------------------------------------
------------------- NOW COHORT HAS BEEN DEFINED, LOAD CODE SETS FOR ALL CONDITIONS/SYMPTOMS OF INTEREST ---------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------


--> CODESET sle:1 vasculitis:1 gout:1 haematuria:1 non-alc-fatty-liver-disease:1 
--> CODESET renal-replacement-therapy:1 kidney-transplant:1 acute-kidney-injury:1 glomerulonephritis:1 polycystic-kidney-disease:1 family-history-kidney-disease:1 end-stage-renal-disease:1
--> CODESET long-covid:1 menopause:1 diabetes:1 myeloma:1 obese:1 haematuria:1 osteoporosis:1
--> CODESET coronary-heart-disease:1 heart-failure:1 stroke:1 tia:1 peripheral-arterial-disease:1 hypertension:1 
--> CODESET depression:1 schizophrenia-psychosis:1 bipolar:1 eating-disorders:1 selfharm-episodes:1
--> CODESET ckd-stage-1:1 ckd-stage-2:1 ckd-stage-3:1 ckd-stage-4:1 ckd-stage-5:1

--CREATE TABLE OF ALL CODE SETS NEEDED FOR THIS FILE (IGNORING OBSERVATION CODE SETS USED TO DEFINE THE COHORT)

-- IF OBJECT_ID('tempdb..#AllCodeSets') IS NOT NULL DROP TABLE #AllCodeSets;
-- CREATE TABLE #AllCodeSets (CodeSet varchar(255))

-- INSERT INTO #AllCodeSets (CodeSet) 
-- VALUES ('sle'),('polycystic-kidney-disease'),('gout'),('haematuria'),('glomerulonephritis'),('non-alc-fatty-liver-disease'),
-- ('renal-replacement-therapy'),('kidney-transplant'),('coronary-heart-disease'),('heart-failure'),('stroke'),('tia'),('peripheral-arterial-disease'),
-- ('hypertension'),('diabetes'),('myeloma'),('obese'),('haematuria'),('osteoporosis'), ('depression'),('schizophrenia-psychosis'),('bipolar'),('eating-disorders'),('selfharm-episodes'),
-- ('ckd-stage-1'),('ckd-stage-2'),('ckd-stage-3'),('ckd-stage-4'),('ckd-stage-5')


-- CREATE TABLES OF DISTINCT CODES AND CONCEPTS - TO REMOVE DUPLICATES IN FINAL TABLE

IF OBJECT_ID('tempdb..#VersionedCodeSetsUnique') IS NOT NULL DROP TABLE #VersionedCodeSetsUnique;
SELECT DISTINCT V.Concept, FK_Reference_Coding_ID, V.[Version]
INTO #VersionedCodeSetsUnique
FROM #VersionedCodeSets V

IF OBJECT_ID('tempdb..#VersionedSnomedSetsUnique') IS NOT NULL DROP TABLE #VersionedSnomedSetsUnique;
SELECT DISTINCT V.Concept, FK_Reference_SnomedCT_ID, V.[Version]
INTO #VersionedSnomedSetsUnique
FROM #VersionedSnomedSets V


---- CREATE OUTPUT TABLE OF DIAGNOSES AND SYMPTOMS, FOR THE COHORT OF INTEREST, AND CODING DATES 

IF OBJECT_ID('tempdb..#DiagnosesAndSymptoms') IS NOT NULL DROP TABLE #DiagnosesAndSymptoms;
SELECT FK_Patient_Link_ID, EventDate, SuppliedCode,case when s.Concept is null then c.Concept else s.Concept end as Concept
INTO #DiagnosesAndSymptoms
FROM RLS.vw_GP_Events gp
LEFT OUTER JOIN #VersionedSnomedSetsUnique s ON s.FK_Reference_SnomedCT_ID = gp.FK_Reference_SnomedCT_ID
LEFT OUTER JOIN #VersionedCodeSetsUnique c ON c.FK_Reference_Coding_ID = gp.FK_Reference_Coding_ID
WHERE gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND gp.EventDate BETWEEN @StartDate AND @EndDate
AND (
	(gp.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSetsUnique WHERE (Concept NOT IN ('egfr','urinary-albumin-creatinine-ratio')))) 
	OR
    (gp.FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSetsUnique WHERE (Concept NOT IN ('egfr','urinary-albumin-creatinine-ratio'))))
);

-- FIND ALL CODES WITH DATES
-- USE DISTINCT TO IGNORE MULTIPLE IDENTICAL CODES ON THE SAME DAY

SELECT DISTINCT *
FROM #DiagnosesAndSymptoms 
ORDER BY FK_Patient_Link_ID, EventDate, SuppliedCode, Concept
