--┌────────────────────────────────────┐
--│ Gynaecological cancer patients     │
--└────────────────────────────────────┘

-- OUTPUT: Data with the following fields

-- 	- FK_Patient_Link_ID,
-- 	- DiagnosisDate,
-- 	- Benign,
-- 	- TStatus,
-- 	- TumourGroup,
-- 	- TumourSite,
-- 	- Histology,
-- 	- Differentiation,
-- 	- T_Stage,
-- 	- N_Stage,
-- 	- M_Stage,
-- 	- OverallStage,
-- PreviousCervicalScreeningAttendance (Y/N)
-- LatestBMI
-- Parity
-- HasDiabetes (Y/N)
-- Past use of oral contraceptives (Y/N)


--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2018-01-01';

-- TODO: Create clinical codeset for gynae cancer diagnosis. 
--> CODESET cancer:4

-- Get patients with a diagnosis for gynae cancer from Jan 2018.
IF OBJECT_ID('tempdb..#GynaeCancerPatients') IS NOT NULL DROP TABLE #GynaeCancerPatients;
SELECT 
  FK_Patient_Link_ID,
  CAST(EventDate AS DATE) AS DiagnosisDate
INTO #GynaeCancerPatients
FROM RLS.vw_GP_Events
WHERE (
  FK_Reference_SnomedCT_ID IN (
      SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('cancer') AND [Version]=4
  ) OR
  FK_Reference_Coding_ID IN (
      SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('cancer') AND [Version]=4
  )  
) 
AND DiagnosisDate >= @StartDate
GROUP BY FK_Patient_Link_ID;

-- Get a distinct list of patient IDs
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT DISTINCT
  FK_Patient_Link_ID
INTO #Patients
FROM #GynaeCancerPatients;

-- Get tumour details information for the patients with a gynae cancer diagnosis from the cancer summary. 
IF OBJECT_ID('tempdb..#TumourDetails') IS NOT NULL DROP TABLE #TumourDetails;
SELECT 
  FK_Patient_Link_ID,
  DiagnosisDate,
  Benign,
  TStatus,
  TumourGroup,
  TumourSite,
  Histology,
  Differentiation,
  T_Stage,
  N_Stage,
  M_Stage,
  OverallStage
INTO #TumourDetails
FROM CCC_PrimaryTumourDetails 
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);

-- TODO: Filter the data to have only gynae-related tumour details, as some patients might have 
-- more than one cancer diagnosis. One way to do this **might be** using the FK_Reference_Coding_ID and FK_Reference_SnomedCT_ID 
-- but can't know for sure, further investigation needed. 


--> EXECUTE query-patient-bmi.sql gp-events-table:RLS.vw_GP_Events

-- Get latest BMI value for the patients in our cohort. 
IF OBJECT_ID('tempdb..#PatientLatestBMI') IS NOT NULL DROP TABLE #PatientLatestBMI;
SELECT 
  FK_Patient_Link_ID,
  BMI AS LatestBMI,
  max(DateOfBMIMeasurement) AS LatestDate
INTO #PatientLatestBMI
FROM PatientBMI


--> CODESET contraceptives-combined-hormonal:1 contraceptives-progesterone-only:1 contraceptives-devices:1

IF OBJECT_ID('tempdb..#PatientContraceptivesHormonal') IS NOT NULL DROP TABLE #PatientContraceptivesHormonal;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #PatientContraceptivesHormonal
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'contraceptives-combined-hormonal' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'contraceptives-combined-hormonal' AND Version = 1)
);

IF OBJECT_ID('tempdb..#PatientContraceptivesProgesterone') IS NOT NULL DROP TABLE #PatientContraceptivesProgesterone;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #PatientContraceptivesProgesterone
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'contraceptives-progesterone-only' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'contraceptives-progesterone-only' AND Version = 1)
);

IF OBJECT_ID('tempdb..#PatientContraceptivesDevices') IS NOT NULL DROP TABLE #PatientContraceptivesDevices;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #PatientContraceptivesDevices
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'contraceptives-devices' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'contraceptives-devices' AND Version = 1)
);



-- TODO: 
-- PreviousCervicalScreeningAttendance (Y/N)
-- Parity
-- HasDiabetes (Y/N)






-- Collate all patient diagnosis details to final output table. 
-- Grain: 1 row per diagnosis date per patient. 
SELECT 
  FK_Patient_Link_ID AS PatientId,
  DiagnosisDate,
  Benign,
  TStatus,
  TumourGroup,
  TumourSite,
  Histology,
  Differentiation,
  T_Stage,
  N_Stage,
  M_Stage,
  OverallStage,  
  LatestBMI,
  CASE WHEN pch.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS ContraceptivesHormonal,
  CASE WHEN pcp.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS ContraceptivesProgesteroneOnly,
  CASE WHEN pcd.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS ContraceptiveDevices

FROM #TumourDetails p
LEFT OUTER JOIN #PatientLatestBMI pbmi ON pbmi.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientContraceptivesHormonal pch ON pch.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientContraceptivesProgesterone pcp ON pcp.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientContraceptivesDevices pcd ON pcd.FK_Patient_Link_ID = p.FK_Patient_Link_ID


