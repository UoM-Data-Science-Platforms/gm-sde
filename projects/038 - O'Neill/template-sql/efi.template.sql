--┌──────────┐
--│ EFI file │
--└──────────┘

-- OUTPUT: Data showing the cumulative deficits for each person over time

--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the temp end date until new legal basis
DECLARE @TEMPRQ038EndDate datetime;
SET @TEMPRQ038EndDate = '2022-06-01';

-- Only include patients who were first registered at a GP practice prior
-- to June 2022. This is 1 month before COPI expired and so acts as a buffer.
-- If we only looked at patients who first registered before July 2022, then
-- there is a chance that their data was processed after COPI expired.
IF OBJECT_ID('tempdb..#PatientsToInclude') IS NOT NULL DROP TABLE #PatientsToInclude;
SELECT FK_Patient_Link_ID INTO #PatientsToInclude
FROM SharedCare.Patient_GP_History
GROUP BY FK_Patient_Link_ID
HAVING MIN(StartDate) < @TEMPRQ038EndDate;

-- First get all people with COVID positive test
--> EXECUTE query-patients-with-covid.sql start-date:2020-01-01 all-patients:true gp-events-table:SharedCare.GP_Events

-- Table of all patients with COVID at least once
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT FK_Patient_Link_ID INTO #Patients FROM #CovidPatientsMultipleDiagnoses

--> EXECUTE query-patients-calculate-efi-over-time.sql all-patients:false gp-events-table:SharedCare.GP_Events gp-medications-table:SharedCare.GP_Medications

-- Finally we just select from the EFI table with the required fields
SELECT
  FK_Patient_Link_ID,
  DateFrom,
  NumberOfDeficits
FROM #PatientEFIOverTime
ORDER BY FK_Patient_Link_ID, DateFrom;