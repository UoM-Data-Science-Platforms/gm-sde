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
SET @EndDate = '2023-08-31';

--Just want the output, not the messages
SET NOCOUNT ON;

--> EXECUTE query-build-rq041-cohort.sql

---------------------------------------------------------------------------------------------------------
---------------------------------------- OBSERVATIONS/MEASUREMENTS --------------------------------------
---------------------------------------------------------------------------------------------------------

-- LOAD CODESETS FOR SEX HORMONES WITH A VALUE (EXCEPT THOSE ALREADY LOADED AT START OF SCRIPT)

--> CODESET fsh:1 luteinising-hormone:1 oestradiol:1 testosterone:1 sex-hormone-binding-globulin:1 androgen-level:1

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
	(gp.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept NOT IN ('egfr','urinary-albumin-creatinine-ratio','glomerulonephritis', 'kidney-transplant', 'kidney-stones', 'vasculitis')) ) OR
     gp.FK_Reference_Coding_ID   IN (SELECT FK_Reference_Coding_ID   FROM #VersionedCodeSets WHERE (Concept NOT IN ('egfr','urinary-albumin-creatinine-ratio','glomerulonephritis', 'kidney-transplant', 'kidney-stones', 'vasculitis'))  ) )
AND gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort)
AND EventDate BETWEEN @StartDate and @EndDate


-- BRING TOGETHER FOR FINAL OUTPUT AND REMOVE USELESS RECORDS

SELECT DISTINCT
	PatientId = o.FK_Patient_Link_ID
	,TestName = o.Concept
	,TestDate = o.EventDate
	,TestResult = TRY_CONVERT(NUMERIC (18,5), [Value]) -- convert to numeric so no text can appear.
	,TestUnit = o.[Units]
FROM #observations o
WHERE 
	[Value] IS NOT NULL AND TRY_CONVERT(NUMERIC (18,5), [Value]) <> 0 AND [Value] <> '0' -- REMOVE NULLS AND ZEROES
	AND UPPER([Value]) NOT LIKE '%[A-Z]%'  -- REMOVES ANY TEXT VALUES
