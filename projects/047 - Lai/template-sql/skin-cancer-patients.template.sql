--┌────────────────────────────────────┐
--│ Skin cancer patients               │
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
-- 	- CurrentSmokingStatus, - [non-trivial-smoker/trivial-smoker/non-smoker]
-- 	- CurrentAlcoholIntake, - [heavy drinker/moderate drinker/light drinker/non-drinker] - most recent code
-- 	- LatestBMI, - latest BMI value recorded
-- 	- Hydrochlorothiazide, - (Y/N) from GP_Medications after startDate
-- 	- Immunosuppression, - (Y/N) from GP_Events, includes HIV.


--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2018-01-01';
SET @EndDate = '2022-06-01';


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


--> CODESET hydrochlorothiazide:1 
--> CODESET immunosuppression:1 
--> EXECUTE query-patient-smoking-status.sql gp-events-table:RLS.vw_GP_Events
--> EXECUTE query-patient-alcohol-intake.sql gp-events-table:RLS.vw_GP_Events
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
WHERE TumourGroup = 'Skin (excl Melanoma)' AND DiagnosisDate < @EndDate AND DiagnosisDate >= @StartDate
      AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);


-- Find the patients with a code related to hydrochlorothiazide in their GP Medications records===============================================================
IF OBJECT_ID('tempdb..#PatientMedicationsHydrochlorothiazide') IS NOT NULL DROP TABLE #PatientMedicationsHydrochlorothiazide;
SELECT DISTINCT	FK_Patient_Link_ID
INTO #PatientMedicationsHydrochlorothiazide
FROM RLS.vw_GP_Medications
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('hydrochlorothiazide') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('hydrochlorothiazide') AND [Version]=1))
) 
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND MedicationDate >= @StartDate AND MedicationDate < @EndDate;


-- Get latest BMI value for the patients in our cohort=========================================================================================================
IF OBJECT_ID('tempdb..#PatientLatestBMI') IS NOT NULL DROP TABLE #PatientLatestBMI;
SELECT 
  FK_Patient_Link_ID,
  BMI AS LatestBMI,
  max(DateOfBMIMeasurement) AS LatestDate
INTO #PatientLatestBMI
FROM PatientBMI



-- Get a distinct list of patients with a recorded code related with immunosuppression. 
IF OBJECT_ID('tempdb..#PatientImmunosuppression') IS NOT NULL DROP TABLE #PatientImmunosuppression;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #PatientImmunosuppression
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'immunosuppression' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'immunosuppression' AND Version = 1)
);

--> CODESET hiv:1 

-- The immunosuppression codeset excludes HIV, so we get this separate.
IF OBJECT_ID('tempdb..#PatientHIV') IS NOT NULL DROP TABLE #PatientHIV;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #PatientHIV
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'hiv' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'hiv' AND Version = 1)
);

-- Collate immunosuppression with HIV. (Union removes duplicates)
IF OBJECT_ID('tempdb..#PatientAllImmunosuppression') IS NOT NULL DROP TABLE #PatientAllImmunosuppression;
SELECT FK_Patient_Link_ID
INTO #PatientAllImmunosuppression
FROM #PatientImmunosuppression
UNION
SELECT FK_Patient_Link_ID 
FROM #PatientHIV;



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
  CurrentSmokingStatus,
  CurrentAlcoholIntake,
  LatestBMI,
  CASE WHEN pmh.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS Hydrochlorothiazide,
  CASE WHEN pi.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS Immunosuppression
FROM #TumourDetails p
LEFT OUTER JOIN #PatientSmokingStatus ps ON ps.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientMedicationsHydrochlorothiazide pmh ON pmh.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientLatestBMI pbmi ON pbmi.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientAllImmunosuppression pi ON pi.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientAlcoholIntake pa ON pa.FK_Patient_Link_ID = p.FK_Patient_Link_ID


