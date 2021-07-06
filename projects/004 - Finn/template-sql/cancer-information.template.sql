--┌─────────────────────────────────┐
--│ Cancer information              │
--└─────────────────────────────────┘


-- OUTPUT: A single table with the following:
--	FK_Patient_Link_ID
--	DiagnosisDate (YYYY-MM-DD)
--	CancerCode 
--  CodingScheme 


--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2020-02-01';

--> EXECUTE query-cancer-cohort-matching.sql
-- OUTPUTS:
-- - #Patients2
-- - #VersionedCodeSets
-- - #VersionedSnomedSets


-- Get all events with a cancer code captured before index date for all cancer patients from the cohort.
-- Grain: multiple events for each patient
IF OBJECT_ID('tempdb..#CancerDiagnosisHistory') IS NOT NULL DROP TABLE #CancerDiagnosisHistory;
Select 
  FK_Patient_Link_ID,
  CAST(EventDate AS DATE) AS DiagnosisDate,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID 
INTO #CancerDiagnosisHistory
FROM RLS.vw_GP_Events
WHERE  
  EventDate <= @StartDate AND (
    FK_Reference_SnomedCT_ID IN (
      SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('cancer') AND [Version]=1
    ) OR FK_Reference_Coding_ID IN (
      SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('cancer') AND [Version]=1
    )
  ) AND FK_Patient_Link_ID IN (
    SELECT FK_Patient_Link_ID FROM #Patients2 WHERE HasCancer = 'Y'
  );


-- Get the actual cancer codes associated for each Ref_Code.
-- Grain: multiple cancer codes per event date
SELECT 
  FK_Patient_Link_ID AS PatientId,
  DiagnosisDate,
  map.MainCode AS CancerCode,
  map.CodingScheme
FROM #CancerDiagnosisHistory p
INNER JOIN [SharedCare].[Reference_SnomedCT_Mappings] AS map 
  ON (p.FK_Reference_Coding_ID = map.FK_Reference_Coding_ID OR p.FK_Reference_SnomedCT_ID = map.FK_Reference_SnomedCT_ID);

