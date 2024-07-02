--┌────────────────────────────┐
--│ Diagnoses of dementia      │
--└────────────────────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------

------------------------------------------------------

-- Set the start date
DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2018-03-01';
SET @EndDate = '2023-08-31';

--DECLARE @IndexDate datetime;
--SET @IndexDate = '2020-03-01';

--Just want the output, not the messages
SET NOCOUNT ON;

--> EXECUTE query-build-rq041-cohort.sql


--> CODESET dementia:1

-- WE NEED TO PROVIDE MEDICATION DESCRIPTION, BUT SOME CODES APPEAR MULTIPLE TIMES IN THE VERSIONEDCODESET TABLES WITH DIFFERENT DESCRIPTIONS
-- THEREFORE, TAKE THE FIRST DESCRIPTION BY USING ROW_NUMBER

IF OBJECT_ID('tempdb..#VersionedCodeSets_1') IS NOT NULL DROP TABLE #VersionedCodeSets_1;
SELECT *
INTO #VersionedCodeSets_1
FROM (
SELECT *,
	ROWNUM = ROW_NUMBER() OVER (PARTITION BY FK_Reference_Coding_ID ORDER BY [description])
FROM #VersionedCodeSets ) SUB
WHERE ROWNUM = 1

IF OBJECT_ID('tempdb..#VersionedSnomedSets_1') IS NOT NULL DROP TABLE #VersionedSnomedSets_1;
SELECT *
INTO #VersionedSnomedSets_1
FROM (
SELECT *,
	ROWNUM = ROW_NUMBER() OVER (PARTITION BY FK_Reference_SnomedCT_ID ORDER BY [description])
FROM #VersionedSnomedSets) SUB
WHERE ROWNUM = 1

---- CREATE OUTPUT TABLE OF DIAGNOSES AND SYMPTOMS, FOR THE COHORT OF INTEREST, AND CODING DATES 

IF OBJECT_ID('tempdb..#DiagnosesAndSymptoms') IS NOT NULL DROP TABLE #DiagnosesAndSymptoms;
SELECT FK_Patient_Link_ID, 
		EventDate, 
		SuppliedCode,
		case when s.Concept is null then c.Concept else s.Concept end as Concept,
		case when s.description is null then c.description else s.description end as [Description]
INTO #DiagnosesAndSymptoms
FROM #PatientEventData gp
LEFT OUTER JOIN #VersionedSnomedSets_1 s ON s.FK_Reference_SnomedCT_ID = gp.FK_Reference_SnomedCT_ID
LEFT OUTER JOIN #VersionedCodeSets_1 c ON c.FK_Reference_Coding_ID = gp.FK_Reference_Coding_ID
WHERE gp.EventDate BETWEEN @StartDate AND @EndDate
AND (
	(gp.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets_1 WHERE (Concept NOT IN ('egfr','urinary-albumin-creatinine-ratio','glomerulonephritis', 'kidney-transplant', 'kidney-stones', 'vasculitis')))) 
	OR
    (gp.FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets_1 WHERE (Concept NOT IN ('egfr','urinary-albumin-creatinine-ratio','glomerulonephritis', 'kidney-transplant', 'kidney-stones', 'vasculitis'))))
);


SELECT DISTINCT PatientId = FK_Patient_Link_ID, -- ASSUME THAT CODES FROM SAME CODE SET ON SAME DAY ARE DUPLICATES
	EventDate,
	Concept,
	SuppliedCode,
	[Description] = REPLACE([Description], ',', '|')
FROM #DiagnosesAndSymptoms
