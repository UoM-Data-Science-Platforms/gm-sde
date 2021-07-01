--┌───────────────────────────────────┐
--│ Summary of death counts per month │
--└───────────────────────────────────┘

------------------------ RDE CHECK -------------------------
-- RDE NAME: ___, DATE OF CHECK: ___ -------
------------------------------------------------------------

-- Cohort is diabetic patients with a positive covid test. Also a 1:5 matched cohort, 
-- matched on year of birth (+-5 years), sex, and date of positive covid test (+-14 days).
-- For each we provide the following:

-- Table with the following columns:
--  - Year
--  - Month
--  - T1Population  - Number of T1DM patients in GM alive at the start of the month
--  - T1Deaths  - Number of T1DM patients in GM dying during the month
--  - T2Population  - Number of T2DM patients in GM alive at the start of the month
--  - T2Deaths  - Number of T2DM patients in GM dying during the month
--  - TotalPopulation  - Number of patients in GM alive at the start of the month
--  - TotalDeaths  - Number of patients in GM dying during the month

--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2019-01-01';

-- Get all patients with T1DM and the first diagnosis date
--> CODESET diabetes-type-i:1
IF OBJECT_ID('tempdb..#DiabeticTypeIPatients') IS NOT NULL DROP TABLE #DiabeticTypeIPatients;
SELECT FK_Patient_Link_ID, MIN(CAST(EventDate AS DATE)) AS FirstT1DiagnosisDate INTO #DiabeticTypeIPatients
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('diabetes-type-i') AND [Version]=1) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('diabetes-type-i') AND [Version]=1)
)
GROUP BY FK_Patient_Link_ID;

-- Get all patients with T2DM and the first diagnosis date
--> CODESET diabetes-type-ii:1
IF OBJECT_ID('tempdb..#DiabeticTypeIIPatients') IS NOT NULL DROP TABLE #DiabeticTypeIIPatients;
SELECT FK_Patient_Link_ID, MIN(CAST(EventDate AS DATE)) AS FirstT2DiagnosisDate INTO #DiabeticTypeIIPatients
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('diabetes-type-ii') AND [Version]=1) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('diabetes-type-ii') AND [Version]=1)
)
GROUP BY FK_Patient_Link_ID;

-- Get all patients with a GP


-- Get patient list of those with COVID death within 28 days of positive test
IF OBJECT_ID('tempdb..#COVIDDeath') IS NOT NULL DROP TABLE #COVIDDeath;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #COVIDDeath FROM RLS.vw_COVID19
WHERE DeathWithin28Days = 'Y';

-- Bring together for final output
-- Patients in main cohort
SELECT 
  m.FK_Patient_Link_ID AS PatientId,
  NULL AS MainCohortMatchedPatientId,
  YearOfBirth,
  DeathDate,
  CASE WHEN covidDeath.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS DeathWithin28DaysCovidPositiveTest,
  Sex,
  LSOA_Code AS LSOA,
  TownsendScoreHigherIsMoreDeprived,
  TownsendQuintileHigherIsMoreDeprived,
  FirstDiagnosisDate,
  FirstT1DiagnosisDate,
  FirstT2DiagnosisDate,
  IndexDate AS COVIDPositiveTestDate,
  FirstAdmissionPostCOVIDTest,
  LengthOfStay,
  EthnicCategoryDescription,
  LatestBMIValue,
  LatestHBA1CValue,
  LatestCHOLESTEROLValue,
  LatestLDLValue,
  LatestHDLValue,
  LatestVITAMINDValue,
  LatestTESTOSTERONEValue,
  LatestEGFRValue,
  LatestSHBGValue,
  smok.PassiveSmoker AS IsPassiveSmoker,
  smok.WorstSmokingStatus,
  smok.CurrentSmokingStatus,
  CASE WHEN copd.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PatientHasCOPD,
  CASE WHEN asthma.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PatientHasASTHMA,
  CASE WHEN smi.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PatientHasSMI,
  IsOnACEI,
  IsOnAspirin,
  IsOnClopidogrel,
  IsOnMetformin
FROM #MainCohort m
LEFT OUTER JOIN RLS.vw_Patient_Link pl ON pl.PK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientValuesBMI bmi ON bmi.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientTownsend town ON town.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientValuesHBA1C hba1c ON hba1c.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientValuesCHOLESTEROL cholesterol ON cholesterol.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientValuesLDL ldl ON ldl.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientValuesHDL hdl ON hdl.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientValuesVITAMIND vitamind ON vitamind.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientValuesTESTOSTERONE testosterone ON testosterone.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientValuesEGFR egfr ON egfr.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientValuesSHBG shbg ON shbg.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosesCOPD copd ON copd.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosesASTHMA asthma ON asthma.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosesSEVEREMENTALILLNESS smi ON smi.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientMedications pm ON pm.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSmokingStatus smok ON smok.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDDeath covidDeath ON covidDeath.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientsFirstAdmissionPostTest fa ON fa.FK_Patient_Link_ID = m.FK_Patient_Link_ID
UNION
--Patients in matched cohort
SELECT 
  m.FK_Patient_Link_ID AS PatientId,
  m.PatientWhoIsMatched AS MainCohortMatchedPatientId,
  MatchingYearOfBirth,
  DeathDate,
  CASE WHEN covidDeath.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS DeathWithin28DaysCovidPositiveTest,
  Sex,
  LSOA_Code AS LSOA,
  TownsendScoreHigherIsMoreDeprived,
  TownsendQuintileHigherIsMoreDeprived,
  NULL AS FirstDiagnosisDate,
  NULL AS FirstT1DiagnosisDate,
  NULL AS FirstT2DiagnosisDate,
  IndexDate AS COVIDPositiveTestDate,
  FirstAdmissionPostCOVIDTest,
  LengthOfStay,
  EthnicCategoryDescription,
  LatestBMIValue,
  LatestHBA1CValue,
  LatestCHOLESTEROLValue,
  LatestLDLValue,
  LatestHDLValue,
  LatestVITAMINDValue,
  LatestTESTOSTERONEValue,
  LatestEGFRValue,
  LatestSHBGValue,
  smok.PassiveSmoker AS IsPassiveSmoker,
  smok.WorstSmokingStatus,
  smok.CurrentSmokingStatus,
  CASE WHEN copd.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PatientHasCOPD,
  CASE WHEN asthma.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PatientHasASTHMA,
  CASE WHEN smi.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PatientHasSMI,
  IsOnACEI,
  IsOnAspirin,
  IsOnClopidogrel,
  IsOnMetformin
FROM #MatchedCohort m
LEFT OUTER JOIN RLS.vw_Patient_Link pl ON pl.PK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientValuesBMI bmi ON bmi.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientTownsend town ON town.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientValuesHBA1C hba1c ON hba1c.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientValuesCHOLESTEROL cholesterol ON cholesterol.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientValuesLDL ldl ON ldl.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientValuesHDL hdl ON hdl.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientValuesVITAMIND vitamind ON vitamind.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientValuesTESTOSTERONE testosterone ON testosterone.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientValuesEGFR egfr ON egfr.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientValuesSHBG shbg ON shbg.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosesCOPD copd ON copd.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosesASTHMA asthma ON asthma.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosesSEVEREMENTALILLNESS smi ON smi.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientMedications pm ON pm.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSmokingStatus smok ON smok.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDDeath covidDeath ON covidDeath.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientsFirstAdmissionPostTest fa ON fa.FK_Patient_Link_ID = m.FK_Patient_Link_ID;