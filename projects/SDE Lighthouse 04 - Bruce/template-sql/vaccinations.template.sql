--┌────────────────────────────────────┐
--│ LH004 Vaccinations file            │
--└────────────────────────────────────┘

-- OUTPUT: Data with the following fields
-- 	- PatientId (int)
--  - Date
--  - VaccinationType

--Just want the output, not the messages
SET NOCOUNT ON;

DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2020-01-01';  -- CHECK
SET @EndDate = '2023-10-31'; -- CHECK

--> EXECUTE query-build-lh004-cohort.sql

--> CODESET flu-vaccination:1 covid-vaccination:1 pneumococcal-vaccination:1 shingles-vaccination:1

-- TABLE OF ALL VACCINATIONS FOR THE COHORT

IF OBJECT_ID('tempdb..#Vaccinations') IS NOT NULL DROP TABLE #Vaccinations;
SELECT FK_Patient_Link_ID,
	EventDate = CAST(EventDate as DATE),
	[Concept] = CASE WHEN s.[concept] IS NOT NULL THEN s.[concept] ELSE c.[concept] END
INTO #Vaccinations
FROM SharedCare.GP_Events m
LEFT OUTER JOIN #VersionedSnomedSets s ON s.FK_Reference_SnomedCT_ID = m.FK_Reference_SnomedCT_ID
LEFT OUTER JOIN #VersionedCodeSets c ON c.FK_Reference_Coding_ID = m.FK_Reference_Coding_ID
WHERE m.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort)
AND m.EventDate BETWEEN @StartDate AND @EndDate
AND (
	m.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept in ('flu-vaccination', 'covid-vaccination', 'pneumococcal-vaccination', 'shingles-vaccination')) OR
    m.FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept in ('flu-vaccination', 'covid-vaccination', 'pneumococcal-vaccination', 'shingles-vaccination'))
);


--bring together for final output
SELECT	DISTINCT PatientId = m.FK_Patient_Link_ID,   -- use distinct, assuming multiple codes for same concept, on same day, are the same vaccination
		EventDate,
		Concept
FROM #Vaccinations m