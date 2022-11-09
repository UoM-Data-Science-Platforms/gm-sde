--┌──────────────┐
--│ Observations │
--└──────────────┘

-------- RESEARCH DATA ENGINEER CHECK -------------------------------
-- Richard Williams	2021-11-26	Review complete
-- Richard Williams	2022-08-04	Review complete following changes
---------------------------------------------------------------------

/* Observations including: 
	Systolic blood pressure
	Diastolic blood pressure
	HbA1c
	Total cholesterol
	LDL cholesterol
	HDL Cholesterol
	Triglyceride
	Creatinine
	eGFR
	Urinary albumin creatinine ratio
*/

-- OUTPUT: Data with the following fields
-- 	-   PatientId (int)
--  -   MatchedPatientId (int or NULL)
--	-	ObservationName
--	-	ObservationDateTime (YYYY-MM-DD 00:00:00)
--  -   TestResult 
--  -   TestUnit

------ Find the main cohort and the matched controls ---------

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2019-07-09';
DECLARE @EndDate datetime;
SET @EndDate = '2022-03-31';


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

------------------------------------------------------------------------------
--> EXECUTE query-build-rq032-cohort.sql
------------------------------------------------------------------------------

--> CODESET hba1c:2 cholesterol:2 hdl-cholesterol:1 ldl-cholesterol:1 egfr:1 creatinine:1 triglycerides:1
--> CODESET systolic-blood-pressure:1 diastolic-blood-pressure:1 urinary-albumin-creatinine-ratio:1
--> CODESET height:1 weight:1

-- Get observation values for the main and matched cohort
IF OBJECT_ID('tempdb..#observations') IS NOT NULL DROP TABLE #observations;
SELECT 
	FK_Patient_Link_ID,
	CAST(EventDate AS DATE) AS EventDate,
	Concept = CASE WHEN sn.Concept IS NOT NULL THEN sn.Concept ELSE co.Concept END,
	[Version] =  CASE WHEN sn.[Version] IS NOT NULL THEN sn.[Version] ELSE co.[Version] END,
	[Value],
	[Units]
INTO #observations
FROM RLS.vw_GP_Events gp
LEFT JOIN #VersionedSnomedSets sn ON sn.FK_Reference_SnomedCT_ID = gp.FK_Reference_SnomedCT_ID
LEFT JOIN #VersionedCodeSets co ON co.FK_Reference_Coding_ID = gp.FK_Reference_Coding_ID
WHERE
	(gp.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept NOT IN ('polycystic-ovarian-syndrome', 'gestational-diabetes', 'diabetes-type-ii' )) OR
    gp.FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept NOT IN ('polycystic-ovarian-syndrome', 'gestational-diabetes', 'diabetes-type-ii' )) )
AND (gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #MainCohort) OR gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #MatchedCohort))
AND EventDate BETWEEN '2016-04-01' AND @EndDate

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

-- REMOVE USELESS OBSERVATIONS WITH NO VALUE

IF OBJECT_ID('tempdb..#observations_final') IS NOT NULL DROP TABLE #observations_final;
SELECT FK_Patient_Link_ID,
	EventDate,
	Concept,
	[Value] = TRY_CONVERT(NUMERIC (18,5), [Value]), --convert to numeric
	[Units]
INTO #observations_final
FROM #all_observations
WHERE [Value] IS NOT NULL AND TRY_CONVERT(NUMERIC (18,5), [Value]) <> 0 AND [Value] <> '0' -- REMOVE NULLS AND ZEROES
	AND UPPER([Value]) NOT LIKE '%[A-Z]%'  -- REMOVES ANY TEXT VALUES


-- BRING TOGETHER FOR FINAL OUTPUT

SELECT	 
	PatientId = m.FK_Patient_Link_ID
	,MainCohortMatchedPatientId = NULL
	,TestName = o.Concept
	,TestDate = o.EventDate
	,TestResult =o.[Value]
	,TestUnit = o.[Units]
FROM #MainCohort m
LEFT JOIN #observations_final o ON o.FK_Patient_Link_ID = m.FK_Patient_Link_ID 
 UNION
-- patients in matched cohort
SELECT	 
	PatientId = m.FK_Patient_Link_ID
	,MainCohortMatchedPatientId = m.PatientWhoIsMatched 
	,TestName = o.Concept
	,TestDate = o.EventDate
	,TestResult = o.[Value]
	,TestUnit = o.[Units]
FROM #MatchedCohort m
LEFT JOIN #observations_final o ON o.FK_Patient_Link_ID = m.FK_Patient_Link_ID
