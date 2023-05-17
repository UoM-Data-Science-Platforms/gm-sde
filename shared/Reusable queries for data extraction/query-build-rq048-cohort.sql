--┌──────────────────────────────────────────┐
--│ Define Cohort for RQ048: Oximetry@Home   │
--└──────────────────────────────────────────┘

-- OBJECTIVE: To build the cohort of patients needed for RQ048. This reduces
--						duplication of code in the template scripts. The cohort is any
--						patient who was recruited into the Oximetry@Home programme. This
--            script also builds the matched cohort.
-- INPUT: None

-- OUTPUT: Temp tables as follows:
-- #Patients - list of patient ids of the cohort and matched cohort
-- #MainCohort - patient attributes for the ox@home patients
-- #CohortStore - output from the cohort matching
-- #OximmetryPatients - deduplicated version of the oximetry@home patients

------------------------------------------------------------------------------

-- Assume temp table #OxAtHome (FK_Patient_Link_ID, AdmissionDate, DischargeDate)

-- Remove admissions ahead of our cut-off date
DELETE FROM #OxAtHome WHERE AdmissionDate > '2022-06-01';

-- Censor discharges after cut-off to appear as NULL
UPDATE #OxAtHome SET DischargeDate = NULL WHERE DischargeDate > '2022-06-01';

-- Assume max discharge date in the case of multiple admission dates
IF OBJECT_ID('tempdb..#OximmetryPatients') IS NOT NULL DROP TABLE #OximmetryPatients;
SELECT FK_Patient_Link_ID, MAX(DischargeDate) AS DischargeDate, AdmissionDate
INTO #OximmetryPatients
FROM #OxAtHome
GROUP BY FK_Patient_Link_ID, AdmissionDate;

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
INNER JOIN #OximmetryPatients o ON o.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
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
WHERE o.FK_Patient_Link_ID NOT IN (SELECT FK_Patient_Link_ID FROM #OximmetryPatients);



--> EXECUTE query-cohort-matching-yob-sex-imd-index-date.sql yob-flex:1 num-matches:15 index-date-flex:30

-- Reduce #Patients table to just ox patients and the matching cohort
TRUNCATE TABLE #Patients;
INSERT INTO #Patients
SELECT PatientId FROM #CohortStore
UNION
SELECT MatchingPatientId FROM #CohortStore;