--┌───────────────────────┐
--│ Main cohort for RQ042 │
--└───────────────────────┘

----------------------- RDE CHECK ---------------------
-- George Tilston  - 7 April 2022 - via pull request --
-------------------------------------------------------

-- Cohort is patients who have visited the GP with a dental issue. Each row in the output
-- file corresponds to a single GP visit, so a person can appear multiple times

TODO Get codes from SNOMED codes for meds
TODO Get diagnosis codes

-- OUTPUT: Data with the following fields
--  - PatientId
--  - DateOfConsultation (YYYY/MM/DD)
--  - Age
--  - Sex
--  - LSOA
--  - Ethnicity
--  - PatientHasT1DM
--  - PatientHasT2DM
--  - PatientHasCANCER
--  - PatientHasCHD
--  - GPPracticeCode
--  - DiagnosisCodes (comma separated list of the dental diagnosis codes)
--  - PrescribedAntimicrobial (Y/N) (whether patient has a prescription for an antimicrobial on the consultation date)
--  - PrescribedAnalgesic (Y/N)
--  - PrescribedOpioid (Y/N)
--  - PrescribedBenzodiazepine (Y/N)
--  - ReferralToUrgentDentalCare (Y/N) OPTIONAL FIELD
--  - ReferralToOMFS (Y/N) OPTIONAL FIELD
--  - ReferralToAE (Y/N) OPTIONAL FIELD

--Just want the output, not the messages
SET NOCOUNT ON;

-- First get all the patients with dental issues
--> CODESET dental-problems:1
IF OBJECT_ID('tempdb..#DentalPatients') IS NOT NULL DROP TABLE #DentalPatients;
SELECT FK_Patient_Link_ID, CAST(EventDate AS DATE) AS ConsultationDate INTO #DentalPatients
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'dental-problems' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'dental-problems' AND Version = 1)
)
AND EventDate>'2018-12-31';

-- Table of all patients
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT DISTINCT FK_Patient_Link_ID INTO #Patients FROM #DentalPatients;

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
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);

IF OBJECT_ID('tempdb..#PatientMedicationData') IS NOT NULL DROP TABLE #PatientMedicationData;
SELECT 
  FK_Patient_Link_ID,
  CAST(MedicationDate AS DATE) AS MedicationDate,
  SuppliedCode,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID
INTO #PatientMedicationData
FROM [RLS].vw_GP_Medications
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);

--> EXECUTE query-patient-year-of-birth.sql
--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-lsoa.sql
--> EXECUTE query-patient-practice-and-ccg.sql

-- Now the comorbidities
--> CODESET diabetes-type-i:1
IF OBJECT_ID('tempdb..#PatientDiagnosesT1DM') IS NOT NULL DROP TABLE #PatientDiagnosesT1DM;
SELECT DISTINCT FK_Patient_Link_ID
INTO #PatientDiagnosesT1DM
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('diabetes-type-i') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('diabetes-type-i') AND [Version]=1))
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);

--> CODESET diabetes-type-ii:1
IF OBJECT_ID('tempdb..#PatientDiagnosesT2DM') IS NOT NULL DROP TABLE #PatientDiagnosesT2DM;
SELECT DISTINCT FK_Patient_Link_ID
INTO #PatientDiagnosesT2DM
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('diabetes-type-ii') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('diabetes-type-ii') AND [Version]=1))
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);

--> CODESET cancer:1
IF OBJECT_ID('tempdb..#PatientDiagnosesCANCER') IS NOT NULL DROP TABLE #PatientDiagnosesCANCER;
SELECT DISTINCT FK_Patient_Link_ID
INTO #PatientDiagnosesCANCER
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('cancer') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('cancer') AND [Version]=1))
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);

--> CODESET coronary-heart-disease:1
IF OBJECT_ID('tempdb..#PatientDiagnosesCHD') IS NOT NULL DROP TABLE #PatientDiagnosesCHD;
SELECT DISTINCT FK_Patient_Link_ID
INTO #PatientDiagnosesCHD
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('coronary-heart-disease') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('coronary-heart-disease') AND [Version]=1))
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);


-- Bring together for final output
SELECT 
  m.FK_Patient_Link_ID AS PatientId,
  m.ConsultationDate,
  yob.YearOfBirth,
  sex.Sex,
  lsoa.LSOA_Code AS LSOA,
  pl.EthnicCategoryDescription,
  --pl.DeathDate (not requested)
  CASE WHEN t1dm.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PatientHasT1DM,
  CASE WHEN t2dm.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PatientHasT2DM,
  CASE WHEN cancer.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PatientHasCANCER,
  CASE WHEN chd.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PatientHasCHD,
  practice.GPPracticeCode
  --  DiagnosisCodes (comma separated list of the dental diagnosis codes)
  --  PrescribedAntimicrobial (Y/N) (whether patient has a prescription for an antimicrobial on the consultation date) (0501)
  --  PrescribedAnalgesic (Y/N)  (analgesics 0407 OR non-opioid analgesics (040701/1501042))
  --  PrescribedOpioid (Y/N)(1501043/040702)
  --  PrescribedBenzodiazepine (Y/N)
  --  ReferralToUrgentDentalCare (Y/N) OPTIONAL FIELD
  --  ReferralToOMFS (Y/N) OPTIONAL FIELD
  --  ReferralToAE (Y/N) OPTIONAL FIELD
FROM #DentalPatients m
LEFT OUTER JOIN RLS.vw_Patient_Link pl ON pl.PK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientLSOA lsoa ON lsoa.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosesT1DM t1dm ON t1dm.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosesT2DM t2dm ON t2dm.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosesCANCER cancer ON cancer.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosesCHD chd ON chd.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientPractice practice on practice.FK_Patient_Link_ID = m.FK_Patient_Link_ID