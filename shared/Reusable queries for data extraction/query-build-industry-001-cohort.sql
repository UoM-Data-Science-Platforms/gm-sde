--┌───────────────────────────────────────────────────────────────────┐
--│ Define Cohort for Gendius project: patients with T2D but no CKD   │
--└───────────────────────────────────────────────────────────────────┘

-- OBJECTIVE: To build the cohort of patients needed for the Gendius
--		project. This reduces duplication of code in the template scripts.
--            
--    Index date = 2.5 years prior to extraction date. Adults who
--      (1) have a type 2 diabetes diagnosis before the date of extraction, 
-- 			(2) were registered with a GP in GM between the index and
--			    extraction date,
--      (3) at the index date:
--        - are alive,and
--        - do not have a diagnosis of CKD stage 3-5.

-- INPUT: A single variable:
--  - extraction-date: date - (YYYY-MM-DD) the date of the extract

-- OUTPUT: Four temp tables:
--  - #Patients - list of all patients in the cohort
--  -   - FK_Patient_Link_ID - int
--  - #Cohort - table with each patient in the cohort and dx details
--  -   - FK_Patient_Link_ID - int
--  -   - FirstT2dDiagnosisYear - int
--  -   - FirstT2dDiagnosisMonth  - int
--  -   - FirstCkdDiagnosisYear - int
--  -   - FirstCkdDiagnosisMonth - int
--  -   - DeathDate - date (YYYY-MM-DD)
--  - #PatientEventData - table with all GP_Event codes for cohort
--  - #PatientMedicationDate - table with all GP_Medication codes for cohort

-- Table of all patients (not necessarily with a GP record yet)
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT DISTINCT FK_Patient_Link_ID
INTO #Patients
FROM SharedCare.Patient
WHERE FK_Reference_Tenancy_ID=2;

-- Get first T2D diagnosis date
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:SharedCare.GP_Events code-set:diabetes-type-ii version:1 temp-table-name:#PatientT2D

-- For improved performance let's get all the events and medications for patients with T2D
TRUNCATE TABLE #Patients
INSERT INTO #Patients
SELECT FK_Patient_Link_ID FROM #PatientT2D;


-- Now we create a table of events for all the people in our cohort.
-- We do this for Ref_Coding_ID and SNOMED_ID separately for performance reasons.
-- 1. Patients with a FK_Reference_Coding_ID
IF OBJECT_ID('tempdb..#PatientEventData1') IS NOT NULL DROP TABLE #PatientEventData1;
SELECT 
  FK_Patient_Link_ID,
  CAST(EventDate AS DATE) AS EventDate,
  CASE WHEN ISNUMERIC([Value]) = 1 THEN CAST([Value] AS float) ELSE NULL END AS [Value],
  Units,
  SuppliedCode,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID
INTO #PatientEventData1
FROM [SharedCare].GP_Events
WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);
--23s

-- 2. Patients with a FK_Reference_SnomedCT_ID
IF OBJECT_ID('tempdb..#PatientEventData2') IS NOT NULL DROP TABLE #PatientEventData2;
SELECT 
  FK_Patient_Link_ID,
  CAST(EventDate AS DATE) AS EventDate,
  CASE WHEN ISNUMERIC([Value]) = 1 THEN CAST([Value] AS float) ELSE NULL END AS [Value],
  Units,
  SuppliedCode,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID
INTO #PatientEventData2
FROM [SharedCare].GP_Events
WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);
--23s

-- 3. Merge the 2 tables together
IF OBJECT_ID('tempdb..#PatientEventData') IS NOT NULL DROP TABLE #PatientEventData;
SELECT * INTO #PatientEventData FROM #PatientEventData1
UNION
SELECT * FROM #PatientEventData2;
--6s

-- 4. Add indexes for future speed increase
DROP INDEX IF EXISTS eventFKData1 ON #PatientEventData;
CREATE INDEX eventFKData1 ON #PatientEventData (FK_Reference_Coding_ID) INCLUDE (FK_Patient_Link_ID, EventDate, [Value], Units);
DROP INDEX IF EXISTS eventFKData2 ON #PatientEventData;
CREATE INDEX eventFKData2 ON #PatientEventData (FK_Reference_SnomedCT_ID) INCLUDE (FK_Patient_Link_ID, EventDate, [Value], Units);
DROP INDEX IF EXISTS eventFKData3 ON #PatientEventData;
CREATE INDEX eventFKData3 ON #PatientEventData (SuppliedCode) INCLUDE (FK_Patient_Link_ID, EventDate, [Value], Units);
--5s for both

-- Now we create a table of medications for all the people in our cohort.
-- Just using SuppliedCode
-- 1. Patients with a FK_Reference_Coding_ID
IF OBJECT_ID('tempdb..#PatientMedicationData') IS NOT NULL DROP TABLE #PatientMedicationData;
SELECT 
  FK_Patient_Link_ID,
  CAST(MedicationDate AS DATE) AS MedicationDate,
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

-- Get first CKD stage 3 diagnosis date
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:ckd-stage-3 version:1 temp-table-name:#PatientCKD3
-- Get first CKD stage 4 diagnosis date
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:ckd-stage-4 version:1 temp-table-name:#PatientCKD4
-- Get first CKD stage 5 diagnosis date
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:ckd-stage-5 version:1 temp-table-name:#PatientCKD5

-- Combine the 3 CKD stages into a single table
IF OBJECT_ID('tempdb..#PatientCKDAll') IS NOT NULL DROP TABLE #PatientCKDAll;
SELECT FK_Patient_Link_ID, DateOfFirstDiagnosis 
INTO #PatientCKDAll
FROM #PatientCKD3
UNION
SELECT * FROM #PatientCKD4
UNION
SELECT * FROM #PatientCKD5;

-- Then find the earliest diagnosis date for each patient
IF OBJECT_ID('tempdb..#PatientCKD') IS NOT NULL DROP TABLE #PatientCKD;
SELECT FK_Patient_Link_ID, MIN(DateOfFirstDiagnosis) AS DateOfFirstDiagnosis
INTO #PatientCKD
FROM #PatientCKDAll
GROUP BY FK_Patient_Link_ID;

IF OBJECT_ID('tempdb..#Cohort') IS NOT NULL DROP TABLE #Cohort;
SELECT 
	t2d.FK_Patient_Link_ID,
	YEAR(t2d.DateOfFirstDiagnosis) AS FirstT2dDiagnosisYear,
	MONTH(t2d.DateOfFirstDiagnosis) AS FirstT2dDiagnosisMonth, 
	YEAR(ckd.DateOfFirstDiagnosis) AS FirstCkdDiagnosisYear,
	MONTH(ckd.DateOfFirstDiagnosis) AS FirstCkdDiagnosisMonth,
  DeathDate
INTO #Cohort
FROM #PatientT2D t2d
LEFT OUTER JOIN #PatientCKD ckd ON t2d.FK_Patient_Link_ID = ckd.FK_Patient_Link_ID
LEFT OUTER JOIN SharedCare.Patient_Link pl ON pl.PK_Patient_Link_ID = t2d.FK_Patient_Link_ID
WHERE t2d.DateOfFirstDiagnosis < '{param:extraction-date}'
AND (DeathDate IS NULL OR DeathDate > DATEADD(month, -30, '2023-09-19'))
AND (ckd.DateOfFirstDiagnosis IS NULL OR ckd.DateOfFirstDiagnosis > DATEADD(month, -30, '{param:extraction-date}'));

TRUNCATE TABLE #Patients
INSERT INTO #Patients
SELECT FK_Patient_Link_ID FROM #Cohort;


