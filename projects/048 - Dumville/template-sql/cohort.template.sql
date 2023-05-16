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

-- Assume temp table #OxAtHome (FK_Patient_Link_ID, AdmissionDate, DischargeDate)

-- Remove admissions ahead of our cut-off date
DELETE FROM #OxAtHome WHERE AdmissionDate > '2022-06-01';

-- Censor discharges after cut-off to appear as NULL
UPDATE #OxAtHome SET DischargeDate = NULL WHERE DischargeDate > '2022-06-01';

-- Table of all patients (not matching cohort - will do that subsequently)
-- IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
-- SELECT FK_Patient_Link_ID INTO #Patients FROM #OxAtHome
-- WHERE AdmissionDate < '2022-07-01'
-- AND (DischargeDate IS NULL OR DischargeDate < '2022-07-01')
-- AND FK_Patient_Link_ID IN (SELECT PK_Patient_Link_ID FROM SharedCare.Patient_Link); --ensure we don't include opt-outs


-- Only include patients who were first registered at a GP practice prior
-- to June 2022. This is 1 month before COPI expired and so acts as a buffer.
-- If we only looked at patients who first registered before July 2022, then
-- there is a chance that their data was processed after COPI expired.
IF OBJECT_ID('tempdb..#PatientsToInclude') IS NOT NULL DROP TABLE #PatientsToInclude;
SELECT FK_Patient_Link_ID INTO #PatientsToInclude
FROM SharedCare.Patient_GP_History
GROUP BY FK_Patient_Link_ID
HAVING MIN(StartDate) < '2022-06-01';

-- Table of all patients with a GP record
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT DISTINCT FK_Patient_Link_ID
INTO #Patients
FROM SharedCare.Patient
WHERE FK_Reference_Tenancy_ID=2
AND GPPracticeCode NOT LIKE 'ZZZ%'
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

--> EXECUTE query-patients-with-covid.sql start-date:2020-01-01 all-patients:false gp-events-table:SharedCare.GP_Events
--> EXECUTE query-patient-year-of-birth.sql
--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-lsoa.sql
--> EXECUTE query-patient-imd.sql

-- define the main cohort and the factors that will be matched
IF OBJECT_ID('tempdb..#MainCohort') IS NOT NULL DROP TABLE #MainCohort;
SELECT 
  o.FK_Patient_Link_ID,
  AdmissionDate AS IndexDate,
  Sex,
  YearOfBirth, 
  CASE
		WHEN imd.IMD2019Decile1IsMostDeprived10IsLeastDeprived BETWEEN 1 AND 2 THEN 1
		WHEN imd.IMD2019Decile1IsMostDeprived10IsLeastDeprived BETWEEN 3 AND 4 THEN 2
		WHEN imd.IMD2019Decile1IsMostDeprived10IsLeastDeprived BETWEEN 5 AND 6 THEN 3
		WHEN imd.IMD2019Decile1IsMostDeprived10IsLeastDeprived BETWEEN 7 AND 8 THEN 4
		WHEN imd.IMD2019Decile1IsMostDeprived10IsLeastDeprived BETWEEN 9 AND 10 THEN 5
	END AS IMD2019Quintile1IsMostDeprived5IsLeastDeprived
INTO #MainCohort
FROM #Patients pat
INNER JOIN #OxAtHome o ON o.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientIMDDecile imd ON imd.FK_Patient_Link_ID = pat.FK_Patient_Link_ID;

-- define the pool of people from whom the matches can be extracted
IF OBJECT_ID('tempdb..#PotentialMatches') IS NOT NULL DROP TABLE #PotentialMatches;
SELECT 
  o.FK_Patient_Link_ID,
  FirstCovidPositiveDate AS IndexDate,
  Sex,
  YearOfBirth, 
  CASE
		WHEN imd.IMD2019Decile1IsMostDeprived10IsLeastDeprived BETWEEN 1 AND 2 THEN 1
		WHEN imd.IMD2019Decile1IsMostDeprived10IsLeastDeprived BETWEEN 3 AND 4 THEN 2
		WHEN imd.IMD2019Decile1IsMostDeprived10IsLeastDeprived BETWEEN 5 AND 6 THEN 3
		WHEN imd.IMD2019Decile1IsMostDeprived10IsLeastDeprived BETWEEN 7 AND 8 THEN 4
		WHEN imd.IMD2019Decile1IsMostDeprived10IsLeastDeprived BETWEEN 9 AND 10 THEN 5
	END AS IMD2019Quintile1IsMostDeprived5IsLeastDeprived
INTO #PotentialMatches
FROM #CovidPatientsMultipleDiagnoses o
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = o.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = o.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientIMDDecile imd ON imd.FK_Patient_Link_ID = o.FK_Patient_Link_ID
WHERE o.FK_Patient_Link_ID NOT IN (SELECT FK_Patient_Link_ID FROM #OxAtHome);



--> EXECUTE query-cohort-matching-yob-sex-imd-index-date.sql yob-flex:1 num-matches:15 index-date-flex:30

-- Reduce #Patients table to just ox patients and the matching cohort

TRUNCATE TABLE #Patients;
INSERT INTO #Patients
SELECT PatientId FROM #CohortStore
UNION
SELECT MatchingPatientId FROM #CohortStore;

--> EXECUTE query-patient-ltcs-code-sets.sql

-- 1. Patients with a FK_Patient_Link_ID in our list
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

-- 2. Patients with a FK_Reference_SnomedCT_ID in our list
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

IF OBJECT_ID('tempdb..#PatientEventData') IS NOT NULL DROP TABLE #PatientEventData;
SELECT * INTO #PatientEventData FROM #PatientEventData1
UNION
SELECT * FROM #PatientEventData2;
--3s

DROP INDEX IF EXISTS eventFKData1 ON #PatientEventData;
CREATE INDEX eventFKData1 ON #PatientEventData (FK_Reference_Coding_ID) INCLUDE (FK_Patient_Link_ID, EventDate);
DROP INDEX IF EXISTS eventFKData2 ON #PatientEventData;
CREATE INDEX eventFKData2 ON #PatientEventData (FK_Reference_SnomedCT_ID) INCLUDE (FK_Patient_Link_ID, EventDate);
--3s for both

-- 1. Patients with a FK_Patient_Link_ID in our list
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

-- 2. Patients with a FK_Reference_SnomedCT_ID in our list
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

IF OBJECT_ID('tempdb..#PatientMedicationData') IS NOT NULL DROP TABLE #PatientMedicationData;
SELECT * INTO #PatientMedicationData FROM #PatientMedicationData1
UNION
SELECT * FROM #PatientMedicationData2;
-- 5s

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
SELECT 
  m.*,
  o.AdmissionDate AS OximetryAtHomeStart,
  o.DischargeDate AS OximetryAtHomeEnd,
  FirstCovidPositiveDate,
  SecondCovidPositiveDate,
  ThirdCovidPositiveDate,
  YearOfBirth,
  Sex,
  LSOA_Code AS LSOA,
  EthnicCategoryDescription,
  IMD2019Decile1IsMostDeprived10IsLeastDeprived,
  MONTH(DeathDate) AS MonthOfDeath,
  YEAR(DeathDate) AS YearOfDeath,
  IsCareHomeResident
FROM #LTCOnIndexDate m
LEFT OUTER JOIN #OxAtHome o ON o.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #CovidPatientsMultipleDiagnoses cov ON cov.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientLSOA lsoa ON lsoa.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN SharedCare.Patient_Link pl ON pl.PK_Patient_Link_ID = m.FK_Patient_Link_ID --ethnicity and deathdate
LEFT OUTER JOIN #PatientIMDDecile imd ON imd.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientCareHomeStatus chs ON chs.FK_Patient_Link_ID = m.FK_Patient_Link_ID;