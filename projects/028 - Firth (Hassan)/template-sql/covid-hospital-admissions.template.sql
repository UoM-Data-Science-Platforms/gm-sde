--┌────────────────────────────────────┐
--│ Hospital stay information  	       │
--└────────────────────────────────────┘

-- REVIEW LOG:

-- OUTPUT: Data with the following fields
-- Patient Id
-- AdmissionDate (DD-MM-YYYY)
-- DischargeDate (DD-MM-YYYY)
-- LengthOfStay 
-- Hospital - ANONYMOUS

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2020-01-31';

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

--> CODESET severe-mental-illness

--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-year-of-birth.sql


-- COHORT: PATIENTS THAT HAVE AN SMI DIAGNOSIS AS OF 31.01.20
IF OBJECT_ID('tempdb..#SMI_Episodes') IS NOT NULL DROP TABLE #SMI_Episodes;
SELECT gp.FK_Patient_Link_ID,
	YearOfBirth,
	Sex
INTO #SMI_Episodes
FROM [RLS].[vw_GP_Events] gp
LEFT OUTER JOIN #Patients p ON p.FK_Patient_Link_ID  = gp.FK_Patient_Link_ID 
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE SuppliedCode IN 
	(SELECT [Code] FROM #AllCodes WHERE [Concept] IN ('severe-mental-illness') AND [Version] = 1)
	AND gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
	AND (gp.EventDate) <= '2020-01-31'


-- Define the main cohort to be matched

IF OBJECT_ID('tempdb..#MainCohort') IS NOT NULL DROP TABLE #MainCohort;
SELECT DISTINCT FK_Patient_Link_ID, 
		YearOfBirth, 
		Sex
INTO #MainCohort
FROM #SMI_Episodes
--57,622

-- Define the population of potential matches for the cohort
IF OBJECT_ID('tempdb..#PotentialMatches') IS NOT NULL DROP TABLE #PotentialMatches;
SELECT p.FK_Patient_Link_ID, Sex, YearOfBirth
INTO #PotentialMatches
FROM #Patients p
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
EXCEPT
SELECT FK_Patient_Link_ID, Sex, YearOfBirth FROM #MainCohort;
-- 3,378,730

--> EXECUTE query-cohort-matching-yob-sex-alt.sql yob-flex:1 num-matches:5


-- Get the matched cohort detail - same as main cohort
IF OBJECT_ID('tempdb..#MatchedCohort') IS NOT NULL DROP TABLE #MatchedCohort;
SELECT 
  c.MatchingPatientId AS FK_Patient_Link_ID,
  Sex,
  MatchingYearOfBirth,
  PatientId AS PatientWhoIsMatched
INTO #MatchedCohort
FROM #CohortStore c
WHERE c.PatientId IN (SELECT FK_Patient_Link_ID FROM #Patients);
--254,824

-- Define a table with all the patient ids for the main cohort and the matched cohort
IF OBJECT_ID('tempdb..#PatientIds') IS NOT NULL DROP TABLE #PatientIds;
SELECT PatientId AS FK_Patient_Link_ID INTO #PatientIds FROM #CohortStore
UNION
SELECT MatchingPatientId FROM #CohortStore;


--> EXECUTE query-get-admissions-and-length-of-stay.sql
--> EXECUTE query-admissions-covid-utilisation.sql


----- create anonymised identifier for each hospital

IF OBJECT_ID('tempdb..#hospitals') IS NOT NULL DROP TABLE #hospitals;
SELECT DISTINCT AcuteProvider
INTO #hospitals
FROM #LengthOfStay

IF OBJECT_ID('tempdb..#RandomiseHospital') IS NOT NULL DROP TABLE #RandomiseHospital;
SELECT AcuteProvider
	, HospitalID = ROW_NUMBER() OVER (order by AcuteProvider)
INTO #RandomiseHospital
FROM #hospitals


--bring together for final output
--patients in main cohort
SELECT 
	PatientId = m.FK_Patient_Link_ID,
	NULL AS MainCohortMatchedPatientId,
	l.AdmissionDate,
	l.DischargeDate,
	rh.HospitalID
FROM #MainCohort m 
LEFT JOIN #LengthOfStay l ON m.FK_Patient_Link_ID = l.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDUtilisationAdmissions c ON c.FK_Patient_Link_ID = l.FK_Patient_Link_ID AND c.AdmissionDate = l.AdmissionDate AND c.AcuteProvider = l.AcuteProvider
LEFT OUTER JOIN #RandomiseHospital rh ON rh.AcuteProvider = l.AcuteProvider
WHERE c.CovidHealthcareUtilisation = 'TRUE'
--patients in matched cohort
UNION
SELECT 
	PatientId = m.FK_Patient_Link_ID,
	PatientWhoIsMatched AS MainCohortMatchedPatientId,
	l.AdmissionDate,
	DischargeDate,
	rh.HospitalID
FROM #MatchedCohort m 
LEFT JOIN #LengthOfStay l ON m.FK_Patient_Link_ID = l.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDUtilisationAdmissions c ON c.FK_Patient_Link_ID = l.FK_Patient_Link_ID AND c.AdmissionDate = l.AdmissionDate AND c.AcuteProvider = l.AcuteProvider
LEFT OUTER JOIN #RandomiseHospital rh ON rh.AcuteProvider = l.AcuteProvider
WHERE c.CovidHealthcareUtilisation = 'TRUE'
--2,007