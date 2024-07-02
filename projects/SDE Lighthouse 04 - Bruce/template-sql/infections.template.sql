--┌────────────────────────────────────┐
--│ LH004 Infections file              │
--└────────────────────────────────────┘

-- OUTPUT: Data with the following fields
-- 	- PatientId (int)
--  - Date

-- ** TO DO: ask if PI needs description of each infection

--Just want the output, not the messages
SET NOCOUNT ON;

DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2020-01-01';  -- CHECK
SET @EndDate = '2023-10-31'; -- CHECK

--> EXECUTE query-build-lh004-cohort.sql

--> CODESET infections:1


-- WE NEED TO PROVIDE INFECTION DESCRIPTION, BUT SOME CODES APPEAR MULTIPLE TIMES IN THE VERSIONEDCODESET TABLES WITH DIFFERENT DESCRIPTIONS
-- THEREFORE, TAKE THE FIRST DESCRIPTION BY USING ROW_NUMBER

IF OBJECT_ID('tempdb..#VersionedCodeSets_1') IS NOT NULL DROP TABLE #VersionedCodeSets_1;
SELECT *
INTO #VersionedCodeSets_1
FROM (
SELECT *,
	ROWNUM = ROW_NUMBER() OVER (PARTITION BY FK_Reference_Coding_ID ORDER BY [description])
FROM #VersionedCodeSets ) SUB
WHERE ROWNUM = 1

IF OBJECT_ID('tempdb..#VersionedSnomedSets_1') IS NOT NULL DROP TABLE #VersionedSnomedSets_1;
SELECT *
INTO #VersionedSnomedSets_1
FROM (
SELECT *,
	ROWNUM = ROW_NUMBER() OVER (PARTITION BY FK_Reference_SnomedCT_ID ORDER BY [description])
FROM #VersionedSnomedSets) SUB
WHERE ROWNUM = 1

-- TABLE OF ALL INFECTIONS FOR THE COHORT

IF OBJECT_ID('tempdb..#Infections') IS NOT NULL DROP TABLE #Infections;
SELECT FK_Patient_Link_ID,
	EventDate = CAST(EventDate as DATE),
	[Concept] = CASE WHEN s.[concept] IS NOT NULL THEN s.[concept] ELSE c.[concept] END,
	[description] = CASE WHEN s.[description] IS NOT NULL THEN s.[description] ELSE c.[description] END
INTO #Infections
FROM SharedCare.GP_Events m
LEFT OUTER JOIN #VersionedSnomedSets_1 s ON s.FK_Reference_SnomedCT_ID = m.FK_Reference_SnomedCT_ID
LEFT OUTER JOIN #VersionedCodeSets_1 c ON c.FK_Reference_Coding_ID = m.FK_Reference_Coding_ID
WHERE m.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort)
AND m.EventDate BETWEEN @StartDate AND @EndDate
AND (
	m.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets_1 WHERE Concept = 'infections') OR
    m.FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets_1 WHERE Concept = 'infections')
);


--bring together for final output
SELECT	PatientId = m.FK_Patient_Link_ID,
		EventDate,
		Concept = concept,
		[Description] = REPLACE([Description], ',', '|')
FROM #Infections m