--┌─────────────────────────────┐
--│ Patient first/main language │
--└─────────────────────────────┘

-- OBJECTIVE: To provide the first/main language for each patient

-- INPUT: Assumes there exists a temp table as follows:
-- #Patients (FK_Patient_Link_ID)

-- OUTPUT: A temp table as follows:
-- PatientId
-- FirstLanguage
-- DateRecorded

-- NOTE: make sure to redact first languages that have small counts when providing data to researchers, 
-- given that it might make a patient identifiable


--> CODESET first-language:1

-- where a code has more than one description, take just one of them.

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

IF OBJECT_ID('tempdb..#FirstLanguageCodes') IS NOT NULL DROP TABLE #FirstLanguageCodes;
SELECT FK_Patient_Link_ID, 
		EventDate, 
		SuppliedCode,
		case when s.Concept is null then c.Concept else s.Concept end as Concept,
		case when s.description is null then c.description else s.description end as [Description]
INTO #FirstLanguageCodes
FROM SharedCare.GP_Events gp
LEFT OUTER JOIN #VersionedSnomedSets_1 s ON s.FK_Reference_SnomedCT_ID = gp.FK_Reference_SnomedCT_ID
LEFT OUTER JOIN #VersionedCodeSets_1 c ON c.FK_Reference_Coding_ID = gp.FK_Reference_Coding_ID
WHERE gp.EventDate <= GetDate()
	AND gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
	AND (
	(gp.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets_1 )) 
	OR
    (gp.FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets_1))
		);


IF OBJECT_ID('tempdb..#MostRecentFirstLanguageCode') IS NOT NULL DROP TABLE #MostRecentFirstLanguageCode;
SELECT 
	a.FK_Patient_Link_ID, 
	Max(EventDate) as EventDate,
	Max(Description) as Description
INTO #MostRecentFirstLanguageCode
FROM #FirstLanguageCodes a
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(EventDate) AS MostRecentDate 
	FROM #FirstLanguageCodes
	GROUP BY FK_Patient_Link_ID
) sub ON sub.MostRecentDate = a.EventDate and sub.FK_Patient_Link_ID = a.FK_Patient_Link_ID
GROUP BY a.FK_Patient_Link_ID;

-- bring together for final table, which can be joined to, to get first language (where recorded)

IF OBJECT_ID('tempdb..#FirstLanguage') IS NOT NULL DROP TABLE #FirstLanguage;
SELECT FK_Patient_Link_ID, 
	FirstLanguage = REPLACE(REPLACE(Description, ' (finding)', ''), 'Main spoken language ', ''),
	FirstLanguageEnglish = CASE WHEN Description = 'Main spoken language English (finding)' THEN 1 ELSE 0 END
INTO #FirstLanguage
FROM #MostRecentFirstLanguageCode