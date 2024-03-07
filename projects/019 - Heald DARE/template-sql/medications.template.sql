--┌─────────────────┐
--│ Medication file │
--└─────────────────┘

------------------------ RDE CHECK ---------------------
--------------------------------------------------------

-- Richard Williams - changes at 29th February 2024
-- PI requested:
--		- Longitudinal data for slgt2 inhibitors and metformin

-- Cohort is patients included in the DARE study. The below queries produce the data
-- that is required for each patient. However, a filter needs to be applied to only
-- provide this data for patients in the DARE study. Adrian Heald will provide GraphNet
-- with a list of NHS numbers, then they will execute the below but filtered to the list
-- of NHS numbers.

-- We assume that a temporary table will exist as follows:
-- CREATE TABLE #DAREPatients (NhsNo NVARCHAR(30));

--Just want the output, not the messages
SET NOCOUNT ON;

--Create DARECohort Table
SELECT SUBSTRING(REPLACE(NHSNo, ' ', ''),1,3) + ' ' + SUBSTRING(REPLACE(NHSNo, ' ', ''),4,3) + ' ' + SUBSTRING(REPLACE(NHSNo, ' ', ''),7,4) 'NHSNo' INTO #DAREPatients FROM [dbo].[DARECohort]

-- Get link ids of patients
SELECT DISTINCT FK_Patient_Link_ID INTO #Patients
FROM SharedCare.Patient p
INNER JOIN #DAREPatients dp ON dp.NhsNo = p.NhsNo;

-- Get lookup between nhs number and fk_patient_link_id
SELECT DISTINCT p.NhsNo, p.FK_Patient_Link_ID INTO #NhsNoToLinkId
FROM SharedCare.Patient p
INNER JOIN #DAREPatients dp ON dp.NhsNo = p.NhsNo;

--> CODESET sglt2-inhibitors:1 metformin:1

-- Create a table of medications for all the people in our cohort.
-- Just using SuppliedCode
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

-- Add indexes for future speed increase
DROP INDEX IF EXISTS medicationData1 ON #PatientMedicationData;
CREATE INDEX medicationData1 ON #PatientMedicationData (SuppliedCode) INCLUDE (FK_Patient_Link_ID, MedicationDate);
--15s

-- Final output
SELECT NhsNo, MedicationDate, a.description AS Medication, Units AS Method, Dosage As DosageInstruction, Quantity
FROM #PatientMedicationData m
LEFT OUTER JOIN #AllCodes a ON a.Code = SuppliedCode
INNER JOIN #NhsNoToLinkId n on n.FK_Patient_Link_ID = m.FK_Patient_Link_ID
WHERE SuppliedCode IN (SELECT [Code] FROM #AllCodes WHERE [Concept] IN ('sglt2-inhibitors','metformin') AND [Version] = 1)
ORDER BY NhsNo, MedicationDate;
