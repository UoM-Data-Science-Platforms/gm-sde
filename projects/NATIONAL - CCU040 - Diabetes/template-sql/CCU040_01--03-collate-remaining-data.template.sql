-- Define a table with all the patient ids and index dates for the main cohort and the matched cohort
CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Patient_Ids_And_Index_Dates
AS
SELECT PatientId, FirstCovidPositiveDate AS IndexDate FROM dars_nic_391419_j3w9t_collab.CCU040_01_Patients_With_Matches
UNION
SELECT PatientIdOfMatchingPatient, FirstCovidPositiveDateOfMatchingPatient FROM dars_nic_391419_j3w9t_collab.CCU040_01_Patients_With_Matches;

-- SPLIT HERE --

%run ./CCU040_01-smoking_status

--- SPLIT HERE ---

%run ./CCU040_01-lsoa $date="2020-01-01"

--- SPLIT HERE ---

%run ./CCU040_01-townsend $date="2020-01-01"

--- SPLIT HERE ---

-- Make the table permanent for query performance
CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Townsend
AS
SELECT * FROM global_temp.CCU040_Townsend
WHERE PatientId IN (SELECT PatientId FROM dars_nic_391419_j3w9t_collab.CCU040_01_Patient_Ids_And_Index_Dates);

-- SPLIT HERE --

-- Make the table permanent for query performance
CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Smoking_Status
AS
SELECT * FROM global_temp.CCU040_SmokingStatus
WHERE PatientId IN (SELECT PatientId FROM dars_nic_391419_j3w9t_collab.CCU040_01_Patient_Ids_And_Index_Dates);

-- SPLIT HERE --

-- SPLIT HERE --
--#region Biomarkers

-- Get all the patient values for key bio markers
--\> CODESET bmi:2 hba1c:2 cholesterol:2 ldl-cholesterol:1 hdl-cholesterol:1 vitamin-d:1 testosterone:1 sex-hormone-binding-globulin:1 egfr:1
CREATE OR REPLACE GLOBAL TEMPORARY VIEW CCU040_01_Patient_Values_With_Ids
AS
SELECT DISTINCT
	NHS_NUMBER_DEID AS PatientId,
	DATE AS EventDate,
  CODE,
	VALUE1_CONDITION AS Value
FROM dars_nic_391419_j3w9t_collab.gdppr_dars_nic_391419_j3w9t_archive
WHERE CODE IN (/*--bmi--*/,
/*--hba1c--*/,
/*--cholesterol--*/,
/*--ldl-cholesterol--*/,
/*--hdl-cholesterol--*/,
/*--egfr--*/)
AND NHS_NUMBER_DEID IN (SELECT PatientId FROM dars_nic_391419_j3w9t_collab.CCU040_01_Patient_Ids_And_Index_Dates)
AND DATE > '2018-01-01'
AND VALUE1_CONDITION IS NOT NULL
AND VALUE1_CONDITION != 0;

-- Make the table permanent for query performance
CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Patient_Values_With_Ids
AS
SELECT * FROM global_temp.CCU040_01_Patient_Values_With_Ids;

-- SPLIT HERE --

-- Find the most recent bmi value prior to covid diagnosis for each patient
CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Patient_bmi_value
AS
SELECT x.PatientId, MAX(Value) AS LatestBMIValue FROM (
  SELECT a.PatientId, MAX(EventDate) AS LatestBMIDate
  FROM dars_nic_391419_j3w9t_collab.CCU040_01_Patient_Ids_And_Index_Dates b
  LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patient_Values_With_Ids a
  ON a.PatientId = b.PatientId
  AND a.EventDate <= b.IndexDate
  AND a.EventDate >= b.IndexDate - INTERVAL '2 year'
  WHERE CODE IN (/*--bmi--*/)
  GROUP BY a.PatientId) x
INNER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patient_Values_With_Ids y
ON x.PatientId = y.PatientId
AND x.LatestBMIDate = y.EventDate
WHERE CODE IN (/*--bmi--*/)
GROUP BY x.PatientId;

-- SPLIT HERE --

-- Find the most recent hba1c value prior to covid diagnosis for each patient
CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Patient_hba1c_value
AS
SELECT x.PatientId, MAX(Value) AS LatestHBA1CValue FROM (
  SELECT a.PatientId, MAX(EventDate) AS LatestHBA1CDate
  FROM dars_nic_391419_j3w9t_collab.CCU040_01_Patient_Ids_And_Index_Dates b
  LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patient_Values_With_Ids a
  ON a.PatientId = b.PatientId
  AND a.EventDate <= b.IndexDate
  AND a.EventDate >= b.IndexDate - INTERVAL '2 year'
  WHERE CODE IN (/*--hba1c--*/)
  GROUP BY a.PatientId) x
INNER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patient_Values_With_Ids y
ON x.PatientId = y.PatientId
AND x.LatestHBA1CDate = y.EventDate
WHERE CODE IN (/*--hba1c--*/)
GROUP BY x.PatientId;

-- SPLIT HERE --

-- Find the most recent cholesterol value prior to covid diagnosis for each patient
CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Patient_cholesterol_value
AS
SELECT x.PatientId, MAX(Value) AS LatestCHOLESTEROLValue FROM (
  SELECT a.PatientId, MAX(EventDate) AS LatestCHOLESTEROLDate
  FROM dars_nic_391419_j3w9t_collab.CCU040_01_Patient_Ids_And_Index_Dates b
  LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patient_Values_With_Ids a
  ON a.PatientId = b.PatientId
  AND a.EventDate <= b.IndexDate
  AND a.EventDate >= b.IndexDate - INTERVAL '2 year'
  WHERE CODE IN (/*--cholesterol--*/)
  GROUP BY a.PatientId) x
INNER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patient_Values_With_Ids y
ON x.PatientId = y.PatientId
AND x.LatestCHOLESTEROLDate = y.EventDate
WHERE CODE IN (/*--cholesterol--*/)
GROUP BY x.PatientId;

-- SPLIT HERE --

-- Find the most recent ldl-cholesterol value prior to covid diagnosis for each patient
CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Patient_ldl_value
AS
SELECT x.PatientId, MAX(Value) AS LatestLDLValue FROM (
  SELECT a.PatientId, MAX(EventDate) AS LatestLDLDate
  FROM dars_nic_391419_j3w9t_collab.CCU040_01_Patient_Ids_And_Index_Dates b
  LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patient_Values_With_Ids a
  ON a.PatientId = b.PatientId
  AND a.EventDate <= b.IndexDate
  AND a.EventDate >= b.IndexDate - INTERVAL '2 year'
  WHERE CODE IN (/*--ldl-cholesterol--*/)
  GROUP BY a.PatientId) x
INNER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patient_Values_With_Ids y
ON x.PatientId = y.PatientId
AND x.LatestLDLDate = y.EventDate
WHERE CODE IN (/*--ldl-cholesterol--*/)
GROUP BY x.PatientId;

-- SPLIT HERE --

-- Find the most recent hdl-cholesterol value prior to covid diagnosis for each patient
CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Patient_hdl_value
AS
SELECT x.PatientId, MAX(Value) AS LatestHDLValue FROM (
  SELECT a.PatientId, MAX(EventDate) AS LatestHDLDate
  FROM dars_nic_391419_j3w9t_collab.CCU040_01_Patient_Ids_And_Index_Dates b
  LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patient_Values_With_Ids a
  ON a.PatientId = b.PatientId
  AND a.EventDate <= b.IndexDate
  AND a.EventDate >= b.IndexDate - INTERVAL '2 year'
  WHERE CODE IN (/*--hdl-cholesterol--*/)
  GROUP BY a.PatientId) x
INNER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patient_Values_With_Ids y
ON x.PatientId = y.PatientId
AND x.LatestHDLDate = y.EventDate
WHERE CODE IN (/*--hdl-cholesterol--*/)
GROUP BY x.PatientId;

-- SPLIT HERE --

-- Find the most recent egfr value prior to covid diagnosis for each patient
CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Patient_egfr_value
AS
SELECT x.PatientId, MAX(Value) AS LatestEGFRValue FROM (
  SELECT a.PatientId, MAX(EventDate) AS LatestEGFRDate
  FROM dars_nic_391419_j3w9t_collab.CCU040_01_Patient_Ids_And_Index_Dates b
  LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patient_Values_With_Ids a
  ON a.PatientId = b.PatientId
  AND a.EventDate <= b.IndexDate
  AND a.EventDate >= b.IndexDate - INTERVAL '2 year'
  WHERE CODE IN (/*--egfr--*/)
  GROUP BY a.PatientId) x
INNER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patient_Values_With_Ids y
ON x.PatientId = y.PatientId
AND x.LatestEGFRDate = y.EventDate
WHERE CODE IN (/*--egfr--*/)
GROUP BY x.PatientId;

--#endregion
-- SPLIT HERE --

-- For each patient find the first hospital admission following their positive covid test
-- We allow the test to be within 48 hours post admission and still count it
CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Patient_First_Admission_Post_COVID
AS
SELECT a.PatientId, MIN(b.ADMIDATE) AS FirstAdmissionPostCOVIDTest
FROM dars_nic_391419_j3w9t_collab.CCU040_01_Patient_Ids_And_Index_Dates a
  INNER JOIN dars_nic_391419_j3w9t_collab.hes_apc_all_years b
  ON a.PatientId = b.PERSON_ID_DEID
AND b.ADMIDATE >= a.IndexDate - INTERVAL '2 day'
GROUP BY a.PatientId;

-- SPLIT HERE --
CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Patient_First_Admission_Post_COVID_And_LOS
AS
SELECT x.PatientId, x.FirstAdmissionPostCOVIDTest, DATEDIFF(MAX(y.DISDATE), x.FirstAdmissionPostCOVIDTest) AS LengthOfStay
FROM dars_nic_391419_j3w9t_collab.CCU040_01_Patient_First_Admission_Post_COVID x
INNER JOIN dars_nic_391419_j3w9t_collab.hes_apc_all_years y
ON x.PatientId = y.PERSON_ID_DEID
AND x.FirstAdmissionPostCOVIDTest = y.ADMIDATE
GROUP BY x.PatientId, x.FirstAdmissionPostCOVIDTest;

-- SPLIT HERE --

-- Get all diagnoses into a single table for future use
CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Diagnoses
AS
SELECT DISTINCT
	NHS_NUMBER_DEID AS PatientId,
	DATE AS EventDate,
  CODE
FROM dars_nic_391419_j3w9t_collab.gdppr_dars_nic_391419_j3w9t_archive
WHERE CODE IN (/*--copd--*/,
/*--asthma--*/,
/*--hypertension--*/,
/*--smi--*/)
AND NHS_NUMBER_DEID IN (SELECT PatientId FROM dars_nic_391419_j3w9t_collab.CCU040_01_Patient_Ids_And_Index_Dates);

-- SPLIT HERE --

-- Get all medications into a single table for future use
CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Medications
AS
SELECT DISTINCT
	NHS_NUMBER_DEID AS PatientId,
	DATE AS EventDate,
  CODE
FROM dars_nic_391419_j3w9t_collab.gdppr_dars_nic_391419_j3w9t_archive
WHERE CODE IN (/*--metformin--*/,
/*--glp1--*/,
/*--insulin--*/,
/*--sglti--*/,
/*--sulphonylureas--*/,
/*--acei--*/,
/*--aspirin--*/,
/*--clopidogrel--*/)
AND NHS_NUMBER_DEID IN (SELECT PatientId FROM dars_nic_391419_j3w9t_collab.CCU040_01_Patient_Ids_And_Index_Dates)
AND DATE >= '2019-07-01';

-- SPLIT HERE --

-- Find patients with COPD at time of COVID diagnosis
CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Patients_With_COPD
AS
SELECT a.PatientId, MIN(EventDate) AS FirstDiagnosisDate
FROM dars_nic_391419_j3w9t_collab.CCU040_01_Patient_Ids_And_Index_Dates b
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Diagnoses a
ON a.PatientId = b.PatientId
AND a.EventDate <= b.IndexDate
WHERE CODE IN (/*--copd--*/)
GROUP BY a.PatientId;

-- SPLIT HERE --

-- Find patients with ASTHMA at time of COVID diagnosis
CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Patients_With_ASTHMA
AS
SELECT a.PatientId, MIN(EventDate) AS FirstDiagnosisDate
FROM dars_nic_391419_j3w9t_collab.CCU040_01_Patient_Ids_And_Index_Dates b
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Diagnoses a
ON a.PatientId = b.PatientId
AND a.EventDate <= b.IndexDate
WHERE CODE IN (/*--asthma--*/)
GROUP BY a.PatientId;

-- SPLIT HERE --

-- Find patients with HYPERTENSION at time of COVID diagnosis
CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Patients_With_HYPERTENSION
AS
SELECT a.PatientId, MIN(EventDate) AS FirstDiagnosisDate
FROM dars_nic_391419_j3w9t_collab.CCU040_01_Patient_Ids_And_Index_Dates b
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Diagnoses a
ON a.PatientId = b.PatientId
AND a.EventDate <= b.IndexDate
WHERE CODE IN (/*--hypertension--*/)
GROUP BY a.PatientId;

-- SPLIT HERE --

-- Find patients with SMI at time of COVID diagnosis
CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Patients_With_SMI
AS
SELECT a.PatientId, MIN(EventDate) AS FirstDiagnosisDate
FROM dars_nic_391419_j3w9t_collab.CCU040_01_Patient_Ids_And_Index_Dates b
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Diagnoses a
ON a.PatientId = b.PatientId
AND a.EventDate <= b.IndexDate
WHERE CODE IN (/*--smi--*/)
GROUP BY a.PatientId;

-- SPLIT HERE --

-- Find patients taking METFORMIN at the time of COVID diagnosis
CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Patients_On_METFORMIN
AS
SELECT a.PatientId, MAX(EventDate) AS MostRecentPrescriptionPriorToCovid
FROM dars_nic_391419_j3w9t_collab.CCU040_01_Patient_Ids_And_Index_Dates b
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Medications a
ON a.PatientId = b.PatientId
AND a.EventDate <= b.IndexDate
AND a.EventDate >= b.IndexDate - INTERVAL '6 month'
WHERE CODE IN (/*--metformin--*/)
GROUP BY a.PatientId;


-- Find patients taking GLP1 at the time of COVID diagnosis
CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Patients_On_GLP1
AS
SELECT a.PatientId, MAX(EventDate) AS MostRecentPrescriptionPriorToCovid
FROM dars_nic_391419_j3w9t_collab.CCU040_01_Patient_Ids_And_Index_Dates b
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Medications a
ON a.PatientId = b.PatientId
AND a.EventDate <= b.IndexDate
AND a.EventDate >= b.IndexDate - INTERVAL '6 month'
WHERE CODE IN (/*--glp1--*/)
GROUP BY a.PatientId;

-- SPLIT HERE --

-- Find patients taking INSULIN at the time of COVID diagnosis
CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Patients_On_INSULIN
AS
SELECT a.PatientId, MAX(EventDate) AS MostRecentPrescriptionPriorToCovid
FROM dars_nic_391419_j3w9t_collab.CCU040_01_Patient_Ids_And_Index_Dates b
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Medications a
ON a.PatientId = b.PatientId
AND a.EventDate <= b.IndexDate
AND a.EventDate >= b.IndexDate - INTERVAL '6 month'
WHERE CODE IN (/*--insulin--*/)
GROUP BY a.PatientId;

-- SPLIT HERE --

-- Find patients taking SGLTI at the time of COVID diagnosis
CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Patients_On_SGLTI
AS
SELECT a.PatientId, MAX(EventDate) AS MostRecentPrescriptionPriorToCovid
FROM dars_nic_391419_j3w9t_collab.CCU040_01_Patient_Ids_And_Index_Dates b
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Medications a
ON a.PatientId = b.PatientId
AND a.EventDate <= b.IndexDate
AND a.EventDate >= b.IndexDate - INTERVAL '6 month'
WHERE CODE IN (/*--sglti--*/)
GROUP BY a.PatientId;

-- SPLIT HERE --

-- Find patients taking SULPHONYLUREAS at the time of COVID diagnosis
CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Patients_On_SULPHONYLUREAS
AS
SELECT a.PatientId, MAX(EventDate) AS MostRecentPrescriptionPriorToCovid
FROM dars_nic_391419_j3w9t_collab.CCU040_01_Patient_Ids_And_Index_Dates b
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Medications a
ON a.PatientId = b.PatientId
AND a.EventDate <= b.IndexDate
AND a.EventDate >= b.IndexDate - INTERVAL '6 month'
WHERE CODE IN (/*--sulphonylureas--*/)
GROUP BY a.PatientId;

-- SPLIT HERE --

-- Find patients taking ACEI at the time of COVID diagnosis
CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Patients_On_ACEI
AS
SELECT a.PatientId, MAX(EventDate) AS MostRecentPrescriptionPriorToCovid
FROM dars_nic_391419_j3w9t_collab.CCU040_01_Patient_Ids_And_Index_Dates b
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Medications a
ON a.PatientId = b.PatientId
AND a.EventDate <= b.IndexDate
AND a.EventDate >= b.IndexDate - INTERVAL '6 month'
WHERE CODE IN (/*--acei--*/)
GROUP BY a.PatientId;

-- SPLIT HERE --

-- Find patients taking ASPIRIN at the time of COVID diagnosis
CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Patients_On_ASPIRIN
AS
SELECT a.PatientId, MAX(EventDate) AS MostRecentPrescriptionPriorToCovid
FROM dars_nic_391419_j3w9t_collab.CCU040_01_Patient_Ids_And_Index_Dates b
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Medications a
ON a.PatientId = b.PatientId
AND a.EventDate <= b.IndexDate
AND a.EventDate >= b.IndexDate - INTERVAL '6 month'
WHERE CODE IN (/*--aspirin--*/)
GROUP BY a.PatientId;

-- SPLIT HERE --

-- Find patients taking CLOPIDOGREL at the time of COVID diagnosis
CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Patients_On_CLOPIDOGREL
AS
SELECT a.PatientId, MAX(EventDate) AS MostRecentPrescriptionPriorToCovid
FROM dars_nic_391419_j3w9t_collab.CCU040_01_Patient_Ids_And_Index_Dates b
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Medications a
ON a.PatientId = b.PatientId
AND a.EventDate <= b.IndexDate
AND a.EventDate >= b.IndexDate - INTERVAL '6 month'
WHERE CODE IN (/*--clopidogrel--*/)
GROUP BY a.PatientId;

-- SPLIT HERE --

CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Patients_Demographics
AS
SELECT NHS_NUMBER_DEID, ETHNIC, SEX, DATE_OF_BIRTH, DATE_OF_DEATH
FROM dars_nic_391419_j3w9t_collab.curr302_patient_skinny_record
WHERE NHS_NUMBER_DEID IN (SELECT PatientId FROM dars_nic_391419_j3w9t_collab.CCU040_01_Patient_Ids_And_Index_Dates);

-- SPLIT HERE --

-- Get all the main cohort patients... and union with the matching patients
CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Output_Cohort_Table
AS
SELECT
  cohort.PatientId AS PatientId,
  CAST(NULL AS VARCHAR(50)) AS MainCohortMatchedPatientId,
  demo.DATE_OF_BIRTH AS YearOfBirth,
  demo.DATE_OF_DEATH AS DeathDate,
  CASE WHEN (demo.DATE_OF_DEATH < patients.IndexDate + INTERVAL '28 day') THEN 'Y' ELSE 'N' END AS DeathWithin28DaysCovidPositiveTest,
  demo.SEX AS Sex,
  town.LSOA,
  town.TownsendScoreHigherIsMoreDeprived,
  town.TownsendQuintileHigherIsMoreDeprived,
  dm.FirstDiagnosisDate,
  type1.FirstDiagnosisDate AS FirstT1DiagnosisDate,
  type2.FirstDiagnosisDate AS FirstT2DiagnosisDate,
  patients.IndexDate AS COVIDPositiveTestDate,
  admission.FirstAdmissionPostCOVIDTest,
  admission.LengthOfStay,
  demo.ETHNIC AS EthnicCategoryDescription,
  bmi.LatestBMIValue,
  hba1c.LatestHBA1CValue,
  cholesterol.LatestCHOLESTEROLValue,
  ldl.LatestLDLValue,
  hdl.LatestHDLValue,
  CAST(NULL AS DECIMAL(14,4)) AS LatestVITAMINDValue, --Not in gdppr - but keeping to preserve shape of table
  CAST(NULL AS DECIMAL(14,4)) AS LatestTESTOSTERONEValue, --Not in gdppr - but keeping to preserve shape of table
  egfr.LatestEGFRValue,
  CAST(NULL AS DECIMAL(14,4)) AS LatestSHBGValue, --Not in gdppr - but keeping to preserve shape of table
  '' AS IsPassiveSmoker, --Not in gdppr - but keeping to preserve shape of table
  smok.WorstSmokingStatus,
  smok.CurrentSmokingStatus,
  CASE WHEN (copd.PatientId IS NULL) THEN 'N' ELSE 'Y' END AS PatientHasCOPD,
  CASE WHEN (asthma.PatientId IS NULL) THEN 'N' ELSE 'Y' END AS PatientHasASTHMA,
  CASE WHEN (smi.PatientId IS NULL) THEN 'N' ELSE 'Y' END AS PatientHasSMI,
  CASE WHEN (acei.PatientId IS NULL) THEN 'N' ELSE 'Y' END AS IsOnACEIorARB,
  CASE WHEN (aspirin.PatientId IS NULL) THEN 'N' ELSE 'Y' END AS IsOnAspirin,
  CASE WHEN (clopidogrel.PatientId IS NULL) THEN 'N' ELSE 'Y' END AS IsOnClopidogrel,
  CASE WHEN (metformin.PatientId IS NULL) THEN 'N' ELSE 'Y' END AS IsOnMetformin,
  CASE WHEN (hypertension.PatientId IS NULL) THEN 'N' ELSE 'Y' END AS PatientHasHYPERTENSION,
  CASE WHEN (insulin.PatientId IS NULL) THEN 'N' ELSE 'Y' END AS IsOnInsulin,
  CASE WHEN (sglti.PatientId IS NULL) THEN 'N' ELSE 'Y' END AS IsOnSGLTI,
  CASE WHEN (glp1.PatientId IS NULL) THEN 'N' ELSE 'Y' END AS IsOnGLP1A,  
  CASE WHEN (sulphonylureas.PatientId IS NULL) THEN 'N' ELSE 'Y' END AS IsOnSulphonylurea
FROM dars_nic_391419_j3w9t_collab.CCU040_01_Main_Cohort_Ids cohort
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Cohort_DM dm ON cohort.PatientId = dm.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Cohort_DM_Type1 type1 ON cohort.PatientId = type1.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Cohort_DM_Type2 type2 ON cohort.PatientId = type2.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patients_Demographics demo ON cohort.PatientId = demo.NHS_NUMBER_DEID
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patient_Ids_And_Index_Dates patients ON cohort.PatientId = patients.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Townsend town ON cohort.PatientId = town.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patient_First_Admission_Post_COVID_And_LOS admission ON cohort.PatientId = admission.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patient_bmi_value bmi ON cohort.PatientId = bmi.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patient_hba1c_value hba1c ON cohort.PatientId = hba1c.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patient_cholesterol_value cholesterol ON cohort.PatientId = cholesterol.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patient_ldl_value ldl ON cohort.PatientId = ldl.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patient_hdl_value hdl ON cohort.PatientId = hdl.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patient_egfr_value egfr ON cohort.PatientId = egfr.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Smoking_Status smok ON cohort.PatientId = smok.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patients_With_COPD copd ON cohort.PatientId = copd.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patients_With_ASTHMA asthma ON cohort.PatientId = asthma.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patients_With_HYPERTENSION hypertension ON cohort.PatientId = hypertension.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patients_With_SMI smi ON cohort.PatientId = smi.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patients_On_METFORMIN metformin ON cohort.PatientId = metformin.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patients_On_GLP1 glp1 ON cohort.PatientId = glp1.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patients_On_INSULIN insulin ON cohort.PatientId = insulin.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patients_On_SGLTI sglti ON cohort.PatientId = sglti.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patients_On_SULPHONYLUREAS sulphonylureas ON cohort.PatientId = sulphonylureas.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patients_On_ACEI acei ON cohort.PatientId = acei.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patients_On_ASPIRIN aspirin ON cohort.PatientId = aspirin.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patients_On_CLOPIDOGREL clopidogrel ON cohort.PatientId = clopidogrel.PatientId
UNION
SELECT
  patients.PatientIdOfMatchingPatient AS PatientId,
  patients.PatientId AS MainCohortMatchedPatientId,
  demo.DATE_OF_BIRTH AS YearOfBirth,
  demo.DATE_OF_DEATH AS DeathDate,
  CASE WHEN (demo.DATE_OF_DEATH < patients.FirstCovidPositiveDateOfMatchingPatient + INTERVAL '28 day') THEN 'Y' ELSE 'N' END AS DeathWithin28DaysCovidPositiveTest,
  demo.SEX AS Sex,
  town.LSOA,
  town.TownsendScoreHigherIsMoreDeprived,
  town.TownsendQuintileHigherIsMoreDeprived,
  NULL AS FirstDiagnosisDate,
  NULL AS FirstT1DiagnosisDate,
  NULL AS FirstT2DiagnosisDate,
  patients.FirstCovidPositiveDateOfMatchingPatient AS COVIDPositiveTestDate,
  admission.FirstAdmissionPostCOVIDTest,
  admission.LengthOfStay,
  demo.ETHNIC AS EthnicCategoryDescription,
  bmi.LatestBMIValue,
  hba1c.LatestHBA1CValue,
  cholesterol.LatestCHOLESTEROLValue,
  ldl.LatestLDLValue,
  hdl.LatestHDLValue,
  NULL AS LatestVITAMINDValue, --Not in gdppr - but keeping to preserve shape of table
  NULL AS LatestTESTOSTERONEValue, --Not in gdppr - but keeping to preserve shape of table
  egfr.LatestEGFRValue,
  NULL AS LatestSHBGValue, --Not in gdppr - but keeping to preserve shape of table
  '' AS IsPassiveSmoker, --Not in gdppr - but keeping to preserve shape of table
  smok.WorstSmokingStatus,
  smok.CurrentSmokingStatus,
  CASE WHEN (copd.PatientId IS NULL) THEN 'N' ELSE 'Y' END AS PatientHasCOPD,
  CASE WHEN (asthma.PatientId IS NULL) THEN 'N' ELSE 'Y' END AS PatientHasASTHMA,
  CASE WHEN (smi.PatientId IS NULL) THEN 'N' ELSE 'Y' END AS PatientHasSMI,
  CASE WHEN (acei.PatientId IS NULL) THEN 'N' ELSE 'Y' END AS IsOnACEIorARB,
  CASE WHEN (aspirin.PatientId IS NULL) THEN 'N' ELSE 'Y' END AS IsOnAspirin,
  CASE WHEN (clopidogrel.PatientId IS NULL) THEN 'N' ELSE 'Y' END AS IsOnClopidogrel,
  CASE WHEN (metformin.PatientId IS NULL) THEN 'N' ELSE 'Y' END AS IsOnMetformin,
  CASE WHEN (hypertension.PatientId IS NULL) THEN 'N' ELSE 'Y' END AS PatientHasHYPERTENSION,
  CASE WHEN (insulin.PatientId IS NULL) THEN 'N' ELSE 'Y' END AS IsOnInsulin,
  CASE WHEN (sglti.PatientId IS NULL) THEN 'N' ELSE 'Y' END AS IsOnSGLTI,
  CASE WHEN (glp1.PatientId IS NULL) THEN 'N' ELSE 'Y' END AS IsOnGLP1A,  
  CASE WHEN (sulphonylureas.PatientId IS NULL) THEN 'N' ELSE 'Y' END AS IsOnSulphonylurea
FROM dars_nic_391419_j3w9t_collab.CCU040_01_Patients_With_Matches patients
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Cohort_DM dm ON patients.PatientIdOfMatchingPatient = dm.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patients_Demographics demo ON patients.PatientIdOfMatchingPatient = demo.NHS_NUMBER_DEID
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Townsend town ON patients.PatientIdOfMatchingPatient = town.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patient_First_Admission_Post_COVID_And_LOS admission ON patients.PatientIdOfMatchingPatient = admission.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patient_bmi_value bmi ON patients.PatientIdOfMatchingPatient = bmi.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patient_hba1c_value hba1c ON patients.PatientIdOfMatchingPatient = hba1c.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patient_cholesterol_value cholesterol ON patients.PatientIdOfMatchingPatient = cholesterol.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patient_ldl_value ldl ON patients.PatientIdOfMatchingPatient = ldl.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patient_hdl_value hdl ON patients.PatientIdOfMatchingPatient = hdl.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patient_egfr_value egfr ON patients.PatientIdOfMatchingPatient = egfr.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Smoking_Status smok ON patients.PatientIdOfMatchingPatient = smok.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patients_With_COPD copd ON patients.PatientIdOfMatchingPatient = copd.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patients_With_ASTHMA asthma ON patients.PatientIdOfMatchingPatient = asthma.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patients_With_HYPERTENSION hypertension ON patients.PatientIdOfMatchingPatient = hypertension.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patients_With_SMI smi ON patients.PatientIdOfMatchingPatient = smi.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patients_On_METFORMIN metformin ON patients.PatientIdOfMatchingPatient = metformin.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patients_On_GLP1 glp1 ON patients.PatientIdOfMatchingPatient = glp1.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patients_On_INSULIN insulin ON patients.PatientIdOfMatchingPatient = insulin.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patients_On_SGLTI sglti ON patients.PatientIdOfMatchingPatient = sglti.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patients_On_SULPHONYLUREAS sulphonylureas ON patients.PatientIdOfMatchingPatient = sulphonylureas.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patients_On_ACEI acei ON patients.PatientIdOfMatchingPatient = acei.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patients_On_ASPIRIN aspirin ON patients.PatientIdOfMatchingPatient = aspirin.PatientId
LEFT OUTER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Patients_On_CLOPIDOGREL clopidogrel ON patients.PatientIdOfMatchingPatient = clopidogrel.PatientId;