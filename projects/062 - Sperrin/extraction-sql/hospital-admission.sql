--+--------------------------------------------------------------------------------+
--¦ Patient hospital admisson                                                      ¦
--+--------------------------------------------------------------------------------+
-- !!! NEED TO DO: WHEN WE HAVE WEEK OF BIRTH, PLEASE CHANGE THE QUERY-BUILD-RQ062-COHORT.SQL TO UPDATE THE COHORT. ALSO ADD WEEK OF BRTH FOR THE TABLE BELOW. THANKS.
-- !!! NEED TO DO: DISCUSS TO MAKE SURE THE PROVIDED DATA IS NOT IDENTIFIABLE.

-------- RESEARCH DATA ENGINEER CHECK ---------


-- OUTPUT: Data with the following fields
-- - PatientId
-- - AdmissionDate
-- - DischargeDate


--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2014-01-01';


--┌───────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
--│ Define Cohort for RQ062: all individuals registered with a GP who were aged 50 years or older on September 1 2013 │
--└───────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

-- NEED TO DO!!!: CHANGE YEAR AND MONTH OF BIRTH INTO WEEK OF BIRTH LATER WHEN THE WEEK OF BIRTH DATA IS AVAILABLE

-- OBJECTIVE: To build the cohort of patients needed for RQ062. This reduces duplication of code in the template scripts.

-- COHORT: All individuals who registered with a GP, and were aged 50 years or older on September 1 2013 (the start of the herpes zoster vaccine programme in the UK)

-- OUTPUT: Temp tables as follows:
-- #Patients (FK_Patient_Link_ID)
-- A distinct list of FK_Patient_Link_IDs for each patient in the cohort


-- Create table #Patients for the reusable queries =========================================================================================================================
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT PK_Patient_Link_ID AS FK_Patient_Link_ID INTO #Patients
FROM [SharedCare].[Patient_Link]

--┌───────────────────────────────────────┐
--│ GET practice and ccg for each patient │
--└───────────────────────────────────────┘

-- OBJECTIVE:	For each patient to get the practice id that they are registered to, and 
--						the CCG name that the practice belongs to.

-- INPUT: Assumes there exists a temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: Two temp tables as follows:
-- #PatientPractice (FK_Patient_Link_ID, GPPracticeCode)
--	- FK_Patient_Link_ID - unique patient id
--	- GPPracticeCode - the nationally recognised practice id for the patient
-- #PatientPracticeAndCCG (FK_Patient_Link_ID, GPPracticeCode, CCG)
--	- FK_Patient_Link_ID - unique patient id
--	- GPPracticeCode - the nationally recognised practice id for the patient
--	- CCG - the name of the patient's CCG

-- If patients have a tenancy id of 2 we take this as their most likely GP practice
-- as this is the GP data feed and so most likely to be up to date
IF OBJECT_ID('tempdb..#PatientPractice') IS NOT NULL DROP TABLE #PatientPractice;
SELECT FK_Patient_Link_ID, MIN(GPPracticeCode) as GPPracticeCode INTO #PatientPractice FROM SharedCare.Patient
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_Tenancy_ID = 2
AND GPPracticeCode IS NOT NULL
GROUP BY FK_Patient_Link_ID;
-- 1298467 rows
-- 00:00:11

-- Find the patients who remain unmatched
IF OBJECT_ID('tempdb..#UnmatchedPatientsForPracticeCode') IS NOT NULL DROP TABLE #UnmatchedPatientsForPracticeCode;
SELECT FK_Patient_Link_ID INTO #UnmatchedPatientsForPracticeCode FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientPractice;
-- 12702 rows
-- 00:00:00

-- If every GPPracticeCode is the same for all their linked patient ids then we use that
INSERT INTO #PatientPractice
SELECT FK_Patient_Link_ID, MIN(GPPracticeCode) FROM SharedCare.Patient
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedPatientsForPracticeCode)
AND GPPracticeCode IS NOT NULL
GROUP BY FK_Patient_Link_ID
HAVING MIN(GPPracticeCode) = MAX(GPPracticeCode);
-- 12141
-- 00:00:00

-- Find any still unmatched patients
TRUNCATE TABLE #UnmatchedPatientsForPracticeCode;
INSERT INTO #UnmatchedPatientsForPracticeCode
SELECT FK_Patient_Link_ID FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientPractice;
-- 561 rows
-- 00:00:00

-- If there is a unique most recent gp practice then we use that
INSERT INTO #PatientPractice
SELECT p.FK_Patient_Link_ID, MIN(p.GPPracticeCode) FROM SharedCare.Patient p
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(HDMModifDate) MostRecentDate FROM SharedCare.Patient
	WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedPatientsForPracticeCode)
	GROUP BY FK_Patient_Link_ID
) sub ON sub.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND sub.MostRecentDate = p.HDMModifDate
WHERE p.GPPracticeCode IS NOT NULL
GROUP BY p.FK_Patient_Link_ID
HAVING MIN(GPPracticeCode) = MAX(GPPracticeCode);
-- 15

--┌──────────────────┐
--│ CCG lookup table │
--└──────────────────┘

-- OBJECTIVE: To provide lookup table for CCG names. The GMCR provides the CCG id (e.g. '00T', '01G') but not 
--            the CCG name. This table can be used in other queries when the output is required to be a ccg 
--            name rather than an id.

-- INPUT: No pre-requisites

-- OUTPUT: A temp table as follows:
-- #CCGLookup (CcgId, CcgName)
-- 	- CcgId - Nationally recognised ccg id
--	- CcgName - Bolton, Stockport etc..

IF OBJECT_ID('tempdb..#CCGLookup') IS NOT NULL DROP TABLE #CCGLookup;
CREATE TABLE #CCGLookup (CcgId nchar(3), CcgName nvarchar(20));
INSERT INTO #CCGLookup VALUES ('01G', 'Salford'); 
INSERT INTO #CCGLookup VALUES ('00T', 'Bolton'); 
INSERT INTO #CCGLookup VALUES ('01D', 'HMR'); 
INSERT INTO #CCGLookup VALUES ('02A', 'Trafford'); 
INSERT INTO #CCGLookup VALUES ('01W', 'Stockport');
INSERT INTO #CCGLookup VALUES ('00Y', 'Oldham'); 
INSERT INTO #CCGLookup VALUES ('02H', 'Wigan'); 
INSERT INTO #CCGLookup VALUES ('00V', 'Bury'); 
INSERT INTO #CCGLookup VALUES ('14L', 'Manchester'); 
INSERT INTO #CCGLookup VALUES ('01Y', 'Tameside Glossop'); 

IF OBJECT_ID('tempdb..#PatientPracticeAndCCG') IS NOT NULL DROP TABLE #PatientPracticeAndCCG;
SELECT p.FK_Patient_Link_ID, ISNULL(pp.GPPracticeCode,'') AS GPPracticeCode, ISNULL(ccg.CcgName, '') AS CCG
INTO #PatientPracticeAndCCG
FROM #Patients p
LEFT OUTER JOIN #PatientPractice pp ON pp.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN SharedCare.Reference_GP_Practice gp ON gp.OrganisationCode = pp.GPPracticeCode
LEFT OUTER JOIN #CCGLookup ccg ON ccg.CcgId = gp.Commissioner;
--┌────────────────────────────────┐
--│ Year and quarter month of birth│
--└────────────────────────────────┘

-- OBJECTIVE: To get the year of birth for each patient.

-- INPUT: Assumes there exists a temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: A temp table as follows:
-- #PatientYearAndQuarterMonthOfBirth (FK_Patient_Link_ID, YearAndQuarterMonthOfBirth)
-- 	- FK_Patient_Link_ID - unique patient id
--	- YearAndQuarterMonthOfBirth - (YYYY-MM-01)

-- ASSUMPTIONS:
--	- Patient data is obtained from multiple sources. Where patients have multiple YearAndQuarterMonthOfBirths we determine the YearAndQuarterMonthOfBirth as follows:
--	-	If the patients has a YearAndQuarterMonthOfBirth in their primary care data feed we use that as most likely to be up to date
--	-	If every YearAndQuarterMonthOfBirth for a patient is the same, then we use that
--	-	If there is a single most recently updated YearAndQuarterMonthOfBirth in the database then we use that
--	-	Otherwise we take the highest YearAndQuarterMonthOfBirth for the patient that is not in the future

-- Get all patients year and quarter month of birth for the cohort
IF OBJECT_ID('tempdb..#AllPatientYearAndQuarterMonthOfBirths') IS NOT NULL DROP TABLE #AllPatientYearAndQuarterMonthOfBirths;
SELECT 
	FK_Patient_Link_ID,
	FK_Reference_Tenancy_ID,
	HDMModifDate,
	CONVERT(date, Dob) AS YearAndQuarterMonthOfBirth
INTO #AllPatientYearAndQuarterMonthOfBirths
FROM SharedCare.Patient p
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND Dob IS NOT NULL;


-- If patients have a tenancy id of 2 we take this as their most likely YearAndQuarterMonthOfBirth
-- as this is the GP data feed and so most likely to be up to date
IF OBJECT_ID('tempdb..#PatientYearAndQuarterMonthOfBirth') IS NOT NULL DROP TABLE #PatientYearAndQuarterMonthOfBirth;
SELECT FK_Patient_Link_ID, MIN(YearAndQuarterMonthOfBirth) as YearAndQuarterMonthOfBirth INTO #PatientYearAndQuarterMonthOfBirth FROM #AllPatientYearAndQuarterMonthOfBirths
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_Tenancy_ID = 2
GROUP BY FK_Patient_Link_ID
HAVING MIN(YearAndQuarterMonthOfBirth) = MAX(YearAndQuarterMonthOfBirth);

-- Find the patients who remain unmatched
IF OBJECT_ID('tempdb..#UnmatchedYobPatients') IS NOT NULL DROP TABLE #UnmatchedYobPatients;
SELECT FK_Patient_Link_ID INTO #UnmatchedYobPatients FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientYearAndQuarterMonthOfBirth;

-- If every YearAndQuarterMonthOfBirth is the same for all their linked patient ids then we use that
INSERT INTO #PatientYearAndQuarterMonthOfBirth
SELECT FK_Patient_Link_ID, MIN(YearAndQuarterMonthOfBirth) FROM #AllPatientYearAndQuarterMonthOfBirths
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedYobPatients)
GROUP BY FK_Patient_Link_ID
HAVING MIN(YearAndQuarterMonthOfBirth) = MAX(YearAndQuarterMonthOfBirth);

-- Find any still unmatched patients
TRUNCATE TABLE #UnmatchedYobPatients;
INSERT INTO #UnmatchedYobPatients
SELECT FK_Patient_Link_ID FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientYearAndQuarterMonthOfBirth;

-- If there is a unique most recent YearAndQuarterMonthOfBirth then use that
INSERT INTO #PatientYearAndQuarterMonthOfBirth
SELECT p.FK_Patient_Link_ID, MIN(p.YearAndQuarterMonthOfBirth) FROM #AllPatientYearAndQuarterMonthOfBirths p
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(HDMModifDate) MostRecentDate FROM #AllPatientYearAndQuarterMonthOfBirths
	WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedYobPatients)
	GROUP BY FK_Patient_Link_ID
) sub ON sub.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND sub.MostRecentDate = p.HDMModifDate
GROUP BY p.FK_Patient_Link_ID
HAVING MIN(YearAndQuarterMonthOfBirth) = MAX(YearAndQuarterMonthOfBirth);

-- Find any still unmatched patients
TRUNCATE TABLE #UnmatchedYobPatients;
INSERT INTO #UnmatchedYobPatients
SELECT FK_Patient_Link_ID FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientYearAndQuarterMonthOfBirth;

-- Otherwise just use the highest value (with the exception that can't be in the future)
INSERT INTO #PatientYearAndQuarterMonthOfBirth
SELECT FK_Patient_Link_ID, MAX(YearAndQuarterMonthOfBirth) FROM #AllPatientYearAndQuarterMonthOfBirths
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedYobPatients)
GROUP BY FK_Patient_Link_ID
HAVING MAX(YearAndQuarterMonthOfBirth) <= GETDATE();

-- Tidy up - helpful in ensuring the tempdb doesn't run out of space mid-query
DROP TABLE #AllPatientYearAndQuarterMonthOfBirths;
DROP TABLE #UnmatchedYobPatients;


-- Merge information========================================================================================================================================================
IF OBJECT_ID('tempdb..#Table') IS NOT NULL DROP TABLE #Table;
SELECT
  p.FK_Patient_Link_ID as PatientId, 
  gp.GPPracticeCode, 
  yob.YearAndQuarterMonthOfBirth, DATEDIFF(year, yob.YearAndQuarterMonthOfBirth, '2013-09-01') AS [Time]
INTO #Table
FROM #Patients p
LEFT OUTER JOIN #PatientPractice gp ON gp.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearAndQuarterMonthOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID;


-- Reduce #Patients table to just the cohort patients========================================================================================================================
TRUNCATE TABLE #Patients;
INSERT INTO #Patients
SELECT PatientId
FROM #Table
WHERE GPPracticeCode IS NOT NULL AND YearAndQuarterMonthOfBirth < '1963-09-01'


-- Populate temporary table with admissions
-- Convert AdmissionDate to a date to avoid issues where a person has two admissions
-- on the same day (but only one discharge)
IF OBJECT_ID('tempdb..#Admissions') IS NOT NULL DROP TABLE #Admissions;
CREATE TABLE #Admissions (
	FK_Patient_Link_ID BIGINT,
	AdmissionDate DATE,
	AcuteProvider NVARCHAR(150)
);

INSERT INTO #Admissions
SELECT DISTINCT FK_Patient_Link_ID, CONVERT(DATE, AdmissionDate) AS AdmissionDate, t.TenancyName AS AcuteProvider
FROM [SharedCare].[Acute_Inpatients] i
LEFT OUTER JOIN SharedCare.Reference_Tenancy t ON t.PK_Reference_Tenancy_ID = i.FK_Reference_Tenancy_ID
WHERE EventType = 'Admission'
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND AdmissionDate >= @StartDate;


--┌──────────────────────┐
--│ Secondary discharges │
--└──────────────────────┘

-- OBJECTIVE: To obtain a table with every secondary care discharge, along with the acute provider,
--						and the date of discharge.

-- INPUT: One parameter
--	-	all-patients: boolean - (true/false) if true, then all patients are included, otherwise only those in the pre-existing #Patients table.

-- OUTPUT: A temp table as follows:
-- #Discharges (FK_Patient_Link_ID, DischargeDate, AcuteProvider)
-- 	- FK_Patient_Link_ID - unique patient id
--	- DischargeDate - date of discharge (YYYY-MM-DD)
--	- AcuteProvider - Bolton, SRFT, Stockport etc..
--  (Limited to one discharge per person per hospital per day, because if a patient has 2 discharges 
--   on the same day to the same hopsital then it's most likely data duplication rather than two short
--   hospital stays)

-- Set the temp end date until new legal basis
--DECLARE @TEMPDischargesEndDate datetime;
--SET @TEMPDischargesEndDate = '2022-06-01';

-- Populate temporary table with discharges
IF OBJECT_ID('tempdb..#Discharges') IS NOT NULL DROP TABLE #Discharges;
CREATE TABLE #Discharges (
	FK_Patient_Link_ID BIGINT,
	DischargeDate DATE,
	AcuteProvider NVARCHAR(150)
);
BEGIN
	IF 'false'='true'
		INSERT INTO #Discharges
    SELECT DISTINCT FK_Patient_Link_ID, CONVERT(DATE, DischargeDate) AS DischargeDate, t.TenancyName AS AcuteProvider 
    FROM [SharedCare].[Acute_Inpatients] i
    LEFT OUTER JOIN SharedCare.Reference_Tenancy t ON t.PK_Reference_Tenancy_ID = i.FK_Reference_Tenancy_ID
    WHERE EventType = 'Discharge'
    AND DischargeDate >= @StartDate
   -- AND DischargeDate <= @TEMPDischargesEndDate;
  ELSE
		INSERT INTO #Discharges
    SELECT DISTINCT FK_Patient_Link_ID, CONVERT(DATE, DischargeDate) AS DischargeDate, t.TenancyName AS AcuteProvider 
    FROM [SharedCare].[Acute_Inpatients] i
    LEFT OUTER JOIN SharedCare.Reference_Tenancy t ON t.PK_Reference_Tenancy_ID = i.FK_Reference_Tenancy_ID
    WHERE EventType = 'Discharge'
		AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
    AND DischargeDate >= @StartDate
    --AND DischargeDate <= @TEMPDischargesEndDate;;
END
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

----- create anonymised identifier for each hospital
-- this is included in case PI wants to consider the fact that each hospitalstarted providing complete data on different dates

IF OBJECT_ID('tempdb..#hospitals') IS NOT NULL DROP TABLE #hospitals;
SELECT DISTINCT AcuteProvider
INTO #hospitals
FROM #LengthOfStay

IF OBJECT_ID('tempdb..#RandomiseHospital') IS NOT NULL DROP TABLE #RandomiseHospital;
SELECT AcuteProvider
	, HospitalID = ROW_NUMBER() OVER (order by newid())
INTO #RandomiseHospital
FROM #hospitals

-- Create the final table
SELECT FK_Patient_Link_ID AS PatientID,
 	   YearAndMonthOfAdmission = DATEADD(dd, -( DAY( AdmissionDate) -1 ), AdmissionDate),
	   LengthOfStayDays = LengthOfStay,
	   HospitalID 
FROM #LengthOfStay los
LEFT JOIN #RandomiseHospital rh ON rh.AcuteProvider = los.AcuteProvider
ORDER BY FK_Patient_Link_ID, AdmissionDate


------ advise team that some hospitals only started providing data in 2020/21. Show them table on this page: https://github.com/rw251/gm-idcr/blob/master/docs/index.md