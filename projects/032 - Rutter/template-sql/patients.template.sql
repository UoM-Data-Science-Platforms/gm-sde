--┌─────────────────────────────────────────────────────┐
--│ Patient information for diabetes cohort and controls│
--└─────────────────────────────────────────────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------


-- OUTPUT: Data with the following fields
-- Patient Id
-- Cohort (e.g. DMW/MyCognition/Oviva/DMW_and_MyCognition/control)
-- Age at index date (09/07/19)
-- Sex (M/F/U)
-- EthnicMainGroup (White/Black or Black British/Asian or Asian British/Mixed/Other/NotRecorded)
-- IMD Decile (1-10) (based on GP postcode)
-- DateOfEarliestT2DDiagnosis (dd/mm/yyyy)
-- DiabetesDuration (days) (number of days between diagnosis and index date)
-- HistoryOfComorbidities (this will be several columns: one for each co-morbidity)


-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2019-07-09';

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

--> CODESET diabetes-type-ii:1 polycystic-ovarian-syndrome:1 gestational-diabetes:1

--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-imd.sql
--> EXECUTE query-patient-year-of-birth.sql

--> EXECUTE query-patient-ltcs.sql

-- FIND PATIENTS WITH A DIAGNOSIS OF POLYCYSTIC OVARY SYNDROME OR GESTATIONAL DIABETES, TO EXCLUDE

IF OBJECT_ID('tempdb..#exclusions') IS NOT NULL DROP TABLE #exclusions;
SELECT DISTINCT gp.FK_Patient_Link_ID
INTO #exclusions
FROM [RLS].[vw_GP_Events] gp
LEFT OUTER JOIN #Patients p ON p.FK_Patient_Link_ID = gp.FK_Patient_Link_ID
WHERE SuppliedCode IN 
	(SELECT [Code] FROM #AllCodes WHERE [Concept] IN 
		('polycystic-ovarian-syndrome', 'gestational-diabetes') AND [Version] = 1)
			AND EventDate BETWEEN '2018-07-09' AND '2022-03-31'

---- CREATE TABLE OF ALL PATIENTS THAT HAVE ANY LIFETIME DIAGNOSES OF T2D OF 2019-07-09

IF OBJECT_ID('tempdb..#diabetes2_diagnoses') IS NOT NULL DROP TABLE #diabetes2_diagnoses;
SELECT gp.FK_Patient_Link_ID, 
		YearOfBirth, 
		Sex,
		EthnicMainGroup,
		IMD2019Decile1IsMostDeprived10IsLeastDeprived, --may need changing to IMD Score
		EventDate,
		SuppliedCode,
		[diabetes_type_ii_Code] = CASE WHEN SuppliedCode IN 
					( SELECT [Code] FROM #AllCodes WHERE [Concept] IN ('diabetes-type-ii') AND [Version] = 1 ) THEN 1 ELSE 0 END

INTO #diabetes2_diagnoses
FROM [RLS].[vw_GP_Events] gp
LEFT OUTER JOIN #Patients p ON p.FK_Patient_Link_ID = gp.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientIMDDecile imd ON imd.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE (SuppliedCode IN 
	(SELECT [Code] FROM #AllCodes WHERE [Concept] IN ('diabetes-type-ii') AND [Version] = 1)) 
    AND gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
	AND (gp.EventDate) <= '2019-07-09'
	AND YEAR('2019-07-09') - yob.YearOfBirth >= 18


-- Define the main cohort to be matched
IF OBJECT_ID('tempdb..#MainCohort') IS NOT NULL DROP TABLE #MainCohort;
SELECT DISTINCT FK_Patient_Link_ID, 
		YearOfBirth, -- NEED TO ENSURE OVER 18S ONLY AT SOME POINT
		Sex,
		EthnicMainGroup,
		IMD2019Decile1IsMostDeprived10IsLeastDeprived
INTO #MainCohort
FROM #diabetes2_diagnoses
--WHERE FK_Patient_Link_ID IN (#####INTERVENTION_TABLE)

/*

-- Define the population of potential matches for the cohort
IF OBJECT_ID('tempdb..#PotentialMatches') IS NOT NULL DROP TABLE #PotentialMatches;
SELECT DISTINCT p.FK_Patient_Link_ID, Sex, YearOfBirth
INTO #PotentialMatches
FROM #diabetes2_diagnoses
WHERE p.FK_Patient_Link_ID NOT IN (SELECT FK_Patient_Link_ID FROM #MainCohort)


--> EXECUTE query-cohort-matching-yob-sex-alt.sql yob-flex:1 num-matches:20


-- Get the matched cohort detail - same as main cohort
IF OBJECT_ID('tempdb..#MatchedCohort') IS NOT NULL DROP TABLE #MatchedCohort;
SELECT 
  c.MatchingPatientId AS FK_Patient_Link_ID,
  Sex,
  MatchingYearOfBirth,
  EthnicMainGroup,
  IMD2019Decile1IsMostDeprived10IsLeastDeprived, 
  PatientId AS PatientWhoIsMatched
INTO #MatchedCohort
FROM #CohortStore c
LEFT OUTER JOIN #Patients p ON p.FK_Patient_Link_ID = c.MatchingPatientId
LEFT OUTER JOIN #PatientIMDDecile imd ON imd.FK_Patient_Link_ID = c.MatchingPatientId
WHERE c.PatientId IN (SELECT FK_Patient_Link_ID FROM #Patients);



-- Define a table with all the patient ids for the main cohort and the matched cohort
IF OBJECT_ID('tempdb..#PatientIds') IS NOT NULL DROP TABLE #PatientIds;
SELECT PatientId AS FK_Patient_Link_ID INTO #PatientIds FROM #CohortStore
UNION
SELECT MatchingPatientId FROM #CohortStore;

*/

-- Find earliest diagnosis of T2D for each patient

IF OBJECT_ID('tempdb..#EarliestDiagnosis_T2D') IS NOT NULL DROP TABLE #EarliestDiagnosis_T2D;
SELECT FK_Patient_Link_ID
	,EarliestDiagnosis_T2D = MIN(CAST(EventDate AS date))
INTO #EarliestDiagnosis_T2D
FROM #diabetes2_diagnoses
WHERE diabetes_type_ii_Code = 1
GROUP BY FK_Patient_Link_ID



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
		HO_dementia						= MAX(CASE WHEN LTC = 'dementia' then 1 else 0 end),
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
GROUP BY FK_Patient_Link_ID


--bring together for final output
--patients in main cohort
SELECT	 PatientId = m.FK_Patient_Link_ID
		,Cohort = NULL
		,NULL AS MainCohortMatchedPatientId
		,AgeAtIndexDate =  YEAR('2019-07-09') - M.YearOfBirth
		,m.Sex
		,m.EthnicMainGroup
		,IMD2019Decile1IsMostDeprived10IsLeastDeprived
		,T2D_EarliestDiagnosisDate = t2d.EarliestDiagnosis_T2D
		,T2D_Duration = DATEDIFF(DAY, t2d.EarliestDiagnosis_T2D, '2019-07-09')
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
FROM #MainCohort m
LEFT OUTER JOIN RLS.vw_Patient_Link pl ON pl.PK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #HistoryOfLTCs ltc on ltc.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #EarliestDiagnosis_T2D t2d on t2d.FK_Patient_Link_ID = m.FK_Patient_Link_ID
WHERE M.FK_Patient_Link_ID in (SELECT FK_Patient_Link_ID FROM #Patients)
--UNION
----patients in matched cohort
--SELECT	 PatientId = m.FK_Patient_Link_ID
--		,Cohort = NULL
--		,m.PatientWhoIsMatched AS MainCohortMatchedPatientId		
--		,AgeAtIndexDate =  YEAR('2019-07-09') - M.YearOfBirth
--		,m.Sex
--		,m.EthnicMainGroup
--		,IMD2019Decile1IsMostDeprived10IsLeastDeprived
--		,T2D_EarliestDiagnosisDate = t2d.EarliestDiagnosis_T2D
--		,T2D_Duration = DATEDIFF(DAY, t2d.EarliestDiagnosis_T2D, '2019-07-19')
--		,HO_cancer = ISNULL(HO_painful_condition, 0)
--		,HO_painful_condition = ISNULL(HO_painful_condition, 0)
--		,HO_migraine  = ISNULL(HO_migraine , 0)
--		,HO_epilepsy = ISNULL(HO_epilepsy, 0)
--		,HO_coronary_heart_disease  = ISNULL(HO_coronary_heart_disease , 0)
--		,HO_atrial_fibrillation  = ISNULL(HO_atrial_fibrillation , 0)
--		,HO_heart_failure = ISNULL(HO_heart_failure, 0)
--		,HO_hypertension = ISNULL(HO_hypertension, 0)
--		,HO_peripheral_vascular_disease = ISNULL(HO_peripheral_vascular_disease, 0)
--		,HO_stroke_and_transient_ischaemic_attack = ISNULL(HO_stroke_and_transient_ischaemic_attack, 0)
--		,HO_diabetes  = ISNULL(HO_diabetes , 0)
--		,HO_thyroid_disorders  = ISNULL(HO_thyroid_disorders , 0)
--		,HO_chronic_liver_disease  = ISNULL(HO_chronic_liver_disease , 0)
--		,HO_diverticular_disease_of_intestine = ISNULL(HO_diverticular_disease_of_intestine, 0)
--		,HO_inflammatory_bowel_disease  = ISNULL(HO_inflammatory_bowel_disease , 0)
--		,HO_irritable_bowel_syndrome  = ISNULL(HO_irritable_bowel_syndrome , 0)
--		,HO_constipation = ISNULL(HO_constipation, 0)
--		,HO_dyspepsia = ISNULL(HO_dyspepsia, 0)
--		,HO_peptic_ulcer_disease  = ISNULL(HO_peptic_ulcer_disease , 0)
--		,HO_psoriasis_or_eczema  = ISNULL(HO_psoriasis_or_eczema , 0)
--		,HO_rheumatoid_arthritis_other_inflammatory_polyarthropathies = ISNULL(HO_rheumatoid_arthritis_other_inflammatory_polyarthropathies, 0)
--		,HO_multiple_sclerosis = ISNULL(HO_multiple_sclerosis, 0)
--		,HO_parkinsons_disease  = ISNULL(HO_parkinsons_disease , 0)
--		,HO_anorexia_bulimia  = ISNULL(HO_anorexia_bulimia , 0)
--		,HO_anxiety_other_somatoform_disorders = ISNULL(HO_anxiety_other_somatoform_disorders, 0)
--		,HO_dementia = ISNULL(HO_dementia, 0)
--		,HO_chronic_kidney_disease = ISNULL(HO_chronic_kidney_disease, 0)
--		,HO_prostate_disorders = ISNULL(HO_prostate_disorders, 0)
--		,HO_asthma = ISNULL(HO_asthma, 0)
--		,HO_bronchiectasis = ISNULL(HO_bronchiectasis, 0)
--		,HO_chronic_sinusitis = ISNULL(HO_chronic_sinusitis, 0)
--		,HO_copd = ISNULL(HO_copd, 0)
--		,HO_blindness_low_vision = ISNULL(HO_blindness_low_vision, 0)
--		,HO_glaucoma = ISNULL(HO_glaucoma, 0)
--		,HO_hearing_loss = ISNULL(HO_hearing_loss, 0)
--		,HO_learning_disability = ISNULL(HO_learning_disability, 0)
--		,HO_alcohol_problems = ISNULL(HO_alcohol_problems, 0)
--		,HO_psychoactive_substance_abuse = ISNULL(HO_psychoactive_substance_abuse, 0)
--FROM #MatchedCohort m
--LEFT OUTER JOIN RLS.vw_Patient_Link pl ON pl.PK_Patient_Link_ID = m.FK_Patient_Link_ID
--LEFT OUTER JOIN #HistoryOfLTCs ltc on ltc.FK_Patient_Link_ID = m.FK_Patient_Link_ID
--LEFT OUTER JOIN #EarliestDiagnosis_T2D t2d on t2d.FK_Patient_Link_ID = m.FK_Patient_Link_ID