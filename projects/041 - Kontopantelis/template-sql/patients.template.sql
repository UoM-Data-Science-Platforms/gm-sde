--┌─────────────────────────────────────┐
--│ Patient information for main cohort │
--└─────────────────────────────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------

------------------------------------------------------

-- PatientID
-- registration date with the general practice
-- Month and year of birth (YYYY-MM)
-- Month and year of death (YYYY-MM)
-- Sex at birth (male/female)
-- Ethnicity (white/black/asian/mixed/other)
-- CCG of registered GP practice
-- LSOA Code
-- IMD decile
-- First vaccination date (YYYY-MM or N/A)
-- Second vaccination date (YYYY-MM or N/A)
-- Third vaccination date (YYYY-MM or N/A)
-- Death within 28 days of Covid Diagnosis (Y/N)
-- Date of death due to Covid-19 (YYYY-MM or N/A)
-- Number of AE Episodes before 01.03.20
-- Number of AE Episodes after 01.03.20
-- Total AE Episodes (01.03.18 - 01.03.22)
-- Number of GP appointments before 01.03.20
-- Number of GP appointments after 01.03.20
-- Total GP appointments (01.03.18 - 01.03.22)
-- evidenceOfCKD (yes/no)
-- atRiskOfCKD (yes/no)

-- Set the start date
DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2020-01-31';
SET @EndDate = getdate();

--Just want the output, not the messages
SET NOCOUNT ON;

-- Find all patients alive at start date
IF OBJECT_ID('tempdb..#PossiblePatients') IS NOT NULL DROP TABLE #PossiblePatients;
SELECT PK_Patient_Link_ID as FK_Patient_Link_ID, EthnicMainGroup, DeathDate INTO #PossiblePatients FROM [RLS].vw_Patient_Link
WHERE (DeathDate IS NULL OR DeathDate >= @StartDate);

-- Find all patients registered with a GP
IF OBJECT_ID('tempdb..#PatientsWithGP') IS NOT NULL DROP TABLE #PatientsWithGP;
SELECT DISTINCT FK_Patient_Link_ID INTO #PatientsWithGP FROM [RLS].vw_Patient
where FK_Reference_Tenancy_ID = 2;

-- Make cohort from patients alive at start date and registered with a GP
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT pp.* INTO #Patients FROM #PossiblePatients pp
INNER JOIN #PatientsWithGP gp on gp.FK_Patient_Link_ID = pp.FK_Patient_Link_ID;

--> CODESET sle:1 polycystic-kidney-disease:1 gout:1 haematuria:1 glomerulonephritis:1
--> CODESET schizophrenia-psychosis:1 bipolar:1 depression:1
--> CODESET selfharm-episodes:1 obese:1
--> CODESET hormone-replacement-therapy:1

-- load codesets for observations needed for defining cohort

--> CODESET acr:1 urinary-albumin-creatinine-ratio:1

--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-imd.sql
--> EXECUTE query-patient-year-of-birth.sql
--> EXECUTE query-patient-lsoa.sql
--> EXECUTE query-patient-practice-and-ccg.sql

--> EXECUTE query-get-covid-vaccines.sql all-patients:false gp-events-table:RLS.vw_GP_Events gp-medications-table:RLS.vw_GP_Medications

-- find the first and second vaccine date for each patient

IF OBJECT_ID('tempdb..#COVIDVaccinations1') IS NOT NULL DROP TABLE #COVIDVaccinations1;
SELECT 
	FK_Patient_Link_ID
	,FirstVaccineDate = VaccineDose1Date 
	,SecondVaccineDate = VaccineDose2Date
	,ThirdVaccineDate = VaccineDose3Date 
INTO #COVIDVaccinations1 ----- IS THIS TABLE NEEDED????
FROM #COVIDVaccinations
WHERE
	(VaccineDose1Date <= @EndDate OR VaccineDose1Date IS NULL) AND 
	(VaccineDose2Date <= @EndDate OR VaccineDose2Date IS NULL) AND
	(VaccineDose3Date <= @EndDate OR VaccineDose3Date IS NULL)


-- Get patient list of those with COVID death within 28 days of positive test
IF OBJECT_ID('tempdb..#COVIDDeath') IS NOT NULL DROP TABLE #COVIDDeath;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #COVIDDeath FROM RLS.vw_COVID19
WHERE DeathWithin28Days = 'Y'
	AND EventDate <= @EndDate

---- CREATE COHORT 1: BIOCHEMICAL EVIDENCE OF CKD
---- includes all patients with two EGFR tests (within 3 months) confirming CKD

SELECT gp.FK_Patient_Link_ID, 
	CAST(GP.EventDate AS DATE) AS EventDate, 
	SuppliedCode, 
	[value] = TRY_CONVERT(NUMERIC (18,5), [Value]),  
	[Units],
	egfr_Code = CASE WHEN SuppliedCode IN (
		SELECT [Code] FROM #AllCodes WHERE [Concept] IN ('egfr') AND [Version] = 1 ) THEN 1 ELSE 0 END,
	acr_Code = CASE WHEN SuppliedCode IN (
		SELECT [Code] FROM #AllCodes WHERE [Concept] IN ('urinary-albumin-creatinine-ratio') AND [Version] = 1 ) THEN 1 ELSE 0 END
INTO #EGFR_ACR_TESTS
FROM [RLS].[vw_GP_Events] gp
WHERE SuppliedCode IN (
	SELECT [Code] 
	FROM #AllCodes 
	WHERE [Concept] IN ('egfr', 'urinary-albumin-creatinine-ratio') 
		AND [Version] = 1 
	)
AND gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND (gp.EventDate) BETWEEN '2022-03-01' AND '2022-03-31' --@StartDate
AND [Value] IS NOT NULL AND UPPER([Value]) NOT LIKE '%[A-Z]%' 
--and FK_Patient_Link_ID = '6845500210297983914'

-- CREATE TABLE OF EGFR TESTS THAT MEET CKD CRITERIA (VARIOUS STAGEs)

SELECT FK_Patient_Link_ID,
	EventDate,
	egfr_evidence = CASE WHEN egfr_Code = 1 AND [Value] >= 90   THEN 'G1' 
		WHEN egfr_Code = 1 AND [Value] BETWEEN 60 AND 89 		THEN 'G2'
		WHEN egfr_Code = 1 AND [Value] BETWEEN 45 AND 59 		THEN 'G3a'
		WHEN egfr_Code = 1 AND [Value] BETWEEN 30 AND 44 		THEN 'G3b'
		WHEN egfr_Code = 1 AND [Value] BETWEEN 15 AND 29 		THEN 'G4'
		WHEN egfr_Code = 1 AND [Value] BETWEEN  0 AND 15 		THEN 'G5'
				END
INTO #ckd_stages_egfr
FROM #EGFR_ACR_TESTS

-- FIND EGFR TESTS INDICATIVE OF CKD STAGE 3-5, WITH THE DATES OF THE PREVIOUS TEST

IF OBJECT_ID('tempdb..#egfr_dates') IS NOT NULL DROP TABLE #egfr_dates;
SELECT *, 
	stage_previous_egfr = LAG(egfr_evidence, 1, NULL) OVER (PARTITION BY FK_Patient_Link_ID ORDER BY EventDate),
	date_previous_egfr = LAG(EventDate, 1, NULL) OVER (PARTITION BY FK_Patient_Link_ID ORDER BY EventDate)
INTO #egfr_dates
FROM #ckd_stages_egfr
where egfr_evidence in ('G3a', 'G3b', 'G4', 'G5')
ORDER BY FK_Patient_Link_ID, EventDate

-- CREATE TABLE OF PATIENTS THAT HAD TWO EGFR TESTS INDICATIVE OF CKD STAGE 3-5, WITHIN 3 MONTHS OF EACH OTHER

IF OBJECT_ID('tempdb..#egfr_ckd_evidence') IS NOT NULL DROP TABLE #egfr_ckd_evidence;
SELECT *
INTO #egfr_ckd_evidence
FROM #egfr_dates
WHERE datediff(month, date_previous_egfr, EventDate) <=  3 --only find patients with two tests in three months


-- CREATE TABLE OF ACR TESTS THAT MEET CKD CRITERIA (VARIOUS STAGES)
-- ***** NEED TO ASK PI ABOUT THIS

/*
SELECT FK_Patient_Link_ID,
	EventDate, 
	acr_evidence = CASE WHEN acr_Code = 1 AND [Value] > 30  	THEN 'A3' 
		WHEN acr_Code = 1 AND [Value] BETWEEN 3 AND 30 			THEN 'A2'
		WHEN acr_Code = 1 AND [Value] BETWEEN  0 AND 3 			THEN 'A1'
				END 
INTO #ckd_stages_acr
FROM #EGFR_ACR_TESTS
*/

-- CREATE TABLE OF FULL COHORT WHICH INCLUDES THOSE WITH EVIDENCE OF CKD AND THOSE AT RISK

SELECT FK_Patient_Link_ID
		EvidenceOfCKD = CASE WHEN p.FK_Patient_Link_ID IS NOT NULL THEN 1 ELSE 0 END,
		AtRiskOfCKD = NULL
INTO #Cohort
FROM #Patients p
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #egfr_ckd_evidence) 
	-- OR _____

-- FIND NUMBER OF GP APPOINTMENTS FROM MARCH 2018 TO MARCH 2022

DROP TABLE #gp_appointments
SELECT G.FK_Patient_Link_ID, 
	G.AppointmentDate, 
	BeforeOrAfter1stMarch2020 = CASE WHEN G.AppointmentDate < '2020-03-01' THEN 'BEFORE' ELSE 'AFTER' END
INTO #gp_appointments
FROM RLS.vw_GP_Appointments G
WHERE AppointmentCancelledDate IS NULL 
AND AppointmentDate BETWEEN '2018-03-01' AND '2022-03-01'
AND G.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #cohort) 

SELECT FK_Patient_Link_ID, BeforeOrAfter1stMarch2020, COUNT(*) as gp_appointments
INTO #count_gp_appointments
FROM #gp_appointments
GROUP BY FK_Patient_Link_ID, BeforeOrAfter1stMarch2020
ORDER BY FK_Patient_Link_ID, BeforeOrAfter1stMarch2020

-- FIND NUMBER OF A&E APPOINTMENTS FROM MARCH 2018 TO MARCH 2022

DROP TABLE #ae_encounters
SELECT a.FK_Patient_Link_ID, 
	a.AttendanceDate, 
	BeforeOrAfter1stMarch2020 = CASE WHEN a.AttendanceDate < '2020-03-01' THEN 'BEFORE' ELSE 'AFTER' END
INTO #ae_encounters
FROM RLS.vw_Acute_AE a
WHERE EventType = 'Attendance'
AND a.AttendanceDate BETWEEN '2018-03-01' AND '2022-03-01'
AND a.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #cohort) 

SELECT FK_Patient_Link_ID, BeforeOrAfter1stMarch2020, COUNT(*) AS ae_encounters
INTO #count_ae_encounters
FROM #ae_encounters
GROUP BY FK_Patient_Link_ID, BeforeOrAfter1stMarch2020
ORDER BY FK_Patient_Link_ID, BeforeOrAfter1stMarch2020


---- CREATE TABLE OF ALL PATIENTS (EITHER EVIDENCE OF CKD OR AT RISK OF CKD)

SELECT p.FK_Patient_Link_ID, 
		PracticeRegistrationDate = NULL,
		PracticeCCG = prac.CCG
		YearOfBirth, 
		Sex,
		EthnicMainGroup,
	    LSOA_Code,
		IMD2019Decile1IsMostDeprived10IsLeastDeprivedIMDDecile,
		DeathWithin28DaysCovid = CASE WHEN cd.FK_Patient_Link_ID  IS NOT NULL THEN 'Y' ELSE 'N' END,
		DeathDueToCovid_Year = CASE WHEN cd.FK_Patient_Link_ID IS NOT NULL THEN YEAR(pl.DeathDate) ELSE null END,
		DeathDueToCovid_Month = CASE WHEN cd.FK_Patient_Link_ID IS NOT NULL THEN MONTH(pl.DeathDate) ELSE null END,
		FirstVaccineYear =  YEAR(FirstVaccineDate),
		FirstVaccineMonth = MONTH(FirstVaccineDate),
		SecondVaccineYear =  YEAR(SecondVaccineDate),
		SecondVaccineMonth = MONTH(SecondVaccineDate),
		ThirdVaccineYear =  YEAR(ThirdVaccineDate),
		ThirdVaccineMonth = MONTH(ThirdVaccineDate),
		AEEncountersBefore1stMarch2020 = CASE WHEN ae.BeforeOrAfter1stMarch2020 = 'BEFORE' THEN ae_encounters ELSE NULL END
		AEEncountersAfter1stMarch2020 = CASE WHEN ae.BeforeOrAfter1stMarch2020 = 'AFTER' THEN ae_encounters ELSE NULL END
		GPAppointmentsBefore1stMarch2020 = CASE WHEN gp.BeforeOrAfter1stMarch2020 = 'BEFORE' THEN gp_appointments ELSE NULL END
		GPAppointmentsAfter1stMarch2020 = CASE WHEN gp.BeforeOrAfter1stMarch2020 = 'AFTER' THEN gp_appointments ELSE NULL END
		EvidenceOfCKD = CASE WHEN eg.FK_Patient_Link_ID IS NOT NULL THEN 1 ELSE 0 END
		--acr_ckd_evidence = CASE WHEN acr.FK_Patient_Link_ID IS NOT NULL THEN 1 ELSE 0 END
		AtRiskOfCKD = NULL
FROM #Cohort p
LEFT OUTER JOIN #egfr_ckd_evidence eg on eg.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #acr_ckd_evidence acr ON acr.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientLSOA lsoa ON lsoa.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientIMDDecile imd ON imd.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientPracticeAndCCG prac ON prac.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDVaccinations1 vac ON vac.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDDeath cd ON cd.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #count_ae_encounters ae ON ae.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #count_gp_appointments gpa ON gpa.FK_Patient_Link_ID = p.FK_Patient_Link_ID



-- CREATE WIDE TABLE SHOWING WHICH PATIENTS HAVE A HISTORY OF EACH LTC

SELECT FK_Patient_Link_ID,
		HO_cancer 						= MAX(CASE WHEN LTC = 'cancer' then 1 else 0 end),
		HO_painful_condition 			= MAX(CASE WHEN LTC = 'painful condition' then 1 else 0 end),
		HO_migraine 					= MAX(CASE WHEN LTC = 'migraine' then 1 else 0 end),
		HO_epilepsy						= MAX(CASE WHEN LTC = 'epilepsy' then 1 else 0 end),
		HO_coronary_heart_disease 		= MAX(CASE WHEN LTC = 'coronary heart disease' then 1 else 0 end),
		HO_atrial_fibrillation 			= MAX(CASE WHEN LTC = 'atrial fibrillation' then 1 else 0 end),
		HO_heart_failure 				= MAX(CASE WHEN LTC = 'heart failure' then 1 else 0 end),
		HO_hypertension 				= MAX(CASE WHEN LTC = 'hypertension' then 1 else 0 end),
		HO_peripheral_vascular_disease  = MAX(CASE WHEN LTC = 'peripheral vascular disease' then 1 else 0 end),
		HO_stroke_and_transient_ischaemic_attack = MAX(CASE WHEN LTC = 'stroke and tia' then 1 else 0 end),
		HO_diabetes 					= MAX(CASE WHEN LTC = 'diabetes' then 1 else 0 end),
		HO_thyroid_disorders 			= MAX(CASE WHEN LTC = 'thyroid disorders' then 1 else 0 end),
		HO_chronic_liver_disease 		= MAX(CASE WHEN LTC = 'chronic liver disease' then 1 else 0 end),
		HO_diverticular_disease_of_intestine = MAX(CASE WHEN LTC = 'diverticular disease of intestine' then 1 else 0 end),
		HO_inflammatory_bowel_disease 	= MAX(CASE WHEN LTC = 'inflammatory bowel disease' then 1 else 0 end),
		HO_irritable_bowel_syndrome 	= MAX(CASE WHEN LTC = 'irritable bowel syndrome' then 1 else 0 end),
		HO_constipation					= MAX(CASE WHEN LTC = 'constipation' then 1 else 0 end),
		HO_dyspepsia					= MAX(CASE WHEN LTC = 'dyspepsia' then 1 else 0 end),
		HO_peptic_ulcer_disease 		= MAX(CASE WHEN LTC = 'peptic ulcer disease' then 1 else 0 end),
		HO_psoriasis_or_eczema 			= MAX(CASE WHEN LTC = 'psoriasis or eczema' then 1 else 0 end),
		HO_rheumatoid_arthritis_other_inflammatory_polyarthropathies	= MAX(CASE WHEN LTC = 'rheumatoid arthritis and other inflammatory polyarthropathies' then 1 else 0 end),
		HO_multiple_sclerosis			= MAX(CASE WHEN LTC = 'multiple sclerosis' then 1 else 0 end),
		HO_parkinsons_disease 			= MAX(CASE WHEN LTC = 'parkinsons disease' then 1 else 0 end),
		HO_anorexia_bulimia 			= MAX(CASE WHEN LTC = 'anorexia or bulimia' then 1 else 0 end),
		HO_anxiety_other_somatoform_disorders	= MAX(CASE WHEN LTC = 'anxiety and other somatoform disorders' then 1 else 0 end),
		HO_chronic_kidney_disease		= MAX(CASE WHEN LTC = 'chronic kidney disease' then 1 else 0 end),
INTO #HistoryOfLTCs
FROM #PatientsWithLTCs
GROUP BY FK_Patient_Link_ID


----- create anonymised identifier for each GP Practice

IF OBJECT_ID('tempdb..#UniquePractices') IS NOT NULL DROP TABLE #UniquePractices;
SELECT DISTINCT GPPracticeCode
INTO #UniquePractices
FROM #PatientPractice
Order by GPPracticeCode desc

IF OBJECT_ID('tempdb..#RandomisePractice') IS NOT NULL DROP TABLE #RandomisePractice;
SELECT GPPracticeCode
	, RandomPracticeID = ROW_NUMBER() OVER (order by newid())
INTO #RandomisePractice
FROM #UniquePractices

--bring together for final output
--patients in main cohort
SELECT	 PatientId = m.FK_Patient_Link_ID
		,NULL AS MainCohortMatchedPatientId
		,m.YearOfBirth
		,m.Sex
		,LSOA_Code
		,m.EthnicMainGroup
		,IMD2019Decile1IsMostDeprived10IsLeastDeprived
		,rp.RandomPracticeID 
		,HO_cancer = ISNULL(HO_painful_condition, 0)
		,HO_painful_condition = ISNULL(HO_painful_condition, 0)
		,HO_migraine  = ISNULL(HO_migraine , 0)
		,HO_epilepsy = ISNULL(HO_epilepsy, 0)
		,HO_coronary_heart_disease  = ISNULL(HO_coronary_heart_disease , 0)
		,HO_atrial_fibrillation  = ISNULL(HO_atrial_fibrillation , 0)
		,HO_heart_failure = ISNULL(HO_heart_failure, 0)
		,HO_hypertension = ISNULL(HO_hypertension, 0)
		,HO_peripheral_vascular_disease = ISNULL(HO_peripheral_vascular_disease, 0)
		,HO_stroke_and_transient_ischaemic_attack = ISNULL(HO_stroke_and_transient_ischaemic_attack, 0)
		,HO_diabetes  = ISNULL(HO_diabetes , 0)
		,HO_thyroid_disorders  = ISNULL(HO_thyroid_disorders , 0)
		,HO_chronic_liver_disease  = ISNULL(HO_chronic_liver_disease , 0)
		,HO_diverticular_disease_of_intestine = ISNULL(HO_diverticular_disease_of_intestine, 0)
		,HO_inflammatory_bowel_disease  = ISNULL(HO_inflammatory_bowel_disease , 0)
		,HO_irritable_bowel_syndrome  = ISNULL(HO_irritable_bowel_syndrome , 0)
		,HO_constipation = ISNULL(HO_constipation, 0)
		,HO_dyspepsia = ISNULL(HO_dyspepsia, 0)
		,HO_peptic_ulcer_disease  = ISNULL(HO_peptic_ulcer_disease , 0)
		,HO_psoriasis_or_eczema  = ISNULL(HO_psoriasis_or_eczema , 0)
		,HO_rheumatoid_arthritis_other_inflammatory_polyarthropathies = ISNULL(HO_rheumatoid_arthritis_other_inflammatory_polyarthropathies, 0)
		,HO_multiple_sclerosis = ISNULL(HO_multiple_sclerosis, 0)
		,HO_parkinsons_disease  = ISNULL(HO_parkinsons_disease , 0)
		,HO_anorexia_bulimia  = ISNULL(HO_anorexia_bulimia , 0)
		,HO_anxiety_other_somatoform_disorders = ISNULL(HO_anxiety_other_somatoform_disorders, 0)
		,HO_dementia = ISNULL(HO_dementia, 0)
		,HO_chronic_kidney_disease = ISNULL(HO_chronic_kidney_disease, 0)
		,HO_prostate_disorders = ISNULL(HO_prostate_disorders, 0)
		,HO_asthma = ISNULL(HO_asthma, 0)
		,HO_bronchiectasis = ISNULL(HO_bronchiectasis, 0)
		,HO_chronic_sinusitis = ISNULL(HO_chronic_sinusitis, 0)
		,HO_copd = ISNULL(HO_copd, 0)
		,HO_blindness_low_vision = ISNULL(HO_blindness_low_vision, 0)
		,HO_glaucoma = ISNULL(HO_glaucoma, 0)
		,HO_hearing_loss = ISNULL(HO_hearing_loss, 0)
		,HO_learning_disability = ISNULL(HO_learning_disability, 0)
		,HO_alcohol_problems = ISNULL(HO_alcohol_problems, 0)
		,HO_psychoactive_substance_abuse = ISNULL(HO_psychoactive_substance_abuse, 0)
		,HO_Schizophrenia_Psychosis = ISNULL(CASE WHEN EarliestDiagnosis_Schizophrenia_Psychosis IS NULL THEN 0 ELSE 1 END, 0)
		,EarliestDiagnosis_Schizophrenia_Psychosis
		,HO_Bipolar = ISNULL(CASE WHEN EarliestDiagnosis_Bipolar IS NULL THEN 0 ELSE 1 END, 0)
		,EarliestDiagnosis_Bipolar
		,HO_Recurrent_Depressive = ISNULL(CASE WHEN EarliestDiagnosis_Recurrent_Depressive IS NULL THEN 0 ELSE 1 END, 0)
		,EarliestDiagnosis_Recurrent_Depressive
		,HO_Depression = ISNULL(CASE WHEN EarliestDiagnosis_Depression IS NULL THEN 0 ELSE 1 END, 0)
		,EarliestDiagnosis_Depression
		,DeathAfter31Jan20 = CASE WHEN pl.DeathDate > '2020-01-31' THEN 'Y' ELSE 'N' END
		,DeathWithin28DaysCovid = CASE WHEN cd.FK_Patient_Link_ID  IS NOT NULL THEN 'Y' ELSE 'N' END
		,DeathDate_Year = CASE WHEN pl.DeathDate > '2020-01-31' THEN YEAR(pl.DeathDate) ELSE null END
		,DeathDate_Month = CASE WHEN pl.DeathDate > '2020-01-31' THEN MONTH(pl.DeathDate) ELSE null END
		,FirstVaccineYear =  YEAR(FirstVaccineDate)
		,FirstVaccineMonth = MONTH(FirstVaccineDate)
		,SecondVaccineYear =  YEAR(SecondVaccineDate)
		,SecondVaccineMonth = MONTH(SecondVaccineDate)
		,VaccineDeclined = CASE WHEN vd.FK_Patient_Link_ID is not null and DateVaccineDeclined is not null THEN 1 ELSE 0 END
FROM #MainCohort m
LEFT OUTER JOIN RLS.vw_Patient_Link pl ON pl.PK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #HistoryOfLTCs ltc on ltc.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #EarliestDiagnosis_Schizophrenia_Psychosis edsc on edsc.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #EarliestDiagnosis_Bipolar edbp on edbp.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #EarliestDiagnosis_Recurrent_Depressive edmd on edmd.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #EarliestDiagnosis_Depression edde on edde.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDVaccinations1 vac on vac.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #VaccineDeclinedPatients vd ON vd.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDDeath cd ON cd.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #RandomisePractice rp ON rp.GPPracticeCode = m.GPPracticeCode
WHERE M.FK_Patient_Link_ID in (SELECT FK_Patient_Link_ID FROM #Patients)
UNION
--patients in matched cohort
SELECT	PatientId = m.FK_Patient_Link_ID
		,m.PatientWhoIsMatched AS MainCohortMatchedPatientId
		,m.MatchingYearOfBirth
		,m.Sex
		,LSOA_Code
		,m.EthnicMainGroup
		,IMD2019Decile1IsMostDeprived10IsLeastDeprived 
		,rp.RandomPracticeID 
		,HO_cancer = ISNULL(HO_painful_condition, 0)		
		,HO_painful_condition = ISNULL(HO_painful_condition, 0)
		,HO_migraine  = ISNULL(HO_migraine , 0)
		,HO_epilepsy = ISNULL(HO_epilepsy, 0)
		,HO_coronary_heart_disease  = ISNULL(HO_coronary_heart_disease , 0)
		,HO_atrial_fibrillation  = ISNULL(HO_atrial_fibrillation , 0)
		,HO_heart_failure = ISNULL(HO_heart_failure, 0)
		,HO_hypertension = ISNULL(HO_hypertension, 0)
		,HO_peripheral_vascular_disease = ISNULL(HO_peripheral_vascular_disease, 0)
		,HO_stroke_and_transient_ischaemic_attack = ISNULL(HO_stroke_and_transient_ischaemic_attack, 0)
		,HO_diabetes  = ISNULL(HO_diabetes , 0)
		,HO_thyroid_disorders  = ISNULL(HO_thyroid_disorders , 0)
		,HO_chronic_liver_disease  = ISNULL(HO_chronic_liver_disease , 0)
		,HO_diverticular_disease_of_intestine = ISNULL(HO_diverticular_disease_of_intestine, 0)
		,HO_inflammatory_bowel_disease  = ISNULL(HO_inflammatory_bowel_disease , 0)
		,HO_irritable_bowel_syndrome  = ISNULL(HO_irritable_bowel_syndrome , 0)
		,HO_constipation = ISNULL(HO_constipation, 0)
		,HO_dyspepsia = ISNULL(HO_dyspepsia, 0)
		,HO_peptic_ulcer_disease  = ISNULL(HO_peptic_ulcer_disease , 0)
		,HO_psoriasis_or_eczema  = ISNULL(HO_psoriasis_or_eczema , 0)
		,HO_rheumatoid_arthritis_other_inflammatory_polyarthropathies = ISNULL(HO_rheumatoid_arthritis_other_inflammatory_polyarthropathies, 0)
		,HO_multiple_sclerosis = ISNULL(HO_multiple_sclerosis, 0)
		,HO_parkinsons_disease  = ISNULL(HO_parkinsons_disease , 0)
		,HO_anorexia_bulimia  = ISNULL(HO_anorexia_bulimia , 0)
		,HO_anxiety_other_somatoform_disorders = ISNULL(HO_anxiety_other_somatoform_disorders, 0)
		,HO_dementia = ISNULL(HO_dementia, 0)
		,HO_chronic_kidney_disease = ISNULL(HO_chronic_kidney_disease, 0)
		,HO_prostate_disorders = ISNULL(HO_prostate_disorders, 0)
		,HO_asthma = ISNULL(HO_asthma, 0)
		,HO_bronchiectasis = ISNULL(HO_bronchiectasis, 0)
		,HO_chronic_sinusitis = ISNULL(HO_chronic_sinusitis, 0)
		,HO_copd = ISNULL(HO_copd, 0)
		,HO_blindness_low_vision = ISNULL(HO_blindness_low_vision, 0)
		,HO_glaucoma = ISNULL(HO_glaucoma, 0)
		,HO_hearing_loss = ISNULL(HO_hearing_loss, 0)
		,HO_learning_disability = ISNULL(HO_learning_disability, 0)
		,HO_alcohol_problems = ISNULL(HO_alcohol_problems, 0)
		,HO_psychoactive_substance_abuse = ISNULL(HO_psychoactive_substance_abuse, 0)
		,HO_Schizophrenia_Psychosis = ISNULL(CASE WHEN EarliestDiagnosis_Schizophrenia_Psychosis IS NULL THEN 0 ELSE 1 END, 0)
		,EarliestDiagnosis_Schizophrenia_Psychosis
		,HO_Bipolar = ISNULL(CASE WHEN EarliestDiagnosis_Bipolar IS NULL THEN 0 ELSE 1 END, 0)
		,EarliestDiagnosis_Bipolar
		,HO_Recurrent_Depressive = ISNULL(CASE WHEN EarliestDiagnosis_Recurrent_Depressive IS NULL THEN 0 ELSE 1 END, 0)
		,EarliestDiagnosis_Recurrent_Depressive
		,HO_Depression = ISNULL(CASE WHEN EarliestDiagnosis_Depression IS NULL THEN 0 ELSE 1 END, 0)
		,EarliestDiagnosis_Depression
		,DeathAfter31Jan20 = CASE WHEN pl.DeathDate > '2020-01-31' THEN 'Y' ELSE 'N' END
		,DeathWithin28DaysCovid = CASE WHEN cd.FK_Patient_Link_ID  IS NOT NULL THEN 'Y' ELSE 'N' END
		,DeathDate_Year = CASE WHEN pl.DeathDate > '2020-01-31' THEN YEAR(pl.DeathDate) ELSE null END
		,DeathDate_Month = CASE WHEN pl.DeathDate > '2020-01-31' THEN MONTH(pl.DeathDate) ELSE null END
		,FirstVaccineYear =  YEAR(FirstVaccineDate)
		,FirstVaccineMonth = MONTH(FirstVaccineDate)
		,SecondVaccineYear =  YEAR(SecondVaccineDate)
		,SecondVaccineMonth = MONTH(SecondVaccineDate)
		,VaccineDeclined = CASE WHEN vd.FK_Patient_Link_ID is not null and DateVaccineDeclined is not null THEN 1 ELSE 0 END
FROM #MatchedCohort m
LEFT OUTER JOIN RLS.vw_Patient_Link pl ON pl.PK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #HistoryOfLTCs ltc on ltc.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #EarliestDiagnosis_Schizophrenia_Psychosis edsc on edsc.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #EarliestDiagnosis_Bipolar edbp on edbp.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #EarliestDiagnosis_Recurrent_Depressive edmd on edmd.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #EarliestDiagnosis_Depression edde on edde.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDVaccinations1 vac on vac.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #VaccineDeclinedPatients vd ON vd.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDDeath cd ON cd.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #RandomisePractice rp ON rp.GPPracticeCode = m.GPPracticeCode;

