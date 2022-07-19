--┌──────────────┐
--│ Observations │
--└──────────────┘

-------- RESEARCH DATA ENGINEER CHECK ---------


-- OUTPUT: Data with the following fields
-- 	-   PatientId (int)
--	-	ObservationName
--	-	ObservationDateTime (YYYY-MM-DD 00:00:00)
--  -   TestResult 
--  -   TestUnit

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2018-03-01';
DECLARE @EndDate datetime;
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
----------------------------------- DEFINE MAIN COHORT -----------------------------------------------
--------------------------------------------------------------------------------------------------------
-- COHORT WILL BE ANY PATIENT WITH BIOCHEMICAL EVIDENCE OF CKD


-- LOAD CODESETS NEEDED FOR DEFINING COHORT

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
WHERE datediff(month, date_previous_acr, EventDate) >=  3 --only find patients with acr stages A2/A3 lasting at least 3 months

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
  [Value],
  [Units]
INTO #PatientEventData
FROM [RLS].vw_GP_Events
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort);

---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------------
---------------------------------------- OBSERVATIONS/MEASUREMENTS --------------------------------------
---------------------------------------------------------------------------------------------------------

-- LOAD CODESETS FOR OBSERVATIONS WITH A VALUE (EXCEPT THOSE ALREADY LOADED AT START OF SCRIPT)

--> CODESET hba1c:2 creatinine:1 triglycerides:1 urea:1 vitamin-d:1 calcium:1 bicarbonate:1 ferritin:1 b12:1 folate:1 haemoglobin:1 
--> CODESET systolic-blood-pressure:1 diastolic-blood-pressure:1 urine-protein-creatinine-ratio:1
--> CODESET alanine-aminotransferase:1 albumin:1 alkaline-phosphatase:1 total-bilirubin:1 gamma-glutamyl-transferase:1
--> CODESET cholesterol:2 ldl-cholesterol:1 hdl-cholesterol:1 urine-blood:1  

-- GET VALUES FOR ALL OBSERVATIONS OF INTEREST

IF OBJECT_ID('tempdb..#observations') IS NOT NULL DROP TABLE #observations;
SELECT 
	FK_Patient_Link_ID,
	CAST(EventDate AS DATE) AS EventDate,
	Concept = CASE WHEN sn.Concept IS NOT NULL THEN sn.Concept ELSE co.Concept END,
	[Version] =  CASE WHEN sn.[Version] IS NOT NULL THEN sn.[Version] ELSE co.[Version] END,
	[Value],
	[Units]
INTO #observations
FROM #PatientEventData gp
LEFT JOIN #VersionedSnomedSets sn ON sn.FK_Reference_SnomedCT_ID = gp.FK_Reference_SnomedCT_ID
LEFT JOIN #VersionedCodeSets co ON co.FK_Reference_Coding_ID = gp.FK_Reference_Coding_ID
WHERE
	(gp.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept NOT IN ('glomerulonephritis', 'kidney-transplant', 'kidney-stones', 'vasculitis')) ) OR
     gp.FK_Reference_Coding_ID   IN (SELECT FK_Reference_Coding_ID   FROM #VersionedCodeSets WHERE (Concept NOT IN ('glomerulonephritis', 'kidney-transplant', 'kidney-stones', 'vasculitis'))  ) )
AND gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort)
AND EventDate BETWEEN @StartDate and @EndDate

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

-- BRING TOGETHER FOR FINAL OUTPUT AND REMOVE USELESS RECORDS

SELECT	 
	PatientId = o.FK_Patient_Link_ID
	,TestName = o.Concept
	,TestDate = o.EventDate
	,TestResult = TRY_CONVERT(NUMERIC (18,5), [Value]) -- convert to numeric so no text can appear.
	,TestUnit = o.[Units]
FROM #observations o
WHERE  [Value] IS NOT NULL AND [Value] != '0' AND UPPER([Value]) NOT LIKE '%[A-Z]%'  -- CHECKS IN CASE ANY ZERO, NULL OR TEXT VALUES REMAINED
