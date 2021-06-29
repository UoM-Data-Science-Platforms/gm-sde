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






--┌─────────────────────────────────────────┐
--│ Secondary admissions and length of stay │
--└─────────────────────────────────────────┘

-- OBJECTIVE: To obtain a table with every secondary care admission, along with the acute provider,
--						the date of admission, the date of discharge, and the length of stay.

-- INPUT: No pre-requisites

-- OUTPUT: Two temp table as follows:
-- #Admissions (FK_Patient_Link_ID, AdmissionDate, AcuteProvider)
-- 	- FK_Patient_Link_ID - unique patient id
--	- AdmissionDate - date of discharge (YYYY-MM-DD)
--	- AcuteProvider - Bolton, SRFT, Stockport etc..
--  (Limited to one admission per person per hospital per day, because if a patient has 2 admissions 
--   on the same day to the same hopsital then it's most likely data duplication rather than two short
--   hospital stays)
-- #LengthOfStay (FK_Patient_Link_ID, AdmissionDate)
-- 	- FK_Patient_Link_ID - unique patient id
--	- AdmissionDate - date of discharge (YYYY-MM-DD)
--	- DischargeDate - date of discharge (YYYY-MM-DD)
--	- LengthOfStay - Number of days between admission and discharge. 1 = [0,1) days, 2 = [1,2) days, etc.

-- Populate temporary table with admissions
-- Convert AdmissionDate to a date to avoid issues where a person has two admissions
-- on the same day (but only one discharge)
IF OBJECT_ID('tempdb..#Admissions') IS NOT NULL DROP TABLE #Admissions;
SELECT DISTINCT FK_Patient_Link_ID, CONVERT(DATE, AdmissionDate) AS AdmissionDate, t.TenancyName AS AcuteProvider INTO #Admissions FROM [RLS].[vw_Acute_Inpatients] i
LEFT OUTER JOIN SharedCare.Reference_Tenancy t ON t.PK_Reference_Tenancy_ID = i.FK_Reference_Tenancy_ID
WHERE EventType = 'Admission'
AND AdmissionDate >= @StartDate;
-- 523477 rows	523477 rows
-- 00:00:19		00:00:15

--┌──────────────────────┐
--│ Secondary discharges │
--└──────────────────────┘

-- OBJECTIVE: To obtain a table with every secondary care discharge, along with the acute provider,
--						and the date of discharge.

-- INPUT: No pre-requisites

-- OUTPUT: A temp table as follows:
-- #Discharges (FK_Patient_Link_ID, DischargeDate, AcuteProvider)
-- 	- FK_Patient_Link_ID - unique patient id
--	- DischargeDate - date of discharge (YYYY-MM-DD)
--	- AcuteProvider - Bolton, SRFT, Stockport etc..
--  (Limited to one discharge per person per hospital per day, because if a patient has 2 discharges 
--   on the same day to the same hopsital then it's most likely data duplication rather than two short
--   hospital stays)

-- Populate temporary table with discharges
IF OBJECT_ID('tempdb..#Discharges') IS NOT NULL DROP TABLE #Discharges;
SELECT DISTINCT FK_Patient_Link_ID, CONVERT(DATE, DischargeDate) AS DischargeDate, t.TenancyName AS AcuteProvider INTO #Discharges FROM [RLS].[vw_Acute_Inpatients] i
LEFT OUTER JOIN SharedCare.Reference_Tenancy t ON t.PK_Reference_Tenancy_ID = i.FK_Reference_Tenancy_ID
WHERE EventType = 'Discharge'
AND DischargeDate >= @StartDate;
-- 535285 rows	535285 rows
-- 00:00:28		00:00:14


-- Link admission with discharge to get length of stay
-- Length of stay is zero-indexed e.g. 
-- 1 = [0,1) days
-- 2 = [1,2) days
IF OBJECT_ID('tempdb..#LengthOfStay') IS NOT NULL DROP TABLE #LengthOfStay;
SELECT 
	a.FK_Patient_Link_ID, a.AdmissionDate, a.AcuteProvider, 
	MIN(d.DischargeDate) AS DischargeDate, 
	1 + DATEDIFF(day,a.AdmissionDate, MIN(d.DischargeDate)) AS LengthOfStay
	INTO #LengthOfStay
FROM #Admissions a
INNER JOIN #Discharges d ON d.FK_Patient_Link_ID = a.FK_Patient_Link_ID AND d.DischargeDate >= a.AdmissionDate AND d.AcuteProvider = a.AcuteProvider
GROUP BY a.FK_Patient_Link_ID, a.AdmissionDate, a.AcuteProvider
ORDER BY a.FK_Patient_Link_ID, a.AdmissionDate, a.AcuteProvider;
-- 511740 rows	511740 rows	
-- 00:00:04		00:00:05

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