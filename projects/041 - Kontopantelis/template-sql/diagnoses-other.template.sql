--┌──────────────────────────────────────────────┐
--│ Diagnoses of non kidney-related conditions   │
--└──────────────────────────────────────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------

------------------------------------------------------


-- Set the start date
DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2018-03-01';
SET @EndDate = '2022-03-01';

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
SELECT FK_Patient_Link_ID, EventDate, case when s.Concept is null then c.Concept else s.Concept end as Concept
INTO #DiagnosesAndSymptoms
FROM #PatientEventData gp
LEFT OUTER JOIN #VersionedSnomedSetsUnique s ON s.FK_Reference_SnomedCT_ID = gp.FK_Reference_SnomedCT_ID
LEFT OUTER JOIN #VersionedCodeSetsUnique c ON c.FK_Reference_Coding_ID = gp.FK_Reference_Coding_ID
WHERE gp.EventDate BETWEEN @StartDate AND @EndDate
AND (
	(gp.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSetsUnique WHERE (Concept NOT IN ('egfr','urinary-albumin-creatinine-ratio','glomerulonephritis', 'kidney-transplant', 'kidney-stones', 'vasculitis'))))
	OR
    (gp.FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSetsUnique WHERE (Concept NOT IN ('egfr','urinary-albumin-creatinine-ratio','glomerulonephritis', 'kidney-transplant', 'kidney-stones', 'vasculitis'))))
);

-- FIND ALL CODES PER YEAR FOR EACH PATIENT

SELECT PatientId = FK_Patient_Link_ID,
	[Year] = YEAR(EventDate),
	sle = ISNULL(SUM(CASE WHEN Concept = 'sle' THEN 1 ELSE 0 END),0),
	gout = ISNULL(SUM(CASE WHEN Concept = 'gout' THEN 1 ELSE 0 END),0),
	non_alc_fatty_liver_disease = ISNULL(SUM(CASE WHEN Concept = 'non-alc-fatty-liver-disease' THEN 1 ELSE 0 END),0),
	long_covid = ISNULL(SUM(CASE WHEN Concept = 'long-covid' THEN 1 ELSE 0 END),0),
	menopause = ISNULL(SUM(CASE WHEN Concept = 'menopause' THEN 1 ELSE 0 END),0),
	myeloma = ISNULL(SUM(CASE WHEN Concept = 'myeloma' THEN 1 ELSE 0 END),0),
	obese = ISNULL(SUM(CASE WHEN Concept = 'obese' THEN 1 ELSE 0 END),0),
	haematuria = ISNULL(SUM(CASE WHEN Concept = 'haematuria' THEN 1 ELSE 0 END),0),
	osteoporosis = ISNULL(SUM(CASE WHEN Concept = 'osteoporosis' THEN 1 ELSE 0 END),0),
	CHD = ISNULL(SUM(CASE WHEN Concept = 'coronary-heart-disease' THEN 1 ELSE 0 END),0),
	HF = ISNULL(SUM(CASE WHEN Concept = 'heart-failure' THEN 1 ELSE 0 END),0),
	stroke = ISNULL(SUM(CASE WHEN Concept = 'stroke' THEN 1 ELSE 0 END),0),
	TIA = ISNULL(SUM(CASE WHEN Concept = 'tia' THEN 1 ELSE 0 END),0),
	PAD = ISNULL(SUM(CASE WHEN Concept = 'peripheral-arterial-disease' THEN 1 ELSE 0 END),0),
	depression = ISNULL(SUM(CASE WHEN Concept = 'depression' THEN 1 ELSE 0 END),0),
	schizophrenia_psychosis = ISNULL(SUM(CASE WHEN Concept = 'schizophrenia-psychosis' THEN 1 ELSE 0 END),0),
	bipolar = ISNULL(SUM(CASE WHEN Concept = 'bipolar' THEN 1 ELSE 0 END),0),
	eating_disorders = ISNULL(SUM(CASE WHEN Concept = 'eating-disorders' THEN 1 ELSE 0 END),0),
	selfharm = ISNULL(SUM(CASE WHEN Concept = 'selfharm-episodes' THEN 1 ELSE 0 END),0),
	uti = ISNULL(SUM(CASE WHEN Concept = 'uti' THEN 1 ELSE 0 END),0),
	palliative_and_eol_care = ISNULL(SUM(CASE WHEN Concept = 'palliative-and-end-of-life-care' THEN 1 ELSE 0 END),0),
	hypogonadotropic_hypogonadism = ISNULL(SUM(CASE WHEN Concept = 'hypogonadotropic-hypogonadism' THEN 1 ELSE 0 END),0)
FROM #DiagnosesAndSymptoms
GROUP BY FK_Patient_Link_ID, YEAR(EventDate)
ORDER BY FK_Patient_Link_ID, YEAR(EventDate)