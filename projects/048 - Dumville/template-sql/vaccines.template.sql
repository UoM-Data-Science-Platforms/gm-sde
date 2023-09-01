--┌───────────────┐
--│ Vaccine doses │
--└───────────────┘

--------------------- RDE CHECK ---------------------
-- Le Mai Parkes  - 25 May 2022 - via pull request --
-----------------------------------------------------

-- OUTPUT: Data with the following fields
--  - PatientId (int)
--  - VaccineDate (YYYYMMDD)


--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the end date
DECLARE @EndDate datetime;
SET @EndDate = '2022-07-01';

--> EXECUTE query-build-rq048-cohort.sql

-- As it's a small cohort, it's quicker to get all data in to a temp table
-- and then all subsequent queries will target that data
IF OBJECT_ID('tempdb..#PatientEventData') IS NOT NULL DROP TABLE #PatientEventData;
SELECT 
  FK_Patient_Link_ID,
  CAST(EventDate AS DATE) AS EventDate,
  SuppliedCode,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID,
  [Value]
INTO #PatientEventData
FROM SharedCare.GP_Events
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate < @EndDate;

IF OBJECT_ID('tempdb..#PatientMedicationData') IS NOT NULL DROP TABLE #PatientMedicationData;
SELECT 
  FK_Patient_Link_ID,
  CAST(MedicationDate AS DATE) AS MedicationDate,
  SuppliedCode,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID
INTO #PatientMedicationData
FROM SharedCare.GP_Medications
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND MedicationDate < @EndDate;

--> EXECUTE query-get-covid-vaccines.sql gp-events-table:#PatientEventData gp-medications-table:#PatientMedicationData

SELECT FK_Patient_Link_ID AS PatientId, EventDate AS VaccineDate FROM #COVIDVaccines
WHERE FK_Patient_Link_ID IN (SELECT PK_Patient_Link_ID FROM SharedCare.Patient_Link) --ensure we don't include opt-outs
ORDER BY FK_Patient_Link_ID, EventDate;