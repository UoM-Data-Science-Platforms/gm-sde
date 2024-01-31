--┌────────────────────────────┐
--│ Main cohort file for RQ066 │
--└────────────────────────────┘

-- OUTPUT: Data with the following fields
-- 	- PatientId (int)
--  - DateOfFirstDiagnosis (YYYY-MM-DD) 

-- Patient ID
-- Sex
-- Year of Birth
-- Ethnicity
-- Townsend Score
-- GP practice code
-- BMI values
-- Dates of positive COVID-19 test
-- Date of hospitalisations
-- Dates of COVID-19 vaccinations
-- Month of Death recorded (any causes)
-- Major comorbidities including type 1 diabetes, type 2 diabetes, asthma, COPD, angina, heart failure, MI, CABG, coronary angioplasty, stroke, any diagnosed malignancy, connective tissue disorders (especially rheumatoid arthritis, SLE, undifferentiated connective tissue disorders and ankylosing spondylitis), hypertension, depression, CKD, PTSD, Autism Spectrum Disorder, ADHD
-- Smoking/alcohol intake (units per week)


--Just want the output, not the messages
SET NOCOUNT ON;

--> EXECUTE query-build-rq066-cohort.sql
-- 10m

--> EXECUTE query-patient-lsoa.sql
-- 17s
--> EXECUTE query-patient-townsend.sql
-- 6s
--> EXECUTE query-patient-practice-and-ccg.sql
-- 2s
--> EXECUTE query-patient-smoking-status.sql gp-events-table:#PatientEventData
-- 14s

--> EXECUTE query-get-closest-value-to-date.sql code-set:bmi version:2 temp-table-name:#PostStartBMI date:2020-01-01 comparison:>= all-patients:false gp-events-table:#PatientEventData
--> EXECUTE query-get-closest-value-to-date.sql code-set:bmi version:2 temp-table-name:#PreStartBMI date:2020-01-01 comparison:< all-patients:false gp-events-table:#PatientEventData
--> EXECUTE query-get-closest-value-to-date.sql code-set:bmi version:2 temp-table-name:#RecentBMI date:2030-01-01 comparison:< all-patients:false gp-events-table:#PatientEventData
-- 6s for both

-- Get the admissions and lengths of stay post covid tests
DECLARE @StartDate datetime;
SET @StartDate = '2020-01-01';
--> EXECUTE query-get-admissions-and-length-of-stay-post-covid.sql all-patients:false
-- 18s

--> EXECUTE query-get-covid-vaccines.sql gp-events-table:#PatientEventData gp-medications-table:#PatientMedicationData
-- 6s

--> CODESET angina:1 ankylosing-spondylitis:1 asthma:1 attention-deficit-hyperactivity-disorder:1
--> CODESET autism-spectrum-disorder:1 cancer:3 ckd-stage-3:1 ckd-stage-4:1 ckd-stage-5:1 copd:1
--> CODESET coronary-angioplasty:1 coronary-artery-bypass-graft:1 depression:1 diabetes-type-i:1
--> CODESET diabetes-type-ii:1 heart-failure:1 hypertension:1 myocardial-infarction:1 ptsd:1
--> CODESET rheumatoid-arthritis:1 sle:1 stroke:1

--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:angina version:1 temp-table-name:#PatientDiagnosisANGINA
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:ankylosing-spondylitis version:1 temp-table-name:#PatientDiagnosisANKYLOSING
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:asthma version:1 temp-table-name:#PatientDiagnosisASTHMA
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:attention-deficit-hyperactivity-disorder version:1 temp-table-name:#PatientDiagnosisATTENTION
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:autism-spectrum-disorder version:1 temp-table-name:#PatientDiagnosisAUTISM
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:cancer version:3 temp-table-name:#PatientDiagnosisCANCER
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:ckd-stage-3 version:1 temp-table-name:#PatientDiagnosisCKD3
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:ckd-stage-4 version:1 temp-table-name:#PatientDiagnosisCKD4
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:ckd-stage-5 version:1 temp-table-name:#PatientDiagnosisCKD5
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:copd version:1 temp-table-name:#PatientDiagnosisCOPD
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:coronary-angioplasty version:1 temp-table-name:#PatientDiagnosisCORONARYANGIOPLASTY
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:coronary-artery-bypass-graft version:1 temp-table-name:#PatientDiagnosisCABG
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:depression version:1 temp-table-name:#PatientDiagnosisDEPRESSION
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:diabetes-type-i version:1 temp-table-name:#PatientDiagnosisDIABETES1
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:diabetes-type-ii version:1 temp-table-name:#PatientDiagnosisDIABETES2
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:heart-failure version:1 temp-table-name:#PatientDiagnosisHEART
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:hypertension version:1 temp-table-name:#PatientDiagnosisHYPERTENSION
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:myocardial-infarction version:1 temp-table-name:#PatientDiagnosisMYOCARDIAL
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:ptsd version:1 temp-table-name:#PatientDiagnosisPTSD
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:rheumatoid-arthritis version:1 temp-table-name:#PatientDiagnosisRHEUMATOID
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:sle version:1 temp-table-name:#PatientDiagnosisSLE
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:stroke version:1 temp-table-name:#PatientDiagnosisSTROKE
-- 7s for all of the above

-- Take first of CKD3,4 or 5 as first CKD date
IF OBJECT_ID('tempdb..#PatientDiagnosisCKD') IS NOT NULL DROP TABLE #PatientDiagnosisCKD;
SELECT 
	CASE
		WHEN ckd3.FK_Patient_Link_ID IS NOT NULL THEN ckd3.FK_Patient_Link_ID
		WHEN ckd4.FK_Patient_Link_ID IS NOT NULL THEN ckd4.FK_Patient_Link_ID
		ELSE ckd5.FK_Patient_Link_ID
	END AS FK_Patient_Link_ID,
	CASE
		WHEN ckd3.DateOfFirstDiagnosis IS NOT NULL THEN ckd3.DateOfFirstDiagnosis
		WHEN ckd4.DateOfFirstDiagnosis IS NOT NULL THEN ckd4.DateOfFirstDiagnosis
		ELSE ckd5.DateOfFirstDiagnosis
	END AS DateOfFirstDiagnosis
INTO #PatientDiagnosisCKD
FROM #PatientDiagnosisCKD3 ckd3
FULL JOIN #PatientDiagnosisCKD4 ckd4 on ckd3.FK_Patient_Link_ID = ckd4.FK_Patient_Link_ID
FULL JOIN #PatientDiagnosisCKD5 ckd5 on ckd3.FK_Patient_Link_ID = ckd5.FK_Patient_Link_ID;

-- First the main cohort
SELECT 
  pat.FK_Patient_Link_ID AS PatientId,
  NULL AS MainCohortMatchedPatientId,
  sex.Sex,
  yob.YearOfBirth,
  pl.EthnicCategoryDescription AS Ethnicity,
  town.TownsendScoreHigherIsMoreDeprived,
  town.TownsendQuintileHigherIsMoreDeprived,
  practice.GPPracticeCode,
  postCovid.FirstPostCOVIDDiagnosisDate AS DateOfLongCovidDiagnosis,
  postCovid.FirstPostCOVIDAssessmentDate AS DateOfLongCovidAssessment,
  postCovid.FirstPostCOVIDReferralDate AS DateOfLongCovidReferral,
  bmi.DateOfFirstValue AS DateOfBMIBefore,
  bmi.Value AS ValueOfBMIBefore,
  bmiPost.DateOfFirstValue AS DateOfBMIAfter,
  bmiPost.Value AS ValueOfBMIAfter,
  bmiRecent.DateOfFirstValue AS DateOfBMIMostRecent,
  bmiRecent.Value AS ValueOfBMIMostRecent,
  covid.FirstCovidPositiveDate, admission.FirstAdmissionPost1stCOVIDTest, los.LengthOfStay1stAdmission1stCOVIDTest,
  covid.SecondCovidPositiveDate, admission.FirstAdmissionPost2ndCOVIDTest, los.LengthOfStay1stAdmission2ndCOVIDTest,
  covid.ThirdCovidPositiveDate, admission.FirstAdmissionPost3rdCOVIDTest, los.LengthOfStay1stAdmission3rdCOVIDTest,
  covid.FourthCovidPositiveDate, admission.FirstAdmissionPost4thCOVIDTest, los.LengthOfStay1stAdmission4thCOVIDTest,
  covid.FifthCovidPositiveDate, admission.FirstAdmissionPost5thCOVIDTest, los.LengthOfStay1stAdmission5thCOVIDTest,
  vacc.VaccineDose1Date AS FirstVaccineDate,
  vacc.VaccineDose2Date AS SecondVaccineDate,
  vacc.VaccineDose3Date AS ThirdVaccineDate,
  vacc.VaccineDose4Date AS FourthVaccineDate,
  vacc.VaccineDose5Date AS FifthVaccineDate,
  YEAR(pl.DeathDate) YearOfDeath,
  MONTH(pl.DeathDate) MonthOfDeath,
  angina.DateOfFirstDiagnosis AS DateOfAngina,
  ankylosing.DateOfFirstDiagnosis AS DateOfAnkylosingSpondylitis,
  asthma.DateOfFirstDiagnosis AS DateOfAsthma,
  attention.DateOfFirstDiagnosis AS DateOfADHD,
  autism.DateOfFirstDiagnosis AS DateOfAutism,
  cancer.DateOfFirstDiagnosis AS DateOfCancer,
  ckd.DateOfFirstDiagnosis AS DateOfCkdStages345,
  copd.DateOfFirstDiagnosis AS DateOfCOPD,
  coronaryangioplasty.DateOfFirstDiagnosis AS DateOfCoronaryAngioplasty,
  cabg.DateOfFirstDiagnosis AS DateOfCABG,
  depression.DateOfFirstDiagnosis AS DateOfDepression,
  diabetes1.DateOfFirstDiagnosis AS DateOfDiabetesT1,
  diabetes2.DateOfFirstDiagnosis AS DateOfDiabetesT2,
  heart.DateOfFirstDiagnosis AS DateOfHeartFailure,
  hypertension.DateOfFirstDiagnosis AS DateOfHypertension,
  myocardial.DateOfFirstDiagnosis AS DateOfMyocardialInfarction,
  ptsd.DateOfFirstDiagnosis AS DateOfPTSD,
  rheumatoid.DateOfFirstDiagnosis AS DateOfRheumatoidArthritis,
  sle.DateOfFirstDiagnosis AS DateOfSLE,
  stroke.DateOfFirstDiagnosis AS DateOfStroke
FROM #MainCohort pat
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN SharedCare.Patient_Link pl ON pl.PK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientTownsend town ON town.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientPractice practice ON practice.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PostCOVIDPatients postCovid ON postCovid.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PostStartBMI bmiPost ON bmiPost.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PreStartBMI bmi ON bmi.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #RecentBMI bmiRecent ON bmiRecent.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #CovidPatientsMultipleDiagnoses covid ON covid.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientsAdmissionsPostTest admission ON admission.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientsLOSPostTest los on los.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDVaccinations vacc ON vacc.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisANGINA angina ON angina.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisANKYLOSING ankylosing ON ankylosing.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisASTHMA asthma ON asthma.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisATTENTION attention ON attention.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisAUTISM autism ON autism.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisCANCER cancer ON cancer.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisCKD ckd ON ckd.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisCOPD copd ON copd.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisCORONARYANGIOPLASTY coronaryangioplasty ON coronaryangioplasty.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisCABG cabg ON cabg.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisDEPRESSION depression ON depression.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisDIABETES1 diabetes1 ON diabetes1.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisDIABETES2 diabetes2 ON diabetes2.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisHEART heart ON heart.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisHYPERTENSION hypertension ON hypertension.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisMYOCARDIAL myocardial ON myocardial.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisPTSD ptsd ON ptsd.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisRHEUMATOID rheumatoid ON rheumatoid.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisSLE sle ON sle.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisSTROKE stroke ON stroke.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
UNION
-- The matched cohort
SELECT 
  pat.FK_Patient_Link_ID AS PatientId,
  PatientWhoIsMatched AS MainCohortMatchedPatientId,
  sex.Sex,
  yob.YearOfBirth,
  pl.EthnicCategoryDescription AS Ethnicity,
  town.TownsendScoreHigherIsMoreDeprived,
  town.TownsendQuintileHigherIsMoreDeprived,
  practice.GPPracticeCode,
  postCovid.FirstPostCOVIDDiagnosisDate AS DateOfLongCovidDiagnosis,
  postCovid.FirstPostCOVIDAssessmentDate AS DateOfLongCovidAssessment,
  postCovid.FirstPostCOVIDReferralDate AS DateOfLongCovidReferral,
  bmi.DateOfFirstValue AS DateOfBMIBeforeJan2020,
  bmi.Value AS ValueOfBMIBeforeJan2020,
  bmiPost.DateOfFirstValue AS DateOfBMIAfterJan2020,
  bmiPost.Value AS ValueOfBMIAfterJan2020,
  bmiRecent.DateOfFirstValue AS DateOfBMIMostRecent,
  bmiRecent.Value AS ValueOfBMIMostRecent,
  covid.FirstCovidPositiveDate, admission.FirstAdmissionPost1stCOVIDTest, los.LengthOfStay1stAdmission1stCOVIDTest,
  covid.SecondCovidPositiveDate, admission.FirstAdmissionPost2ndCOVIDTest, los.LengthOfStay1stAdmission2ndCOVIDTest,
  covid.ThirdCovidPositiveDate, admission.FirstAdmissionPost3rdCOVIDTest, los.LengthOfStay1stAdmission3rdCOVIDTest,
  covid.FourthCovidPositiveDate, admission.FirstAdmissionPost4thCOVIDTest, los.LengthOfStay1stAdmission4thCOVIDTest,
  covid.FifthCovidPositiveDate, admission.FirstAdmissionPost5thCOVIDTest, los.LengthOfStay1stAdmission5thCOVIDTest,
  vacc.VaccineDose1Date AS FirstVaccineDate,
  vacc.VaccineDose2Date AS SecondVaccineDate,
  vacc.VaccineDose3Date AS ThirdVaccineDate,
  vacc.VaccineDose4Date AS FourthVaccineDate,
  vacc.VaccineDose5Date AS FifthVaccineDate,
  YEAR(pl.DeathDate) YearOfDeath,
  MONTH(pl.DeathDate) MonthOfDeath,
  angina.DateOfFirstDiagnosis AS DateOfAngina,
  ankylosing.DateOfFirstDiagnosis AS DateOfAnkylosingSpondylitis,
  asthma.DateOfFirstDiagnosis AS DateOfAsthma,
  attention.DateOfFirstDiagnosis AS DateOfADHD,
  autism.DateOfFirstDiagnosis AS DateOfAutism,
  cancer.DateOfFirstDiagnosis AS DateOfCancer,
  ckd.DateOfFirstDiagnosis AS DateOfCkdStages345,
  copd.DateOfFirstDiagnosis AS DateOfCOPD,
  coronaryangioplasty.DateOfFirstDiagnosis AS DateOfCoronaryAngioplasty,
  cabg.DateOfFirstDiagnosis AS DateOfCABG,
  depression.DateOfFirstDiagnosis AS DateOfDepression,
  diabetes1.DateOfFirstDiagnosis AS DateOfDiabetesT1,
  diabetes2.DateOfFirstDiagnosis AS DateOfDiabetesT2,
  heart.DateOfFirstDiagnosis AS DateOfHeartFailure,
  hypertension.DateOfFirstDiagnosis AS DateOfHypertension,
  myocardial.DateOfFirstDiagnosis AS DateOfMyocardialInfarction,
  ptsd.DateOfFirstDiagnosis AS DateOfPTSD,
  rheumatoid.DateOfFirstDiagnosis AS DateOfRheumatoidArthritis,
  sle.DateOfFirstDiagnosis AS DateOfSLE,
  stroke.DateOfFirstDiagnosis AS DateOfStroke
FROM #MatchedCohort pat
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN SharedCare.Patient_Link pl ON pl.PK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientTownsend town ON town.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientPractice practice ON practice.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PostCOVIDPatients postCovid ON postCovid.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PostStartBMI bmiPost ON bmiPost.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PreStartBMI bmi ON bmi.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #RecentBMI bmiRecent ON bmiRecent.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #CovidPatientsMultipleDiagnoses covid ON covid.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientsAdmissionsPostTest admission ON admission.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientsLOSPostTest los on los.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDVaccinations vacc ON vacc.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisANGINA angina ON angina.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisANKYLOSING ankylosing ON ankylosing.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisASTHMA asthma ON asthma.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisATTENTION attention ON attention.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisAUTISM autism ON autism.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisCANCER cancer ON cancer.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisCKD ckd ON ckd.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisCOPD copd ON copd.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisCORONARYANGIOPLASTY coronaryangioplasty ON coronaryangioplasty.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisCABG cabg ON cabg.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisDEPRESSION depression ON depression.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisDIABETES1 diabetes1 ON diabetes1.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisDIABETES2 diabetes2 ON diabetes2.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisHEART heart ON heart.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisHYPERTENSION hypertension ON hypertension.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisMYOCARDIAL myocardial ON myocardial.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisPTSD ptsd ON ptsd.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisRHEUMATOID rheumatoid ON rheumatoid.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisSLE sle ON sle.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisSTROKE stroke ON stroke.FK_Patient_Link_ID = pat.FK_Patient_Link_ID;