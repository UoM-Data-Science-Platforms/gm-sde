--┌────────────┐
--│ Admissions │
--└────────────┘

--------------------- RDE CHECK ---------------------
-- Le Mai Parkes  - 25 May 2022 - via pull request --
-----------------------------------------------------

-- OUTPUT: Data with the following fields
--  - PatientId (int)
--  - AdmissionDate (YYYYMMDD)
--  - DischargeDate (YYYYMMDD)
--  - Status (planned/unplanned/maternity/transfer/other)

--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2020-01-01';

-- Set the end date
DECLARE @EndDate datetime;
SET @EndDate = '2022-07-01';

-- Assume temp table #OxAtHome (FK_Patient_Link_ID, AdmissionDate, DischargeDate)

-- Remove admissions ahead of our cut-off date
DELETE FROM #OxAtHome WHERE AdmissionDate > '2022-06-01';

-- Censor discharges after cut-off to appear as NULL
UPDATE #OxAtHome SET DischargeDate = NULL WHERE DischargeDate > '2022-06-01';

-- Table of all patients (not matching cohort - will do that subsequently)
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT FK_Patient_Link_ID INTO #Patients FROM #OxAtHome
WHERE AdmissionDate < @EndDate
AND (DischargeDate IS NULL OR DischargeDate < @EndDate);

--> EXECUTE query-classify-secondary-admissions.sql
--> EXECUTE query-get-admissions-and-length-of-stay.sql all-patients:false

SELECT 
  o.FK_Patient_Link_ID AS PatientId,
  admit.AdmissionDate,
  los.DischargeDate,
  admit.AdmissionType AS [Status]
FROM #OxAtHome o
LEFT OUTER JOIN #AdmissionTypes admit ON admit.FK_Patient_Link_ID = o.FK_Patient_Link_ID
LEFT OUTER JOIN #LengthOfStay los 
  ON los.FK_Patient_Link_ID = o.FK_Patient_Link_ID
  AND los.AdmissionDate = admit.AdmissionDate
WHERE admit.AdmissionDate < @EndDate
AND (los.DischargeDate IS NULL OR los.DischargeDate < @EndDate);