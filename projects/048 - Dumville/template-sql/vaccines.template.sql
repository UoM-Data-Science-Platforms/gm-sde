--┌───────────────┐
--│ Vaccine doses │
--└───────────────┘

-- OUTPUT: Data with the following fields
--  - PatientId (int)
--  - VaccineDate (YYYYMMDD)


--Just want the output, not the messages
SET NOCOUNT ON;

-- Assume temp table #OxAtHome (FK_Patient_Link_ID, AdmissionDate, DischargeDate)

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
FROM [RLS].vw_GP_Events
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #OxAtHome);

IF OBJECT_ID('tempdb..#PatientMedicationData') IS NOT NULL DROP TABLE #PatientMedicationData;
SELECT 
  FK_Patient_Link_ID,
  CAST(MedicationDate AS DATE) AS MedicationDate,
  SuppliedCode,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID
INTO #PatientMedicationData
FROM [RLS].vw_GP_Medications
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #OxAtHome);

--> EXECUTE query-get-covid-vaccines.sql gp-events-table:#PatientEventData gp-medications-table:#PatientMedicationData

SELECT FK_Patient_Link_ID AS PatientId, VaccineDoseDate FROM #COVIDVaccines
ORDER BY FK_Patient_Link_ID, VaccineDoseDate;