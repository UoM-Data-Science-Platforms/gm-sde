--┌───────────────────────────────────────────────────────────────────┐
--│ Define Cohort for Gendius project: patients with T2D but no CKD   │
--└───────────────────────────────────────────────────────────────────┘

-- OBJECTIVE: To build the cohort of patients needed for the Gendius
--						project. This reduces duplication of code in the template 
--						scripts.

-- COHORT: Index date: 2.5 years prior to extract. Adults who have a
--					type 2 diabetes diagnosis before the date of extraction, 
-- 					were registered with a GP in GM between the index and
--					extraction date, at the index date:	are alive,and do not
--					have a diagnosis of CKD stage 3-5.

-- INPUT: A single variable:
--  - index-date: date - (YYYY-MM-DD) the date of the extract

TODO
- update OUTPUT section
- check CKD codes
- ensure only people alive at index date (2.5 years ago)
- think about whether registered at a GP in last 2.5 years
-- OUTPUT: TODO A temp table as follows:
-- #Cohort (FK_Patient_Link_ID)
-- #PatientEventData

-- Table of all patients (not necessarily with a GP record yet)
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT DISTINCT FK_Patient_Link_ID
INTO #Patients
FROM SharedCare.Patient
WHERE FK_Reference_Tenancy_ID=2;

-- Get first T2D diagnosis date
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:SharedCare.GP_Events code-set:diabetes-type-ii version:1 temp-table-name:#PatientT2D

-- Get first CKD diagnosis date
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:SharedCare.GP_Events code-set:chronic-kidney-disease version:1 temp-table-name:#PatientCKD

IF OBJECT_ID('tempdb..#Cohort') IS NOT NULL DROP TABLE #Cohort;
SELECT 
	t2d.FK_Patient_Link_ID,
	YEAR(t2d.DateOfFirstDiagnosis) * 100 + MONTH(t2d.DateOfFirstDiagnosis) AS YearMonthOfFirstT2DDiagnosis, 
	YEAR(ckd.DateOfFirstDiagnosis) * 100 + MONTH(ckd.DateOfFirstDiagnosis) AS YearMonthOfFirstCKDDiagnosis
INTO #Cohort
FROM #PatientT2D t2d
LEFT OUTER JOIN #PatientCKD ckd ON t2d.FK_Patient_Link_ID = ckd.FK_Patient_Link_ID
WHERE t2d.DateOfFirstDiagnosis < '{param:date}'
AND (ckd.DateOfFirstDiagnosis IS NULL OR ckd.DateOfFirstDiagnosis > DATEADD(month, -30, '{param:date}'));

TRUNCATE TABLE #Patients
INSERT INTO #Patients
SELECT FK_Patient_Link_ID FROM #Cohort;

