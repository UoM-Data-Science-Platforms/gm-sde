--┌─────────────────────────────────────────┐
--│ Diagnoses of kidney related conditions  │
--└─────────────────────────────────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------

------------------------------------------------------

-- Set the start date
DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2018-03-01';
SET @EndDate = '2022-03-01';

DECLARE @IndexDate datetime;
SET @IndexDate = '2020-03-01';

--Just want the output, not the messages
SET NOCOUNT ON;

--> EXECUTE query-build-rq041-cohort.sql

-----------------------------------------------------------------------------------------------------------------------------------------
------------------- NOW COHORT HAS BEEN DEFINED, LOAD CODE SETS FOR ALL KIDNEY RELATED DIAGNOSES ----------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------

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
SELECT FK_Patient_Link_ID, EventDate, case when s.Concept is null then c.Concept else s.Concept end as Concept
INTO #DiagnosesAndSymptoms
FROM #PatientEventData gp
LEFT OUTER JOIN #VersionedSnomedSetsUnique s ON s.FK_Reference_SnomedCT_ID = gp.FK_Reference_SnomedCT_ID
LEFT OUTER JOIN #VersionedCodeSetsUnique c ON c.FK_Reference_Coding_ID = gp.FK_Reference_Coding_ID
WHERE gp.EventDate BETWEEN @StartDate AND @EndDate
AND (
	(gp.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSetsUnique WHERE (Concept NOT IN ('egfr','urinary-albumin-creatinine-ratio')))) 
	OR
    (gp.FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSetsUnique WHERE (Concept NOT IN ('egfr','urinary-albumin-creatinine-ratio'))))
);


SELECT DISTINCT PatientId = FK_Patient_Link_ID, -- ASSUME THAT CODES FROM SAME CODE SET ON SAME DAY ARE DUPLICATES
	EventDate,
	Concept
FROM #DiagnosesAndSymptoms
ORDER BY FK_Patient_Link_ID, EventDate, Concept