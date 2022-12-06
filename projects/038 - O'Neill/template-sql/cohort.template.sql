--┌──────────────────┐
--│ Main cohort file │
--└──────────────────┘

-- OUTPUT: Data with the following fields
-- 	All individuals alive in Greater Manchester on 1 January 2020 who were 60 years of age 
--  or older on that day and who have had at least one COVID-19 positive test recorded in
--  their GP record. There are no exclusion criteria. Follow-up is until 30 June 2022

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
--  BMI, SBP, DBP, eGFR, HbA1x, VitD, FBC

TODO Dementia, MI,FBC

--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the temp end date until new legal basis
DECLARE @TEMPRQ038EndDate datetime;
SET @TEMPRQ038EndDate = '2022-06-01';

-- Build the main cohort
--> EXECUTE query-build-rq038-cohort.sql

-- Now the other stuff we need
--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-lsoa.sql
--> EXECUTE query-patient-townsend.sql

-- Get the admissions and lengths of stay post covid tests
--> EXECUTE query-get-admissions-and-length-of-stay-post-covid.sql all-patients:false

IF OBJECT_ID('tempdb..#PatientEventData') IS NOT NULL DROP TABLE #PatientEventData;
SELECT 
  FK_Patient_Link_ID,
  CAST(EventDate AS DATE) AS EventDate,
  SuppliedCode,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID,
  [Value]
INTO #PatientEventData
FROM [SharedCare].GP_Events
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate < @TEMPRQ038EndDate
AND UPPER([Value]) NOT LIKE '%[A-Z]%'; -- ignore any upper case values

IF OBJECT_ID('tempdb..#PatientMedicationData') IS NOT NULL DROP TABLE #PatientMedicationData;
SELECT 
  FK_Patient_Link_ID,
  CAST(MedicationDate AS DATE) AS MedicationDate,
  SuppliedCode,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID
INTO #PatientMedicationData
FROM [SharedCare].GP_Medications
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND MedicationDate < @TEMPRQ038EndDate
AND MedicationDate >= @MedicationsFromDate;

--> EXECUTE query-patients-with-post-covid-syndrome.sql start-date:2020-01-01 gp-events-table:#PatientEventData all-patients:false
--> EXECUTE query-get-covid-vaccines.sql gp-events-table:#PatientEventData gp-medications-table:#PatientMedicationData

--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:pagets-disease version:1 temp-table-name:#PatientDiagnosisPagetsDisease
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:hypertension version:1 temp-table-name:#PatientDiagnosisHypertension
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:diabetes-type-i version:1 temp-table-name:#PatientDiagnosisDiabetesTypeI
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:diabetes-type-ii version:1 temp-table-name:#PatientDiagnosisDiabetesTypeII
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:copd version:1 temp-table-name:#PatientDiagnosisCOPD
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:asthma version:1 temp-table-name:#PatientDiagnosisAsthma
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:severe-mental-illness version:1 temp-table-name:#PatientDiagnosisSMI
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


-- Get patient list of those with COVID death within 28 days of positive test
IF OBJECT_ID('tempdb..#COVIDDeath') IS NOT NULL DROP TABLE #COVIDDeath;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #COVIDDeath FROM SharedCare.COVID19
WHERE DeathWithin28Days = 'Y'
AND (
	(GroupDescription = 'Confirmed' AND SubGroupDescription != 'Negative') OR
	(GroupDescription = 'Tested' AND SubGroupDescription = 'Positive')
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate < @TEMPRQ037EndDate;

SELECT 
  pat.FK_Patient_Link_ID AS PatientId,
  yob.YearOfBirth,
  sex.Sex,
  pl.EthnicCategoryDescription AS Ethnicity,
  town.TownsendScoreHigherIsMoreDeprived,
  town.TownsendQuintileHigherIsMoreDeprived,
  lsoa.LSOA_Code AS LSOA,
  CASE WHEN pl.DeathDate < @TEMPRQ020EndDate THEN YEAR(pl.DeathDate) ELSE NULL END AS YearOfDeath,
  CASE WHEN pl.DeathDate < @TEMPRQ020EndDate THEN MONTH(pl.DeathDate) ELSE NULL END AS MonthOfDeath,
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
  smi.DateOfFirstDiagnosis AS DateOfSMI,
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
  egfr.DateOfFirstValue  AS DateOfEGFRBefore,
  egfr.Value AS ValueOfEGFRBefore,
  egfrPost.DateOfFirstValue AS DateOfEGFRAfter,
  egfrPost.Value AS ValueOfEGFRAfter,
  hba1c.DateOfFirstValue AS DateOfHBA1CBefore,
  hba1c.Value AS ValueOfHBA1CBefore,
  hba1cPost.DateOfFirstValue AS DateOfHBA1CAfter,
  hba1cPost.Value AS ValueOfHBA1CAfter,
  vitd.DateOfFirstValue  AS DateOfVitDBefore,
  vitd.Value AS ValueOfVitDBefore,
  vitdPost.DateOfFirstValue AS DateOfVitDAfter,
  vitdPost.Value AS ValueOfVitDAfter
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
LEFT OUTER JOIN #PatientDiagnosisSMI  smi ON smi.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
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