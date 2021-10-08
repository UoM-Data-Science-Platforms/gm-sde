--┌──────────────┐
--│ Observations │
--└──────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------


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
	Smoking Status (current/ex/never)
	bodyweight
	height
	BMI
*/

-- OUTPUT: Data with the following fields
-- 	-   PatientId (int)
--	-	ObservationName
--	-	ObservationDateTime (YYYY-MM-DD 00:00:00)
--  -   TestResult 
--  -   TestUnit


--> CODESET hba1c:2 cholesterol:2 hdl-cholesterol:1 ldl-cholesterol:1 egfr:1 creatinine:1 triglycerides:1
--> CODESET systolic-blood-pressure:1 diastolic-blood-pressure:1
--> CODESET smoking-status-current:1 smoking-status-currently-not:1 smoking-status-ex:1 smoking-status-ex-trivial:1 smoking-status-never:1 smoking-status-passive:1 smoking-status-trivial:1
--> CODESET bmi:2 height:1 weight:1


------ Find the main cohort and the matched controls ---------

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2019-07-19';

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

--> CODESET diabetes-type-ii:1 polycystic-ovarian-syndrome:1 gestational-diabetes:1

--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-year-of-birth.sql

-- FIND PATIENTS WITH A DIAGNOSIS OF POLYCYSTIC OVARY SYNDROME OR GESTATIONAL DIABETES, TO EXCLUDE

IF OBJECT_ID('tempdb..#exclusions') IS NOT NULL DROP TABLE #exclusions;
SELECT DISTINCT gp.FK_Patient_Link_ID
INTO #exclusions
FROM [RLS].[vw_GP_Events] gp
LEFT OUTER JOIN #Patients p ON p.FK_Patient_Link_ID = gp.FK_Patient_Link_ID
WHERE SuppliedCode IN 
	(SELECT [Code] FROM #AllCodes WHERE [Concept] IN 
		('polycystic-ovarian-syndrome', 'gestational-diabetes') AND [Version] = 1)
			AND EventDate BETWEEN '2018-07-09' AND '2022-03-31'

---- CREATE TABLE OF ALL PATIENTS THAT HAVE ANY LIFETIME DIAGNOSES OF T2D OF 2019-07-19

IF OBJECT_ID('tempdb..#diabetes2_diagnoses') IS NOT NULL DROP TABLE #diabetes2_diagnoses;
SELECT gp.FK_Patient_Link_ID, 
		YearOfBirth, 
		Sex,
		EthnicMainGroup,
		EventDate,
		SuppliedCode,
		[diabetes_type_ii_Code] = CASE WHEN SuppliedCode IN 
					( SELECT [Code] FROM #AllCodes WHERE [Concept] IN ('diabetes-type-ii') AND [Version] = 1 ) THEN 1 ELSE 0 END

INTO #diabetes2_diagnoses
FROM [RLS].[vw_GP_Events] gp
LEFT OUTER JOIN #Patients p ON p.FK_Patient_Link_ID = gp.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE (SuppliedCode IN 
	(SELECT [Code] FROM #AllCodes WHERE [Concept] IN ('diabetes-type-ii') AND [Version] = 1)) 
    AND gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
	AND (gp.EventDate) <= '2019-07-19'


-- Define the main cohort to be matched
IF OBJECT_ID('tempdb..#MainCohort') IS NOT NULL DROP TABLE #MainCohort;
SELECT DISTINCT FK_Patient_Link_ID, 
		YearOfBirth, -- NEED TO ENSURE OVER 18S ONLY AT SOME POINT
		Sex,
		EthnicMainGroup
INTO #MainCohort
FROM #diabetes2_diagnoses
WHERE FK_Patient_Link_ID IN (#####INTERVENTION_TABLE)

-- Define the population of potential matches for the cohort
IF OBJECT_ID('tempdb..#PotentialMatches') IS NOT NULL DROP TABLE #PotentialMatches;
SELECT DISTINCT p.FK_Patient_Link_ID, Sex, YearOfBirth
INTO #PotentialMatches
FROM #diabetes2_diagnoses
WHERE p.FK_Patient_Link_ID NOT IN (SELECT FK_Patient_Link_ID FROM #MainCohort)

-- AND THE RELEVANT DATA (HBA1C AND CVD RISK FACTORS) ARE AVAILABLE  WITHIN 3-6 MONTHS OF INDEX DATE


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
LEFT OUTER JOIN #PatientIMDDecile imd ON imd.FK_Patient_Link_ID = c.MatchingPatientId
WHERE c.PatientId IN (SELECT FK_Patient_Link_ID FROM #Patients);

-- Define a table with all the patient ids for the main cohort and the matched cohort
IF OBJECT_ID('tempdb..#PatientIds') IS NOT NULL DROP TABLE #PatientIds;
SELECT PatientId AS FK_Patient_Link_ID INTO #PatientIds FROM #CohortStore
UNION
SELECT MatchingPatientId FROM #CohortStore;


-- Get observation values for the cohort
IF OBJECT_ID('tempdb..#observations') IS NOT NULL DROP TABLE #observations;
SELECT DISTINCT
	FK_Patient_Link_ID,
	CAST(EventDate AS DATE) AS EventDate,
	Concept = CASE WHEN sn.Concept IS NOT NULL THEN sn.Concept ELSE co.Concept END,
	[Description] =  CASE WHEN sn.[description] IS NOT NULL THEN sn.[description] ELSE co.[description] END,
	[Value] 
INTO #observations
FROM RLS.vw_GP_Events gp
LEFT JOIN #VersionedSnomedSets sn ON sn.FK_Reference_SnomedCT_ID = gp.FK_Reference_SnomedCT_ID
LEFT JOIN #VersionedCodeSets co ON co.FK_Reference_Coding_ID = gp.FK_Reference_Coding_ID
WHERE (
	gp.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE 
			(Concept IN ('hba1c') 							AND [Version]=2) OR
			(Concept IN ('cholesterol') 					AND [Version]=2) OR
			(Concept IN ('hdl-cholesterol') 		 		AND [Version]=1) OR
			(Concept IN ('ldl-cholesterol') 		 		AND [Version]=1) OR
			(Concept IN ('egfr') 					 		AND [Version]=1) OR
			(Concept IN ('creatinine') 				 		AND [Version]=1) OR
			(Concept IN ('systolic-blood-pressure')  		AND [Version]=1) OR
			(Concept IN ('diastolic-blood-pressure') 		AND [Version]=1) OR
			(Concept IN ('triglycerides') 			 		AND [Version]=2) OR
			(Concept IN ('bmi') 					 		AND [Version]=2) OR
			(Concept IN ('height') 					 		AND [Version]=1) OR
			(Concept IN ('weight') 					 		AND [Version]=1) OR
			(Concept IN ('smoking-status-current') 	 		AND [Version]=1) OR
			(Concept IN ('smoking-status-currently-not') 	AND [Version]=1) OR
			(Concept IN ('smoking-status-never') 	 		AND [Version]=1) OR
			(Concept IN ('smoking-status-passive') 	 		AND [Version]=1) OR
			(Concept IN ('smoking-status-trivial') 	 		AND [Version]=1) 
) OR
  gp.FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE 
			(Concept IN ('hba1c') 							AND [Version]=2) OR
			(Concept IN ('cholesterol') 					AND [Version]=2) OR
			(Concept IN ('hdl-cholesterol') 		 		AND [Version]=1) OR
			(Concept IN ('ldl-cholesterol') 		 		AND [Version]=1) OR
			(Concept IN ('egfr') 					 		AND [Version]=1) OR
			(Concept IN ('creatinine') 				 		AND [Version]=1) OR
			(Concept IN ('systolic-blood-pressure')  		AND [Version]=1) OR
			(Concept IN ('diastolic-blood-pressure') 		AND [Version]=1) OR
			(Concept IN ('triglycerides') 			 		AND [Version]=2) OR
			(Concept IN ('bmi') 					 		AND [Version]=2) OR
			(Concept IN ('height') 					 		AND [Version]=1) OR
			(Concept IN ('weight') 					 		AND [Version]=1) OR
			(Concept IN ('smoking-status-current') 	 		AND [Version]=1) OR
			(Concept IN ('smoking-status-currently-not') 	AND [Version]=1) OR
			(Concept IN ('smoking-status-never') 	 		AND [Version]=1) OR
			(Concept IN ('smoking-status-passive') 	 		AND [Version]=1) OR
			(Concept IN ('smoking-status-trivial') 	 		AND [Version]=1) 
) )
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #MainCohort)
AND EventDate BETWEEN '2016-04-01' AND '2022-03-31'

select  * 
from #observations 
where ([Value] IS NOT NULL AND [Value] != '0') OR 
	(Concept IN ('smoking-status-current', 'smoking-status-currently-not', 'smoking-status-never', 'smoking-status-passive', 'smoking-status-trivial')) 
--where FK_Patient_Link_ID = '3926057756066093444' order by EventDate, Concept



