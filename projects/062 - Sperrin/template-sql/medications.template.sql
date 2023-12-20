--┌─────────────┐
--│ Medications │
--└─────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------
-- 

-- All prescriptions of certain medications during the study period

-- OUTPUT: Data with the following fields
-- 	-   PatientId (int)
--  -   Year
--  -   MedicationDate
--	-	MedicationCategory - number of prescriptions for given medication category

--Just want the output, not the messages
SET NOCOUNT ON;

DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2022-03-01'; --- UPDATE !!!!!!!
SET @EndDate = '2023-08-31';

--> EXECUTE query-build-rq062-cohort.sql

-- load codesets needed for retrieving medication prescriptions

/* antihypertensives */
--> CODESET calcium-channel-blockers:1 beta-blockers:1

--> CODESET statins:1 ace-inhibitor:1 diuretic:1
--> CODESET angiotensin-receptor-blockers:1 acetylcholinesterase-inhibitors:1 

-- FIX ISSUE WITH DUPLICATE MEDICATIONS, CAUSED BY SOME CODES APPEARING MULTIPLE TIMES IN #VersionedCodeSets and #VersionedSnomedSets

IF OBJECT_ID('tempdb..#VersionedCodeSets_1') IS NOT NULL DROP TABLE #VersionedCodeSets_1;
SELECT DISTINCT FK_Reference_Coding_ID, Concept, [Version] INTO #VersionedCodeSets_1 FROM #VersionedCodeSets

IF OBJECT_ID('tempdb..#VersionedSnomedSets_1') IS NOT NULL DROP TABLE #VersionedSnomedSets_1;
SELECT DISTINCT FK_Reference_SnomedCT_ID, Concept, [Version] INTO #VersionedSnomedSets_1 FROM #VersionedSnomedSets

-- RETRIEVE ALL RELEVANT PRESCRPTIONS FOR THE COHORT

IF OBJECT_ID('tempdb..#medications_rx') IS NOT NULL DROP TABLE #medications_rx;
SELECT 
	 m.FK_Patient_Link_ID,
		CAST(MedicationDate AS DATE) as PrescriptionDate,
		Concept = CASE WHEN s.Concept IS NOT NULL THEN s.Concept ELSE c.Concept END,
		Dosage,
		Quantity
INTO #medications_rx
FROM SharedCare.GP_Medications m
LEFT OUTER JOIN #VersionedSnomedSets_1 s ON s.FK_Reference_SnomedCT_ID = m.FK_Reference_SnomedCT_ID
LEFT OUTER JOIN #VersionedCodeSets_1 c ON c.FK_Reference_Coding_ID = m.FK_Reference_Coding_ID
WHERE m.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
	AND m.MedicationDate BETWEEN @StartDate AND @EndDate
	AND 
		(m.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets_1)
		OR
		m.FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets_1))

-- Dosage information *might* contain sensitive information, so let's 
-- restrict to dosage instructions that occur >= 50 times
IF OBJECT_ID('tempdb..#SafeDosages') IS NOT NULL DROP TABLE #SafeDosages;
SELECT Dosage INTO #SafeDosages FROM #medications_rx
group by Dosage
having count(*) >= 50;


select FK_Patient_Link_ID,
		PrescriptionDate,
		Concept,
		Dosage = LEFT(REPLACE(REPLACE(REPLACE(ISNULL(#SafeDosages.Dosage, 'REDACTED'),',',' '),CHAR(13),' '),CHAR(10),' '),50),
		Quantity
from #medications_rx
LEFT OUTER JOIN #SafeDosages ON m.Dosage = #SafeDosages.Dosage
