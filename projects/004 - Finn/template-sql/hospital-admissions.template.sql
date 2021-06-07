--┌─────────────────────────────────┐
--│ Hospital Admissions             │
--└─────────────────────────────────┘

-- Study index date: 1st Feb 2020

-- Hospital admissions for the all the cohort patients who had covid?


-- OUTPUT: A single table with the following:
--	PK: AdmissionID
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


--> EXECUTE patients2.template.sql










--> EXECUTE query-get-admissions-and-length-of-stay.sql
-- OUTPUT: Two temp table as follows:
-- #Admissions (FK_Patient_Link_ID, AdmissionDate, AcuteProvider)
-- #LengthOfStay (FK_Patient_Link_ID, AdmissionDate, DischargeDate, LengthOfStay)

-- For each patient find the first hospital admission following their positive covid test
-- IF OBJECT_ID('tempdb..#PatientsFirstAdmissionPostTest') IS NOT NULL DROP TABLE #PatientsFirstAdmissionPostTest;
-- SELECT l.FK_Patient_Link_ID, MAX(l.AdmissionDate) AS FirstAdmissionPostCOVIDTest, MAX(LengthOfStay) AS LengthOfStay
-- INTO #PatientsFirstAdmissionPostTest
-- FROM #LengthOfStay l
-- INNER JOIN (
--   SELECT p.FK_Patient_Link_ID, MIN(AdmissionDate) AS FirstAdmission
--   FROM #PatientIdsAndIndexDates p
--   LEFT OUTER JOIN #LengthOfStay los
--     ON los.FK_Patient_Link_ID = p.FK_Patient_Link_ID
--     AND los.AdmissionDate >= p.IndexDate
--   GROUP BY p.FK_Patient_Link_ID
-- ) sub ON sub.FK_Patient_Link_ID = l.FK_Patient_Link_ID AND sub.FirstAdmission = l.AdmissionDate
-- GROUP BY l.FK_Patient_Link_ID;