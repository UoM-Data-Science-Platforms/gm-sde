--┌──────────┐
--│ EFI file │
--└──────────┘

-- OUTPUT: Data showing the cumulative deficits for each person over time with
--         the following fields:
--  - PatientId
--  - DateFrom - the date from which this number of deficits occurred
--  - NumberOfDeficits - the number of deficits on the DateFrom date

--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the temp end date until new legal basis
DECLARE @TEMPRQ038EndDate datetime;
SET @TEMPRQ038EndDate = '2022-06-01';

-- Build the main cohort
--> EXECUTE query-build-rq038-cohort.sql

IF OBJECT_ID('tempdb..#PatientEventData') IS NOT NULL DROP TABLE #PatientEventData;
SELECT 
  FK_Patient_Link_ID,
  CAST(EventDate AS DATE) AS EventDate,
  SuppliedCode,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID,
  [Value]
INTO #PatientEventData
FROM [SharedCare].GP_Events
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate < @TEMPRQ038EndDate
AND UPPER([Value]) NOT LIKE '%[A-Z]%'; -- ignore any upper case values

-- Improve performance later with an index (creates in ~1 minute - saves loads more than that)
DROP INDEX IF EXISTS eventData ON #PatientEventData;
CREATE INDEX eventData ON #PatientEventData (SuppliedCode) INCLUDE (FK_Patient_Link_ID, EventDate, [Value]);

IF OBJECT_ID('tempdb..#PatientMedicationData') IS NOT NULL DROP TABLE #PatientMedicationData;
SELECT 
  FK_Patient_Link_ID,
  CAST(MedicationDate AS DATE) AS MedicationDate,
  SuppliedCode,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID
INTO #PatientMedicationData
FROM [SharedCare].GP_Medications
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND MedicationDate < @TEMPRQ038EndDate;

-- Improve performance later with an index
DROP INDEX IF EXISTS medData ON #PatientMedicationData;
CREATE INDEX medData ON #PatientMedicationData (FK_Patient_Link_ID, MedicationDate) INCLUDE (SuppliedCode);

-- Get the EFI over time
--> EXECUTE query-patients-calculate-efi-over-time.sql all-patients:false gp-events-table:#PatientEventData gp-medications-table:#PatientMedicationData

-- Finally we just select from the EFI table with the required fields
SELECT
  FK_Patient_Link_ID AS PatientId,
  DateFrom,
  NumberOfDeficits
FROM #PatientEFIOverTime
ORDER BY FK_Patient_Link_ID, DateFrom;