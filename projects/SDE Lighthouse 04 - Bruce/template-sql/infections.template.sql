--┌────────────────────────────────────┐
--│ LH004 Infections file              │
--└────────────────────────────────────┘

-- OUTPUT: Data with the following fields
-- 	- PatientId (int)
--  - Date
--  - 

--Just want the output, not the messages
SET NOCOUNT ON;

DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2020-01-01';  -- CHECK
SET @EndDate = '2023-10-31'; -- CHECK

--> EXECUTE query-build-lh004-cohort.sql

--> CODESET infections:1

-- TABLE OF ALL INFECTIONS FOR THE COHORT

IF OBJECT_ID('tempdb..#Infections') IS NOT NULL DROP TABLE #Infections;
SELECT FK_Patient_Link_ID,
	EventDate = CAST(EventDate as DATE)
INTO #Infections
FROM SharedCare.GP_Events m
LEFT OUTER JOIN #VersionedSnomedSets s ON s.FK_Reference_SnomedCT_ID = m.FK_Reference_SnomedCT_ID
LEFT OUTER JOIN #VersionedCodeSets c ON c.FK_Reference_Coding_ID = m.FK_Reference_Coding_ID
WHERE m.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort)
AND m.EventDate BETWEEN @StartDate AND @EndDate
AND (
	m.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'infections') OR
    m.FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'infections')
);


--bring together for final output
SELECT	 PatientId = m.FK_Patient_Link_ID,
		EventDate
FROM #Infections m
