--┌──────────────┐
--│ Observations │
--└──────────────┘

-------- RESEARCH DATA ENGINEER CHECK ---------


-- OUTPUT: Data with the following fields
-- 	-   PatientId (int)
--	-	TestName
--	-	TestDate (YYYY-MM-DD)
--  -   TestResult 

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2012-03-01';
DECLARE @EndDate datetime;
SET @EndDate = '2022-03-01';

--Just want the output, not the messages
SET NOCOUNT ON;

----------------------------------------
--> EXECUTE query-build-rq050-cohort.sql
----------------------------------------

---------------------------------------------------------------------------------------------------------
---------------------------------------- OBSERVATIONS/MEASUREMENTS --------------------------------------
---------------------------------------------------------------------------------------------------------

-- LOAD CODESETS FOR OBSERVATIONS WITH A VALUE

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
	[Value] = TRY_CONVERT(NUMERIC (18,5), [Value])
INTO #observations
FROM #PatientEventData gp
LEFT JOIN #VersionedSnomedSets sn ON sn.FK_Reference_SnomedCT_ID = gp.FK_Reference_SnomedCT_ID
LEFT JOIN #VersionedCodeSets co ON co.FK_Reference_Coding_ID = gp.FK_Reference_Coding_ID
WHERE
	(gp.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN 
		('haemoglobin', 'white-blood-cells', 'red-blood-cells', 'platelets', 'haematocrit', 'mean-corpuscular-volume',' mean-corpuscular-haemoglobin','systolic-blood-pressure', 'diastolic-blood-pressure', 'urine-blood', 'urine-protein', 'urine-ketones', 'urine-glucose')
		) OR
     gp.FK_Reference_Coding_ID   IN (SELECT FK_Reference_Coding_ID   FROM #VersionedCodeSets WHERE Concept IN 
		('haemoglobin', 'white-blood-cells', 'red-blood-cells', 'platelets', 'haematocrit', 'mean-corpuscular-volume',' mean-corpuscular-haemoglobin','systolic-blood-pressure', 'diastolic-blood-pressure', 'urine-blood', 'urine-protein', 'urine-ketones', 'urine-glucose')
		) 
	)
AND EventDate BETWEEN @StartDate and @EndDate
AND [Value] IS NOT NULL AND [Value] != '0' AND TRY_CONVERT(NUMERIC (18,5), [VALUE]) <> 0 -- EXCLUDE NULLS AND ZERO VALUES
AND UPPER([Value]) NOT LIKE '%[A-Z]%'  -- EXCLUDE ANY TEXT VALUES


-- BRING TOGETHER FOR FINAL OUTPUT AND REMOVE USELESS RECORDS

SELECT	 
	PatientId = o.FK_Patient_Link_ID
	,TestName = o.Concept
	,TestDate = o.EventDate
	,TestResult =  o.Value-- convert to numeric so no text can appear.
FROM #observations o
