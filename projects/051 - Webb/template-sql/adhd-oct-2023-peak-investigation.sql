--> CODESET attention-deficit-hyperactivity-disorder-medications:1

IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT DISTINCT FK_Patient_Link_ID
INTO #Patients
FROM SharedCare.Patient
WHERE FK_Reference_Tenancy_ID=2
AND GPPracticeCode NOT LIKE 'ZZZ%';
-- 14s

--> EXECUTE query-patient-year-of-birth.sql
-- 15s

-- Max age is 24 and first year is 2019, so we can exclude everyone born in 1994 and before.
TRUNCATE TABLE #Patients;
INSERT INTO #Patients
SELECT FK_Patient_Link_ID FROM #PatientYearOfBirth WHERE YearOfBirth > 1994;

-- Creat a smaller version of GP event table------------------------------------------------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#GPMeds') IS NOT NULL DROP TABLE #GPMeds;
SELECT FK_Patient_Link_ID, CAST(MedicationDate AS DATE) AS MedicationDate, SuppliedCode
INTO #GPMeds
FROM SharedCare.GP_Medications
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND SuppliedCode IN (SELECT Code FROM #AllCodes);