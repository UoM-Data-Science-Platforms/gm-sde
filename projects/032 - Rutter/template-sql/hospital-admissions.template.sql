--┌───────────────────────────────────────────────────────────────────────────┐
--│ Hospital stay information for T2D intervention cohort and T2D controls    │
--└───────────────────────────────────────────────────────────────────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------

-- OUTPUT: Data with the following fields
-- Patient Id
-- AdmissionDate (DD-MM-YYYY)
-- DischargeDate (DD-MM-YYYY)
-- AdmissionType
-- CovidAdmission
-- Hospital - ANONYMOUS

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2019-07-09';

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
WHERE (SuppliedCode IN 
	(SELECT [Code] FROM #AllCodes WHERE [Concept] IN 
		('polycystic-ovarian-syndrome', 'gestational-diabetes') AND [Version] = 1
			AND EventDate BETWEEN '2018-07-09' AND '2022-03-31')) 
    
---- CREATE TABLE OF ALL PATIENTS THAT HAVE ANY LIFETIME DIAGNOSES OF T2D OF 2019-07-19

IF OBJECT_ID('tempdb..#diabetes2_diagnoses') IS NOT NULL DROP TABLE #diabetes2_diagnoses;
SELECT gp.FK_Patient_Link_ID, 
		YearOfBirth, 
		Sex,
		EthnicMainGroup,
		EventDate,
		SuppliedCode
INTO #diabetes2_diagnoses
FROM [RLS].[vw_GP_Events] gp
LEFT OUTER JOIN #Patients p ON p.FK_Patient_Link_ID = gp.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE (SuppliedCode IN 
	(SELECT [Code] FROM #AllCodes WHERE [Concept] IN ('diabetes-type-ii') AND [Version] = 1)) 
    AND gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
	AND gp.FK_Patient_Link_ID NOT IN (SELECT FK_Patient_Link_ID FROM #exclusions)
	AND (gp.EventDate) <= '2019-07-09'
	AND DATEDIFF(YEAR, yob.YearOfBirth, '2019-07-09') >= 18


-- Define the main cohort to be matched
IF OBJECT_ID('tempdb..#MainCohort') IS NOT NULL DROP TABLE #MainCohort;
SELECT DISTINCT FK_Patient_Link_ID, 
		YearOfBirth,
		Sex,
		EthnicMainGroup
INTO #MainCohort
FROM #diabetes2_diagnoses
--WHERE FK_Patient_Link_ID IN (#####INTERVENTION_TABLE)

/*

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
WHERE c.PatientId IN (SELECT FK_Patient_Link_ID FROM #Patients);

-- Define a table with all the patient ids for the main cohort and the matched cohort
IF OBJECT_ID('tempdb..#PatientIds') IS NOT NULL DROP TABLE #PatientIds;
SELECT PatientId AS FK_Patient_Link_ID INTO #PatientIds FROM #CohortStore
UNION
SELECT MatchingPatientId FROM #CohortStore;

*/

--> EXECUTE query-get-admissions-and-length-of-stay.sql
--> EXECUTE query-admissions-covid-utilisation.sql start-date:'2019-07-01'
--> EXECUTE query-classify-secondary-admissions.sql


--bring together for final output
--patients in main cohort
SELECT 
	PatientId = m.FK_Patient_Link_ID,
	NULL AS MainCohortMatchedPatientId,
	l.AdmissionDate,
	l.DischargeDate,
	ty.AdmissionType
    --c.CovidHealthcareUtilisation
FROM #MainCohort m 
INNER JOIN #LengthOfStay l ON m.FK_Patient_Link_ID = l.FK_Patient_Link_ID
INNER JOIN #COVIDUtilisationAdmissions c ON c.FK_Patient_Link_ID = l.FK_Patient_Link_ID AND c.AdmissionDate = l.AdmissionDate AND c.AcuteProvider = l.AcuteProvider
INNER JOIN #AdmissionTypes ty ON ty.FK_Patient_Link_ID = m.FK_Patient_Link_ID AND ty.AdmissionDate = l.AdmissionDate
--patients in matched cohort
--UNION
--SELECT 
--	PatientId = m.FK_Patient_Link_ID,
--	PatientWhoIsMatched AS MainCohortMatchedPatientId,
--	l.AdmissionDate,
--	DischargeDate,
--	ty.AdmissionType,
--    c.CovidHealthcareUtilisation
--FROM #MatchedCohort m 
--INNER JOIN #LengthOfStay l ON m.FK_Patient_Link_ID = l.FK_Patient_Link_ID
--INNER JOIN #COVIDUtilisationAdmissions c ON c.FK_Patient_Link_ID = l.FK_Patient_Link_ID AND c.AdmissionDate = l.AdmissionDate AND c.AcuteProvider = l.AcuteProvider
--INNER JOIN #AdmissionTypes ty ON ty.FK_Patient_Link_ID = m.FK_Patient_Link_ID AND ty.AdmissionDate = l.AdmissionDate