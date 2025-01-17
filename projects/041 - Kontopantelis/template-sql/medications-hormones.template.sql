--┌─────────────────────────────────────────┐
--│ Medications - sex hormone prescriptions │
--└─────────────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK -------------------------------

---------------------------------------------------------------------

-- All prescriptions for sex hormone medications:
	-- female_sex_hormones
	-- male_sex_hormones
	-- anabolic_steroids
	-- hormone_replacement_therapy

-- OUTPUT: Data with the following fields
-- 	-   PatientId (int)
--	-	MedicationCategory (varchar)
--	-	PrescriptionDate (YYYY-MM-DD)
--  -   MedicationDescription (varchar)
--  -   Quantity (varchar)

DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2018-03-01';
SET @EndDate = '2023-08-31';

--Just want the output, not the messages
SET NOCOUNT ON;

------------------------------------------------------------------------------
--> EXECUTE query-build-rq041-cohort.sql
------------------------------------------------------------------------------

--> CODESET hormone-replacement-therapy-meds:1 female-sex-hormones:1 male-sex-hormones:1 anabolic-steroids:1

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

-- RX OF MEDS SINCE 01.03.18 FOR COHORT, WITH CONCEPT AND DESCRIPTION


IF OBJECT_ID('tempdb..#meds_deduped') IS NOT NULL DROP TABLE #meds_deduped;
SELECT 
	 m.FK_Patient_Link_ID,
	 m.SuppliedCode,
	 m.FK_Reference_SnomedCT_ID,
	 m.FK_Reference_Coding_ID,
	 Quantity,
	 CAST(MedicationDate AS DATE) as PrescriptionDate
INTO #meds_deduped
FROM SharedCare.GP_Medications m
WHERE m.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort)
	AND m.MedicationDate BETWEEN @StartDate AND @EndDate
	AND (
		m.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets_1 WHERE (Concept NOT IN ('egfr','urinary-albumin-creatinine-ratio','glomerulonephritis', 'kidney-transplant', 'kidney-stones', 'vasculitis')))
		OR
		m.FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets_1 WHERE (Concept NOT IN ('egfr','urinary-albumin-creatinine-ratio','glomerulonephritis', 'kidney-transplant', 'kidney-stones', 'vasculitis')))
		)
GROUP BY m.FK_Patient_Link_ID,
	 m.SuppliedCode,
	 m.FK_Reference_SnomedCT_ID,
	 m.FK_Reference_Coding_ID,
	 Quantity,
	 CAST(MedicationDate AS DATE)

IF OBJECT_ID('tempdb..#meds') IS NOT NULL DROP TABLE #meds;
SELECT 
	 m.FK_Patient_Link_ID,
	 PrescriptionDate,
	 [concept] = CASE WHEN s.[concept] IS NOT NULL THEN s.[concept] ELSE c.[concept] END,
	 Quantity,
	 [description] = CASE WHEN s.[description] IS NOT NULL THEN s.[description] ELSE c.[description] END
INTO #meds
FROM #meds_deduped m
LEFT OUTER JOIN #VersionedSnomedSets_1 s ON s.FK_Reference_SnomedCT_ID = m.FK_Reference_SnomedCT_ID
LEFT OUTER JOIN #VersionedCodeSets_1 c ON c.FK_Reference_Coding_ID = m.FK_Reference_Coding_ID

-- Produce final table of all medication prescriptions for main and matched cohort
SELECT	 
	PatientId = FK_Patient_Link_ID
	,MedicationCategory = concept
	,MedicationDescription = REPLACE([description], ',', '|')
	,Quantity
	,PrescriptionDate
FROM #meds m 
