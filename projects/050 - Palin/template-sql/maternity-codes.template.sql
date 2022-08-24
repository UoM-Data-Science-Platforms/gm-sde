--┌──────────────────────────────────────────────┐
--│ Maternity-related codes					     │
--└──────────────────────────────────────────────┘

----- RESEARCH DATA ENGINEER CHECK ------
-- 18th August 2022 - Richard Williams --
-----------------------------------------

-- Set the start date
DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2012-03-01';
SET @EndDate = '2022-03-01';

--Just want the output, not the messages
SET NOCOUNT ON;

----------------------------------------
--> EXECUTE query-build-rq050-cohort.sql
----------------------------------------

-- LOAD CODES THAT AREN'T ALREADY LOADED FROM THE ABOVE COHORT QUERY

--> CODESET gestational-diabetes:1 pre-eclampsia:1 

-- CREATE TABLES OF DISTINCT CODES AND CONCEPTS - TO REMOVE DUPLICATES IN FINAL TABLE

IF OBJECT_ID('tempdb..#VersionedCodeSetsUnique') IS NOT NULL DROP TABLE #VersionedCodeSetsUnique;
SELECT DISTINCT V.Concept, V.FK_Reference_Coding_ID, r.FullDescription, V.[Version]
INTO #VersionedCodeSetsUnique
FROM #VersionedCodeSets V
LEFT JOIN SharedCare.Reference_Coding r on r.PK_Reference_Coding_ID = V.FK_Reference_Coding_ID

IF OBJECT_ID('tempdb..#VersionedSnomedSetsUnique') IS NOT NULL DROP TABLE #VersionedSnomedSetsUnique;
SELECT DISTINCT V.Concept, V.FK_Reference_SnomedCT_ID, r.FullDescription, V.[Version]
INTO #VersionedSnomedSetsUnique
FROM #VersionedSnomedSets V
LEFT JOIN SharedCare.Reference_Coding r on r.FK_Reference_SnomedCT_ID = V.FK_Reference_SnomedCT_ID

---- CREATE OUTPUT TABLE OF DIAGNOSES AND SYMPTOMS, FOR THE COHORT OF INTEREST, AND CODING DATES 

IF OBJECT_ID('tempdb..#DiagnosesAndSymptoms') IS NOT NULL DROP TABLE #DiagnosesAndSymptoms;
SELECT FK_Patient_Link_ID, EventDate, SuppliedCode, gp.FK_Reference_SnomedCT_ID, gp.FK_Reference_Coding_ID,
	case when s.Concept is null then c.Concept else s.Concept end as Concept,
	case when s.FullDescription is null then c.FullDescription else s.FullDescription end as FullDescription
INTO #DiagnosesAndSymptoms
FROM #PatientEventData gp
LEFT OUTER JOIN #VersionedSnomedSetsUnique s ON s.FK_Reference_SnomedCT_ID = gp.FK_Reference_SnomedCT_ID
LEFT OUTER JOIN #VersionedCodeSetsUnique c ON c.FK_Reference_Coding_ID = gp.FK_Reference_Coding_ID
WHERE ((SuppliedCode IN 
			(SELECT [Code] FROM #AllCodes WHERE ([Concept] LIKE 'pregnancy%' OR Concept IN ('gestational-diabetes', 'pre-eclampsia'))
				AND Concept NOT IN ('pregnancy-preterm', 'pregnancy-postterm') AND [Version] = 1)) 
	  OR  -- use ID instead of code for preterm and postterm as it is more specific (see READMEs in code set folders)
		gp.FK_Reference_Coding_ID in (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSetsUnique WHERE Concept IN ('pregnancy-preterm', 'pregnancy-postterm')) OR 
		gp.FK_Reference_SnomedCT_ID in (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSetsUnique WHERE Concept IN ('pregnancy-preterm', 'pregnancy-postterm')))
	AND gp.EventDate BETWEEN @StartDate AND @EndDate
	AND s.FullDescription IS NOT NULL AND c.FullDescription IS NOT NULL
	AND gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort);


-- PULL TOGETHER FOR FINAL TABLE
-- USES MAX(FullDescription) TO GET OVER THE ISSUE OF MULTIPLE SIMILAR DESCRIPTIONS FOR THE SAME CODE

select 
	PatientId = FK_Patient_Link_ID, 
	EventDate, 
	Concept, 
	SuppliedCode,
	MAX([FullDescription])
from #DiagnosesAndSymptoms
where FK_Reference_Coding_ID <> '-1'
group by FK_Patient_Link_ID, EventDate, Concept, SuppliedCode
order by FK_Patient_Link_ID, EventDate, Concept, SuppliedCode
