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

IF OBJECT_ID('tempdb..#PatientsToInclude') IS NOT NULL DROP TABLE #PatientsToInclude;
SELECT FK_Patient_Link_ID INTO #PatientsToInclude
FROM RLS.vw_Patient_GP_History
GROUP BY FK_Patient_Link_ID
HAVING MIN(StartDate) < '2022-06-01';

-- Set the date variables for the LTC code

DECLARE @IndexDate datetime;
DECLARE @MinDate datetime;
SET @IndexDate = '2022-05-01';
SET @MinDate = '1900-01-01';

--> EXECUTE query-patient-ltcs-date-range.sql 
--> EXECUTE query-patient-ltcs-number-of.sql

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


--> EXECUTE query-patient-year-of-birth.sql
--> EXECUTE query-patients-with-covid.sql start-date:2020-01-01 gp-events-table:RLS.vw_GP_Events all-patients:false

------------------------------------ CREATE COHORT -------------------------------------
	-- REGISTERED WITH A GM GP
	-- OVER  18
	-- HAD A COVID19 INFECTION
	-- 2 OR MORE LTCs INCLUDING ONE MENTAL CONDITION (diagnosed before March 2020)

IF OBJECT_ID('tempdb..#Cohort') IS NOT NULL DROP TABLE #Cohort;
SELECT p.FK_Patient_Link_ID, 
	EthnicMainGroup,
	DeathDate,
	yob.YearOfBirth
INTO #Cohort
FROM #Patients p
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE YEAR(@StartDate) - YearOfBirth >= 19 														 -- Over 18
	AND p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #CovidPatientsMultipleDiagnoses) -- had at least one covid19 infection
	AND p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #2orMoreLTCsIncludingMental)     -- at least 2 LTCs including one mental
	AND p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude) 			 -- exclude new patients processed post-COPI notice

-- Get patient list of those with COVID death within 28 days of positive test
IF OBJECT_ID('tempdb..#COVIDDeath') IS NOT NULL DROP TABLE #COVIDDeath;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #COVIDDeath FROM RLS.vw_COVID19
WHERE DeathWithin28Days = 'Y'
	AND EventDate <= @EndDate


-- TABLE OF GP EVENTS FOR COHORT TO SPEED UP REUSABLE QUERIES

IF OBJECT_ID('tempdb..#PatientEventData') IS NOT NULL DROP TABLE #PatientEventData;
SELECT 
  FK_Patient_Link_ID,
  CAST(EventDate AS DATE) AS EventDate,
  SuppliedCode,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID,
  [Value]
INTO #PatientEventData
FROM [RLS].vw_GP_Events
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort);


--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-imd.sql
--> EXECUTE query-patient-lsoa.sql
--> EXECUTE query-patient-bmi.sql gp-events-table:#PatientEventData
--> EXECUTE query-patient-smoking-status.sql gp-events-table:#PatientEventData
--> EXECUTE query-patient-care-home-resident.sql

--> EXECUTE query-get-covid-vaccines.sql gp-events-table:#PatientEventData gp-medications-table:RLS.vw_GP_Medications

-- CREATE WIDE TABLE SHOWING WHICH PATIENTS HAVE A HISTORY OF EACH LTC

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


------------------------------- OBSERVATIONS -------------------------------------

--> CODESET systolic-blood-pressure:1 diastolic-blood-pressure:1 hba1c:2
--> CODESET cholesterol:2 ldl-cholesterol:1 hdl-cholesterol:1 triglycerides:1 egfr:1

-- CREATE TABLE OF OBSERVATIONS REQUESTED BY THE PI

IF OBJECT_ID('tempdb..#observations') IS NOT NULL DROP TABLE #observations;
SELECT 
	FK_Patient_Link_ID,
	CAST(EventDate AS DATE) AS EventDate,
	Concept = CASE WHEN sn.Concept IS NOT NULL THEN sn.Concept ELSE co.Concept END,
	[Version] =  CASE WHEN sn.[Version] IS NOT NULL THEN sn.[Version] ELSE co.[Version] END,
	[Value] = TRY_CONVERT(NUMERIC (18,5), [Value]),
	[Units]
INTO #observations
FROM #PatientEventData gp
LEFT JOIN #VersionedSnomedSets sn ON sn.FK_Reference_SnomedCT_ID = gp.FK_Reference_SnomedCT_ID
LEFT JOIN #VersionedCodeSets co ON co.FK_Reference_Coding_ID = gp.FK_Reference_Coding_ID
WHERE
	((gp.FK_Reference_SnomedCT_ID IN (
		SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept In ('systolic-blood-pressure', 'diastolic-blood-pressure', 'ldl-cholesterol', 'hdl-cholesterol', 'triglycerides', 'egfr') AND [Version] = 1) 
			OR Concept IN ('hba1c', 'cholesterol') AND [Version] = 2 )
		OR (gp.FK_Reference_Coding_ID   IN (
		SELECT FK_Reference_Coding_ID   FROM #VersionedCodeSets   WHERE Concept In ('systolic-blood-pressure', 'diastolic-blood-pressure', 'ldl-cholesterol', 'hdl-cholesterol', 'triglycerides', 'egfr') AND [Version] = 1) 
			OR Concept IN ('hba1c', 'cholesterol') AND [Version] = 2 ))

	AND gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort)
	AND [Value] IS NOT NULL AND [Value] != '0' AND UPPER([Value]) NOT LIKE '%[A-Z]%'  -- CHECKS IN CASE ANY ZERO, NULL OR TEXT VALUES REMAINED


-- WHERE CODES EXIST IN BOTH VERSIONS OF THE CODE SET (OR IN OTHER SIMILAR CODE SETS), THERE WILL BE DUPLICATES, SO EXCLUDE THEM FROM THE SETS/VERSIONS THAT WE DON'T WANT 

IF OBJECT_ID('tempdb..#all_observations') IS NOT NULL DROP TABLE #all_observations;
select 
	FK_Patient_Link_ID, CAST(EventDate AS DATE) EventDate, Concept, [Value], [Units], [Version]
into #all_observations
from #observations
except
select FK_Patient_Link_ID, EventDate, Concept, [Value], [Units], [Version] from #observations 
where 
	(Concept = 'cholesterol' and [Version] <> 2) OR -- e.g. serum HDL cholesterol appears in cholesterol v1 code set, which we don't want, but we do want the code as part of the hdl-cholesterol code set.
	(Concept = 'hba1c' and [Version] <> 2) -- e.g. hba1c level appears twice with same value: from version 1 and version 2. We only want version 2 so exclude any others.
	AND [Value] > 0

-- FIND CLOSEST OBSERVATIONS BEFORE AND AFTER FIRST COVID POSITIVE DATE

IF OBJECT_ID('tempdb..#most_recent_date_before_covid') IS NOT NULL DROP TABLE #most_recent_date_before_covid;
SELECT o.FK_Patient_Link_ID, Concept, MAX(EventDate) as MostRecentDate
INTO #most_recent_date_before_covid
FROM #all_observations o
LEFT OUTER JOIN #CovidPatientsMultipleDiagnoses cv ON cv.FK_Patient_Link_ID = o.FK_Patient_Link_ID
WHERE EventDate < cv.FirstCovidPositiveDate
GROUP BY o.FK_Patient_Link_ID, Concept

IF OBJECT_ID('tempdb..#most_recent_date_after_covid') IS NOT NULL DROP TABLE #most_recent_date_after_covid;
SELECT o.FK_Patient_Link_ID, Concept, MIN(EventDate) as MostRecentDate
INTO #most_recent_date_after_covid
FROM #all_observations o
LEFT OUTER JOIN #CovidPatientsMultipleDiagnoses cv ON cv.FK_Patient_Link_ID = o.FK_Patient_Link_ID
WHERE EventDate >= cv.FirstCovidPositiveDate
GROUP BY o.FK_Patient_Link_ID, Concept

IF OBJECT_ID('tempdb..#closest_observations') IS NOT NULL DROP TABLE #closest_observations;
SELECT o.FK_Patient_Link_ID, 
	o.EventDate, 
	o.Concept, 
	o.[Value], 
	o.[Units],
	BeforeOrAfterCovid = CASE WHEN bef.MostRecentDate = o.EventDate THEN 'before' WHEN aft.MostRecentDate = o.EventDate THEN 'after' ELSE 'check' END,
	ROW_NUM = ROW_NUMBER () OVER (PARTITION BY o.FK_Patient_Link_ID, o.EventDate, o.Concept ORDER BY [Value] DESC) -- THIS WILL BE USED IN NEXT QUERY TO TAKE THE MAX VALUE WHERE THERE ARE MULTIPLE
INTO #closest_observations
FROM #all_observations o
LEFT JOIN #most_recent_date_before_covid bef ON bef.FK_Patient_Link_ID = o.FK_Patient_Link_ID AND bef.MostRecentDate = o.EventDate and bef.Concept = o.Concept
LEFT JOIN #most_recent_date_after_covid aft ON aft.FK_Patient_Link_ID = o.FK_Patient_Link_ID AND aft.MostRecentDate = o.EventDate and aft.Concept = o.Concept
WHERE bef.MostRecentDate = o.EventDate OR aft.MostRecentDate = o.EventDate

-- CREATE WIDE TABLE WITH CLOSEST OBSERVATIONS BEFORE AND AFTER COVID POSITIVE DATE

IF OBJECT_ID('tempdb..#observations_wide') IS NOT NULL DROP TABLE #observations_wide;
SELECT
	 FK_Patient_Link_ID
	,SystolicBP_1 = MAX(CASE WHEN [Concept] = 'systolic-blood-pressure' AND BeforeOrAfterCovid = 'before' THEN [Value] ELSE NULL END)
	,SystolicBP_1_dt = MAX(CASE WHEN [Concept] = 'systolic-blood-pressure' AND BeforeOrAfterCovid = 'before' THEN EventDate ELSE NULL END)
	,SystolicBP_2 = MAX(CASE WHEN [Concept] = 'systolic-blood-pressure' AND BeforeOrAfterCovid = 'after' THEN [Value] ELSE NULL END)
	,SystolicBP_2_dt = MAX(CASE WHEN [Concept] = 'systolic-blood-pressure' AND BeforeOrAfterCovid = 'after' THEN EventDate ELSE NULL END)
	,diastolicBP_1 = MAX(CASE WHEN [Concept] = 'diastolic-blood-pressure' AND BeforeOrAfterCovid = 'before' THEN [Value] ELSE NULL END)
	,diastolicBP_1_dt = MAX(CASE WHEN [Concept] = 'diastolic-blood-pressure' AND BeforeOrAfterCovid = 'before' THEN EventDate ELSE NULL END)
	,diastolicBP_2 = MAX(CASE WHEN [Concept] = 'diastolic-blood-pressure' AND BeforeOrAfterCovid = 'after' THEN [Value] ELSE NULL END)
	,diastolicBP_2_dt = MAX(CASE WHEN [Concept] = 'diastolic-blood-pressure' AND BeforeOrAfterCovid = 'after' THEN EventDate ELSE NULL END)
	,cholesterol_1 = MAX(CASE WHEN [Concept] = 'cholesterol' AND BeforeOrAfterCovid = 'before' THEN [Value] ELSE NULL END)
	,cholesterol_1_dt = MAX(CASE WHEN [Concept] = 'cholesterol' AND BeforeOrAfterCovid = 'before' THEN EventDate ELSE NULL END)
	,cholesterol_2 = MAX(CASE WHEN [Concept] = 'cholesterol' AND BeforeOrAfterCovid = 'after' THEN [Value] ELSE NULL END)
	,cholesterol_2_dt = MAX(CASE WHEN [Concept] = 'cholesterol' AND BeforeOrAfterCovid = 'after' THEN EventDate ELSE NULL END)
	,HDLcholesterol_1 = MAX(CASE WHEN [Concept] = 'hdl-cholesterol' AND BeforeOrAfterCovid = 'before' THEN [Value] ELSE NULL END)
	,HDLcholesterol_1_dt = MAX(CASE WHEN [Concept] = 'hdl-cholesterol' AND BeforeOrAfterCovid = 'before' THEN EventDate ELSE NULL END)
	,HDLcholesterol_2 = MAX(CASE WHEN [Concept] = 'hdl-cholesterol' AND BeforeOrAfterCovid = 'after' THEN [Value] ELSE NULL END)
	,HDLcholesterol_2_dt = MAX(CASE WHEN [Concept] = 'hdl-cholesterol' AND BeforeOrAfterCovid = 'after' THEN EventDate ELSE NULL END)
	,LDL_cholesterol_1 = MAX(CASE WHEN [Concept] = 'ldl-cholesterol' AND BeforeOrAfterCovid = 'before' THEN [Value] ELSE NULL END)
	,LDL_cholesterol_1_dt = MAX(CASE WHEN [Concept] = 'ldl-cholesterol' AND BeforeOrAfterCovid = 'before' THEN EventDate ELSE NULL END)
	,LDL_cholesterol_2 = MAX(CASE WHEN [Concept] = 'ldl-cholesterol' AND BeforeOrAfterCovid = 'after' THEN [Value] ELSE NULL END)
	,LDL_cholesterol_2_dt = MAX(CASE WHEN [Concept] = 'ldl-cholesterol' AND BeforeOrAfterCovid = 'after' THEN EventDate ELSE NULL END)
	,Triglyceride_1 = MAX(CASE WHEN [Concept] = 'triglycerides' AND BeforeOrAfterCovid = 'before' THEN [Value] ELSE NULL END)
	,Triglyceride_1_dt = MAX(CASE WHEN [Concept] = 'triglycerides' AND BeforeOrAfterCovid = 'before' THEN EventDate ELSE NULL END)
	,Triglyceride_2 = MAX(CASE WHEN [Concept] = 'triglycerides' AND BeforeOrAfterCovid = 'after' THEN [Value] ELSE NULL END)
	,Triglyceride_2_dt = MAX(CASE WHEN [Concept] = 'triglycerides' AND BeforeOrAfterCovid = 'after' THEN EventDate ELSE NULL END)
	,egfr_1 = MAX(CASE WHEN [Concept] = 'egfr' AND BeforeOrAfterCovid = 'before' THEN [Value] ELSE NULL END)
	,egfr_1_dt = MAX(CASE WHEN [Concept] = 'egfr' AND BeforeOrAfterCovid = 'before' THEN EventDate ELSE NULL END)
	,egfr_2 = MAX(CASE WHEN [Concept] = 'egfr' AND BeforeOrAfterCovid = 'after' THEN [Value] ELSE NULL END)
	,egfr_2_dt = MAX(CASE WHEN [Concept] = 'egfr' AND BeforeOrAfterCovid = 'after' THEN EventDate ELSE NULL END)
	,hba1c_1 = MAX(CASE WHEN [Concept] = 'hba1c' AND BeforeOrAfterCovid = 'before' THEN [Value] ELSE NULL END)
	,hba1c_1_dt = MAX(CASE WHEN [Concept] = 'hba1c' AND BeforeOrAfterCovid = 'before' THEN EventDate ELSE NULL END)
	,hba1c_2 = MAX(CASE WHEN [Concept] = 'hba1c' AND BeforeOrAfterCovid = 'after' THEN [Value] ELSE NULL END)
	,hba1c_2_dt = MAX(CASE WHEN [Concept] = 'hba1c' AND BeforeOrAfterCovid = 'after' THEN EventDate ELSE NULL END)
INTO #observations_wide
FROM #closest_observations
WHERE ROW_NUM = 1
GROUP BY FK_Patient_Link_ID


-- BRING TOGETHER FOR FINAL DATA EXTRACT


SELECT  
	p.FK_Patient_Link_ID, 
	p.YearOfBirth, 
	Sex,
	BMI,
	BMIDate = bmi.EventDate,
	CurrentSmokingStatus = smok.CurrentSmokingStatus,
	WorstSmokingStatus = smok.WorstSmokingStatus,
	p.EthnicMainGroup,
	LSOA_Code,
	IMD2019Decile1IsMostDeprived10IsLeastDeprived,
	IsCareHomeResident,
	DeathWithin28DaysCovid = CASE WHEN cd.FK_Patient_Link_ID  IS NOT NULL THEN 'Y' ELSE 'N' END,
	DeathDueToCovid_Year = CASE WHEN cd.FK_Patient_Link_ID IS NOT NULL THEN YEAR(p.DeathDate) ELSE null END,
	DeathDueToCovid_Month = CASE WHEN cd.FK_Patient_Link_ID IS NOT NULL THEN MONTH(p.DeathDate) ELSE null END,
	FirstCovidPositiveDate,
	SecondCovidPositiveDate, 
	ThirdCovidPositiveDate, 
	FourthCovidPositiveDate, 
	FifthCovidPositiveDate,
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
	,NEW_cancer = ISNULL(NEW_painful_condition, 0)
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
	,SystolicBP_1
	,SystolicBP_1_dt 
	,SystolicBP_2
	,SystolicBP_2_dt 
	,diastolicBP_1
	,diastolicBP_1_dt
	,diastolicBP_2
	,diastolicBP_2_dt
	,cholesterol_1
	,cholesterol_1_dt
	,cholesterol_2
	,cholesterol_2_dt
	,HDLcholesterol_1
	,HDLcholesterol_1_dt 
	,HDLcholesterol_2
	,HDLcholesterol_2_dt 
	,LDL_cholesterol_1
	,LDL_cholesterol_1_dt
	,LDL_cholesterol_2
	,LDL_cholesterol_2_dt
	,Triglyceride_1
	,Triglyceride_1_dt
	,Triglyceride_2
	,Triglyceride_2_dt
	,egfr_1
	,egfr_1_dt 
	,egfr_2
	,egfr_2_dt 
	,hba1c_1
	,hba1c_1_dt
	,hba1c_2
	,hba1c_2_dt
FROM #Cohort p 
LEFT OUTER JOIN #PatientLSOA lsoa ON lsoa.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientIMDDecile imd ON imd.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientBMI bmi ON bmi.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSmokingStatus smok ON smok.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDDeath cd ON cd.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDVaccinations vac ON vac.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #CovidPatientsMultipleDiagnoses cv ON cv.FK_Patient_Link_ID = P.FK_Patient_Link_ID
LEFT OUTER JOIN #HistoryOfLTCs ltc on ltc.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #NewLTCs nltc on nltc.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #observations_wide obs on obs.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientCareHomeStatus ch on ch.FK_Patient_Link_ID = p.FK_Patient_Link_ID 