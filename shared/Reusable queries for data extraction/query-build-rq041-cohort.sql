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

IF OBJECT_ID('tempdb..#PatientsToInclude') IS NOT NULL DROP TABLE #PatientsToInclude;
SELECT FK_Patient_Link_ID INTO #PatientsToInclude
FROM RLS.vw_Patient_GP_History
GROUP BY FK_Patient_Link_ID
HAVING MIN(StartDate) < '2022-06-01';

-- LOAD CODESETS NEEDED FOR DEFINING COHORT

--> CODESET egfr:1 urinary-albumin-creatinine-ratio:1 glomerulonephritis:1 kidney-transplant:1 kidney-stones:1 vasculitis:1

---- FIND PATIENTS WITH BIOCHEMICAL EVIDENCE OF CKD

---- find all eGFR and ACR tests

IF OBJECT_ID('tempdb..#EGFR_TESTS') IS NOT NULL DROP TABLE #EGFR_TESTS;
SELECT gp.FK_Patient_Link_ID, 
	CAST(GP.EventDate AS DATE) AS EventDate, 
	[value] = TRY_CONVERT(NUMERIC (18,5), [Value])
INTO #EGFR_TESTS
FROM [RLS].[vw_GP_Events] gp
WHERE 
	(gp.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'egfr' AND [Version]=1) OR
	 gp.FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'egfr' AND [Version]=1))
		AND gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
		AND (gp.EventDate) BETWEEN DATEADD(month, -26, @StartDate) and @EndDate
		AND [Value] IS NOT NULL AND TRY_CONVERT(NUMERIC (18,5), [Value]) <> 0 AND [Value] <> '0' -- REMOVE NULLS AND ZEROES
		AND UPPER([Value]) NOT LIKE '%[A-Z]%' -- REMOVE RECORDS WITH TEXT 

IF OBJECT_ID('tempdb..#ACR_TESTS') IS NOT NULL DROP TABLE #ACR_TESTS;
SELECT gp.FK_Patient_Link_ID, 
	CAST(GP.EventDate AS DATE) AS EventDate, 
	[value] = TRY_CONVERT(NUMERIC (18,5), [Value])
INTO #ACR_TESTS
FROM [RLS].[vw_GP_Events] gp
WHERE 
	(gp.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'urinary-albumin-creatinine-ratio' AND [Version]=1) OR
	 gp.FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'urinary-albumin-creatinine-ratio'  AND [Version]=1))
		AND gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
		AND gp.EventDate BETWEEN DATEADD(month, -26, @StartDate) and @EndDate
		AND [Value] IS NOT NULL AND TRY_CONVERT(NUMERIC (18,5), [Value]) <> 0 AND [Value] <> '0' -- REMOVE NULLS AND ZEROES
		AND UPPER([Value]) NOT LIKE '%[A-Z]%' -- REMOVE RECORDS WITH TEXT 

-- "eGFR < 60 Ml/Min lasting for at least 3 months"

-- For each low egfr we calculate the first date more than 3 months in the future when they also have a low egfr.
IF OBJECT_ID('tempdb..#E1TEMP') IS NOT NULL DROP TABLE #E1TEMP
SELECT E1.FK_Patient_Link_ID, E1.EventDate, MIN(E2.EventDate) AS FirstLowDatePost3Months 
INTO #E1Temp 
FROM #EGFR_TESTS E1
  INNER JOIN #EGFR_TESTS E2 ON
    E1.FK_Patient_Link_ID = E2.FK_Patient_Link_ID AND
    E2.EventDate >= DATEADD(month, 3, E1.EventDate)
WHERE TRY_CONVERT(NUMERIC, E1.Value) < 60 AND TRY_CONVERT(NUMERIC, E2.Value)  < 60
GROUP BY E1.FK_Patient_Link_ID, E1.EventDate;

-- For each low egfr we find the first date after where their egfr wasn't low
IF OBJECT_ID('tempdb..#E2TEMP') IS NOT NULL DROP TABLE #E2TEMP
SELECT E1.FK_Patient_Link_ID, E1.EventDate, MIN(E2.EventDate) AS FirstOkDatePostValue 
INTO #E2Temp 
FROM #EGFR_TESTS E1
  INNER JOIN #EGFR_TESTS E2 ON
    E1.FK_Patient_Link_ID = E2.FK_Patient_Link_ID AND
    E1.EventDate < E2.EventDate AND
    E2.EventDate < DATEADD(month, 3, E1.EventDate)
WHERE TRY_CONVERT(NUMERIC, E1.Value) < 60 AND TRY_CONVERT(NUMERIC, E2.Value) >= 60
GROUP BY E1.FK_Patient_Link_ID, E1.EventDate;

-- We want everyone in the first table UNLESS they have a healthy egfr in between
IF OBJECT_ID('tempdb..#EGFR_cohort') IS NOT NULL DROP TABLE #EGFR_cohort
SELECT DISTINCT E1.FK_Patient_Link_ID
INTO #EGFR_cohort
FROM #E1Temp E1
LEFT OUTER JOIN #E2Temp E2 ON E1.FK_Patient_Link_ID = E2.FK_Patient_Link_ID AND E1.EventDate = E2.EventDate
WHERE FirstOkDatePostValue IS NULL OR FirstOkDatePostValue > FirstLowDatePost3Months;

--------------- Same as above but for: "ACR > 3mg/mmol lasting for at least 3 months” ---------------------

-- For each high ACR we calculate the first date more than 3 months in the future when they also have a high ACR.

IF OBJECT_ID('tempdb..#A1TEMP') IS NOT NULL DROP TABLE #A1TEMP
SELECT A1.FK_Patient_Link_ID, A1.EventDate, MIN(A2.EventDate) AS FirstLowDatePost3Months 
INTO #A1Temp 
FROM #ACR_TESTS A1
  INNER JOIN #ACR_TESTS A2 ON
    A1.FK_Patient_Link_ID = A2.FK_Patient_Link_ID AND
    A2.EventDate >= DATEADD(month, 3, A1.EventDate)
WHERE TRY_CONVERT(NUMERIC, A1.Value) >= 3 AND TRY_CONVERT(NUMERIC, A2.Value)  >= 3
GROUP BY A1.FK_Patient_Link_ID, A1.EventDate;

-- For each high ACR we find the first date after where their ACR wasn't high
IF OBJECT_ID('tempdb..#A2TEMP') IS NOT NULL DROP TABLE #A2TEMP
SELECT A1.FK_Patient_Link_ID, A1.EventDate, MIN(A2.EventDate) AS FirstOkDatePostValue 
INTO #A2Temp 
FROM #ACR_TESTS A1
  INNER JOIN #ACR_TESTS A2 ON
    A1.FK_Patient_Link_ID = A2.FK_Patient_Link_ID AND
    A1.EventDate < A2.EventDate AND
    A2.EventDate < DATEADD(month, 3, A1.EventDate)
WHERE TRY_CONVERT(NUMERIC, A1.Value) >= 3 AND TRY_CONVERT(NUMERIC, A2.Value) < 3
GROUP BY A1.FK_Patient_Link_ID, A1.EventDate;

-- We want everyone in the first table UNLESS they have a healthy ACR in between
IF OBJECT_ID('tempdb..#ACR_cohort') IS NOT NULL DROP TABLE #ACR_cohort
SELECT DISTINCT A1.FK_Patient_Link_ID
INTO #ACR_cohort
FROM #A1Temp A1
LEFT OUTER JOIN #A2Temp A2 ON A1.FK_Patient_Link_ID = A2.FK_Patient_Link_ID AND A1.EventDate = A2.EventDate
WHERE FirstOkDatePostValue IS NULL OR FirstOkDatePostValue > FirstLowDatePost3Months;


-- CREATE TABLE OF PATIENTS THAT HAVE A HISTORY OF KIDNEY DAMAGE (TO BE USED AS EXTRA CRITERIA FOR EGFRs INDICATING CKD STAGE 1 AND 2)

IF OBJECT_ID('tempdb..#kidney_damage') IS NOT NULL DROP TABLE #kidney_damage;
SELECT DISTINCT FK_Patient_Link_ID
INTO #kidney_damage
FROM [RLS].[vw_GP_Events] gp
WHERE (
	gp.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('glomerulonephritis', 'kidney-transplant', 'kidney-stones', 'vasculitis') AND [Version]=1) OR
    gp.FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('glomerulonephritis', 'kidney-transplant', 'kidney-stones', 'vasculitis') AND [Version]=1)
	)
	AND EventDate <= @StartDate

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
		EvidenceOfCKD_combo = CASE WHEN (p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #EGFR_TESTS where [Value] >= 60) -- egfr indicating stage 1 or 2, with ACR evidence or kidney damage
				AND ((p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #ACR_cohort)) 
					OR p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #kidney_damage)))						THEN 1 ELSE 0 END,
		EvidenceOfCKD_acr = CASE WHEN p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #ACR_cohort) 		THEN 1 ELSE 0 END -- ACR evidence
INTO #Cohort
FROM #Patients p
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE 
	(YEAR(@StartDate) - YearOfBirth > 18) AND 								-- OVER 18s ONLY
		( 
	p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #EGFR_cohort ) -- egfr indicating stages 3-5
		OR (
	p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #EGFR_TESTS where [Value] >= 60) -- egfr indicating stage 1 or 2, with ACR evidence or kidney damage
			AND ((p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #ACR_cohort)) OR p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #kidney_damage))
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
