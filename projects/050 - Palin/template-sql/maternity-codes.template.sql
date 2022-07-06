--┌──────────────────────────────────────────────┐
--│ Diagnoses of maternity-related conditions    │
--└──────────────────────────────────────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------

------------------------------------------------------


-- Set the start date
DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2012-03-01';
SET @EndDate = '2022-03-01';

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


--------------------------------------------------------------------------------------------------------
----------------------------------- DEFINE MAIN COHORT -----------------------------------------------
--------------------------------------------------------------------------------------------------------



---------------------------------------------------------------------------------------------------------------


-----------------------------------------------------------------------------------------------------------------------------------------
------------------- NOW COHORT HAS BEEN DEFINED, LOAD CODE SETS FOR ALL CONDITIONS/SYMPTOMS OF INTEREST ---------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------


--> CODESET pre-eclampsia:1 pregnancy-failed:1 hypertension:1 gestational-diabetes:1 
--> CODESET postnatal-6week-check:1

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
FROM RLS.vw_GP_Events gp
LEFT OUTER JOIN #VersionedSnomedSetsUnique s ON s.FK_Reference_SnomedCT_ID = gp.FK_Reference_SnomedCT_ID
LEFT OUTER JOIN #VersionedCodeSetsUnique c ON c.FK_Reference_Coding_ID = gp.FK_Reference_Coding_ID
WHERE gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort)
AND gp.EventDate BETWEEN @StartDate AND @EndDate;

-- FIND ALL CODES PER YEAR FOR EACH PATIENT

SELECT PatientID = FK_Patient_Link_ID,
	[Year] = YEAR(EventDate),
	[pre-eclampsia] = ISNULL(SUM(CASE WHEN Concept = 'pre-eclampsia' THEN 1 ELSE 0 END),0),
	[pregnancy-failed] = ISNULL(SUM(CASE WHEN Concept = 'pregnancy-failed' THEN 1 ELSE 0 END),0),
	[hypertension] = ISNULL(SUM(CASE WHEN Concept = 'hypertension' THEN 1 ELSE 0 END),0),
	[gestational-diabetes] = ISNULL(SUM(CASE WHEN Concept = 'gestational-diabetes' THEN 1 ELSE 0 END),0),

FROM #DiagnosesAndSymptoms
GROUP BY FK_Patient_Link_ID, YEAR(EventDate)
ORDER BY FK_Patient_Link_ID, YEAR(EventDate)