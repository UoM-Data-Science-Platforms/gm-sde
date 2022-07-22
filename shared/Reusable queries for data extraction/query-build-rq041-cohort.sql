--┌──────────────────────────────────────────────────────────────────────┐
--│ Define Cohort for RQ041: patients with biochemical evidence of CKD   │
--└──────────────────────────────────────────────────────────────────────┘

-- OBJECTIVE: To build the cohort of patients needed for RQ041. This reduces duplication of code in the template scripts.

-- COHORT: Any patient with biochemical evidence of CKD. More detail in the comments throughout this script.

-- INPUT: assumes there exists one temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: A temp table as follows:
-- #Cohort (FK_Patient_Link_ID)
-- #PatientEventData



-- LOAD CODESETS NEEDED FOR DEFINING COHORT

--> CODESET egfr:1 urinary-albumin-creatinine-ratio:1 glomerulonephritis:1 kidney-transplant:1 kidney-stones:1 vasculitis:1

---- FIND PATIENTS WITH BIOCHEMICAL EVIDENCE OF CKD

---- find all eGFR and ACR tests

IF OBJECT_ID('tempdb..#EGFR_TESTS') IS NOT NULL DROP TABLE #EGFR_TESTS;
SELECT gp.FK_Patient_Link_ID, 
	CAST(GP.EventDate AS DATE) AS EventDate, 
	SuppliedCode, 
	[value] = TRY_CONVERT(NUMERIC (18,5), [Value]),  
	[Units],
	Code = CASE WHEN SuppliedCode IN (
		SELECT [Code] FROM #AllCodes WHERE [Concept] IN ('egfr') AND [Version] = 1 ) THEN 1 ELSE 0 END
INTO #EGFR_TESTS
FROM [RLS].[vw_GP_Events] gp
WHERE 
	(gp.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'egfr' AND [Version]=1) OR
	 gp.FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'egfr' AND [Version]=1))
		AND gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
		AND (gp.EventDate) BETWEEN DATEADD(month, -26, @StartDate) and @EndDate
		AND [Value] IS NOT NULL AND [Value] <> 0 AND [Value] <> '0' -- REMOVE NULLS AND ZEROES
		AND UPPER([Value]) NOT LIKE '%[A-Z]%' -- REMOVE RECORDS WITH TEXT 

IF OBJECT_ID('tempdb..#ACR_TESTS') IS NOT NULL DROP TABLE #ACR_TESTS;
SELECT gp.FK_Patient_Link_ID, 
	CAST(GP.EventDate AS DATE) AS EventDate, 
	SuppliedCode, 
	[value] = TRY_CONVERT(NUMERIC (18,5), [Value]),  
	[Units],
	Code = CASE WHEN SuppliedCode IN (
		SELECT [Code] FROM #AllCodes WHERE [Concept] IN ('urinary-albumin-creatinine-ratio') AND [Version] = 1 ) THEN 1 ELSE 0 END
INTO #ACR_TESTS
FROM [RLS].[vw_GP_Events] gp
WHERE 
	(gp.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'urinary-albumin-creatinine-ratio' AND [Version]=1) OR
	 gp.FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'urinary-albumin-creatinine-ratio'  AND [Version]=1))
		AND gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
		AND gp.EventDate BETWEEN DATEADD(month, -26, @StartDate) and @EndDate
		AND [Value] IS NOT NULL AND TRY_CONVERT(NUMERIC (18,5), [Value]) <> 0 AND [Value] <> '0' -- REMOVE NULLS AND ZEROES
		AND UPPER([Value]) NOT LIKE '%[A-Z]%' -- REMOVE RECORDS WITH TEXT 

-- CATEGORISE EGFR TESTS INTO CKD STAGES

IF OBJECT_ID('tempdb..#egfr_ckd_stages') IS NOT NULL DROP TABLE #egfr_ckd_stages;
SELECT FK_Patient_Link_ID,
	EventDate,
	Stage = CASE WHEN Code = 1 AND [Value] >= 90   THEN 'G1' 
		WHEN Code = 1 AND [Value] BETWEEN 60 AND 89 		THEN 'G2'
		WHEN Code = 1 AND [Value] BETWEEN 45 AND 59 		THEN 'G3a'
		WHEN Code = 1 AND [Value] BETWEEN 30 AND 44 		THEN 'G3b'
		WHEN Code = 1 AND [Value] BETWEEN 15 AND 29 		THEN 'G4'
		WHEN Code = 1 AND [Value] BETWEEN  0 AND 15 		THEN 'G5'
			ELSE NULL END
INTO #egfr_ckd_stages
FROM #EGFR_TESTS

-- CATEGORISE ACR TESTS INTO CKD STAGES

IF OBJECT_ID('tempdb..#acr_ckd_stages') IS NOT NULL DROP TABLE #acr_ckd_stages;
SELECT FK_Patient_Link_ID,
	EventDate,
	Stage = CASE WHEN Code = 1 AND [Value] > 30  	THEN 'A3' 
		WHEN Code = 1 AND [Value] BETWEEN 3 AND 30 			THEN 'A2'
		WHEN Code = 1 AND [Value] BETWEEN  0 AND 3 			THEN 'A1'
			ELSE NULL END 
INTO #acr_ckd_stages
FROM #ACR_TESTS

-- FIND EGFR TESTS INDICATIVE OF CKD STAGE 3-5, WITH THE MIN AND MAX DATES FOR THESE

IF OBJECT_ID('tempdb..#egfr_dates') IS NOT NULL DROP TABLE #egfr_dates;
SELECT *, MAX(EventDate) AS MAXDATE, MIN(EventDate) AS MINDATE
INTO #egfr_dates
FROM #egfr_ckd_stages
where Stage IN ('G3Aa', 'G3b', 'G4', 'G5') -- FILTER TO STAGES 3 TO 5 ONLY
GROUP BY FK_Patient_Link_ID

-- FIND PATIENTS THAT HAD >= 2 EGFRs INDICATING STAGE 3-5 CKD, AT LEAST 3 MONTHS APART

IF OBJECT_ID('tempdb..#EGFR_cohort') IS NOT NULL DROP TABLE #EGFR_cohort;
SELECT FK_Patient_Link_ID
INTO #EGFR_cohort
FROM #egfr_dates
WHERE MAXDATE >= DATEADD(month, 3, MINDATE)
GROUP BY FK_Patient_Link_ID

-- CREATE TABLE OF PATIENTS THAT HAVE A HISTORY OF KIDNEY DAMAGE (TO BE USED AS EXTRA CRITERIA FOR FINDING CKD STAGE 1 AND 2)

IF OBJECT_ID('tempdb..#kidney_damage') IS NOT NULL DROP TABLE #kidney_damage;
SELECT DISTINCT FK_Patient_Link_ID
INTO #kidney_damage
FROM [RLS].[vw_GP_Events] gp
WHERE  gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #egfr_ckd_stages)
AND (
	gp.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('glomerulonephritis', 'kidney-transplant', 'kidney-stones', 'vasculitis') AND [Version]=1) OR
    gp.FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('glomerulonephritis', 'kidney-transplant', 'kidney-stones', 'vasculitis') AND [Version]=1)
	)
	AND EventDate <= @StartDate

-- FIND PATIENTS THAT MEET THE FOLLOWING: "ACR > 3mg/mmol lasting for at least 3 months”

-- FIND ACR TESTS THAT ARE >3mg/mmol AND SHOW MIN AND MAX DATES FOR THESE

IF OBJECT_ID('tempdb..#ACR_dates') IS NOT NULL DROP TABLE #ACR_dates;
SELECT *, MAX(EventDate) AS MAXDATE, MIN(EventDate) AS MINDATE
INTO #ACR_dates
FROM #ACR_ckd_stages
where Stage IN ('A3','A2') -- FILTER TO STAGES A3 AND A2 ONLY
GROUP BY FK_Patient_Link_ID

-- FIND PATIENTS THAT HAD >= 2 ACRs INDICATING STAGE A3 AND A2, AT LEAST 3 MONTHS APART

IF OBJECT_ID('tempdb..#ACR_cohort') IS NOT NULL DROP TABLE #ACR_cohort;
SELECT FK_Patient_Link_ID
INTO #ACR_cohort
FROM #ACR_dates
WHERE MAXDATE >= DATEADD(month, 3, MINDATE)
GROUP BY FK_Patient_Link_ID

--> EXECUTE query-patient-year-of-birth.sql

---- CREATE COHORT:
	-- 1. PATIENTS WITH EGFR TESTS INDICATIVE OF CKD STAGES 1-2, PLUS RAISED ACR OR HISTORY OF KIDNEY DAMAGE
	-- 2. PATIENTS WITH EGFR TESTS INDICATIVE OF CKD STAGES 3-5 (AT LEAST 3 MONTHS APART)
	-- 3. PATIENTS WITH ACR TESTS INDICATIVE OF CKD (A3 AND A2) (AT LEAST 3 MONTHS APART)

IF OBJECT_ID('tempdb..#Cohort') IS NOT NULL DROP TABLE #Cohort;
SELECT p.FK_Patient_Link_ID,
		p.EthnicMainGroup,
		yob.YearOfBirth,
		p.DeathDate,
		EvidenceOfCKD_egfr = CASE WHEN p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #EGFR_cohort) 			THEN 1 ELSE 0 END,-- egfr indicating stages 3-5 	
		EvidenceOfCKD_combo = CASE WHEN (p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #egfr_ckd_stages where Stage in ('G1', 'G2')) -- egfr indicating stage 1 or 2, with ACR evidence or kidney damage
				AND ((p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #acr_dates)) 
					OR p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #kidney_damage)))						THEN 1 ELSE 0 END,
		EvidenceOfCKD_acr = CASE WHEN p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #acr_ckd_stages) 		THEN 1 ELSE 0 END -- ACR evidence
INTO #Cohort
FROM #Patients p
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE 
	(YEAR(@StartDate) - YearOfBirth > 18) AND 								-- OVER 18s ONLY
		( 
	p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #EGFR_cohort ) -- egfr indicating stages 3-5
		OR (
	p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #egfr_ckd_stages where Stage in ('G1', 'G2')) -- egfr indicating stage 1 or 2, with ACR evidence or kidney damage
			AND ((p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #acr_dates)) OR p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #kidney_damage))
			) 
		OR p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #ACR_cohort) -- ACR evidence
		)

-- TABLE OF GP EVENTS FOR COHORT TO SPEED UP REUSABLE QUERIES

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
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort);


--Outputs from this reusable query:
-- #Cohort
-- #PatientEventData

---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
