--┌──────────────────────────────────────────────┐
--│ Diagnoses of non kidney-related conditions   │
--└──────────────────────────────────────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------

------------------------------------------------------


-- Set the start date
DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2018-03-01';
SET @EndDate = '2023-08-31';

--Just want the output, not the messages
SET NOCOUNT ON;

--> EXECUTE query-build-rq041-cohort.sql

-----------------------------------------------------------------------------------------------------------------------------------------
------------------- NOW COHORT HAS BEEN DEFINED, LOAD CODE SETS FOR ALL CONDITIONS/SYMPTOMS OF INTEREST ---------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------

--> CODESET sle:1 vasculitis:1 gout:1 haematuria:1 non-alc-fatty-liver-disease:1 hormone-replacement-therapy:1
--> CODESET long-covid:1 menopause:1 myeloma:1 obese:1 haematuria:1 osteoporosis:1
--> CODESET coronary-heart-disease:1 heart-failure:1 stroke:1 tia:1 peripheral-arterial-disease:1 
--> CODESET depression:1 schizophrenia-psychosis:1 bipolar:1 eating-disorders:1 anxiety:1 selfharm-episodes:1 uti:1
--> CODESET palliative-and-end-of-life-care:1 hypogonadotropic-hypogonadism:1
--> CODESET renal-replacement-therapy:1 acute-kidney-injury:1 polycystic-kidney-disease:1 family-history-kidney-disease:1 end-stage-renal-disease:1
--> CODESET ckd-stage-1:1 ckd-stage-2:1 ckd-stage-3:1 ckd-stage-4:1 ckd-stage-5:1 chronic-kidney-disease:1
--> CODESET allergy-ace:1 allergy-arb:1 allergy-aspirin:1 allergy-clopidogrel:1 allergy-statin:1

-- CREATE TABLES OF DISTINCT CODES AND CONCEPTS - TO REMOVE DUPLICATES IN FINAL TABLE

IF OBJECT_ID('tempdb..#VersionedCodeSetsUnique') IS NOT NULL DROP TABLE #VersionedCodeSetsUnique;
SELECT DISTINCT V.Concept, FK_Reference_Coding_ID, V.[Version]
INTO #VersionedCodeSetsUnique
FROM #VersionedCodeSets V

IF OBJECT_ID('tempdb..#VersionedSnomedSetsUnique') IS NOT NULL DROP TABLE #VersionedSnomedSetsUnique;
SELECT DISTINCT V.Concept, FK_Reference_SnomedCT_ID, V.[Version]
INTO #VersionedSnomedSetsUnique
FROM #VersionedSnomedSets V


---- CREATE OUTPUT TABLE OF DIAGNOSES AND SYMPTOMS, FOR THE COHORT OF INTEREST, AND CODING DATES 

IF OBJECT_ID('tempdb..#DiagnosesAndSymptoms') IS NOT NULL DROP TABLE #DiagnosesAndSymptoms;
SELECT FK_Patient_Link_ID, case when s.Concept is null then c.Concept else s.Concept end as Concept
INTO #DiagnosesAndSymptoms
FROM #PatientEventData gp
LEFT OUTER JOIN #VersionedSnomedSetsUnique s ON s.FK_Reference_SnomedCT_ID = gp.FK_Reference_SnomedCT_ID
LEFT OUTER JOIN #VersionedCodeSetsUnique c ON c.FK_Reference_Coding_ID = gp.FK_Reference_Coding_ID
WHERE gp.EventDate BETWEEN '1900-01-01' AND  @StartDate 
	AND (
	(gp.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSetsUnique WHERE (Concept NOT IN ('egfr','urinary-albumin-creatinine-ratio'))))
	OR
    (gp.FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSetsUnique WHERE (Concept NOT IN ('egfr','urinary-albumin-creatinine-ratio'))))
	)
GROUP BY FK_Patient_Link_ID, case when s.Concept is null then c.Concept else s.Concept end

-- FIND ALL CODES PER YEAR FOR EACH PATIENT

SELECT PatientId = FK_Patient_Link_ID,
	HO_sle = ISNULL(SUM(CASE WHEN Concept = 'sle' THEN 1 ELSE 0 END),0),
	HO_gout = ISNULL(SUM(CASE WHEN Concept = 'gout' THEN 1 ELSE 0 END),0),
	HO_non_alc_fatty_liver_disease = ISNULL(SUM(CASE WHEN Concept = 'non-alc-fatty-liver-disease' THEN 1 ELSE 0 END),0),
	HO_long_covid = ISNULL(SUM(CASE WHEN Concept = 'long-covid' THEN 1 ELSE 0 END),0),
	HO_menopause = ISNULL(SUM(CASE WHEN Concept = 'menopause' THEN 1 ELSE 0 END),0),
	HO_myeloma = ISNULL(SUM(CASE WHEN Concept = 'myeloma' THEN 1 ELSE 0 END),0),
	HO_obese = ISNULL(SUM(CASE WHEN Concept = 'obese' THEN 1 ELSE 0 END),0),
	HO_haematuria = ISNULL(SUM(CASE WHEN Concept = 'haematuria' THEN 1 ELSE 0 END),0),
	HO_osteoporosis = ISNULL(SUM(CASE WHEN Concept = 'osteoporosis' THEN 1 ELSE 0 END),0),
	HO_CHD = ISNULL(SUM(CASE WHEN Concept = 'coronary-heart-disease' THEN 1 ELSE 0 END),0),
	HO_HF = ISNULL(SUM(CASE WHEN Concept = 'heart-failure' THEN 1 ELSE 0 END),0),
	HO_stroke = ISNULL(SUM(CASE WHEN Concept = 'stroke' THEN 1 ELSE 0 END),0),
	HO_TIA = ISNULL(SUM(CASE WHEN Concept = 'tia' THEN 1 ELSE 0 END),0),
	HO_PAD = ISNULL(SUM(CASE WHEN Concept = 'peripheral-arterial-disease' THEN 1 ELSE 0 END),0),
	HO_depression = ISNULL(SUM(CASE WHEN Concept = 'depression' THEN 1 ELSE 0 END),0),
	HO_schizophrenia_psychosis = ISNULL(SUM(CASE WHEN Concept = 'schizophrenia-psychosis' THEN 1 ELSE 0 END),0),
	HO_bipolar = ISNULL(SUM(CASE WHEN Concept = 'bipolar' THEN 1 ELSE 0 END),0),
	HO_eating_disorders = ISNULL(SUM(CASE WHEN Concept = 'eating-disorders' THEN 1 ELSE 0 END),0),
	HO_selfharm = ISNULL(SUM(CASE WHEN Concept = 'selfharm-episodes' THEN 1 ELSE 0 END),0),
	HO_uti = ISNULL(SUM(CASE WHEN Concept = 'uti' THEN 1 ELSE 0 END),0),
	HO_palliative_and_eol_care = ISNULL(SUM(CASE WHEN Concept = 'palliative-and-end-of-life-care' THEN 1 ELSE 0 END),0),
	HO_hypogonadotropic_hypogonadism = ISNULL(SUM(CASE WHEN Concept = 'hypogonadotropic-hypogonadism' THEN 1 ELSE 0 END),0),
	HO_renal_replacement_therapy = ISNULL(SUM(CASE WHEN Concept = 'renal-replacement-therapy' THEN 1 ELSE 0 END),0),
	HO_acute_kidney_injury = ISNULL(SUM(CASE WHEN Concept = 'acute-kidney-injury' THEN 1 ELSE 0 END),0),
	HO_ckd_stage_1 = ISNULL(SUM(CASE WHEN Concept = 'ckd-stage-1' THEN 1 ELSE 0 END),0),
	HO_ckd_stage_2 = ISNULL(SUM(CASE WHEN Concept = 'ckd-stage-2' THEN 1 ELSE 0 END),0),
	HO_ckd_stage_3 = ISNULL(SUM(CASE WHEN Concept = 'ckd-stage-3' THEN 1 ELSE 0 END),0),
	HO_ckd_stage_4 = ISNULL(SUM(CASE WHEN Concept = 'ckd-stage-4' THEN 1 ELSE 0 END),0),
	HO_ckd_stage_5 = ISNULL(SUM(CASE WHEN Concept = 'ckd-stage-5' THEN 1 ELSE 0 END),0),
	HO_chronic_kidney_disease = ISNULL(SUM(CASE WHEN Concept = 'chronic-kidney-disease' THEN 1 ELSE 0 END),0),
	HO_polycystic_kidney_disease = ISNULL(SUM(CASE WHEN Concept = 'polycystic-kidney-disease' THEN 1 ELSE 0 END),0),
	HO_family_history_kidney_disease = ISNULL(SUM(CASE WHEN Concept = 'family-history-kidney-disease' THEN 1 ELSE 0 END),0),
	HO_end_stage_renal_disease = ISNULL(SUM(CASE WHEN Concept = 'end-stage-renal-disease' THEN 1 ELSE 0 END),0),
	HO_allergy_ace = ISNULL(SUM(CASE WHEN Concept = 'allergy-ace' THEN 1 ELSE 0 END),0),
	HO_allergy_arb = ISNULL(SUM(CASE WHEN Concept = 'allergy-arb' THEN 1 ELSE 0 END),0),
	HO_allergy_aspirin = ISNULL(SUM(CASE WHEN Concept = 'allergy-aspirin' THEN 1 ELSE 0 END),0),
	HO_allergy_clopidogrel = ISNULL(SUM(CASE WHEN Concept = 'allergy-clopidogrel' THEN 1 ELSE 0 END),0),
	HO_allergy_statin = ISNULL(SUM(CASE WHEN Concept = 'allergy-statin' THEN 1 ELSE 0 END),0),
	HO_glomerulonephritis = ISNULL(SUM(CASE WHEN Concept = 'glomerulonephritis' THEN 1 ELSE 0 END),0),
	HO_kidney_transplant = ISNULL(SUM(CASE WHEN Concept = 'kidney-transplant' THEN 1 ELSE 0 END),0),
	HO_kidney_stones = ISNULL(SUM(CASE WHEN Concept = 'kidney-stones' THEN 1 ELSE 0 END),0),
	HO_vasculitis = ISNULL(SUM(CASE WHEN Concept = 'vasculitis' THEN 1 ELSE 0 END),0)
FROM #DiagnosesAndSymptoms
GROUP BY FK_Patient_Link_ID
ORDER BY FK_Patient_Link_ID