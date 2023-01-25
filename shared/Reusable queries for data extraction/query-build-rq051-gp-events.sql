--┌────────────────────────────────────────────────────────────────────────────┐
--│ Create counting tables for each conditions based on GPEvents table - RQ051 │
--└────────────────────────────────────────────────────────────────────────────┘
-- OBJECTIVE: To build the counting tables for each mental conditions for RQ051. This reduces duplication of code in the template scripts.

-- COHORT: Any patient in the [RLS].[vw_GP_Events]

-- NOTE: Need to fill the '{param:condition}' and '{param:version}' and {param:conditionname}

-- INPUT: Assumes there exists one temp table as follows:
-- #GPEvents (FK_Patient_Link_ID, EventDate, FK_Reference_Coding_ID, FK_Reference_SnomedCT_ID)

-- OUTPUT: Temp tables as follows:
-- #First{param:conditionname}FullLookback
-- #First{param:conditionname}2019Lookback
-- #First{param:conditionname}Counts

------------------------------------------------------------------------------------------------------------------------------------------------------------
--> CODESET {param:condition}:{param:version}

-- Table for first episode using all of record as lookback
IF OBJECT_ID('tempdb..#First{param:conditionname}FullLookback') IS NOT NULL DROP TABLE #First{param:conditionname}FullLookback;
SELECT FK_Patient_Link_ID, MIN(CAST(EventDate AS DATE)) AS FirstOccurrence
INTO #First{param:conditionname}FullLookback
FROM #GPEvents
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = '{param:condition}' AND Version = '{param:version}') OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = '{param:condition}' AND Version = '{param:version}')
) AND EventDate < '2022-06-01' AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude)
GROUP BY FK_Patient_Link_ID
HAVING MIN(CAST(EventDate AS DATE)) >= '2019-01-01'; -- HAVING is applied after the GROUPing so ensures that we only get people whose first occurrence was 2019 onwards, but the WHERE clause still looks at records before this date.

-- Table for first episode since 2019
IF OBJECT_ID('tempdb..#First{param:conditionname}2019Lookback') IS NOT NULL DROP TABLE #First{param:conditionname}2019Lookback;
SELECT FK_Patient_Link_ID, MIN(CAST(EventDate AS DATE)) AS FirstOccurrenceFrom2019Onwards
INTO #First{param:conditionname}2019Lookback
FROM #GPEvents
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = '{param:condition}' AND Version = '{param:version}') OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = '{param:condition}' AND Version = '{param:version}')
) AND EventDate < '2022-06-01' AND CAST(EventDate AS DATE) >= '2019-01-01' AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude)
GROUP BY FK_Patient_Link_ID; -- The date range is now fully in the WHERE clause so we�re looking at first episode, but only considering post 2019 data.

-- Table for episode counts
IF OBJECT_ID('tempdb..#First{param:conditionname}Counts') IS NOT NULL DROP TABLE #First{param:conditionname}Counts;
SELECT DISTINCT FK_Patient_Link_ID, CAST(EventDate AS DATE) AS EpisodeDate  --DISTINCT + CAST to ensure only one episode per day per patient is counted
INTO #First{param:conditionname}Counts
FROM #GPEvents
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = '{param:condition}' AND Version = '{param:version}') OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = '{param:condition}' AND Version = '{param:version}')
) AND EventDate < '2022-06-01' AND CAST(EventDate AS DATE) >= '2019-01-01' AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude); 
