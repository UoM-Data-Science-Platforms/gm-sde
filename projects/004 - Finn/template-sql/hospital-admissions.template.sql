--┌─────────────────────────────────┐
--│ Hospital Admissions             │
--└─────────────────────────────────┘

-- Study index date: 1st Feb 2020

-- Hospital admissions for the all the cohort patients who had covid

-- OUTPUT: A single table with the following:
--	PatientId (Int)
--	AdmissionDate (YYYY-MM-DD)
--	Admission Type (Unplanned, Planned, Maternity, Transfer, Other)
--	LengthOfStay (Int)
--	DischargeDate (YYYY-MM-DD)


--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2020-02-01';

-- Get all the patients in the cohort
--> EXECUTE query-cancer-cohort-matching.sql
-- OUTPUTS: #Patients, #Patients2

--> EXECUTE query-classify-secondary-admissions.sql
-- OUTPUT: #AdmissionTypes (FK_Patient_Link_ID, AdmissionDate, AcuteProvider, AdmissionType)

--> EXECUTE query-get-admissions-and-length-of-stay.sql
-- OUTPUT: 
-- #LengthOfStay (FK_Patient_Link_ID, AdmissionDate, DischargeDate, LengthOfStay)
-- #Admissions (FK_Patient_Link_ID, AdmissionDate, AcuteProvider)

--> EXECUTE query-admissions-covid-utilisation.sql
-- OUTPUT: #COVIDUtilisationAdmissions (FK_Patient_Link_ID, AdmissionDate, AcuteProvider, CovidHealthcareUtilisation)

SELECT 
    c.FK_Patient_Link_ID AS PatientId,
    c.AdmissionDate,
    a.AdmissionType,
    l.DischargeDate,
    l.LengthOfStay
FROM #COVIDUtilisationAdmissions c
LEFT OUTER JOIN #AdmissionTypes a ON a.FK_Patient_Link_ID = c.FK_Patient_Link_ID AND a.AdmissionDate = c.AdmissionDate 
LEFT OUTER JOIN #LengthOfStay l ON l.FK_Patient_Link_ID = c.FK_Patient_Link_ID AND l.AdmissionDate = c.AdmissionDate 
WHERE c.CovidHealthcareUtilisation = 'TRUE';






