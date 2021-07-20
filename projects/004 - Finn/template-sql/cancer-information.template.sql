--┌─────────────────────────────────┐
--│ Cancer information              │
--└─────────────────────────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------
-- RICHARD WILLIAMS |	DATE: 20/07/21

-- OUTPUT: A single table with the following:
--	PatientId
--	DiagnosisDate (YYYY-MM-DD)
--	CancerCode 


--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2020-02-01';

--> EXECUTE query-cancer-cohort-matching.sql
-- OUTPUTS:
-- - #Patients
-- - #VersionedCodeSets
-- - #VersionedSnomedSets


-- Get all events with a cancer code captured before index date for all cancer patients from the cohort, de-duped.
-- Grain: multiple events for each patient
IF OBJECT_ID('tempdb..#CancerDiagnosisHistory') IS NOT NULL DROP TABLE #CancerDiagnosisHistory;
Select DISTINCT
  FK_Patient_Link_ID AS PatientId,
  CAST(EventDate AS DATE) AS DiagnosisDate,
  SuppliedCode AS CancerCode
FROM RLS.vw_GP_Events
WHERE  
  EventDate <= @StartDate AND (
    FK_Reference_SnomedCT_ID IN (
      SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('cancer') AND [Version]=1
    ) OR FK_Reference_Coding_ID IN (
      SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('cancer') AND [Version]=1
    )
  ) AND FK_Patient_Link_ID IN (
    SELECT FK_Patient_Link_ID FROM #Patients WHERE HasCancer = 'Y'
  );




