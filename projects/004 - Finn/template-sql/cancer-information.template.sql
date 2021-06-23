--┌─────────────────────────────────┐
--│ Patients demographics           │
--└─────────────────────────────────┘

-- Study index date: 1st Feb 2020

-- Defines the cohort (cancer and non cancer patients) that will be used for the study, based on: 
-- Main cohort (cancer patients):
--	- Cancer diagnosis between 1st February 2015 and 1st February 2020
--	- >= 18 year old 
--	- Alive on 1st Feb 2020 
-- Control group (non cancer patients):
--  -	Alive on 1st February 2020 
--  -	no current or history of cancer diagnosis.
-- Matching is 1:5 based on sex and year of birth with a flexible year of birth = ??
-- Index date is: 1st February 2020


-- OUTPUT: A single table with the following:
--	
--	PatientID
--	HasSecondaryCancer (Y/N)
--	FirstDiagnosisDate
--	CancerCode



--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @IndexDate datetime;
SET @IndexDate = '2020-02-01';

--> CODESET cancer

-- Get the first cancer diagnosis date of cancer patients 
IF OBJECT_ID('tempdb..#AllCancerPatients') IS NOT NULL DROP TABLE #AllCancerPatients;
SELECT 
  FK_Patient_Link_ID,
  MIN(CAST(EventDate AS DATE)) AS FirstDiagnosisDate
INTO #AllCancerPatients
FROM RLS.vw_GP_Events
WHERE (
  FK_Reference_SnomedCT_ID IN (
      SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('cancer') AND [Version]=1
  ) OR
  FK_Reference_Coding_ID IN (
      SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('cancer') AND [Version]=1
  ) 
)
GROUP BY FK_Patient_Link_ID;

-- Get patients with a first cancer diagnosis in the time period 1st Feb 2015 - 1st Feb 2020 
IF OBJECT_ID('tempdb..#CancerPatients') IS NOT NULL DROP TABLE #CancerPatients;
Select *
INTO #CancerPatients
From #AllCancerPatients
WHERE FirstDiagnosisDate BETWEEN '2015-02-01' AND @IndexDate;
-- 61.720 patients with a first cancer diagnosis in the last 5 years.

-- Get patients with the first date with a secondary cancer diagnosis of patients 
IF OBJECT_ID('tempdb..#AllSecondaryCancerPatients') IS NOT NULL DROP TABLE #AllSecondaryCancerPatients;
SELECT 
  FK_Patient_Link_ID,
  MIN(CAST(EventDate AS DATE)) AS FirstDiagnosisDate
INTO #AllSecondaryCancerPatients
FROM RLS.vw_GP_Events
WHERE (
  FK_Reference_SnomedCT_ID IN (
      SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('cancer') AND [Version]=2
  ) OR
  FK_Reference_Coding_ID IN (
      SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('cancer') AND [Version]=2
  ) 
)
GROUP BY FK_Patient_Link_ID;
-- 7.529 patients with a secondary cancer diagnosis code captured in GP records.


-- Get patients with a first secondary cancer diagnosis in the time period 1st Feb 2015 - 1st Feb 2020 
IF OBJECT_ID('tempdb..#SecondaryCancerPatients') IS NOT NULL DROP TABLE #SecondaryCancerPatients;
Select *
INTO #SecondaryCancerPatients
From #AllSecondaryCancerPatients
WHERE FirstDiagnosisDate BETWEEN '2015-02-01' AND @IndexDate;
-- 3.820

-- Get unique patients with a first cancer diagnosis or a secondary diagnosis within the time period 1st Feb 2015 - 1st Feb 2020
-- `UNION` will exclude duplicates
IF OBJECT_ID('tempdb..#FirstAndSecondaryCancerPatients') IS NOT NULL DROP TABLE #FirstAndSecondaryCancerPatients;
SELECT 
  FK_Patient_Link_ID
INTO #FirstAndSecondaryCancerPatients 
FROM #CancerPatients
UNION
SELECT 
  FK_Patient_Link_ID
FROM #SecondaryCancerPatients;
-- 63.095