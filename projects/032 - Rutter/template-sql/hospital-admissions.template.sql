--┌───────────────────────────────────────────────────────────────────────────┐
--│ Hospital stay information for T2D intervention cohort and T2D controls    │
--└───────────────────────────────────────────────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK -------------------------------
-- Richard Williams	2021-11-26	Review complete
-- Richard Williams	2022-08-04	Review complete following changes
---------------------------------------------------------------------

-- OUTPUT: Data with the following fields
-- Patient Id
-- AdmissionDate (DD-MM-YYYY)
-- DischargeDate (DD-MM-YYYY)
-- AdmissionType

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

-- REDUCE THE #Patients TABLE SO THAT IT ONLY INCLUDES THE MAIN AND MATCHED COHORT
-- REUSABLE QUERIES CAN USE IT TO RUN QUICKER 

DELETE FROM #Patients
WHERE FK_Patient_Link_ID NOT IN (SELECT FK_Patient_Link_ID FROM #PatientIds)

--> EXECUTE query-get-admissions-and-length-of-stay.sql all-patients:false
--> EXECUTE query-admissions-covid-utilisation.sql start-date:'2019-07-09' all-patients:true gp-events-table:#PatientEventData
--> EXECUTE query-classify-secondary-admissions.sql

--bring together for final output
--patients in main cohort
SELECT 
	PatientId = m.FK_Patient_Link_ID,
	NULL AS MainCohortMatchedPatientId,
	l.AdmissionDate,
	l.DischargeDate,
	ty.AdmissionType,
	c.CovidHealthcareUtilisation
FROM #MainCohort m 
INNER JOIN #LengthOfStay l ON m.FK_Patient_Link_ID = l.FK_Patient_Link_ID
INNER JOIN #COVIDUtilisationAdmissions c ON c.FK_Patient_Link_ID = l.FK_Patient_Link_ID AND c.AdmissionDate = l.AdmissionDate AND c.AcuteProvider = l.AcuteProvider
INNER JOIN #AdmissionTypes ty ON ty.FK_Patient_Link_ID = m.FK_Patient_Link_ID AND ty.AdmissionDate = l.AdmissionDate
WHERE l.AdmissionDate BETWEEN @StartDate AND @EndDate
--patients in matched cohort
UNION
SELECT 
	PatientId = m.FK_Patient_Link_ID,
	PatientWhoIsMatched AS MainCohortMatchedPatientId,
	l.AdmissionDate,
	DischargeDate,
	ty.AdmissionType,
    c.CovidHealthcareUtilisation
FROM #MatchedCohort m 
INNER JOIN #LengthOfStay l ON m.FK_Patient_Link_ID = l.FK_Patient_Link_ID
INNER JOIN #COVIDUtilisationAdmissions c ON c.FK_Patient_Link_ID = l.FK_Patient_Link_ID AND c.AdmissionDate = l.AdmissionDate AND c.AcuteProvider = l.AcuteProvider
INNER JOIN #AdmissionTypes ty ON ty.FK_Patient_Link_ID = m.FK_Patient_Link_ID AND ty.AdmissionDate = l.AdmissionDate
WHERE l.AdmissionDate BETWEEN @StartDate AND @EndDate