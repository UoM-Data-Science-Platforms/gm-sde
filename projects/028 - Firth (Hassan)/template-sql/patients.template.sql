--┌────────────────────────────────────┐
--│ Self-harm episodes per month	     │
--└────────────────────────────────────┘

-- REVIEW LOG:

-- OUTPUT: Data with the following fields
-- Patient Id
-- Month and year of birth (YYYY-MM)
-- Sex (male/female)
-- Ethnicity (white/black/asian/mixed/other)
-- IMD score
-- LSOA code
-- GP practice (anon id)
-- Any hx of psychosis/schizophrenia (yes/no)
-- Earliest recorded date of psychosis/schizophrenia diagnosis (YYYY-MM or N/A)
-- Any hx of bipolar disorder (yes/no)
-- Earliest recorded date of bipolar diagnosis (YYYY-MM or N/A)
-- Any hx of major depressive disorder (yes/no)
-- Earliest recorded date of MDD diagnosis (YYYY-MM or N/A)
-- Recent (12 months) major depression (yes/no)
-- H/O comorbid physical health conditions (all yes/no plus earliest recorded date): coronary heart disease, myocardial infarction, asthma, bronchiectasis, COPD, pulmonary fibrosis, cystic fibrosis,  cancer (within 5 years), dementia,  diabetes, chronic kidney disease, liver disease, hemiplegia, rheumatoid arthritis and other inflammatory diseases,  thyroid disorders, and/or HIV/AIDS
-- Death after 31.01.2020 (yes/no)
-- Death within 28 days of Covid Diagnosis (yes/no)
-- Date of death due to Covid-19 (YYYY-MM or N/A)
-- Vaccination offered (yes/no)
-- Patient refused vaccination (yes/no)
-- Date of vaccination (YYYY-MM or N/A)


--Just want the output, not the messages
SET NOCOUNT ON;

-- *************** INTERIM WORKAROUND DUE TO MISSING PATIENT_LINK_ID'S ***************************
-- find patient_id for all patients, this will be used to link the gp_events table to patient_link
-- ***********************************************************************************************

IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT P.PK_Patient_ID, PL.PK_Patient_Link_ID AS FK_Patient_Link_ID, PL.EthnicMainGroup
INTO #Patients 
FROM [RLS].vw_Patient P
LEFT JOIN [RLS].vw_Patient_Link PL ON P.FK_Patient_Link_ID = PL.PK_Patient_Link_ID

--> EXECUTE load-code-sets.sql
--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-imd.sql
--> EXECUTE query-patient-year-of-birth.sql
--> EXECUTE query-patient-practice-and-ccg.sql

--> EXECUTE query-get-patient-ltcs.sql
--> EXECUTE query-patient-ltcs-group.sql


-- CREATE WIDE TABLE SHOWING WHICH PATIENTS HAVE A HISTORY OF EACH LTC

SELECT FK_Patient_Link_ID,
		HO_coronary_heart_disease 		= MAX(CASE WHEN LTC = 'coronary heart disease' then 1 else 0 end),
		HO_atrial_fibrillation 			= MAX(CASE WHEN LTC = 'atrial fibrillation' then 1 else 0 end),
		HO_heart_failure 				= MAX(CASE WHEN LTC = 'heart failure' then 1 else 0 end),
		HO_hypertension 				= MAX(CASE WHEN LTC = 'hypertension' then 1 else 0 end),
		HO_peripheral_vascular_disease = MAX(CASE WHEN LTC = 'peripheral vascular disease' then 1 else 0 end),
		HO_stroke_and_transient_ischaemic_attack = MAX(CASE WHEN LTC = 'stroke & transient ischaemic attack' then 1 else 0 end),
		HO_diabetes 					= MAX(CASE WHEN LTC = 'diabetes' then 1 else 0 end),
		HO_thyroid_disorders 					= MAX(CASE WHEN LTC = 'thyroid disorders' then 1 else 0 end),
		HO_chronic_liver_disease 		= MAX(CASE WHEN LTC = 'chronic liver disease' then 1 else 0 end),
		HO_chronic_liver_disease_and_viral_hepatitis = MAX(CASE WHEN LTC = 'chronic liver disease and viral hepatitis' then 1 else 0 end),
		HO_constipation_treated 				= MAX(CASE WHEN LTC = 'constipation (treated)' then 1 else 0 end),
		HO_diverticular_disease_of_intestine = MAX(CASE WHEN LTC = 'diverticular disease of intestine' then 1 else 0 end),
		HO_dyspepsia_treated 					= MAX(CASE WHEN LTC = 'dyspepsia (treated)' then 1 else 0 end),
		HO_inflammatory_bowel_disease 			= MAX(CASE WHEN LTC = 'inflammatory bowel disease' then 1 else 0 end),
		HO_irritable_bowel_syndrome 			= MAX(CASE WHEN LTC = 'irritable bowel syndrome' then 1 else 0 end),
		HO_peptic_ulcer_disease 				= MAX(CASE WHEN LTC = 'peptic ulcer disease' then 1 else 0 end),
		HO_psoriasis 							= MAX(CASE WHEN LTC = 'psoriasis' then 1 else 0 end),
		HO_psoriasis_or_eczema medcodes 		= MAX(CASE WHEN LTC = 'psoriasis or eczema medcodes' then 1 else 0 end),
		HO_rheumatoid_arthritis_other_inflammatory_polyarthropathies_and_systematic_connective_tissue_disorders			= MAX(CASE WHEN LTC = 'rheumatoid arthritis, other inflammatory polyarthropathies & systematic connective tissue disorders' then 1 else 0 end),
		HO_rheumatoid_arthritis_sle				= MAX(CASE WHEN LTC = 'rheumatoid arthritis, sle' then 1 else 0 end),
		HO_multiple_sclerosis					= MAX(CASE WHEN LTC = 'multiple sclerosis' then 1 else 0 end),
		HO_other neurological conditions 		= MAX(CASE WHEN LTC = 'other neurological conditions' then 1 else 0 end),
		HO_parkinsons_disease 		= MAX(CASE WHEN LTC = 'parkinsons disease' then 1 else 0 end),
		HO_dementia			= MAX(CASE WHEN LTC = 'dementia' then 1 else 0 end),
		HO_chronic kidney disease				= MAX(CASE WHEN LTC = 'chronic kidney disease' then 1 else 0 end),
		HO_asthma				= MAX(CASE WHEN LTC IN 
									('asthma (currently treated) medcodes', 'asthma (currently treated) prodcodes', 'asthma diagnosis', 'asthma') then 1 else 0 end),
		HO_bronchiectasis				= MAX(CASE WHEN LTC = 'bronchiectasis' then 1 else 0 end),
		HO_copd				= MAX(CASE WHEN LTC = 'copd' then 1 else 0 end),
		HO_learning disability				= MAX(CASE WHEN LTC = 'learning disability' then 1 else 0 end)
INTO #HistoryOfLTCs
FROM #PatientsWithLTCs
GROUP BY FK_Patient_Link_ID

---- CREATE TABLE OF ALL PATIENTS THAT HAVE ANY LIFETIME DIAGNOSES OF SMI AS OF 31.01.20

IF OBJECT_ID('tempdb..#SMI_Episodes') IS NOT NULL DROP TABLE #SMI_Episodes;
SELECT gp.FK_Patient_Link_ID, 
		YearOfBirth -- may need month adding
		Sex,
		EthnicMainGroup,
		IMD2019Decile1IsMostDeprived10IsLeastDeprived, --may need changing to IMD Score
		GPPracticeCode, -- needs anonymising
		EventDate,
		SuppliedCode,
		Schizophrenia_Code = CASE WHEN SuppliedCode IN 
					( SELECT [Code] FROM #AllCodes WHERE [Concept] IN ('schizophrenia') AND [Version] = 1 ) THEN 1 ELSE 0 END,
		Bipolar_Code = CASE WHEN SuppliedCode IN 
					( SELECT [Code] FROM #AllCodes WHERE [Concept] IN ('bipolar') AND [Version] = 1 ) THEN 1 ELSE 0 END,			
		Major_Depression_Code = CASE WHEN SuppliedCode IN 
					( SELECT [Code] FROM #AllCodes WHERE [Concept] IN ('major-depression') AND [Version] = 1 ) THEN 1 ELSE 0 END,
					

INTO #SMI_Episodes
FROM [RLS].[vw_GP_Events] gp
LEFT OUTER JOIN #Patients p ON p.PK_Patient_ID = gp.FK_Patient_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientIMDDecile imd ON imd.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientsWithLTCs ltc ON ltc.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE SuppliedCode IN (
	SELECT [Code] FROM #AllCodes WHERE [Concept] IN ('severe-mental-illness') AND [Version] = 1
)
	AND (gp.EventDate) <= '2020-01-31'


SELECT smi.*, ltc.*
	CASE WHEN FK_Patient_Link_ID IN 
				(SELECT FK_Patient_Link_ID FROM #SMI_Patients WHERE SuppliedCode IN 
								( SELECT [Code] FROM #AllCodes WHERE [Concept] IN ('severe-mental-illness') AND [Version] = 1 )
INTO #SMI_Patients
FROM #SMI_Episodes smi
LEFT JOIN #HistoryOfLTCs ltc on ltc.FK_Patient_Link_ID = smi.FK_Patient_Link_ID

