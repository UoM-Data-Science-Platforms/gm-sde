--┌────────────┐
--│ HbA1c file │
--└────────────┘

------------------------ RDE CHECK -------------------------
-- RDE NAME: GEORGE TILSTON, DATE OF CHECK: 11/05/21 -------
------------------------------------------------------------

-- For each patient with a COVID positive test, this produces 2 years of hbA1c readings
-- leading up to the date of the positive test.

--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2020-01-01';

-- Only need at most hba1c from 2 years prior to COVID test
DECLARE @EventsFromDate datetime;
SET @EventsFromDate = DATEADD(year, -2, @StartDate);

-- Only include patients who were first registered at a GP practice prior
-- to June 2022. This is 1 month before COPI expired and so acts as a buffer.
-- If we only looked at patients who first registered before July 2022, then
-- there is a chance that their data was processed after COPI expired.

/*IF OBJECT_ID('tempdb..#PatientsToInclude') IS NOT NULL DROP TABLE #PatientsToInclude;
SELECT FK_Patient_Link_ID INTO #PatientsToInclude
FROM SharedCare.Patient_GP_History
GROUP BY FK_Patient_Link_ID;*/

--> CODESET hba1c:2

-- Get all covid positive patients as this is the population of the matched cohort
--> EXECUTE query-patients-with-covid.sql start-date:2020-01-01 all-patients:true gp-events-table:RLS.vw_GP_Events

-- Get all hbA1c values for the cohort
IF OBJECT_ID('tempdb..#hba1c') IS NOT NULL DROP TABLE #hba1c;
SELECT 
	FK_Patient_Link_ID,
	CAST(EventDate AS DATE) AS EventDate,
	[Value] AS hbA1c
INTO #hba1c
FROM SharedCare.GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('hba1c') AND [Version]=2)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('hba1c') AND [Version]=2))
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #CovidPatients)
AND EventDate > @EventsFromDate
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
