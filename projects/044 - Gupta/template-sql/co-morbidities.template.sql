--┌──────────────────────────────────────────────┐
--│ Patients with multimorbidity and covid	     │
--└──────────────────────────────────────────────┘

---- RESEARCH DATA ENGINEER CHECK ----
-- 1st July 2022 - Richard Williams --
--------------------------------------	


DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2020-01-01';
SET @EndDate = '2022-05-01';

--Just want the output, not the messages
SET NOCOUNT ON;


-- Set the date variables for the LTC code

DECLARE @IndexDate datetime;
DECLARE @MinDate datetime;
SET @IndexDate = '2022-05-01';
SET @MinDate = '1900-01-01';


--> EXECUTE query-get-possible-patients.sql
--> EXECUTE query-patient-ltcs-date-range.sql 
--> EXECUTE query-patient-ltcs-number-of.sql
--> EXECUTE query-patient-year-of-birth.sql


-- FIND ALL PATIENTS WITH A MENTAL CONDITION

IF OBJECT_ID('tempdb..#PatientsWithMentalCondition') IS NOT NULL DROP TABLE #PatientsWithMentalCondition;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #PatientsWithMentalCondition
FROM #PatientsWithLTCs
WHERE LTC IN ('Anorexia Or Bulimia', 'Anxiety And Other Somatoform Disorders', 'Dementia', 'Depression', 'Schizophrenia Or Bipolar')
	AND FirstDate < '2020-03-01'
--872,174

-- FIND ALL PATIENTS WITH 2 OR MORE CONDITIONS, INCLUDING A MENTAL CONDITION

IF OBJECT_ID('tempdb..#2orMoreLTCsIncludingMental') IS NOT NULL DROP TABLE #2orMoreLTCsIncludingMental;
SELECT DISTINCT FK_Patient_Link_ID
INTO #2orMoreLTCsIncludingMental
FROM #NumLTCs 
WHERE NumberOfLTCs = 2
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsWithMentalCondition)
--677,226

------------------------------------ CREATE COHORT -------------------------------------
	-- REGISTERED WITH A GM GP
	-- OVER  18
	-- HAD A COVID19 INFECTION
	-- 2 OR MORE LTCs INCLUDING ONE MENTAL CONDITION (diagnosed before March 2020)


IF OBJECT_ID('tempdb..#Cohort') IS NOT NULL DROP TABLE #Cohort;
SELECT p.FK_Patient_Link_ID
INTO #Cohort
FROM #Patients p
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE YEAR(@StartDate) - YearOfBirth >= 19 														 -- Over 18
	AND p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #CovidPatientsMultipleDiagnoses) -- had at least one covid19 infection
	AND p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #2orMoreLTCsIncludingMental)     -- at least 2 LTCs including one mental

----------------------------------------------------------------------------------------


-- CREATE WIDE TABLE SHOWING WHICH PATIENTS HAVE A HISTORY OF EACH LTC (DIAGNOSED BEFORE MARCH 2020)

IF OBJECT_ID('tempdb..#HistoryOfLTCs') IS NOT NULL DROP TABLE #HistoryOfLTCs;
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
		HO_dementia						= MAX(CASE WHEN LTC = 'dementia' then 1 else 0 end),
		HO_depression					= MAX(CASE WHEN LTC = 'depression' then 1 else 0 end),
		HO_schizophrenia_or_bipolar		= MAX(CASE WHEN LTC = 'schizophrenia or bipolar' then 1 else 0 end),
		HO_chronic_kidney_disease		= MAX(CASE WHEN LTC = 'chronic kidney disease' then 1 else 0 end),
		HO_prostate_disorders			= MAX(CASE WHEN LTC = 'prostate disorders' then 1 else 0 end),
		HO_asthma						= MAX(CASE WHEN LTC = 'asthma' then 1 else 0 end),
		HO_bronchiectasis				= MAX(CASE WHEN LTC = 'bronchiectasis' then 1 else 0 end),
		HO_chronic_sinusitis			= MAX(CASE WHEN LTC = 'chronic sinusitis' then 1 else 0 end),
		HO_copd							= MAX(CASE WHEN LTC = 'copd' then 1 else 0 end),
		HO_blindness_low_vision			= MAX(CASE WHEN LTC = 'blindness and low vision' then 1 else 0 end),
		HO_glaucoma						= MAX(CASE WHEN LTC = 'glaucoma' then 1 else 0 end),
		HO_hearing_loss					= MAX(CASE WHEN LTC = 'hearing loss' then 1 else 0 end),
		HO_learning_disability			= MAX(CASE WHEN LTC = 'learning disability' then 1 else 0 end),
		HO_alcohol_problems				= MAX(CASE WHEN LTC = 'alcohol problems' then 1 else 0 end),
		HO_psychoactive_substance_abuse	= MAX(CASE WHEN LTC = 'psychoactive substance abuse' then 1 else 0 end)
INTO #HistoryOfLTCs
FROM #PatientsWithLTCs
WHERE FirstDate < '2020-03-01'
GROUP BY FK_Patient_Link_ID

-- CREATE WIDE TABLE SHOWING WHICH PATIENTS HAVE DEVELOPED A NEW LTC FROM MARCH 2020 ONWARDS

IF OBJECT_ID('tempdb..#NewLTCs') IS NOT NULL DROP TABLE #NewLTCs;
SELECT FK_Patient_Link_ID,
		NEW_cancer 						= MAX(CASE WHEN LTC = 'cancer' then 1 else 0 end),
		NEW_painful_condition 			= MAX(CASE WHEN LTC = 'painful condition' then 1 else 0 end),
		NEW_migraine 					= MAX(CASE WHEN LTC = 'migraine' then 1 else 0 end),
		NEW_epilepsy						= MAX(CASE WHEN LTC = 'epilepsy' then 1 else 0 end),
		NEW_coronary_heart_disease 		= MAX(CASE WHEN LTC = 'coronary heart disease' then 1 else 0 end),
		NEW_atrial_fibrillation 			= MAX(CASE WHEN LTC = 'atrial fibrillation' then 1 else 0 end),
		NEW_heart_failure 				= MAX(CASE WHEN LTC = 'heart failure' then 1 else 0 end),
		NEW_hypertension 				= MAX(CASE WHEN LTC = 'hypertension' then 1 else 0 end),
		NEW_peripheral_vascular_disease  = MAX(CASE WHEN LTC = 'peripheral vascular disease' then 1 else 0 end),
		NEW_stroke_and_transient_ischaemic_attack = MAX(CASE WHEN LTC = 'stroke and tia' then 1 else 0 end),
		NEW_diabetes 					= MAX(CASE WHEN LTC = 'diabetes' then 1 else 0 end),
		NEW_thyroid_disorders 			= MAX(CASE WHEN LTC = 'thyroid disorders' then 1 else 0 end),
		NEW_chronic_liver_disease 		= MAX(CASE WHEN LTC = 'chronic liver disease' then 1 else 0 end),
		NEW_diverticular_disease_of_intestine = MAX(CASE WHEN LTC = 'diverticular disease of intestine' then 1 else 0 end),
		NEW_inflammatory_bowel_disease 	= MAX(CASE WHEN LTC = 'inflammatory bowel disease' then 1 else 0 end),
		NEW_irritable_bowel_syndrome 	= MAX(CASE WHEN LTC = 'irritable bowel syndrome' then 1 else 0 end),
		NEW_constipation					= MAX(CASE WHEN LTC = 'constipation' then 1 else 0 end),
		NEW_dyspepsia					= MAX(CASE WHEN LTC = 'dyspepsia' then 1 else 0 end),
		NEW_peptic_ulcer_disease 		= MAX(CASE WHEN LTC = 'peptic ulcer disease' then 1 else 0 end),
		NEW_psoriasis_or_eczema 			= MAX(CASE WHEN LTC = 'psoriasis or eczema' then 1 else 0 end),
		NEW_rheumatoid_arthritis_other_inflammatory_polyarthropathies	= MAX(CASE WHEN LTC = 'rheumatoid arthritis and other inflammatory polyarthropathies' then 1 else 0 end),
		NEW_multiple_sclerosis			= MAX(CASE WHEN LTC = 'multiple sclerosis' then 1 else 0 end),
		NEW_parkinsons_disease 			= MAX(CASE WHEN LTC = 'parkinsons disease' then 1 else 0 end),
		NEW_anorexia_bulimia 			= MAX(CASE WHEN LTC = 'anorexia or bulimia' then 1 else 0 end),
		NEW_anxiety_other_somatoform_disorders	= MAX(CASE WHEN LTC = 'anxiety and other somatoform disorders' then 1 else 0 end),
		NEW_dementia						= MAX(CASE WHEN LTC = 'dementia' then 1 else 0 end),
		NEW_depression					= MAX(CASE WHEN LTC = 'depression' then 1 else 0 end),
		NEW_schizophrenia_or_bipolar		= MAX(CASE WHEN LTC = 'schizophrenia or bipolar' then 1 else 0 end),
		NEW_chronic_kidney_disease		= MAX(CASE WHEN LTC = 'chronic kidney disease' then 1 else 0 end),
		NEW_prostate_disorders			= MAX(CASE WHEN LTC = 'prostate disorders' then 1 else 0 end),
		NEW_asthma						= MAX(CASE WHEN LTC = 'asthma' then 1 else 0 end),
		NEW_bronchiectasis				= MAX(CASE WHEN LTC = 'bronchiectasis' then 1 else 0 end),
		NEW_chronic_sinusitis			= MAX(CASE WHEN LTC = 'chronic sinusitis' then 1 else 0 end),
		NEW_copd							= MAX(CASE WHEN LTC = 'copd' then 1 else 0 end),
		NEW_blindness_low_vision			= MAX(CASE WHEN LTC = 'blindness and low vision' then 1 else 0 end),
		NEW_glaucoma						= MAX(CASE WHEN LTC = 'glaucoma' then 1 else 0 end),
		NEW_hearing_loss					= MAX(CASE WHEN LTC = 'hearing loss' then 1 else 0 end),
		NEW_learning_disability			= MAX(CASE WHEN LTC = 'learning disability' then 1 else 0 end),
		NEW_alcohol_problems				= MAX(CASE WHEN LTC = 'alcohol problems' then 1 else 0 end),
		NEW_psychoactive_substance_abuse	= MAX(CASE WHEN LTC = 'psychoactive substance abuse' then 1 else 0 end)
INTO #NewLTCs
FROM #PatientsWithLTCs
WHERE FirstDate >= '2020-03-01'
GROUP BY FK_Patient_Link_ID


-- BRING TOGETHER FOR FINAL DATA EXTRACT

SELECT  
	PatientId = p.FK_Patient_Link_ID
	,HO_cancer = ISNULL(HO_cancer, 0)
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
	,HO_depression = ISNULL(HO_depression, 0)
	,HO_schizophrenia_or_bipolar = ISNULL(HO_schizophrenia_or_bipolar, 0)
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
	,NEW_cancer = ISNULL(NEW_cancer, 0)
	,NEW_painful_condition = ISNULL(NEW_painful_condition, 0)
	,NEW_migraine  = ISNULL(NEW_migraine , 0)
	,NEW_epilepsy = ISNULL(NEW_epilepsy, 0)
	,NEW_coronary_heart_disease  = ISNULL(NEW_coronary_heart_disease , 0)
	,NEW_atrial_fibrillation  = ISNULL(NEW_atrial_fibrillation , 0)
	,NEW_heart_failure = ISNULL(NEW_heart_failure, 0)
	,NEW_hypertension = ISNULL(NEW_hypertension, 0)
	,NEW_peripheral_vascular_disease = ISNULL(NEW_peripheral_vascular_disease, 0)
	,NEW_stroke_and_transient_ischaemic_attack = ISNULL(NEW_stroke_and_transient_ischaemic_attack, 0)
	,NEW_diabetes  = ISNULL(NEW_diabetes , 0)
	,NEW_thyroid_disorders  = ISNULL(NEW_thyroid_disorders , 0)
	,NEW_chronic_liver_disease  = ISNULL(NEW_chronic_liver_disease , 0)
	,NEW_diverticular_disease_of_intestine = ISNULL(NEW_diverticular_disease_of_intestine, 0)
	,NEW_inflammatory_bowel_disease  = ISNULL(NEW_inflammatory_bowel_disease , 0)
	,NEW_irritable_bowel_syndrome  = ISNULL(NEW_irritable_bowel_syndrome , 0)
	,NEW_constipation = ISNULL(NEW_constipation, 0)
	,NEW_dyspepsia = ISNULL(NEW_dyspepsia, 0)
	,NEW_peptic_ulcer_disease  = ISNULL(NEW_peptic_ulcer_disease , 0)
	,NEW_psoriasis_or_eczema  = ISNULL(NEW_psoriasis_or_eczema , 0)
	,NEW_rheumatoid_arthritis_other_inflammatory_polyarthropathies = ISNULL(NEW_rheumatoid_arthritis_other_inflammatory_polyarthropathies, 0)
	,NEW_multiple_sclerosis = ISNULL(NEW_multiple_sclerosis, 0)
	,NEW_parkinsons_disease  = ISNULL(NEW_parkinsons_disease , 0)
	,NEW_anorexia_bulimia  = ISNULL(NEW_anorexia_bulimia , 0)
	,NEW_anxiety_other_somatoform_disorders = ISNULL(NEW_anxiety_other_somatoform_disorders, 0)
	,NEW_dementia = ISNULL(NEW_dementia, 0)
	,NEW_depression = ISNULL(NEW_depression, 0)
	,NEW_schizophrenia_or_bipolar = ISNULL(NEW_schizophrenia_or_bipolar, 0)
	,NEW_chronic_kidney_disease = ISNULL(NEW_chronic_kidney_disease, 0)
	,NEW_prostate_disorders = ISNULL(NEW_prostate_disorders, 0)
	,NEW_asthma = ISNULL(NEW_asthma, 0)
	,NEW_bronchiectasis = ISNULL(NEW_bronchiectasis, 0)
	,NEW_chronic_sinusitis = ISNULL(NEW_chronic_sinusitis, 0)
	,NEW_copd = ISNULL(NEW_copd, 0)
	,NEW_blindness_low_vision = ISNULL(NEW_blindness_low_vision, 0)
	,NEW_glaucoma = ISNULL(NEW_glaucoma, 0)
	,NEW_hearing_loss = ISNULL(NEW_hearing_loss, 0)
	,NEW_learning_disability = ISNULL(NEW_learning_disability, 0)
	,NEW_alcohol_problems = ISNULL(NEW_alcohol_problems, 0)
	,NEW_psychoactive_substance_abuse = ISNULL(NEW_psychoactive_substance_abuse, 0)
FROM #Cohort p 
LEFT OUTER JOIN #HistoryOfLTCs ltc on ltc.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #NewLTCs nltc on nltc.FK_Patient_Link_ID = p.FK_Patient_Link_ID
