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
DECLARE @EndDate datetime;
DECLARE @IndexDate datetime;
SET @StartDate = '2018-01-01';
SET @EndDate = '2022-06-01';
SET @IndexDate = '2022-06-01';


-- Create a table with all patients (ID)=========================================================================================================================
IF OBJECT_ID('tempdb..#PatientsToInclude') IS NOT NULL DROP TABLE #PatientsToInclude;
SELECT FK_Patient_Link_ID INTO #PatientsToInclude
FROM RLS.vw_Patient_GP_History
GROUP BY FK_Patient_Link_ID
HAVING MIN(StartDate) < '2022-06-01';

IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #Patients 
FROM #PatientsToInclude;


--> CODESET contraceptives-combined-hormonal:1 contraceptives-progesterone-only:1 contraceptives-devices:1
--> CODESET cervical-smear:1 diabetes:1
--> EXECUTE query-patient-bmi.sql gp-events-table:RLS.vw_GP_Events


-- Create a cohort table of all gynaecology cancer patients from 2018 with tumour details===================================================================
IF OBJECT_ID('tempdb..#Cohort') IS NOT NULL DROP TABLE #Cohort;
SELECT FK_Patient_Link_ID, 
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
INTO #Cohort
FROM [SharedCare].[CCC_PrimaryTumourDetails]
WHERE TumourGroup = 'Gynaecological' AND DiagnosisDate < @EndDate AND DiagnosisDate >= @StartDate
      AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);


-- Get latest BMI value for the patients in our cohort=======================================================================================================
IF OBJECT_ID('tempdb..#PatientLatestBMI') IS NOT NULL DROP TABLE #PatientLatestBMI;
SELECT 
  FK_Patient_Link_ID,
  BMI AS LatestBMI,
  max(DateOfBMIMeasurement) AS LatestDate
INTO #PatientLatestBMI
FROM #PatientBMI


-- Create tables for contraceptive methods==================================================================================================================== 
IF OBJECT_ID('tempdb..#PatientContraceptivesHormonal') IS NOT NULL DROP TABLE #PatientContraceptivesHormonal;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #PatientContraceptivesHormonal
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'contraceptives-combined-hormonal' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'contraceptives-combined-hormonal' AND Version = 1)
) AND EventDate >= @StartDate AND EventDate < @EndDate;

IF OBJECT_ID('tempdb..#PatientContraceptivesProgesterone') IS NOT NULL DROP TABLE #PatientContraceptivesProgesterone;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #PatientContraceptivesProgesterone
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'contraceptives-progesterone-only' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'contraceptives-progesterone-only' AND Version = 1)
) AND EventDate >= @StartDate AND EventDate < @EndDate;

IF OBJECT_ID('tempdb..#PatientContraceptivesDevices') IS NOT NULL DROP TABLE #PatientContraceptivesDevices;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #PatientContraceptivesDevices
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'contraceptives-devices' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'contraceptives-devices' AND Version = 1)
) AND EventDate >= @StartDate AND EventDate < @EndDate;


-- Create a table for diabetes any type======================================================================================================================
IF OBJECT_ID('tempdb..#Diabetes') IS NOT NULL DROP TABLE #Diabetes;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #Diabetes
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'diabetes' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'diabetes' AND Version = 1)
) AND EventDate >= @StartDate AND EventDate < @EndDate;


-- Create a table for cervical smear tests======================================================================================================================
IF OBJECT_ID('tempdb..#CervicalSmear') IS NOT NULL DROP TABLE #CervicalSmear;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #CervicalSmear
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'cervical-smear' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'cervical-smear' AND Version = 1)
) AND EventDate >= @StartDate AND EventDate < @EndDate;


-- Collate all patient diagnosis details to final output table. 
-- Grain: 1 row per diagnosis date per patient. 
SELECT 
  p.FK_Patient_Link_ID AS PatientId,
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
  CASE WHEN pcd.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS ContraceptiveDevices,
  CASE WHEN d.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS HasDiabetes,
  CASE WHEN c.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PreviousCervicalScreeningAttendance
FROM #Cohort p
LEFT OUTER JOIN #PatientLatestBMI pbmi ON pbmi.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientContraceptivesHormonal pch ON pch.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientContraceptivesProgesterone pcp ON pcp.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientContraceptivesDevices pcd ON pcd.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #Diabetes d ON d.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #CervicalSmear c ON c.FK_Patient_Link_ID = p.FK_Patient_Link_ID

