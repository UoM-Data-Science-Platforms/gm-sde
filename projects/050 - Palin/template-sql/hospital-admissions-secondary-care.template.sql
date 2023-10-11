--┌────────────────────────────────────────────────────────────────────────────────────┐
--│ Hospital inpatient episodes for pregnancy cohort - identified from secondary care  │
--└────────────────────────────────────────────────────────────────────────────────────┘

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
SET @EndDate = '2023-08-31';

--Just want the output, not the messages
SET NOCOUNT ON;

----------------------------------------
--> EXECUTE query-build-rq050-cohort.sql
----------------------------------------

--> EXECUTE query-get-admissions-and-length-of-stay.sql all-patients:false
--> EXECUTE query-admissions-covid-utilisation.sql start-date:'2020-01-01' all-patients:false gp-events-table:SharedCare.GP_Events

----- create anonymised identifier for each hospital
-- this is included in case PI needs to consider hospitals that don't have as much historic data

IF OBJECT_ID('tempdb..#hospitals') IS NOT NULL DROP TABLE #hospitals;
SELECT DISTINCT AcuteProvider
INTO #hospitals
FROM #LengthOfStay

IF OBJECT_ID('tempdb..#RandomiseHospital') IS NOT NULL DROP TABLE #RandomiseHospital;
SELECT AcuteProvider
	, HospitalID = ROW_NUMBER() OVER (order by newid())
INTO #RandomiseHospital
FROM #hospitals

--bring together for final output
SELECT 
	PatientId = m.FK_Patient_Link_ID,
	rh.HospitalID,
	l.AdmissionDate,
	l.DischargeDate,
	a.AdmissionType,
	c.CovidHealthcareUtilisation
FROM #Cohort m 
LEFT OUTER JOIN #LengthOfStay l ON m.FK_Patient_Link_ID = l.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDUtilisationAdmissions c ON c.FK_Patient_Link_ID = l.FK_Patient_Link_ID AND c.AdmissionDate = l.AdmissionDate AND c.AcuteProvider = l.AcuteProvider
LEFT OUTER JOIN #AdmissionTypes a ON a.FK_Patient_Link_ID = l.FK_Patient_Link_ID AND a.AdmissionDate = l.AdmissionDate AND a.AcuteProvider = l.AcuteProvider
LEFT OUTER JOIN #RandomiseHospital rh ON rh.AcuteProvider = l.AcuteProvider
WHERE l.AdmissionDate <= '2022-03-01'
