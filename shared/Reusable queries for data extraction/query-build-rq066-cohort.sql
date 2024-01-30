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

--> EXECUTE query-patients-with-post-covid-syndrome.sql start-date:2020-01-01 gp-events-table:SharedCare.GP_Events all-patients:false
--> EXECUTE query-patients-with-covid.sql start-date:2020-01-01 all-patients:false gp-events-table:SharedCare.GP_Events

--> EXECUTE query-patient-year-of-birth.sql
--> EXECUTE query-patient-sex.sql

-- Define the main cohort that will be matched
IF OBJECT_ID('tempdb..#MainCohort') IS NOT NULL DROP TABLE #MainCohort;
SELECT 
  c.FK_Patient_Link_ID,
  FirstCovidPositiveDate AS IndexDate,
  FirstPostCOVIDDiagnosisDate,
  FirstPostCOVIDReferralDate,
  FirstPostCOVIDAssessmentDate
  Sex,
  YearOfBirth
INTO #MainCohort
FROM #CovidPatients c
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = c.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = c.FK_Patient_Link_ID
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

