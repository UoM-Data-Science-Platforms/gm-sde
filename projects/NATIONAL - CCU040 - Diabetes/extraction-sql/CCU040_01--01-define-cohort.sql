%md
# Define the main cohort

**Desciption** To define the main cohort - patients with DM and COVID

**Author** Richard Williams

**Github** [https://github.com/rw251/gm-idcr/tree/master/projects/NATIONAL-CCU040-Diabetes](https://github.com/rw251/gm-idcr/tree/master/projects/NATIONAL%20-%20CCU040%20-%20Diabetes)

**Date last updated** 2022-11-23

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
WHERE CODE IN (--diabetes codeset inserted
'4855003','5368009','5969009','8801005','11530004','44054006','46635009','49455004','51002006','70694009','73211009','75682002','111552007','127012008','127013003','127014009','190330002','190368000','190369008','190372001','190388001','190389009','190390000','201724008','230577008','237599002','237601000','237604008','237612000','237613005','237618001','237619009','268519009','284449005','290002008','313435000','313436004','314771006','314893005','314902007','314903002','314904008','395204000','401110002','408540003','413183008','420270002','420279001','420436000','420486006','420514000','420715001','420756003','420789003','420825003','420918009','421075007','421165007','421305000','421326000','421365002','421437000','421468001','421631007','421750000','421779007','421847006','421893009','421920002','421986006','422034002','422099009','422228004','426705001','426875007','427089005','428896009','443694000','444073006','445353002','609561005','609562003','609572000','703136005','703137001','703138006','713702000','713703005','713705003','713706002','719216001','724276006','735537007','735538002','735539005','737212004','739681000','768792007','768793002','768794008','789571005','789572003','816067005','368561000119102','71771000119100','112991000000101','1481000119100','335621000000101','368711000119106','385041000000108','82581000119105','368541000119101');

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
WHERE CODE IN (--diabetes-type-i codeset inserted
'46635009','190330002','190368000','190369008','190372001','290002008','313435000','314771006','314893005','401110002','420270002','420486006','420514000','420789003','420825003','420918009','421075007','421165007','421305000','421365002','421437000','421468001','421893009','421920002','422228004','426875007','428896009','444073006','703137001','713702000','713705003','739681000','789571005','789572003','368561000119102','71771000119100','82581000119105','368541000119101')
GROUP BY PatientId;

CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Cohort_DM_Type2
AS
SELECT PatientId, MIN(DATE) AS FirstDiagnosisDate
FROM dars_nic_391419_j3w9t_collab.CCU040_01_Cohort_DM_ALL
WHERE CODE IN (--diabetes-type-ii codeset inserted
'44054006','190388001','190389009','190390000','237599002','313436004','314902007','314903002','314904008','395204000','420279001','420436000','420715001','420756003','421326000','421631007','421750000','421779007','421847006','421986006','422034002','422099009','443694000','445353002','703136005','703138006','713703005','713706002','719216001','1481000119100')
GROUP BY PatientId;

-- SPLIT HERE --

-- Then get all the positive covid test patients (initially from
-- the GDPPR data as we're replicating a study that only had access
-- to GP data for COVID tests)
CREATE OR REPLACE GLOBAL TEMPORARY VIEW CCU040_01_CovidPatientsFromGDPPR
AS
SELECT NHS_NUMBER_DEID AS PatientId, MIN(DATE) AS FirstCovidPositiveDate
FROM dars_nic_391419_j3w9t_collab.gdppr_dars_nic_391419_j3w9t_archive
WHERE CODE IN (--covid-test-positive codeset inserted
'840533007','840539006','871553007','1322781000000102','1240511000000106','1240581000000104','12802201000006101','1240381000000105','1240391000000107','1240411000000107','1240421000000101','1300721000000109',
--covid-other-positive codeset inserted
'186747009','840539006','1240521000000100','1240531000000103','1240541000000107','1240551000000105','1240561000000108','1240571000000101','1321241000000105','1240751000000100','1300731000000106')
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