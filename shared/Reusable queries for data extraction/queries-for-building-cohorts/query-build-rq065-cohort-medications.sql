--┌────────────────────────────────────────┐
--│ Get all medications for RQ065 cohort   │
--└────────────────────────────────────────┘

------------------------------------------------------------------------------

-- Create a table of medications for all the people in our cohort.
-- Just using SuppliedCode
-- 1. Patients with a FK_Reference_Coding_ID
IF OBJECT_ID('tempdb..#PatientMedicationData') IS NOT NULL DROP TABLE #PatientMedicationData;
SELECT 
  FK_Patient_Link_ID,
  CAST(MedicationDate AS DATE) AS MedicationDate,
  GPPracticeCode,
  Dosage,
  Units,
  Quantity,
  SuppliedCode
INTO #PatientMedicationData
FROM [SharedCare].GP_Medications
WHERE SuppliedCode IN (SELECT [Code] FROM #AllCodes)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);
--31s

-- 4. Add indexes for future speed increase
DROP INDEX IF EXISTS medicationData1 ON #PatientMedicationData;
CREATE INDEX medicationData1 ON #PatientMedicationData (SuppliedCode) INCLUDE (FK_Patient_Link_ID, MedicationDate);
--15s