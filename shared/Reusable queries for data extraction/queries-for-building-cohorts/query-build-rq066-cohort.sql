--┌───────────────────────────────────────┐
--│ Define Cohort for RQ066: Long COVID   │
--└───────────────────────────────────────┘

-- OBJECTIVE: To build the cohort of patients needed for RQ066. This reduces
--						duplication of code in the template scripts. The cohort is any
--						patient with a suggestion of long covid. There is also a matched
--            cohort (3:1) on age, sex and date of covid test.
-- INPUT: No inputs
--
-- OUTPUT: Temp tables as follows:
-- #Patients - list of patient ids of the cohort

------------------------------------------------------------------------------

-- Table of all patients with a GP record
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT DISTINCT FK_Patient_Link_ID
INTO #Patients
FROM SharedCare.Patient
WHERE FK_Reference_Tenancy_ID=2
AND GPPracticeCode NOT LIKE 'ZZZ%';
-- 41s

--> EXECUTE query-patients-with-post-covid-syndrome.sql start-date:2020-01-01 gp-events-table:SharedCare.GP_Events all-patients:false
-- 2m48
--> EXECUTE query-patients-with-covid.sql start-date:2020-01-01 all-patients:false gp-events-table:SharedCare.GP_Events
-- 54s

--> EXECUTE query-patient-year-of-birth.sql
-- 26s
--> EXECUTE query-patient-sex.sql
-- 26s

-- Define the main cohort that will be matched
IF OBJECT_ID('tempdb..#MainCohort') IS NOT NULL DROP TABLE #MainCohort;
SELECT 
  c.FK_Patient_Link_ID,
  FirstCovidPositiveDate AS IndexDate,
  FirstPostCOVIDDiagnosisDate,
  FirstPostCOVIDReferralDate,
  FirstPostCOVIDAssessmentDate,
  Sex,
  YearOfBirth
INTO #MainCohort
FROM #CovidPatients c
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = c.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = c.FK_Patient_Link_ID
LEFT OUTER JOIN #PostCOVIDPatients pcp ON pcp.FK_Patient_Link_ID = c.FK_Patient_Link_ID
WHERE c.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PostCOVIDPatients);

-- Define the population of potential matches for the cohort
IF OBJECT_ID('tempdb..#PotentialMatches') IS NOT NULL DROP TABLE #PotentialMatches;
SELECT c.FK_Patient_Link_ID, FirstCovidPositiveDate AS IndexDate, Sex, YearOfBirth
INTO #PotentialMatches
FROM #CovidPatients c
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = c.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = c.FK_Patient_Link_ID
EXCEPT
SELECT FK_Patient_Link_ID, IndexDate, Sex, YearOfBirth FROM #MainCohort;

--> EXECUTE query-cohort-matching-yob-sex-index-date.sql index-date-flex:14 yob-flex:5

-- Get the matched cohort detail - same as main cohort
IF OBJECT_ID('tempdb..#MatchedCohort') IS NOT NULL DROP TABLE #MatchedCohort;
SELECT 
  c.MatchingPatientId AS FK_Patient_Link_ID,
  MatchingCovidPositiveDate AS IndexDate,
  Sex,
  MatchingYearOfBirth,
  PatientId AS PatientWhoIsMatched
INTO #MatchedCohort
FROM #CohortStore c
WHERE c.PatientId IN (SELECT FK_Patient_Link_ID FROM #PostCOVIDPatients);

-- Define a table with all the patient ids and index dates for the main cohort and the matched cohort
IF OBJECT_ID('tempdb..#PatientIdsAndIndexDates') IS NOT NULL DROP TABLE #PatientIdsAndIndexDates;
SELECT PatientId AS FK_Patient_Link_ID, IndexDate INTO #PatientIdsAndIndexDates FROM #CohortStore
UNION
SELECT MatchingPatientId, MatchingCovidPositiveDate FROM #CohortStore;

-- Filter Patients table to just those in the cohort, and those in the matched cohort
TRUNCATE TABLE #Patients;
INSERT INTO #Patients
SELECT FK_Patient_Link_ID
FROM #PatientIdsAndIndexDates;

-- Create a table of events for all the people in our cohort.
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