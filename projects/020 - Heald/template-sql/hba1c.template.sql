--┌────────────┐
--│ HbA1c file │
--└────────────┘

-- Cohort is diabetic patients with a positive covid test

--> EXECUTE load-code-sets.sql hba1c

-- Get all covid positive patients as this is the population of the matched cohort
IF OBJECT_ID('tempdb..#CovidPatients') IS NOT NULL DROP TABLE #CovidPatients;
SELECT FK_Patient_Link_ID, MIN(CONVERT(DATE, [EventDate])) AS FirstCovidPositiveDate INTO #CovidPatients
FROM [RLS].[vw_COVID19]
WHERE GroupDescription = 'Confirmed'
AND EventDate > '2020-01-01'
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

-- Get all hbA1c values for the cohort
IF OBJECT_ID('tempdb..#hba1c') IS NOT NULL DROP TABLE #hba1c;
SELECT 
	FK_Patient_Link_ID,
	CAST(EventDate AS DATE) AS EventDate,
	[Value] AS hbA1c
INTO #hba1c
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('hba1c') AND [Version]=2)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('hba1c') AND [Version]=2))
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #CovidPatients)
AND EventDate > '2018-01-01'
AND [Value] IS NOT NULL
AND [Value] != '0';

-- Get 2 years of hba1c for each patient relative to covid positive test date
SELECT c.FK_Patient_Link_ID AS PatientId, EventDate, hbA1c
FROM #CovidPatients c
INNER JOIN #hba1c h 
  ON h.FK_Patient_Link_ID = c.FK_Patient_Link_ID
  AND h.EventDate <= FirstCovidPositiveDate
  AND h.EventDate >= DATEADD(year, -2, FirstCovidPositiveDate)
ORDER BY c.FK_Patient_Link_ID, EventDate;
