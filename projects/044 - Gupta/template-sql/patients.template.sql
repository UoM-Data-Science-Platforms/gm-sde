--┌──────────────────────────────────────────────┐
--│ Patients with multimorbidity and covid	     │
--└──────────────────────────────────────────────┘

-- REVIEW LOG:
--	

-- OUTPUT: Data with the following fields


DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2020-01-01';
SET @EndDate = '2022-05-01';

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

-- Set the date variables for the LTC code

DECLARE @IndexDate datetime;
DECLARE @MinDate datetime;
SET @IndexDate = '2020-03-01';
SET @MinDate = '1900-01-01';

--> EXECUTE query-patient-ltcs-date-range.sql
--> EXECUTE query-patient-ltcs-number-of.sql

-- FIND ALL PATIENTS WITH A MENTAL CONDITION

IF OBJECT_ID('tempdb..#PatientsWithMentalCondition') IS NOT NULL DROP TABLE #PatientsWithMentalCondition;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #PatientsWithMentalCondition
FROM #PatientsWithLTCs
WHERE LTC IN ('Anorexia Or Bulimia', 'Anxiety And Other Somatoform Disorders', 'Dementia', 'Depression', 'Schizophrenia Or Bipolar')
--872,174

-- FIND ALL PATIENTS WITH 2 OR MORE CONDITIONS, INCLUDING A MENTAL CONDITION

IF OBJECT_ID('tempdb..#2orMoreLTCsIncludingMental') IS NOT NULL DROP TABLE #2orMoreLTCsIncludingMental;
SELECT DISTINCT FK_Patient_Link_ID
INTO #2orMoreLTCsIncludingMental
FROM #NumLTCs 
WHERE NumberOfLTCs = 2
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsWithMentalCondition)
--677,226


-- find all covid tests for the cohort

IF OBJECT_ID('tempdb..#covidtests') IS NOT NULL DROP TABLE #covidtests;
SELECT 
      [FK_Patient_Link_ID]
      ,[EventDate]
      ,[MainCode]
      ,[CodeDescription]
      ,[GroupDescription]
      ,[SubGroupDescription]
	  ,TestOutcome = CASE WHEN GroupDescription = 'Confirmed'														then 'Positive'
			WHEN SubGroupDescription = '' and GroupDescription = 'Excluded'											then 'Negative'
			WHEN SubGroupDescription = '' and GroupDescription = 'Tested' and CodeDescription like '%not detected%' then 'Negative'
			WHEN SubGroupDescription = 'Offered' and GroupDescription = 'Tested'									then 'Unknown/Inconclusive'
			WHEN SubGroupDescription = 'Unknown' 																	then 'Unknown/Inconclusive'
			WHEN SubGroupDescription = '' and GroupDescription = 'Tested' and CodeDescription not like '%detected%' 
							and CodeDescription not like '%positive%' and CodeDescription not like '%negative%'		then 'Unknown/Inconclusive'
			WHEN SubGroupDescription != ''																			then SubGroupDescription
			WHEN SubGroupDescription = '' and CodeDescription like '%reslt unknow%'									then 'Unknown/Inconclusive'
							ELSE 'CHECK' END
INTO #covidtests
FROM [RLS].[vw_COVID19]
WHERE 
	(FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #2orMoreLTCsIncludingMental))
	--AND EventDate <= @StartDate
	and GroupDescription != 'Vaccination' 
	and GroupDescription not in ('Exposed', 'Suspected', 'Tested for immunity')
	and (GroupDescription != 'Unknown' and SubGroupDescription != '')


-- Get patient list of those with COVID death within 28 days of positive test
IF OBJECT_ID('tempdb..#COVIDDeath') IS NOT NULL DROP TABLE #COVIDDeath;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #COVIDDeath FROM RLS.vw_COVID19
WHERE DeathWithin28Days = 'Y'
	AND EventDate <= @EndDate


--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-imd.sql
--> EXECUTE query-patient-year-of-birth.sql
--> EXECUTE query-get-covid-vaccines.sql gp-events-table:RLS.vw_GP_Events gp-medications-table:RLS.vw_GP_Medications


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
GROUP BY FK_Patient_Link_ID


-- FIND ALL PATIENTS THAT MEET THE FOLLOWING CRITERIA:
	-- REGISTERED WITH A GM GP
	-- OVER  18
	-- HAD A COVID19 INFECTION
	-- 2 OR MORE LTCs INCLUDING ONE MENTAL CONDITION

IF OBJECT_ID('tempdb..#final') IS NOT NULL DROP TABLE #final;
SELECT DISTINCT 
	p.FK_Patient_Link_ID, 
	YearOfBirth, 
	Sex,
	EthnicMainGroup,
	LSOA_Code,
	IMD2019Decile1IsMostDeprived10IsLeastDeprived,
	DeathWithin28DaysCovid = CASE WHEN cd.FK_Patient_Link_ID  IS NOT NULL THEN 'Y' ELSE 'N' END,
	DeathDueToCovid_Year = CASE WHEN cd.FK_Patient_Link_ID IS NOT NULL THEN YEAR(p.DeathDate) ELSE null END,
	DeathDueToCovid_Month = CASE WHEN cd.FK_Patient_Link_ID IS NOT NULL THEN MONTH(p.DeathDate) ELSE null END,
	FirstVaccineYear =  YEAR(VaccineDose1Date),
	FirstVaccineMonth = MONTH(VaccineDose1Date),
	SecondVaccineYear =  YEAR(VaccineDose2Date),
	SecondVaccineMonth = MONTH(VaccineDose2Date),
	ThirdVaccineYear =  YEAR(VaccineDose3Date),
	ThirdVaccineMonth = MONTH(VaccineDose3Date)
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
INTO #Cohort
FROM #2orMoreLTCsIncludingMental p 
LEFT OUTER JOIN #PatientLSOA lsoa ON lsoa.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientIMDDecile imd ON imd.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDDeath cd ON cd.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDVaccinations vac ON vac.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #HistoryOfLTCs ltc on ltc.FK_Patient_Link_ID = m.FK_Patient_Link_ID
WHERE P.FK_Patient_Link_ID IN 
	(SELECT DISTINCT FK_Patient_Link_ID FROM #covidtests WHERE TestOutcome = 'Positive' )
	AND YEAR(@StartDate) - YearOfBirth >= 19 
	AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #2orMoreLTCsIncludingMental)
--70,845