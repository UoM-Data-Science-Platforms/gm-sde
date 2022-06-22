--┌───────────────────────────────────────────────────────┐
--│ Hospital inpatient episodes for pregnancy cohort      │
--└───────────────────────────────────────────────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------

-- OUTPUT: Data with the following fields
-- Patient Id
-- AdmissionDate (DD-MM-YYYY)
-- DischargeDate (DD-MM-YYYY)
-- AdmissionType
-- CovidAdmission (1/0)

-- Set the start date
DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2018-01-01';
SET @EndDate = '2022-01-01';

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
----------------------------------- DEFINE MAIN COHORT -- ----------------------------------------------
--------------------------------------------------------------------------------------------------------


--------------------------------------------------------------------------------------------------------



--> EXECUTE query-get-admissions-and-length-of-stay.sql all-patients:false
--> EXECUTE query-admissions-covid-utilisation.sql start-date:'2020-01-01' all-patients:false gp-events-table:RLS.vw_GP_Events
--> EXECUTE query-classify-secondary-admissions.sql 

--bring together for final output
SELECT 
	PatientId = m.FK_Patient_Link_ID,
	l.AdmissionDate,
	l.DischargeDate,
	a.AdmissionType,
	c.CovidHealthcareUtilisation
FROM #Cohort m 
LEFT OUTER JOIN #LengthOfStay l ON m.FK_Patient_Link_ID = l.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDUtilisationAdmissions c ON c.FK_Patient_Link_ID = l.FK_Patient_Link_ID AND c.AdmissionDate = l.AdmissionDate AND c.AcuteProvider = l.AcuteProvider
LEFT OUTER JOIN #AdmissionTypes a ON a.FK_Patient_Link_ID = l.FK_Patient_Link_ID AND a.AdmissionDate = l.AdmissionDate AND a.AcuteProvider = l.AcuteProvider
WHERE c.CovidHealthcareUtilisation = 'TRUE'
	AND l.AdmissionDate <= @EndDate
