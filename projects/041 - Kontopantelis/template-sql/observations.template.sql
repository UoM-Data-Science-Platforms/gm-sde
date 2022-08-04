--┌──────────────┐
--│ Observations │
--└──────────────┘

-------- RESEARCH DATA ENGINEER CHECK ---------


-- OUTPUT: Data with the following fields
-- 	-   PatientId (int)
--	-	ObservationName
--	-	ObservationDateTime (YYYY-MM-DD 00:00:00)
--  -   TestResult 
--  -   TestUnit

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2018-03-01';
DECLARE @EndDate datetime;
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

-- DEFINE COHORT
--> EXECUTE query-build-rq041-cohort.sql

---------------------------------------------------------------------------------------------------------
---------------------------------------- OBSERVATIONS/MEASUREMENTS --------------------------------------
---------------------------------------------------------------------------------------------------------

-- LOAD CODESETS FOR OBSERVATIONS WITH A VALUE (EXCEPT THOSE ALREADY LOADED AT START OF SCRIPT)

--> CODESET hba1c:2 creatinine:1 triglycerides:1 urea:1 vitamin-d:1 calcium:1 bicarbonate:1 ferritin:1 b12:1 folate:1 haemoglobin:1 
--> CODESET systolic-blood-pressure:1 diastolic-blood-pressure:1 urine-protein-creatinine-ratio:1
--> CODESET alanine-aminotransferase:1 albumin:1 alkaline-phosphatase:1 total-bilirubin:1 gamma-glutamyl-transferase:1
--> CODESET cholesterol:2 ldl-cholesterol:1 hdl-cholesterol:1 urine-blood:1  

-- GET VALUES FOR ALL OBSERVATIONS OF INTEREST

IF OBJECT_ID('tempdb..#observations') IS NOT NULL DROP TABLE #observations;
SELECT 
	FK_Patient_Link_ID,
	CAST(EventDate AS DATE) AS EventDate,
	Concept = CASE WHEN sn.Concept IS NOT NULL THEN sn.Concept ELSE co.Concept END,
	[Version] =  CASE WHEN sn.[Version] IS NOT NULL THEN sn.[Version] ELSE co.[Version] END,
	[Value],
	[Units]
INTO #observations
FROM #PatientEventData gp
LEFT JOIN #VersionedSnomedSets sn ON sn.FK_Reference_SnomedCT_ID = gp.FK_Reference_SnomedCT_ID
LEFT JOIN #VersionedCodeSets co ON co.FK_Reference_Coding_ID = gp.FK_Reference_Coding_ID
WHERE
	(gp.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept NOT IN ('glomerulonephritis', 'kidney-transplant', 'kidney-stones', 'vasculitis')) ) OR
     gp.FK_Reference_Coding_ID   IN (SELECT FK_Reference_Coding_ID   FROM #VersionedCodeSets WHERE (Concept NOT IN ('glomerulonephritis', 'kidney-transplant', 'kidney-stones', 'vasculitis'))  ) )
AND gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort)
AND EventDate BETWEEN @StartDate and @EndDate

-- WHERE CODES EXIST IN BOTH VERSIONS OF THE CODE SET (OR IN OTHER SIMILAR CODE SETS), THERE WILL BE DUPLICATES, SO EXCLUDE THEM FROM THE SETS/VERSIONS THAT WE DON'T WANT 

IF OBJECT_ID('tempdb..#all_observations') IS NOT NULL DROP TABLE #all_observations;
select 
	FK_Patient_Link_ID, CAST(EventDate AS DATE) EventDate, Concept, [Value], [Units], [Version]
into #all_observations
from #observations
except
select FK_Patient_Link_ID, EventDate, Concept, [Value], [Units], [Version] from #observations 
where 
	(Concept = 'cholesterol' and [Version] <> 2) OR -- e.g. serum HDL cholesterol appears in cholesterol v1 code set, which we don't want, but we do want the code as part of the hdl-cholesterol code set.
	(Concept = 'hba1c' and [Version] <> 2) -- e.g. hba1c level appears twice with same value: from version 1 and version 2. We only want version 2 so exclude any others.

-- BRING TOGETHER FOR FINAL OUTPUT AND REMOVE USELESS RECORDS

SELECT DISTINCT
	PatientId = o.FK_Patient_Link_ID
	,TestName = o.Concept
	,TestDate = o.EventDate
	,TestResult = TRY_CONVERT(NUMERIC (18,5), [Value]) -- convert to numeric so no text can appear.
	,TestUnit = o.[Units]
FROM #observations o
WHERE 
	[Value] IS NOT NULL AND TRY_CONVERT(NUMERIC (18,5), [Value]) <> 0 AND [Value] <> '0' -- REMOVE NULLS AND ZEROES
	AND UPPER([Value]) NOT LIKE '%[A-Z]%'  -- REMOVES ANY TEXT VALUES
