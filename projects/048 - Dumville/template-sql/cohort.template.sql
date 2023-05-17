--┌──────────────────┐
--│ Main cohort file │
--└──────────────────┘

--------------------- RDE CHECK ---------------------
-- Le Mai Parkes  - 25 May 2022 - via pull request --
-----------------------------------------------------

-- OUTPUT: Data with the following fields
--  - PatientId (int)
--  - MatchingPatientId (int)
--  - OximetryAtHomeStart (YYYYMMDD - or blank if not used)
--  - OximetryAtHomeEnd (YYYYMMDD - or blank if not used or not discharged)
--  - FirstCovidPositiveDate (DDMMYYYY)
--  - SecondCovidPositiveDate (DDMMYYYY)
--  - ThirdCovidPositiveDate (DDMMYYYY)
--  - YearOfBirth (YYYY)
--  - Sex (M/F)
--  - LSOA
--  - Ethnicity
--  - IMD2019Decile1IsMostDeprived10IsLeastDeprived
--  - MonthOfDeath (MM)
--  - YearOfDeath (YYYY)
--  - IsCareHomeResident (Y/N)


--Just want the output, not the messages
SET NOCOUNT ON;

--> EXECUTE query-build-rq048-cohort.sql
--> EXECUTE query-patient-ltcs-code-sets.sql

-- Now we create a table of events for all the people in our cohort and the matched cohort.
-- We do this for Ref_Coding_ID and SNOMED_ID separately for performance reasons.
-- 1. Patients with a FK_Reference_Coding_ID in our list of LTCs
IF OBJECT_ID('tempdb..#PatientEventData1') IS NOT NULL DROP TABLE #PatientEventData1;
SELECT 
  FK_Patient_Link_ID,
  CAST(EventDate AS DATE) AS EventDate,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID
INTO #PatientEventData1
FROM [SharedCare].GP_Events
WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition NOT IN ('Constipation','Dyspepsia','Painful Condition','Migraine'))
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate < '2022-06-01';
--45s

-- 2. Patients with a FK_Reference_SnomedCT_ID in our list of LTCs
IF OBJECT_ID('tempdb..#PatientEventData2') IS NOT NULL DROP TABLE #PatientEventData2;
SELECT 
  FK_Patient_Link_ID,
  CAST(EventDate AS DATE) AS EventDate,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID
INTO #PatientEventData2
FROM [SharedCare].GP_Events
WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition NOT IN ('Constipation','Dyspepsia','Painful Condition','Migraine'))
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate < '2022-06-01';
--42s

-- 3. Merge the 2 tables together
IF OBJECT_ID('tempdb..#PatientEventData') IS NOT NULL DROP TABLE #PatientEventData;
SELECT * INTO #PatientEventData FROM #PatientEventData1
UNION
SELECT * FROM #PatientEventData2;
--3s

-- 4. Add indexes for future speed increase
DROP INDEX IF EXISTS eventFKData1 ON #PatientEventData;
CREATE INDEX eventFKData1 ON #PatientEventData (FK_Reference_Coding_ID) INCLUDE (FK_Patient_Link_ID, EventDate);
DROP INDEX IF EXISTS eventFKData2 ON #PatientEventData;
CREATE INDEX eventFKData2 ON #PatientEventData (FK_Reference_SnomedCT_ID) INCLUDE (FK_Patient_Link_ID, EventDate);
--3s for both

-- Now we do the same but for medications
-- 1. Patients with a FK_Reference_Coding_ID in our list of LTCs
IF OBJECT_ID('tempdb..#PatientMedicationData1') IS NOT NULL DROP TABLE #PatientMedicationData1;
SELECT 
  FK_Patient_Link_ID,
  CAST(MedicationDate AS DATE) AS MedicationDate,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID
INTO #PatientMedicationData1
FROM [SharedCare].GP_Medications
WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition in ('Irritable Bowel Syndrome','Constipation','Dyspepsia','Painful Condition','Epilepsy','Psoriasis Or Eczema','Migraine'))
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND MedicationDate < '2022-06-01';
--13s

-- 2. Patients with a FK_Reference_SnomedCT_ID in our list of LTCs
IF OBJECT_ID('tempdb..#PatientMedicationData2') IS NOT NULL DROP TABLE #PatientMedicationData2;
SELECT 
  FK_Patient_Link_ID,
  CAST(MedicationDate AS DATE) AS MedicationDate,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID
INTO #PatientMedicationData2
FROM [SharedCare].GP_Medications
WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition in ('Irritable Bowel Syndrome','Constipation','Dyspepsia','Painful Condition','Epilepsy','Psoriasis Or Eczema','Migraine'))
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND MedicationDate < '2022-06-01';
-- 13s

-- 3. Merge the 2 tables together
IF OBJECT_ID('tempdb..#PatientMedicationData') IS NOT NULL DROP TABLE #PatientMedicationData;
SELECT * INTO #PatientMedicationData FROM #PatientMedicationData1
UNION
SELECT * FROM #PatientMedicationData2;
-- 5s

-- 4. Add indexes for future speed increase
DROP INDEX IF EXISTS medFKData1 ON #PatientMedicationData;
CREATE INDEX medFKData1 ON #PatientMedicationData (FK_Reference_Coding_ID) INCLUDE (FK_Patient_Link_ID, MedicationDate);
DROP INDEX IF EXISTS medFKData2 ON #PatientMedicationData;
CREATE INDEX medFKData2 ON #PatientMedicationData (FK_Reference_SnomedCT_ID) INCLUDE (FK_Patient_Link_ID, MedicationDate);
-- 8s for both

-- Get all patients with their index dates to work out what LTCs they had at that point in time
IF OBJECT_ID('tempdb..#PatientsWithIndexDates') IS NOT NULL DROP TABLE #PatientsWithIndexDates;
SELECT PatientId AS FK_Patient_Link_ID, IndexDate INTO #PatientsWithIndexDates FROM #CohortStore
UNION
SELECT MatchingPatientId, MatchingIndexDate FROM #CohortStore;

--> EXECUTE query-patient-ltcs-at-index-date-without-code-sets.sql gp-events-table:#PatientEventData gp-medications-table:#PatientMedicationData

-- Get patient care home status
IF OBJECT_ID('tempdb..#PatientCareHomeStatus') IS NOT NULL DROP TABLE #PatientCareHomeStatus;
SELECT 
	FK_Patient_Link_ID,
	MAX(NursingCareHomeFlag) AS IsCareHomeResident -- max as Y > N > NULL
INTO #PatientCareHomeStatus
FROM SharedCare.Patient p
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND NursingCareHomeFlag IS NOT NULL
GROUP BY FK_Patient_Link_ID;

-- Bring together for final output
-- Main Ox cohort
SELECT
  m.*,
  NULL AS MatchingPatientId,
  ox.AdmissionDate AS OximetryAtHomeStart,
  ox.DischargeDate AS OximetryAtHomeEnd,
  cov.FirstCovidPositiveDate,
  cov.SecondCovidPositiveDate,
  cov.ThirdCovidPositiveDate,
  cohort.YearOfBirth,
  cohort.Sex,
  LSOA_Code AS LSOA,
  pl.EthnicCategoryDescription,
  cohort.IMD2019Quintile1IsMostDeprived5IsLeastDeprived,
  MONTH(pl.DeathDate) AS MonthOfDeath,
  YEAR(pl.DeathDate) AS YearOfDeath,
  chs.IsCareHomeResident
FROM #MainCohort cohort
LEFT OUTER JOIN #LTCOnIndexDate m ON m.PatientId = cohort.FK_Patient_Link_ID
LEFT OUTER JOIN #OximmetryPatients ox ON ox.FK_Patient_Link_ID = cohort.FK_Patient_Link_ID AND ox.AdmissionDate = cohort.IndexDate
LEFT OUTER JOIN #CovidPatientsMultipleDiagnoses cov ON cov.FK_Patient_Link_ID = cohort.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientLSOA lsoa ON lsoa.FK_Patient_Link_ID = cohort.FK_Patient_Link_ID
LEFT OUTER JOIN SharedCare.Patient_Link pl ON pl.PK_Patient_Link_ID = cohort.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientCareHomeStatus chs ON chs.FK_Patient_Link_ID = cohort.FK_Patient_Link_ID
UNION
-- matched cohort
select 
  m.*,
  cohort.PatientId AS MatchingPatientId,
  NULL AS OximetryAtHomeStart,
  NULL AS OximetryAtHomeEnd,
  cov.FirstCovidPositiveDate,
  cov.SecondCovidPositiveDate,
  cov.ThirdCovidPositiveDate,
  cohort.MatchingYearOfBirth,
  cohort.Sex,
  LSOA_Code AS LSOA,
  pl.EthnicCategoryDescription,
  cohort.IMD2019Quintile1IsMostDeprived5IsLeastDeprived,
  MONTH(pl.DeathDate) AS MonthOfDeath,
  YEAR(pl.DeathDate) AS YearOfDeath,
  chs.IsCareHomeResident
FROM #CohortStore cohort
LEFT OUTER JOIN #LTCOnIndexDate m ON m.PatientId = cohort.MatchingPatientId
LEFT OUTER JOIN #CovidPatientsMultipleDiagnoses cov ON cov.FK_Patient_Link_ID = cohort.MatchingPatientId
LEFT OUTER JOIN #PatientLSOA lsoa ON lsoa.FK_Patient_Link_ID = cohort.MatchingPatientId
LEFT OUTER JOIN SharedCare.Patient_Link pl ON pl.PK_Patient_Link_ID = cohort.MatchingPatientId
LEFT OUTER JOIN #PatientCareHomeStatus chs ON chs.FK_Patient_Link_ID = cohort.MatchingPatientId;