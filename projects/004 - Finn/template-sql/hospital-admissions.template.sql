--┌─────────────────────────────────┐
--│ Hospital Admissions             │
--└─────────────────────────────────┘

-- Study index date: 1st Feb 2020

-- Hospital admissions for the all the cohort patients who had covid


-- OUTPUT: A single table with the following:
--	FK: PatientID
--	AdmissionDate 
--	Admission Type Code
--	AdmissionTypeDescription
--	ReasonForAdmissionCode 
--	ReasonForAdmissionDescription 
--	LengthOfStay 
--	Discharge date


--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2020-02-01';

-- Get all the patients in the cohort
--> EXECUTE query-cancer-cohort-matching.sql
-- OUTPUTS: #Patients2


IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT DISTINCT FK_Patient_Link_ID
INTO #Patients
FROM #Patients2;


--> EXECUTE query-classify-secondary-admissions.sql
-- OUTPUT: #AdmissionTypes (FK_Patient_Link_ID, AdmissionDate, AcuteProvider, AdmissionType)


--> EXECUTE query-get-admissions-and-length-of-stay.sql
-- OUTPUT: 
-- #LengthOfStay (FK_Patient_Link_ID, AdmissionDate, DischargeDate, LengthOfStay)
-- #Admissions (FK_Patient_Link_ID, AdmissionDate, AcuteProvider)

--> EXECUTE query-admissions-covid-utilisation.sql
-- #COVIDUtilisationAdmissions (FK_Patient_Link_ID, AdmissionDate, AcuteProvider, CovidHealthcareUtilisation)

IF OBJECT_ID('tempdb..#HospitalAdmissions') IS NOT NULL DROP TABLE #HospitalAdmissions;
SELECT 
    a.FK_Patient_Link_ID AS PatientId,
    a.AdmissionDate,
    AdmissionType,
    l.DischargeDate,
    l.LengthOfStay
FROM #AdmissionTypes p
    LEFT OUTER JOIN #Admissions a ON a.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND a.AdmissionDate = p.AdmissionDate AND a.AcuteProvider = p.AcuteProvider
    LEFT OUTER JOIN #COVIDUtilisationAdmissions c ON c.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND c.AdmissionDate = p.AdmissionDate AND c.AcuteProvider = p.AcuteProvider
    LEFT OUTER JOIN #LengthOfStay l ON l.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND l.AdmissionDate = p.AdmissionDate AND l.AcuteProvider = p.AcuteProvider
WHERE c.CovidHealthcareUtilisation = 'TRUE';
-- GROUP BY p.AdmissionDate,p.AcuteProvider

-- 2.354 rows





