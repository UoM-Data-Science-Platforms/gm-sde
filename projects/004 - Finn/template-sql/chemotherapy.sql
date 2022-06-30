--┌─────────────────────────────────┐
--│ Chemotherapy  information           │
--└─────────────────────────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------


-- All chemotherapy details captured in the cancer summary record for the study cohort.

-- OUTPUT: Data with the following fields
--  - PatientId (Int)
--  -  Intent,
--  -  DrugType,
--  -  RegimeName,
--  -  ClinicalTrial, --Clinical Tiral Flag: Yes - 1, No - 2
--  -  CycleDate,
--  -  Cycle,
--  -  AttendedAs, -- Inpatient, Outpatient or Daycase
--  -  DayNumber


--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2020-02-01';

-- Get all the patients in the cohort
-- > EXECUTE query-cancer-cohort-matching.sql
-- OUTPUTS: #Patients


-- One record per treatment. The same treatment can be applied more than once within the same cycle date
SELECT 
  FK_Patient_Link_ID AS PatientId,
  Intent,
  DrugType,
  RegimeName,
  ClinicalTrial, --Clinical Tiral Flag: Yes - 1, No - 2
  CycleDate,
  Cycle,
  AttendedAs, -- Inpatient, Outpatient or Daycase
  DayNumber
FROM CCC_Chemotherapy 
-- WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);

