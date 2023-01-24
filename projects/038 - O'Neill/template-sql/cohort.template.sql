--┌──────────────────┐
--│ Main cohort file │
--└──────────────────┘

-- OUTPUT: Data with the following fields
-- 	All individuals alive in Greater Manchester on 1 January 2020 who were 60 years of age 
--  or older on that day and who have had at least one COVID-19 positive test recorded in
--  their GP record. There are no exclusion criteria. Follow-up is until 1st June 2022

--  UPDATE 21/12/22 - at recent SURG meeting approval given for ALL patients 60 or over so that
--  they have controls

--  DEMOGRAPHIC DATA 
--  PatientId, YearOfBirth, Sex, Ethnicity, Townsend index, Townsend Quintile, LSOA, MonthOfDeath, YearOfDeath
--  COVID DATA
--  DateofNthCovidPositive, DateOfHospitalisationFollowingNthCovid, LengthOfStayFollowingNthCovid,
--  DeathWithin28DaysCovidTest, DateOfNthVaccine, DateOfLongCovidDiagnosis, DateOfLongCovidAssessment,
--  DateOfLongCovidReferral
--  COMORBIDITIES
--  DateOfPagetsDisease, DateOfHypertension, DateOfDiabetes, DateOfCOPD, DateOfAsthma, DateOfSMI,
--  DateOfDementia, DateOfMI, DateOfAngina, DateOfHeartFailure,
--  DateOfStroke, DateOfRA
--  BIOMARKERS -  for all have ValueBeforeJan1, DateOfValueBeforeJan1, ValueOnOrAfterJan1, DateOfValueBeforeJan1
--  BMI, SBP, DBP, eGFR, HbA1x, VitD, FBC (= HB, WCC, Platelets), 

--Just want the output, not the messages
SET NOCOUNT ON;

DECLARE @StartDate datetime;
SET @StartDate = '2019-01-01';

-- Set the temp end date until new legal basis
DECLARE @TEMPRQ038EndDate datetime;
SET @TEMPRQ038EndDate = '2022-06-01';

-- Build the main cohort
--> EXECUTE query-build-rq038-cohort.sql

-- Now get all people with COVID positive test
--> EXECUTE query-patients-with-covid.sql start-date:2020-01-01 all-patients:true gp-events-table:SharedCare.GP_Events

-- Now the other stuff we need
--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-lsoa.sql
--> EXECUTE query-patient-townsend.sql

-- Get the admissions and lengths of stay post covid tests
--> EXECUTE query-get-admissions-and-length-of-stay-post-covid.sql all-patients:false

-- To optimise the patient event data table further (as there are so many patients),
-- we can initially split it into 3:
-- 1. Patients with a SuppliedCode in our list
IF OBJECT_ID('tempdb..#PatientEventData1') IS NOT NULL DROP TABLE #PatientEventData1;
SELECT 
  FK_Patient_Link_ID,
  CAST(EventDate AS DATE) AS EventDate,
  SuppliedCode,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID,
  [Value]
INTO #PatientEventData1
FROM [SharedCare].GP_Events
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND	SuppliedCode IN (SELECT Code FROM #AllCodes)
AND EventDate < '2022-06-01'
AND ([VALUE] IS NULL OR UPPER([Value]) NOT LIKE '%[A-Z]%'); -- ignore any upper case values
-- 1m

-- 2. Patients with a FK_Patient_Link_ID in our list
IF OBJECT_ID('tempdb..#PatientEventData2') IS NOT NULL DROP TABLE #PatientEventData2;
SELECT 
  FK_Patient_Link_ID,
  CAST(EventDate AS DATE) AS EventDate,
  SuppliedCode,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID,
  [Value]
INTO #PatientEventData2
FROM [SharedCare].GP_Events
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND	FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets)
AND EventDate < '2022-06-01'
AND ([VALUE] IS NULL OR UPPER([Value]) NOT LIKE '%[A-Z]%'); -- ignore any upper case values
--29s

-- 3. Patients with a FK_Reference_SnomedCT_ID in our list
IF OBJECT_ID('tempdb..#PatientEventData3') IS NOT NULL DROP TABLE #PatientEventData3;
SELECT 
  FK_Patient_Link_ID,
  CAST(EventDate AS DATE) AS EventDate,
  SuppliedCode,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID,
  [Value]
INTO #PatientEventData3
FROM [SharedCare].GP_Events
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets)
AND EventDate < '2022-06-01'
AND ([VALUE] IS NULL OR UPPER([Value]) NOT LIKE '%[A-Z]%'); -- ignore any upper case values

IF OBJECT_ID('tempdb..#PatientEventData') IS NOT NULL DROP TABLE #PatientEventData;
SELECT * INTO #PatientEventData FROM #PatientEventData1
UNION
SELECT * FROM #PatientEventData2
UNION
SELECT * FROM #PatientEventData3;

-- Improve performance later with an index (creates in ~1 minute - saves loads more than that)
DROP INDEX IF EXISTS eventData ON #PatientEventData;
CREATE INDEX eventData ON #PatientEventData (SuppliedCode) INCLUDE (FK_Patient_Link_ID, EventDate, [Value]);

-- 1. Patients with a SuppliedCode in our list
IF OBJECT_ID('tempdb..#PatientMedicationData1') IS NOT NULL DROP TABLE #PatientMedicationData1;
SELECT 
  FK_Patient_Link_ID,
  CAST(MedicationDate AS DATE) AS MedicationDate,
  SuppliedCode,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID
INTO #PatientMedicationData1
FROM [SharedCare].GP_Medications
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND	SuppliedCode IN (SELECT Code FROM #AllCodes)
AND MedicationDate < @TEMPRQ038EndDate;
-- 1m

-- 2. Patients with a FK_Patient_Link_ID in our list
IF OBJECT_ID('tempdb..#PatientMedicationData2') IS NOT NULL DROP TABLE #PatientMedicationData2;
SELECT 
  FK_Patient_Link_ID,
  CAST(MedicationDate AS DATE) AS MedicationDate,
  SuppliedCode,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID
INTO #PatientMedicationData2
FROM [SharedCare].GP_Medications
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND	FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets)
AND MedicationDate < @TEMPRQ038EndDate;
--29s

-- 3. Patients with a FK_Reference_SnomedCT_ID in our list
IF OBJECT_ID('tempdb..#PatientMedicationData3') IS NOT NULL DROP TABLE #PatientMedicationData3;
SELECT 
  FK_Patient_Link_ID,
  CAST(MedicationDate AS DATE) AS MedicationDate,
  SuppliedCode,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID
INTO #PatientMedicationData3
FROM [SharedCare].GP_Medications
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets)
AND MedicationDate < @TEMPRQ038EndDate;

IF OBJECT_ID('tempdb..#PatientMedicationData') IS NOT NULL DROP TABLE #PatientMedicationData;
SELECT * INTO #PatientMedicationData FROM #PatientMedicationData1
UNION
SELECT * FROM #PatientMedicationData2
UNION
SELECT * FROM #PatientMedicationData3;

-- Improve performance later with an index (creates in ~1 minute - saves loads more than that)
DROP INDEX IF EXISTS medData ON #PatientMedicationData;
CREATE INDEX medData ON #PatientMedicationData (SuppliedCode) INCLUDE (FK_Patient_Link_ID, MedicationDate);

--> EXECUTE query-patients-with-post-covid-syndrome.sql start-date:2020-01-01 gp-events-table:#PatientEventData all-patients:false
--> EXECUTE query-get-covid-vaccines.sql gp-events-table:#PatientEventData gp-medications-table:#PatientMedicationData

--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:pagets-disease version:1 temp-table-name:#PatientDiagnosisPagetsDisease
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:hypertension version:1 temp-table-name:#PatientDiagnosisHypertension
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:diabetes-type-i version:1 temp-table-name:#PatientDiagnosisDiabetesTypeI
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:diabetes-type-ii version:1 temp-table-name:#PatientDiagnosisDiabetesTypeII
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:copd version:1 temp-table-name:#PatientDiagnosisCOPD
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:asthma version:1 temp-table-name:#PatientDiagnosisAsthma
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:dementia version:1 temp-table-name:#PatientDiagnosisDementia
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:severe-mental-illness version:1 temp-table-name:#PatientDiagnosisSMI
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:myocardial-infarction version:1 temp-table-name:#PatientDiagnosisMI
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:angina version:1 temp-table-name:#PatientDiagnosisAngina
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:heart-failure version:1 temp-table-name:#PatientDiagnosisHeartFailure
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:rheumatoid-arthritis version:1 temp-table-name:#PatientDiagnosisRA
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:stroke version:1 temp-table-name:#PatientDiagnosisStroke



--> EXECUTE query-get-closest-value-to-date.sql code-set:bmi version:2 temp-table-name:#PostStartBMI date:2020-01-01 comparison:>= all-patients:false gp-events-table:#PatientEventData
--> EXECUTE query-get-closest-value-to-date.sql code-set:bmi version:2 temp-table-name:#PreStartBMI date:2020-01-01 comparison:< all-patients:false gp-events-table:#PatientEventData
--> EXECUTE query-get-closest-value-to-date.sql code-set:systolic-blood-pressure version:1 temp-table-name:#PostStartSBP date:2020-01-01 comparison:>= all-patients:false gp-events-table:#PatientEventData
--> EXECUTE query-get-closest-value-to-date.sql code-set:systolic-blood-pressure version:1 temp-table-name:#PreStartSBP date:2020-01-01 comparison:< all-patients:false gp-events-table:#PatientEventData
--> EXECUTE query-get-closest-value-to-date.sql code-set:diastolic-blood-pressure version:1 temp-table-name:#PostStartDBP date:2020-01-01 comparison:>= all-patients:false gp-events-table:#PatientEventData
--> EXECUTE query-get-closest-value-to-date.sql code-set:diastolic-blood-pressure version:1 temp-table-name:#PreStartDBP date:2020-01-01 comparison:< all-patients:false gp-events-table:#PatientEventData
--> EXECUTE query-get-closest-value-to-date.sql code-set:egfr version:1 temp-table-name:#PostStartEGFR date:2020-01-01 comparison:>= all-patients:false gp-events-table:#PatientEventData
--> EXECUTE query-get-closest-value-to-date.sql code-set:egfr version:1 temp-table-name:#PreStartEGFR date:2020-01-01 comparison:< all-patients:false gp-events-table:#PatientEventData
--> EXECUTE query-get-closest-value-to-date.sql code-set:hba1c version:2 temp-table-name:#PostStartHBA1C date:2020-01-01 comparison:>= all-patients:false gp-events-table:#PatientEventData
--> EXECUTE query-get-closest-value-to-date.sql code-set:hba1c version:2 temp-table-name:#PreStartHBA1C date:2020-01-01 comparison:< all-patients:false gp-events-table:#PatientEventData
--> EXECUTE query-get-closest-value-to-date.sql code-set:vitamin-d version:1 temp-table-name:#PostStartVitD date:2020-01-01 comparison:>= all-patients:false gp-events-table:#PatientEventData
--> EXECUTE query-get-closest-value-to-date.sql code-set:vitamin-d version:1 temp-table-name:#PreStartVitD date:2020-01-01 comparison:< all-patients:false gp-events-table:#PatientEventData

--> EXECUTE query-get-closest-value-to-date.sql code-set:haemoglobin version:1 temp-table-name:#PostStartHb date:2020-01-01 comparison:>= all-patients:false gp-events-table:#PatientEventData
--> EXECUTE query-get-closest-value-to-date.sql code-set:haemoglobin version:1 temp-table-name:#PreStartHb date:2020-01-01 comparison:< all-patients:false gp-events-table:#PatientEventData
--> EXECUTE query-get-closest-value-to-date.sql code-set:white-blood-cells version:1 temp-table-name:#PostStartWBC date:2020-01-01 comparison:>= all-patients:false gp-events-table:#PatientEventData
--> EXECUTE query-get-closest-value-to-date.sql code-set:white-blood-cells version:1 temp-table-name:#PreStartWBC date:2020-01-01 comparison:< all-patients:false gp-events-table:#PatientEventData
--> EXECUTE query-get-closest-value-to-date.sql code-set:platelets version:1 temp-table-name:#PostStartPlatelets date:2020-01-01 comparison:>= all-patients:false gp-events-table:#PatientEventData
--> EXECUTE query-get-closest-value-to-date.sql code-set:platelets version:1 temp-table-name:#PreStartPlatelets date:2020-01-01 comparison:< all-patients:false gp-events-table:#PatientEventData
--> EXECUTE query-get-closest-value-to-date.sql code-set:alkaline-phosphatase version:1 temp-table-name:#PostStartAlkalinePhosphatase date:2020-01-01 comparison:>= all-patients:false gp-events-table:#PatientEventData
--> EXECUTE query-get-closest-value-to-date.sql code-set:alkaline-phosphatase version:1 temp-table-name:#PreStartAlkalinePhosphatase date:2020-01-01 comparison:< all-patients:false gp-events-table:#PatientEventData
--> EXECUTE query-get-closest-value-to-date.sql code-set:corrected-calcium version:1 temp-table-name:#PostStartCorrectedCalcium date:2020-01-01 comparison:>= all-patients:false gp-events-table:#PatientEventData
--> EXECUTE query-get-closest-value-to-date.sql code-set:corrected-calcium version:1 temp-table-name:#PreStartCorrectedCalcium date:2020-01-01 comparison:< all-patients:false gp-events-table:#PatientEventData


-- Get patient list of those with COVID death within 28 days of positive test
IF OBJECT_ID('tempdb..#COVIDDeath') IS NOT NULL DROP TABLE #COVIDDeath;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #COVIDDeath FROM SharedCare.COVID19
WHERE (
	(GroupDescription = 'Confirmed' AND SubGroupDescription != 'Negative') OR
	(GroupDescription = 'Tested' AND SubGroupDescription = 'Positive')
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND DATEDIFF(day,EventDate,DeathDate) <= 28
AND EventDate < '2022-06-01';

SELECT 
  pat.FK_Patient_Link_ID AS PatientId,
  yob.YearOfBirth,
  sex.Sex,
  pl.EthnicCategoryDescription AS Ethnicity,
  town.TownsendScoreHigherIsMoreDeprived,
  town.TownsendQuintileHigherIsMoreDeprived,
  lsoa.LSOA_Code AS LSOA,
  CASE WHEN pl.DeathDate < @TEMPRQ038EndDate THEN YEAR(pl.DeathDate) ELSE NULL END AS YearOfDeath,
  CASE WHEN pl.DeathDate < @TEMPRQ038EndDate THEN MONTH(pl.DeathDate) ELSE NULL END AS MonthOfDeath,
  covid.FirstCovidPositiveDate, admission.FirstAdmissionPost1stCOVIDTest, los.LengthOfStay1stAdmission1stCOVIDTest,
  covid.SecondCovidPositiveDate, admission.FirstAdmissionPost2ndCOVIDTest, los.LengthOfStay1stAdmission2ndCOVIDTest,
  covid.ThirdCovidPositiveDate, admission.FirstAdmissionPost3rdCOVIDTest, los.LengthOfStay1stAdmission3rdCOVIDTest,
  covid.FourthCovidPositiveDate, admission.FirstAdmissionPost4thCOVIDTest, los.LengthOfStay1stAdmission4thCOVIDTest,
  covid.FifthCovidPositiveDate, admission.FirstAdmissionPost5thCOVIDTest, los.LengthOfStay1stAdmission5thCOVIDTest,
  CASE WHEN covidDeath.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS DeathWithin28DaysCovidPositiveTest,
  vacc.VaccineDose1Date AS FirstVaccineDate,
  vacc.VaccineDose2Date AS SecondVaccineDate,
  vacc.VaccineDose3Date AS ThirdVaccineDate,
  vacc.VaccineDose4Date AS FourthVaccineDate,
  vacc.VaccineDose5Date AS FifthVaccineDate,
  postCovid.FirstPostCOVIDDiagnosisDate AS DateOfLongCovidDiagnosis,
  postCovid.FirstPostCOVIDAssessmentDate AS DateOfLongCovidAssessment,
  postCovid.FirstPostCOVIDReferralDate AS DateOfLongCovidReferral,
  pagetsdisease.DateOfFirstDiagnosis AS DateOfPagetsDisease,
  hypertension.DateOfFirstDiagnosis AS DateOfHypertension,
  diabetestypei.DateOfFirstDiagnosis AS DateOfDiabetesTypeI,
  diabetestypeii.DateOfFirstDiagnosis AS DateOfDiabetesTypeII,
  copd.DateOfFirstDiagnosis AS DateOfCOPD,
  asthma.DateOfFirstDiagnosis AS DateOfAsthma,
  dementia.DateOfFirstDiagnosis AS DateOfDementia,
  smi.DateOfFirstDiagnosis AS DateOfSMI,
  mi.DateOfFirstDiagnosis AS DateOfMI,
  angina.DateOfFirstDiagnosis AS DateOfAngina,
  heartfailure.DateOfFirstDiagnosis AS DateOfHeartFailure,
  ra.DateOfFirstDiagnosis AS DateOfRA,
  stroke.DateOfFirstDiagnosis AS DateOfStroke,
  bmi.DateOfFirstValue AS DateOfBMIBefore,
  bmi.Value AS ValueOfBMIBefore,
  bmiPost.DateOfFirstValue AS DateOfBMIAfter,
  bmiPost.Value AS ValueOfBMIAfter,
  sbp.DateOfFirstValue AS DateOfSBPBefore,
  sbp.Value AS ValueOfSBPBefore,
  sbpPost.DateOfFirstValue AS DateOfSBPAfter,
  sbpPost.Value AS ValueOfSBPAfter,
  dbp.DateOfFirstValue AS DateOfDBPBefore,
  dbp.Value AS ValueOfDBPBefore,
  dbpPost.DateOfFirstValue AS DateOfDBPAfter,
  dbpPost.Value AS ValueOfDBPAfter,
  egfr.DateOfFirstValue AS DateOfEGFRBefore,
  egfr.Value AS ValueOfEGFRBefore,
  egfrPost.DateOfFirstValue AS DateOfEGFRAfter,
  egfrPost.Value AS ValueOfEGFRAfter,
  hba1c.DateOfFirstValue AS DateOfHBA1CBefore,
  hba1c.Value AS ValueOfHBA1CBefore,
  hba1cPost.DateOfFirstValue AS DateOfHBA1CAfter,
  hba1cPost.Value AS ValueOfHBA1CAfter,
  vitd.DateOfFirstValue AS DateOfVitDBefore,
  vitd.Value AS ValueOfVitDBefore,
  vitdPost.DateOfFirstValue AS DateOfVitDAfter,
  vitdPost.Value AS ValueOfVitDAfter,
  hb.DateOfFirstValue AS DateOfHaemoglobinBefore,
  hb.Value AS ValueOfHaemoglobinBefore,
  hbPost.DateOfFirstValue AS DateOfHaemoglobinAfter,
  hbPost.Value AS ValueOfHaemoglobinAfter,
  wbc.DateOfFirstValue AS DateOfWBCBefore,
  wbc.Value AS ValueOfWBCBefore,
  wbcPost.DateOfFirstValue AS DateOfWBCAfter,
  wbcPost.Value AS ValueOfWBCAfter,
  platelets.DateOfFirstValue AS DateOfPlateletsBefore,
  platelets.Value AS ValueOfPlateletsBefore,
  plateletsPost.DateOfFirstValue AS DateOfPlateletsAfter,
  plateletsPost.Value AS ValueOfPlateletsAfter,
  phosphatase.DateOfFirstValue AS DateOfAlkalinePhosphataseBefore,
  phosphatase.Value AS ValueOfAlkalinePhosphataseBefore,
  phosphatasePost.DateOfFirstValue AS DateOfAlkalinePhosphataseAfter,
  phosphatasePost.Value AS ValueOfAlkalinePhosphataseAfter,
  calcium.DateOfFirstValue AS DateOfCorrectedCalciumBefore,
  calcium.Value AS ValueOfCorrectedCalciumBefore,
  calciumPost.DateOfFirstValue AS DateOfCorrectedCalciumAfter,
  calciumPost.Value AS ValueOfCorrectedCalciumAfter
FROM #Patients pat
LEFT OUTER JOIN SharedCare.Patient_Link pl ON pl.PK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientLSOA lsoa ON lsoa.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientTownsend town ON town.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #CovidPatientsMultipleDiagnoses covid ON covid.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientsAdmissionsPostTest admission ON admission.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientsLOSPostTest los on los.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDDeath covidDeath ON covidDeath.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDVaccinations vacc ON vacc.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PostCOVIDPatients postCovid ON postCovid.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisPagetsDisease pagetsdisease ON pagetsdisease.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisHypertension hypertension ON hypertension.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisDiabetesTypeI  diabetestypei ON diabetestypei.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisDiabetesTypeII diabetestypeii ON diabetestypeii.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisCOPD copd ON copd.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisAsthma asthma ON asthma.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisDementia dementia ON dementia.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisSMI smi ON smi.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisMI mi ON mi.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisAngina angina ON angina.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisHeartFailure heartfailure ON heartfailure.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisRA ra ON ra.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisStroke stroke ON stroke.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PostStartBMI bmiPost ON bmiPost.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PreStartBMI bmi ON bmi.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PostStartSBP sbpPost ON sbpPost.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PreStartSBP sbp ON sbp.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PostStartDBP dbpPost ON dbpPost.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PreStartDBP dbp ON dbp.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PostStartEGFR egfrPost ON egfrPost.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PreStartEGFR egfr ON egfr.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PostStartHBA1C hba1cPost ON hba1cPost.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PreStartHBA1C hba1c ON hba1c.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PostStartVitD vitdPost ON vitdPost.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PreStartVitD vitd ON vitd.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PostStartHb hbPost ON hbPost.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PreStartHb hb ON hb.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PostStartWBC wbcPost ON wbcPost.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PreStartWBC wbc ON wbc.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PostStartPlatelets plateletsPost ON plateletsPost.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PreStartPlatelets platelets ON platelets.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PostStartAlkalinePhosphatase phosphatasePost ON phosphatasePost.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PreStartAlkalinePhosphatase phosphatase ON phosphatase.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PostStartCorrectedCalcium calciumPost ON calciumPost.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PreStartCorrectedCalcium calcium ON calcium.FK_Patient_Link_ID = pat.FK_Patient_Link_ID