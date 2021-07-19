--┌─────────────────────────────────┐
--│ Comorbidities                   │
--└─────────────────────────────────┘

-- This file contains comorbidity information for every patient in the study cohort from 1st February 2019.

-- OUTPUT: A single table with the following:
--	PatientId
--	Comorbidity


--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2020-02-01';

--> EXECUTE query-cancer-cohort-matching.sql
-- OUTPUTS: #Patients

-- Set start date to be 1 year before study index date
SET @StartDate = '2019-02-01';

--> EXECUTE query-patient-ltcs.sql
-- OUTPUT: #PatientsWithLTCs (FK_Patient_Link_ID, LTC)

-- Get long term conditions for the patients in the cohort
-- Grain: multiple conditions per patient 
SELECT
  FK_Patient_Link_ID AS PatientId,
  LTC AS Comorbidity
FROM #PatientsWithLTCs;






