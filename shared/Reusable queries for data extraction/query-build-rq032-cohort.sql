--┌────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
--│ Define Cohort for RQ032: patients that had a diabetes intervention and are included in the MyWay Dataset   │
--└────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

-- OBJECTIVE: To build the cohort of patients needed for RQ032. This reduces duplication of code in the template scripts.

-- COHORT: Any patient in the DiabetesMyWay data, with 20:1 matched controls that have Type 2 Diabetes. More detail in the comments throughout this script.

-- INPUT: assumes there exists one temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: Temp tables as follows:
-- #MainCohort
-- #MatchedCohort
-- #PatientEventData

------------------------------------------------------------------------------------------------------------------------------------------------------------

-- CREATE TABLE OF PATIENTS THAT WERE PROCESSED BEFORE COPI NOTICE EXPIRED

IF OBJECT_ID('tempdb..#PatientsToInclude') IS NOT NULL DROP TABLE #PatientsToInclude;
SELECT FK_Patient_Link_ID INTO #PatientsToInclude
FROM RLS.vw_Patient_GP_History
GROUP BY FK_Patient_Link_ID
HAVING MIN(StartDate) < '2022-06-01';

--> CODESET diabetes-type-ii:1 polycystic-ovarian-syndrome:1 gestational-diabetes:1

--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-year-of-birth.sql

-- FIND PATIENTS WITH A DIAGNOSIS OF POLYCYSTIC OVARY SYNDROME OR GESTATIONAL DIABETES, TO EXCLUDE

IF OBJECT_ID('tempdb..#exclusions') IS NOT NULL DROP TABLE #exclusions;
SELECT DISTINCT gp.FK_Patient_Link_ID
INTO #exclusions
FROM [RLS].[vw_GP_Events] gp
WHERE SuppliedCode IN 
	(SELECT [Code] FROM #AllCodes WHERE [Concept] IN 
		('polycystic-ovarian-syndrome', 'gestational-diabetes') AND [Version] = 1)
			AND EventDate BETWEEN '2018-07-09' AND '2022-03-31'

-- CREATE TABLE OF ALL PATIENTS THAT HAVE ANY LIFETIME DIAGNOSES OF T2D AS OF 2019-07-09
-- THIS TABLE WILL BE JOINED TO IN FINAL TABLE TO PROVIDE ADDITIONAL DIABETES INFO FOR THE MYWAY PATIENTS
-- THIS TABLE WILL ALSO BE USED TO FIND CONTROL PATIENTS WHO HAVE T2D BUT DIDN'T HAVE INTERVENTION

IF OBJECT_ID('tempdb..#diabetes2_diagnoses') IS NOT NULL DROP TABLE #diabetes2_diagnoses;
SELECT gp.FK_Patient_Link_ID, 
	YearOfBirth, 
	Sex,
	EventDate
INTO #diabetes2_diagnoses
FROM [RLS].[vw_GP_Events] gp
LEFT OUTER JOIN #Patients p ON p.FK_Patient_Link_ID = gp.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE (SuppliedCode IN (SELECT [Code] FROM #AllCodes WHERE [Concept] IN ('diabetes-type-ii') AND [Version] = 1)) AND 
	gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
    AND gp.FK_Patient_Link_ID NOT IN (SELECT FK_Patient_Link_ID FROM #exclusions)
	AND (gp.EventDate) <= @StartDate

-- Find earliest diagnosis of T2D for each patient

IF OBJECT_ID('tempdb..#EarliestDiagnosis_T2D') IS NOT NULL DROP TABLE #EarliestDiagnosis_T2D;
SELECT FK_Patient_Link_ID
	,EarliestDiagnosis_T2D = MIN(CAST(EventDate AS DATE))
INTO #EarliestDiagnosis_T2D
FROM #diabetes2_diagnoses
GROUP BY FK_Patient_Link_ID

-- DEFINE MAIN COHORT: PATIENTS IN THE MYWAY DATA

IF OBJECT_ID('tempdb..#MainCohort') IS NOT NULL DROP TABLE #MainCohort;
SELECT DISTINCT
	p.FK_Patient_Link_ID,
	YearOfBirth, 
	Sex,
	EthnicMainGroup
INTO #MainCohort
FROM #Patients p
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE 
	p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM MWDH.Live_Header) 		-- My Way Diabetes Patients
	AND p.FK_Patient_Link_ID NOT IN (SELECT FK_Patient_Link_ID FROM #exclusions)   -- Exclude pts with gestational diabetes
	AND YEAR(@StartDate) - yob.YearOfBirth >= 19									-- Over 18s only
	AND p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude) -- exclude new patients processed post-COPI notice


-- Define the population of potential matches for the cohort
IF OBJECT_ID('tempdb..#PotentialMatches') IS NOT NULL DROP TABLE #PotentialMatches;
SELECT DISTINCT FK_Patient_Link_ID, Sex, YearOfBirth
INTO #PotentialMatches
FROM #diabetes2_diagnoses
WHERE FK_Patient_Link_ID NOT IN (SELECT FK_Patient_Link_ID FROM #MainCohort)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude) -- exclude new patients processed post-COPI notice


--> EXECUTE query-cohort-matching-yob-sex-alt.sql yob-flex:1 num-matches:20


-- Get the matched cohort detail - same as main cohort
IF OBJECT_ID('tempdb..#MatchedCohort') IS NOT NULL DROP TABLE #MatchedCohort;
SELECT 
  c.MatchingPatientId AS FK_Patient_Link_ID,
  Sex,
  MatchingYearOfBirth,
  EthnicMainGroup,
  PatientId AS PatientWhoIsMatched
INTO #MatchedCohort
FROM #CohortStore c
LEFT OUTER JOIN #Patients p ON p.FK_Patient_Link_ID = c.MatchingPatientId

-- Define a table with all the patient ids for the main cohort and the matched cohort
IF OBJECT_ID('tempdb..#PatientIds') IS NOT NULL DROP TABLE #PatientIds;
SELECT PatientId AS FK_Patient_Link_ID INTO #PatientIds FROM #CohortStore
UNION
SELECT MatchingPatientId FROM #CohortStore;


-- CREATE TABLE OF ALL GP EVENTS FOR MAIN AND MATCHED COHORTS - TO SPEED UP FUTURE QUERIES

IF OBJECT_ID('tempdb..#PatientEventData') IS NOT NULL DROP TABLE #PatientEventData;
SELECT 
  FK_Patient_Link_ID,
  CAST(EventDate AS DATE) AS EventDate,
  SuppliedCode,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID,
  [Value],
  [Units]
INTO #PatientEventData
FROM [RLS].vw_GP_Events
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientIds)
		AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude) -- exclude new patients processed post-COPI notice

--Outputs from this reusable query:
-- #MainCohort
-- #MatchedCohort
-- #PatientEventData

---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
