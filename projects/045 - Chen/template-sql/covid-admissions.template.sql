--┌────────────────────────────────────────────────────────────┐
--│ Hospital stay for Covid patients                           │
--└────────────────────────────────────────────────────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------


-- OUTPUT: Data with the following fields
-- Patient Id
-- AdmissionDate (DD-MM-YYYY)
-- DischargeDate (DD-MM-YYYY)
-- LengthOfStay 
-- Hospital - ANONYMOUS

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2020-01-01';
DECLARE @EndDate datetime;
SET @EndDate = '2023-12-31';

--Just want the output, not the messages
SET NOCOUNT ON;

--> EXECUTE query-build-rq045-cohort.sql
--> EXECUTE query-get-admissions-and-length-of-stay.sql all-patients:false
--> EXECUTE query-admissions-covid-utilisation.sql start-date:'2020-01-01' all-patients:false gp-events-table:SharedCare.GP_Events


-- Create anonymised identifier for each hospital============================================================================================================
IF OBJECT_ID('tempdb..#hospitals') IS NOT NULL DROP TABLE #hospitals;
SELECT DISTINCT AcuteProvider
INTO #hospitals
FROM #LengthOfStay

IF OBJECT_ID('tempdb..#RandomiseHospital') IS NOT NULL DROP TABLE #RandomiseHospital;
SELECT AcuteProvider
	, HospitalID = ROW_NUMBER() OVER (order by newid())
INTO #RandomiseHospital
FROM #hospitals


--Bring together for final output============================================================================================================================
--patients in main cohort
SELECT 
	PatientId = m.FK_Patient_Link_ID,
	l.AdmissionDate,
	l.DischargeDate,
	l.LengthOfStay,
	rh.HospitalID
FROM #Patients m 
LEFT JOIN #LengthOfStay l ON m.FK_Patient_Link_ID = l.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDUtilisationAdmissions c ON c.FK_Patient_Link_ID = l.FK_Patient_Link_ID AND c.AdmissionDate = l.AdmissionDate AND c.AcuteProvider = l.AcuteProvider
LEFT OUTER JOIN #RandomiseHospital rh ON rh.AcuteProvider = l.AcuteProvider
WHERE c.CovidHealthcareUtilisation = 'TRUE'
	AND l.AdmissionDate <= @EndDate
