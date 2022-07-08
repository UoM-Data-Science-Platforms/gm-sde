--┌─────────────────────────────────┐
--│ Radiotherapy appointments       │
--└─────────────────────────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------


-- Informaiton on radiotherapy appointments from the cancer summary tables.

-- OUTPUT: Data with the following fields
--  - PatientId (Int)
--  - RadiotherapyType,
--  - AppointmentDate,
--  - AttendedStatus, -- Inpatient, Outpatient or Daycase
--  - FractionGiven, 
--  - PlannedDose,
--  - PlannedFraction,
--  - DurationDays


--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2020-02-01';

-- Get all the patients in the cohort
-- > EXECUTE query-cancer-cohort-matching.sql
-- OUTPUTS: #Patients


-- One record per treatment N.B. the same treatment can be applied more than once on the same day
SELECT 
  FK_Patient_Link_ID AS PatientId,
  RadiotherapyType,
  AppointmentDate,
  AttendedStatus, -- Inpatient, Outpatient or Daycase
  FractionGiven, 
  PlannedDose,
  PlannedFraction,
  DurationDays
FROM CCC_RadiotherapyAppointment 
-- WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);

