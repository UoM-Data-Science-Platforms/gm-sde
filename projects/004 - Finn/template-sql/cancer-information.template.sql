--┌─────────────────────────────────┐
--│ Cancer information              │
--└─────────────────────────────────┘


-- OUTPUT: A single table with the following:
--	PatientID
--	DiagnosisDate
--	CancerCode
--  CodingScheme



--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @IndexDate datetime;
SET @IndexDate = '2020-02-01';

--> EXECUTE query-cancer-cohort-matching.sql
-- OUTPUTS:
-- - #Patients2


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
  EventDate < '2020-02-01' AND (
    FK_Reference_SnomedCT_ID IN (
      SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('cancer') AND [Version]=1
    ) OR FK_Reference_Coding_ID IN (
      SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('cancer') AND [Version]=1
    )
  ) AND FK_Patient_Link_ID IN (
    SELECT FK_Patient_Link_ID FROM #Patients2 WHERE HasCancer = 'Y'
  );




-- TODO: check granularity
-- Get main codes for each 
-- Grain: multiple cancer codes per event date
IF OBJECT_ID('tempdb..#CancerCodes') IS NOT NULL DROP TABLE #CancerCodes;
SELECT 
  FK_Patient_Link_ID,
  DiagnosisDate,
  map.MainCode AS CancerCode,
  map.CodingScheme
INTO #CancerCodes
FROM #CancerDiagnosisHistory p
INNER JOIN [SharedCare].[Reference_SnomedCT_Mappings] AS map 
  ON (p.FK_Reference_Coding_ID = map.FK_Reference_Coding_ID OR p.FK_Reference_SnomedCT_ID = map.FK_Reference_SnomedCT_ID);
