%md
# Define the main cohort

**Desciption** To define the main cohort - patients with DM and COVID

**Author** Richard Williams

**Github** [https://github.com/rw251/gm-idcr/tree/master/projects/NATIONAL-CCU040-Diabetes](https://github.com/rw251/gm-idcr/tree/master/projects/NATIONAL%20-%20CCU040%20-%20Diabetes)

**Date last updated** /*__date__*/

## Notes

We find everyone with a COVID diagnosis who also had diabetes (type I or type II) at the time of their positive COVID test. We
then find the cohort of patients with COVID, but who do not have DM to act as potential matches. Finally for each person we also
work out their smoking status, LSOA and Townsend index.

## Input

No prerequisites

-- SPLIT HERE --

-- Get temp view containing all patients with any dm diagnosis
CREATE OR REPLACE GLOBAL TEMPORARY VIEW CCU040_01_Cohort_DM_ALL
AS
SELECT NHS_NUMBER_DEID AS PatientId, CODE, DATE
FROM dars_nic_391419_j3w9t_collab.gdppr_dars_nic_391419_j3w9t_archive
WHERE CODE IN (/*--diabetes--*/);

-- Crystallize to a permanent table for improved performance later
CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Cohort_DM_ALL
AS
SELECT * FROM global_temp.CCU040_01_Cohort_DM_ALL;

--- SPLIT HERE ---

-- Get separate cohorts for all dm, type 1 and type 2
CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Cohort_DM
AS
SELECT PatientId, MIN(DATE) AS FirstDiagnosisDate
FROM dars_nic_391419_j3w9t_collab.CCU040_01_Cohort_DM_ALL
GROUP BY PatientId;

CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Cohort_DM_Type1
AS
SELECT PatientId, MIN(DATE) AS FirstDiagnosisDate
FROM dars_nic_391419_j3w9t_collab.CCU040_01_Cohort_DM_ALL
WHERE CODE IN (/*--diabetes-type-i--*/)
GROUP BY PatientId;

CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Cohort_DM_Type2
AS
SELECT PatientId, MIN(DATE) AS FirstDiagnosisDate
FROM dars_nic_391419_j3w9t_collab.CCU040_01_Cohort_DM_ALL
WHERE CODE IN (/*--diabetes-type-ii--*/)
GROUP BY PatientId;

-- SPLIT HERE --

-- Then get all the positive covid test patients (initially from
-- the GDPPR data as we're replicating a study that only had access
-- to GP data for COVID tests)
CREATE OR REPLACE GLOBAL TEMPORARY VIEW CCU040_01_CovidPatientsFromGDPPR
AS
SELECT NHS_NUMBER_DEID AS PatientId, MIN(DATE) AS FirstCovidPositiveDate
FROM dars_nic_391419_j3w9t_collab.gdppr_dars_nic_391419_j3w9t_archive
WHERE CODE IN (/*--covid-test-positive--*/,
/*--covid-other-positive--*/)
AND DATE >= '2020-02-01' -- First UK case in feb 2020. Also lots of people appear to have one on 1st Jan 2020 which is clearly incorrect
GROUP BY NHS_NUMBER_DEID;

-- Make the table permanent for query performance
CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_CovidPatientsFromGDPPR
AS
SELECT * FROM global_temp.CCU040_01_CovidPatientsFromGDPPR;

--- SPLIT HERE ---

-- Get the patient ids for the main cohort (diabetes + covid)
CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Main_Cohort_Ids
AS
SELECT PatientId FROM dars_nic_391419_j3w9t_collab.CCU040_01_Cohort_DM
INTERSECT
SELECT PatientId FROM dars_nic_391419_j3w9t_collab.CCU040_01_CovidPatientsFromGDPPR;

--- SPLIT HERE ---

-- Get the patient ids of people not in the cohort who may be matches for the main cohort
CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Potential_Match_Ids
AS
SELECT PatientId FROM dars_nic_391419_j3w9t_collab.CCU040_01_CovidPatientsFromGDPPR
EXCEPT
SELECT PatientId FROM dars_nic_391419_j3w9t_collab.CCU040_01_Main_Cohort_Ids;

--- SPLIT HERE ---
--

CREATE TABLE IF NOT EXISTS dars_nic_391419_j3w9t_collab.CCU040_01_Main_Cohort (
  PatientId string,
  Sex char(1),
  YearOfBirth INT,
  FirstCovidPositiveDate DATE
);

TRUNCATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Main_Cohort;

INSERT INTO dars_nic_391419_j3w9t_collab.CCU040_01_Main_Cohort
SELECT PatientId, CASE WHEN SEX=1 THEN 'M' WHEN SEX=2 THEN 'F' ELSE 'U' END As Sex, YEAR(DATE_OF_BIRTH) AS YearOfBirth, FirstCovidPositiveDate
FROM dars_nic_391419_j3w9t_collab.CCU040_01_CovidPatientsFromGDPPR covid
  LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.curr302_patient_skinny_record skin
    ON PatientId = skin.NHS_NUMBER_DEID
WHERE PatientId IN (SELECT PatientId FROM dars_nic_391419_j3w9t_collab.CCU040_01_Main_Cohort_Ids);

--- SPLIT HERE ---

CREATE TABLE IF NOT EXISTS dars_nic_391419_j3w9t_collab.CCU040_01_Potential_Matches (
  PatientId string,
  Sex char(1),
  YearOfBirth INT,
  FirstCovidPositiveDate DATE
);

TRUNCATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Potential_Matches;

INSERT INTO dars_nic_391419_j3w9t_collab.CCU040_01_Potential_Matches
SELECT PatientId, CASE WHEN SEX=1 THEN 'M' WHEN SEX=2 THEN 'F' ELSE 'U' END As Sex, YEAR(DATE_OF_BIRTH) AS YearOfBirth, FirstCovidPositiveDate
FROM dars_nic_391419_j3w9t_collab.CCU040_01_CovidPatientsFromGDPPR covid
  LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.curr302_patient_skinny_record skin
    ON PatientId = skin.NHS_NUMBER_DEID
WHERE PatientId IN (SELECT PatientId FROM dars_nic_391419_j3w9t_collab.CCU040_01_Potential_Match_Ids);

--- SPLIT HERE ---

-- Create a holding table which will be populated with the patients and their matches
CREATE TABLE IF NOT EXISTS dars_nic_391419_j3w9t_collab.CCU040_01_Patients_With_Matches (
  PatientId string,
  Sex string,
  YearOfBirth INT,
  FirstCovidPositiveDate DATE,
  PatientIdOfMatchingPatient string,
  YearOfBirthOfMatchingPatient INT,
  FirstCovidPositiveDateOfMatchingPatient DATE
);

TRUNCATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Patients_With_Matches;