%md
# Define the main cohort (with SGSS)

**Desciption** To define the main cohort - patients with DM and COVID (from SGSS data)

**Author** Richard Williams

**Github** [https://github.com/rw251/gm-idcr/tree/master/projects/NATIONAL-CCU040-Diabetes](https://github.com/rw251/gm-idcr/tree/master/projects/NATIONAL%20-%20CCU040%20-%20Diabetes)

**Date last updated** /*__date__*/

## Notes

We find everyone with a COVID diagnosis who also had diabetes (type I or type II) at the time of their positive COVID test. We
then find the cohort of patients with COVID, but who do not have DM to act as potential matches. Finally for each person we also
work out their smoking status, LSOA and Townsend index.

The difference with the --01 script is that this uses the GDPPR and the SGSS data to define a covid positive test

## Input

Various tables created by running _CCU040_01--01-define-cohort.template_

--- SPLIT HERE ---

-- Now get all the positive covid test patients from the SGSS
-- which is the best source of information for covid positive
-- tests
CREATE OR REPLACE GLOBAL TEMPORARY VIEW CCU040_01_CovidPatientsFromSGSS
AS
SELECT PERSON_ID_DEID AS PatientId, MIN(Specimen_Date) AS FirstCovidPositiveDate
FROM dars_nic_391419_j3w9t_collab.sgss_dars_nic_391419_j3w9t_archive
WHERE Specimen_Date >= '2020-02-01'
GROUP BY PERSON_ID_DEID;

-- Make the table permanent for query performance
CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_CovidPatientsFromSGSS
AS
SELECT * FROM global_temp.CCU040_01_CovidPatientsFromSGSS;

--- SPLIT HERE ---

-- Find minimum COVID date using either GDPPR or SGSS - whichever comes first
CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_CovidPatients
AS
SELECT
  CASE WHEN a.PatientId IS NULL THEN b.PatientId ELSE a.PatientId END AS PatientId,
  CASE
    WHEN a.FirstCovidPositiveDate IS NULL THEN b.FirstCovidPositiveDate
    WHEN b.FirstCovidPositiveDate IS NULL THEN a.FirstCovidPositiveDate
    WHEN a.FirstCovidPositiveDate < b.FirstCovidPositiveDate THEN a.FirstCovidPositiveDate
    ELSE b.FirstCovidPositiveDate
  END AS FirstCovidPositiveDate
FROM dars_nic_391419_j3w9t_collab.CCU040_01_CovidPatientsFromSGSS a
FULL OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_CovidPatientsFromGDPPR b
ON a.PatientId = b.PatientId;

--- SPLIT HERE ---

-- Get the patient ids for the main cohort (diabetes + covid)
CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_SGSS_Main_Cohort_Ids
AS
SELECT PatientId FROM dars_nic_391419_j3w9t_collab.CCU040_01_Cohort_DM
INTERSECT
SELECT PatientId FROM dars_nic_391419_j3w9t_collab.CCU040_01_CovidPatients;

--- SPLIT HERE ---

-- Get the patient ids of people not in the cohort who may be matches for the main cohort
CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_SGSS_Potential_Match_Ids
AS
SELECT PatientId FROM dars_nic_391419_j3w9t_collab.CCU040_01_CovidPatients
EXCEPT
SELECT PatientId FROM dars_nic_391419_j3w9t_collab.CCU040_01_SGSS_Main_Cohort_Ids;

--- SPLIT HERE ---
--

CREATE TABLE IF NOT EXISTS dars_nic_391419_j3w9t_collab.CCU040_01_SGSS_Main_Cohort (
  PatientId string,
  Sex char(1),
  YearOfBirth INT,
  FirstCovidPositiveDate DATE
);

TRUNCATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_SGSS_Main_Cohort;

INSERT INTO dars_nic_391419_j3w9t_collab.CCU040_01_SGSS_Main_Cohort
SELECT PatientId, CASE WHEN SEX=1 THEN 'M' WHEN SEX=2 THEN 'F' ELSE 'U' END As Sex, YEAR(DATE_OF_BIRTH) AS YearOfBirth, FirstCovidPositiveDate
FROM dars_nic_391419_j3w9t_collab.CCU040_01_CovidPatients covid
  LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.curr302_patient_skinny_record skin
    ON PatientId = skin.NHS_NUMBER_DEID
WHERE PatientId IN (SELECT PatientId FROM dars_nic_391419_j3w9t_collab.CCU040_01_SGSS_Main_Cohort_Ids);

--- SPLIT HERE ---

CREATE TABLE IF NOT EXISTS dars_nic_391419_j3w9t_collab.CCU040_01_SGSS_Potential_Matches (
  PatientId string,
  Sex char(1),
  YearOfBirth INT,
  FirstCovidPositiveDate DATE
);

TRUNCATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_SGSS_Potential_Matches;

INSERT INTO dars_nic_391419_j3w9t_collab.CCU040_01_SGSS_Potential_Matches
SELECT PatientId, CASE WHEN SEX=1 THEN 'M' WHEN SEX=2 THEN 'F' ELSE 'U' END As Sex, YEAR(DATE_OF_BIRTH) AS YearOfBirth, FirstCovidPositiveDate
FROM dars_nic_391419_j3w9t_collab.CCU040_01_CovidPatients covid
  LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.curr302_patient_skinny_record skin
    ON PatientId = skin.NHS_NUMBER_DEID
WHERE PatientId IN (SELECT PatientId FROM dars_nic_391419_j3w9t_collab.CCU040_01_SGSS_Potential_Match_Ids);

--- SPLIT HERE ---

-- Create a holding table which will be populated with the patients and their matches
CREATE TABLE IF NOT EXISTS dars_nic_391419_j3w9t_collab.CCU040_01_SGSS_Patients_With_Matches (
  PatientId string,
  Sex string,
  YearOfBirth INT,
  FirstCovidPositiveDate DATE,
  PatientIdOfMatchingPatient string,
  YearOfBirthOfMatchingPatient INT,
  FirstCovidPositiveDateOfMatchingPatient DATE
);

TRUNCATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_SGSS_Patients_With_Matches;