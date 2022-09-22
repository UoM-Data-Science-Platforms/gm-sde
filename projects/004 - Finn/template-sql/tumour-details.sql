--┌─────────────────────────────────┐
--│ Primary Tumour Details                  │
--└─────────────────────────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------


-- All details captured in the cancer summary record for the study cohort.

-- OUTPUT: Data with the following fields
--  - PatientId (Int)
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
-- 	- OverallStage.


--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2020-02-01';

-- Get all the patients in the cohort
-- > EXECUTE query-cancer-cohort-matching.sql
-- OUTPUTS: #Patients


-- One record per primary tumour diagnosis per patient. A patient can have more than one Primary Tumour recorded over time.
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
  OverallStage
FROM CCC_PrimaryTumourDetails 
-- WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);
