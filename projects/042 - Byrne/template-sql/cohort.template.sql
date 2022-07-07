--┌───────────────────────┐
--│ Main cohort for RQ042 │
--└───────────────────────┘

----------------------- RDE CHECK ---------------------
-- TBA --
-------------------------------------------------------

-- Cohort is patients who have visited the GP with a dental issue. Each row in the output
-- file corresponds to a single GP visit, so a person can appear multiple times

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
--  - DentalCodes (comma separated list of the dental diagnosis codes)
--  - PrescribedAntimicrobial (Y/N) (whether patient has a prescription for an antimicrobial on the consultation date)
--  - PrescribedAnalgesic (Y/N)
--  - PrescribedOpioid (Y/N)
--  - PrescribedBenzodiazepine (Y/N)
--  - ReferralToUrgentDentalCare (Y/N) OPTIONAL FIELD
--  - ReferralToOMFS (Y/N) OPTIONAL FIELD
--  - ReferralToAE (Y/N) OPTIONAL FIELD
--  - GPEncounter (Y/N) added our gp encounter logic to try and work out which dental issues arose from an encounter

--Just want the output, not the messages
SET NOCOUNT ON;

-- First get all the patients with dental issues
--> CODESET dental-problem:1
IF OBJECT_ID('tempdb..#DentalPatients') IS NOT NULL DROP TABLE #DentalPatients;
SELECT FK_Patient_Link_ID, CAST(EventDate AS DATE) AS ConsultationDate, STRING_AGG(SuppliedCode, '|') AS DentalCodes INTO #DentalPatients
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'dental-problem' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'dental-problem' AND Version = 1)
)
AND EventDate>'2018-12-31'
GROUP BY FK_Patient_Link_ID, CAST(EventDate AS DATE);

-- Table of all patients
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT DISTINCT FK_Patient_Link_ID INTO #Patients FROM #DentalPatients;

-- As it's a small cohort, it's quicker to get all data in to a temp table
-- and then all subsequent queries will target that data
IF OBJECT_ID('tempdb..#PatientEventData') IS NOT NULL DROP TABLE #PatientEventData;
SELECT 
  FK_Patient_Link_ID,
  CAST(EventDate AS DATE) AS EventDate,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID
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

-- Now get GP encounters
--> EXECUTE query-patient-gp-encounters.sql all-patients:false gp-events-table:#PatientEventData start-date:2018-12-31 end-date:2100-01-01

--> EXECUTE query-patient-year-of-birth.sql
--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-lsoa.sql
--> EXECUTE query-patient-practice-and-ccg.sql

-- Now the coprescribed meds
--> CODESET antibacterial-drugs:1
IF OBJECT_ID('tempdb..#PatientMedANTIBAC') IS NOT NULL DROP TABLE #PatientMedANTIBAC;
SELECT DISTINCT p.FK_Patient_Link_ID, p.MedicationDate INTO #PatientMedANTIBAC
FROM #PatientMedicationData p
INNER JOIN #DentalPatients d 
  ON p.FK_Patient_Link_ID = d.FK_Patient_Link_ID
  AND p.MedicationDate = d.ConsultationDate
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('antibacterial-drugs') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('antibacterial-drugs') AND [Version]=1))
);

--> CODESET non-opioid-analgesics:1
IF OBJECT_ID('tempdb..#PatientMedANALGESIC') IS NOT NULL DROP TABLE #PatientMedANALGESIC;
SELECT DISTINCT p.FK_Patient_Link_ID, p.MedicationDate INTO #PatientMedANALGESIC
FROM #PatientMedicationData p
INNER JOIN #DentalPatients d 
  ON p.FK_Patient_Link_ID = d.FK_Patient_Link_ID
  AND p.MedicationDate = d.ConsultationDate
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('non-opioid-analgesics') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('non-opioid-analgesics') AND [Version]=1))
);

--> CODESET opioid-analgesics:1
IF OBJECT_ID('tempdb..#PatientMedOPIOID') IS NOT NULL DROP TABLE #PatientMedOPIOID;
SELECT DISTINCT p.FK_Patient_Link_ID, p.MedicationDate INTO #PatientMedOPIOID
FROM #PatientMedicationData p
INNER JOIN #DentalPatients d 
  ON p.FK_Patient_Link_ID = d.FK_Patient_Link_ID
  AND p.MedicationDate = d.ConsultationDate
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('opioid-analgesics') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('opioid-analgesics') AND [Version]=1))
);

--> CODESET benzodiazepines:1
IF OBJECT_ID('tempdb..#PatientMedBENZOS') IS NOT NULL DROP TABLE #PatientMedBENZOS;
SELECT DISTINCT p.FK_Patient_Link_ID, p.MedicationDate INTO #PatientMedBENZOS
FROM #PatientMedicationData p
INNER JOIN #DentalPatients d 
  ON p.FK_Patient_Link_ID = d.FK_Patient_Link_ID
  AND p.MedicationDate = d.ConsultationDate
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('benzodiazepines') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('benzodiazepines') AND [Version]=1))
);

-- Now the comorbidities
--> CODESET diabetes-type-i:1
IF OBJECT_ID('tempdb..#PatientDiagnosesT1DM') IS NOT NULL DROP TABLE #PatientDiagnosesT1DM;
SELECT DISTINCT FK_Patient_Link_ID
INTO #PatientDiagnosesT1DM
FROM #PatientEventData
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('diabetes-type-i') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('diabetes-type-i') AND [Version]=1))
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);

--> CODESET diabetes-type-ii:1
IF OBJECT_ID('tempdb..#PatientDiagnosesT2DM') IS NOT NULL DROP TABLE #PatientDiagnosesT2DM;
SELECT DISTINCT FK_Patient_Link_ID
INTO #PatientDiagnosesT2DM
FROM #PatientEventData
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('diabetes-type-ii') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('diabetes-type-ii') AND [Version]=1))
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);

--> CODESET cancer:1
IF OBJECT_ID('tempdb..#PatientDiagnosesCANCER') IS NOT NULL DROP TABLE #PatientDiagnosesCANCER;
SELECT DISTINCT FK_Patient_Link_ID
INTO #PatientDiagnosesCANCER
FROM #PatientEventData
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('cancer') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('cancer') AND [Version]=1))
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);

--> CODESET coronary-heart-disease:1
IF OBJECT_ID('tempdb..#PatientDiagnosesCHD') IS NOT NULL DROP TABLE #PatientDiagnosesCHD;
SELECT DISTINCT FK_Patient_Link_ID
INTO #PatientDiagnosesCHD
FROM #PatientEventData
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
  practice.GPPracticeCode,
  m.DentalCodes,
  CASE WHEN antibac.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PrescribedAntimicrobial,--  PrescribedAntimicrobial (Y/N) (whether patient has a prescription for an antimicrobial on the consultation date) (0501)
  CASE WHEN analgesic.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PrescribedAnalgesic,--  PrescribedAnalgesic (Y/N)  (analgesics 0407 OR non-opioid analgesics (040701/1501042))
  CASE WHEN opioid.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PrescribedOpioid,--  PrescribedOpioid (Y/N)(1501043/040702)
  CASE WHEN benzos.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PrescribedBenzodiazepine, --  PrescribedBenzodiazepine (Y/N)
  CASE WHEN gp.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS GPEncounter --  (Y/N)
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
LEFT OUTER JOIN #PatientMedANTIBAC antibac on antibac.FK_Patient_Link_ID = m.FK_Patient_Link_ID and antibac.MedicationDate = m.ConsultationDate
LEFT OUTER JOIN #PatientMedANALGESIC analgesic on analgesic.FK_Patient_Link_ID = m.FK_Patient_Link_ID and analgesic.MedicationDate = m.ConsultationDate
LEFT OUTER JOIN #PatientMedOPIOID opioid on opioid.FK_Patient_Link_ID = m.FK_Patient_Link_ID and opioid.MedicationDate = m.ConsultationDate
LEFT OUTER JOIN #PatientMedBENZOS benzos on benzos.FK_Patient_Link_ID = m.FK_Patient_Link_ID and benzos.MedicationDate = m.ConsultationDate
LEFT OUTER JOIN #GPEncounters gp on gp.FK_Patient_Link_ID = m.FK_Patient_Link_ID and gp.EncounterDate = m.ConsultationDate;