--┌─────────────────────────────────┐
--│ Comorbidities                   │
--└─────────────────────────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------
-- RICHARD WILLIAMS |	DATE: 20/07/21

-- This file contains comorbidity information for every patient in the study cohort from 1st February 2019.

-- OUTPUT: A single table with the following:
--	PatientId
--	Comorbidity
--  EventDate


--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2020-02-01';

--> EXECUTE query-cancer-cohort-matching.sql
-- OUTPUTS: #Patients

--> EXECUTE query-patient-condition-events.sql
-- OUTPUT: #PatientConditionsEvents (FK_Patient_Link_ID, Condition, EventDate)

-- Get long term conditions for the patients in the cohort
-- Grain: multiple event dates per condition, and multiple conditions per patient 
SELECT
  FK_Patient_Link_ID AS PatientId,
  Condition AS Comorbidity,
  EventDate
FROM #PatientConditionsEvents
ORDER BY FK_Patient_Link_ID, Condition;
-- 38.877.094 rows
-- running time: ~1hour8min
-- as of 22nd Oct 2021





