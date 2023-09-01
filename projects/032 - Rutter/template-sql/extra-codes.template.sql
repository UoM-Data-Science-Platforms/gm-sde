--┌────────────────────────────────────────────────────┐
--│ Extra codes (diabetes and mental health referrals) │
--└────────────────────────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK -------------------------------

---------------------------------------------------------------------

/* Code sets including: 
	diabetes-clinic
	mental-health-service-referral
*/

-- OUTPUT: Data with the following fields
-- 	-   PatientId (int)
--  -   MatchedPatientId (int or NULL)
--	-	Concept
--	-	Date (YYYY-MM-DD 00:00:00)

------ Find the main cohort and the matched controls ---------

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2019-07-09';
DECLARE @EndDate datetime;
SET @EndDate = '2022-03-31';


--Just want the output, not the messages
SET NOCOUNT ON;

------------------------------------------------------------------------------
--> EXECUTE query-build-rq032-cohort.sql
------------------------------------------------------------------------------

--> CODESET diabetes-clinic:1 mental-health-service-referral:1

-- Get observation values for the main and matched cohort
IF OBJECT_ID('tempdb..#codes') IS NOT NULL DROP TABLE #codes;
SELECT 
	FK_Patient_Link_ID,
	CAST(EventDate AS DATE) AS EventDate,
	Concept = CASE WHEN sn.Concept IS NOT NULL THEN sn.Concept ELSE co.Concept END
INTO #codes
FROM RLS.vw_GP_Events gp
LEFT JOIN #VersionedSnomedSets sn ON sn.FK_Reference_SnomedCT_ID = gp.FK_Reference_SnomedCT_ID
LEFT JOIN #VersionedCodeSets co ON co.FK_Reference_Coding_ID = gp.FK_Reference_Coding_ID
WHERE 
	(gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #MainCohort) 
		OR gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #MatchedCohort))
AND sn.Concept IN ('diabetes-clinic', 'mental-health-service-referral')
AND co.Concept IN ('diabetes-clinic', 'mental-health-service-referral')
AND EventDate BETWEEN '2016-04-01' AND @EndDate

-- DEDUPLICATE CODES TABLE

IF OBJECT_ID('tempdb..#codes_deduped') IS NOT NULL DROP TABLE #codes_deduped;
SELECT DISTINCT * 
INTO #codes_deduped 
FROM #codes

-- BRING TOGETHER FOR FINAL OUTPUT

SELECT	 
	PatientId = m.FK_Patient_Link_ID
	,MainCohortMatchedPatientId = NULL
	,EventDate
	,Concept
FROM #MainCohort m
INNER JOIN #codes_deduped o ON o.FK_Patient_Link_ID = m.FK_Patient_Link_ID 
 UNION
-- patients in matched cohort
SELECT	 
	PatientId = m.FK_Patient_Link_ID
	,MainCohortMatchedPatientId = m.PatientWhoIsMatched
	,EventDate
	,Concept
FROM #MatchedCohort m
INNER JOIN #codes_deduped o ON o.FK_Patient_Link_ID = m.FK_Patient_Link_ID
