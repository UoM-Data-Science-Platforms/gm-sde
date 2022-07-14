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
SET @StartDate = '2012-03-01';
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


---------------------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------------
---------------------------------------- OBSERVATIONS/MEASUREMENTS --------------------------------------
---------------------------------------------------------------------------------------------------------

-- LOAD CODESETS FOR OBSERVATIONS WITH A VALUE (EXCEPT THOSE ALREADY LOADED ALREADY)

--> CODESET haemoglobin:1 white-blood-cells:1 red-blood-cells:1 platelets:1 haematocrit:1 mean-corpuscular-volume:1 mean-corpuscular-haemoglobin:1
--> CODESET systolic-blood-pressure:1 diastolic-blood-pressure:1 
--> CODESET urine-blood:1 urine-protein:1 urine-ketones:1 urine-glucose:1

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
FROM RLS.vw_GP_Events gp
LEFT JOIN #VersionedSnomedSets sn ON sn.FK_Reference_SnomedCT_ID = gp.FK_Reference_SnomedCT_ID
LEFT JOIN #VersionedCodeSets co ON co.FK_Reference_Coding_ID = gp.FK_Reference_Coding_ID
WHERE
	(gp.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets) OR
     gp.FK_Reference_Coding_ID   IN (SELECT FK_Reference_Coding_ID   FROM #VersionedCodeSets) )
AND gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort)
AND EventDate BETWEEN @StartDate and @EndDate

-- BRING TOGETHER FOR FINAL OUTPUT AND REMOVE USELESS RECORDS

SELECT	 
	PatientId = o.FK_Patient_Link_ID
	,TestName = o.Concept
	,TestDate = o.EventDate
	,TestResult = TRY_CONVERT(NUMERIC (18,5), [Value]) -- convert to numeric so no text can appear.
	,TestUnit = o.[Units]
FROM #observations o
WHERE  [Value] IS NOT NULL AND [Value] != '0' AND UPPER([Value]) NOT LIKE '%[A-Z]%'  -- CHECKS IN CASE ANY ZERO, NULL OR TEXT VALUES REMAINED
