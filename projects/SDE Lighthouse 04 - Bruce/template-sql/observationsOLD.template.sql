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
SET @StartDate = '2018-01-01'; -- CHECK
DECLARE @EndDate datetime;
SET @EndDate = '2023-10-31'; ---CHECK

DECLARE @MinDate datetime;
SET @MinDate = '1900-01-01';
DECLARE @IndexDate datetime;
SET @IndexDate = '2023-10-31';

--Just want the output, not the messages
SET NOCOUNT ON;

--> EXECUTE query-build-lh004-cohort.sql

---------------------------------------------------------------------------------------------------------
---------------------------------------- OBSERVATIONS/MEASUREMENTS --------------------------------------
---------------------------------------------------------------------------------------------------------

-- LOAD CODESETS FOR OBSERVATIONS

--> CODESET creatinine:1 egfr:1

-- GET VALUES FOR ALL OBSERVATIONS OF INTEREST

IF OBJECT_ID('tempdb..#egfr_creat') IS NOT NULL DROP TABLE #egfr_creat;
SELECT 
	FK_Patient_Link_ID,
	CAST(EventDate AS DATE) AS EventDate,
	Concept = CASE WHEN sn.Concept IS NOT NULL THEN sn.Concept ELSE co.Concept END,
	[Version] =  CASE WHEN sn.[Version] IS NOT NULL THEN sn.[Version] ELSE co.[Version] END,
	[Value],
	[Units]
INTO #egfr_creat
FROM SharedCare.GP_Events gp
LEFT JOIN #VersionedSnomedSets sn ON sn.FK_Reference_SnomedCT_ID = gp.FK_Reference_SnomedCT_ID
LEFT JOIN #VersionedCodeSets co ON co.FK_Reference_Coding_ID = gp.FK_Reference_Coding_ID
WHERE
	(
	 gp.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('egfr', 'creatinine')) ) OR
     gp.FK_Reference_Coding_ID   IN (SELECT FK_Reference_Coding_ID   FROM #VersionedCodeSets WHERE (Concept IN ('egfr', 'creatinine'))  ) 
	 )
AND gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort)
AND EventDate BETWEEN @MinDate and @IndexDate
AND Value <> ''

-- For Egfr and Creatinine we want closest prior to index date
IF OBJECT_ID('tempdb..#TempCurrentEgfr') IS NOT NULL DROP TABLE #TempCurrentEgfr;
SELECT 
	a.FK_Patient_Link_ID, 
	a.Concept,
	Max([Value]) as [Value],
	Max(EventDate) as EventDate
INTO #TempCurrentEgfr
FROM #egfr_creat a
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(EventDate) AS MostRecentDate 
	FROM #egfr_creat
	WHERE Concept = 'egfr'
	GROUP BY FK_Patient_Link_ID
) sub ON sub.MostRecentDate = a.EventDate and sub.FK_Patient_Link_ID = a.FK_Patient_Link_ID
GROUP BY a.FK_Patient_Link_ID, a.Concept;

-- For Egfr and Creatinine we want closest prior to index date
IF OBJECT_ID('tempdb..#TempCurrentCreatinine') IS NOT NULL DROP TABLE #TempCurrentCreatinine;
SELECT 
	a.FK_Patient_Link_ID, 
	a.Concept,
	Max([Value]) as [Value],
	Max(EventDate) as EventDate
INTO #TempCurrentCreatinine
FROM #egfr_creat a
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(EventDate) AS MostRecentDate 
	FROM #egfr_creat
	WHERE Concept = 'creatinine'
	GROUP BY FK_Patient_Link_ID
) sub ON sub.MostRecentDate = a.EventDate and sub.FK_Patient_Link_ID = a.FK_Patient_Link_ID
GROUP BY a.FK_Patient_Link_ID, a.Concept;

-- bring together in a table that can be joined to
IF OBJECT_ID('tempdb..#PatientEgfrCreatinine') IS NOT NULL DROP TABLE #PatientEgfrCreatinine;
SELECT 
	p.FK_Patient_Link_ID,
	Egfr = MAX(CASE WHEN e.Concept = 'Egfr' THEN TRY_CONVERT(NUMERIC(16,5), [Value]) ELSE NULL END),
	Egfr_dt = MAX(CASE WHEN e.Concept = 'Egfr' THEN EventDate ELSE NULL END),
	Creatinine = MAX(CASE WHEN c.Concept = 'Creatinine' THEN TRY_CONVERT(NUMERIC(16,5), [Value]) ELSE NULL END),
	Creatinine_dt = MAX(CASE WHEN c.Concept = 'Creatinine' THEN EventDate ELSE NULL END)
INTO #PatientEgfrCreatinine
FROM #Cohort p
LEFT OUTER JOIN #TempCurrentEgfr e on e.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #TempCurrentCreatinine c on c.FK_Patient_Link_ID = p.FK_Patient_Link_ID
GROUP BY p.FK_Patient_Link_ID



