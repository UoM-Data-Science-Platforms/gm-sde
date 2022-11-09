--┌──────────────────────────────────┐
--│ RQ025 - Watkinson - Data extract │
--└──────────────────────────────────┘

-- REVIEW LOG:
--	-	George Tilston	2021-04-14	Review complete	

-- OUTPUT: Data with the following fields
-- 	- PatientId
--  - AgeAtIndexDate
--  - Sex (M/F)
--  - Ethnicity
--  - LSOA
--  - IsCareHomeResident (Y/N)
--  - HasHighClinicalVulnerabilityIndicator (Y/N)
--  - DateOfHighClinicalVulnerabilityIndicator
--  - HasModerateClinicalVulnerabilityIndicator (Y/N)
--	-	IsClinicallyEligibleForFluVaccine (Y/N)
--	-	DateOfFluVaccineIn20152016Season (YYYY-MM-DD)
--	-	DateOfFluVaccineIn20162017Season (YYYY-MM-DD)
--	-	DateOfFluVaccineIn20172018Season (YYYY-MM-DD)
--	-	DateOfFluVaccineIn20182019Season (YYYY-MM-DD)
--	-	DateOfFluVaccineIn20192020Season (YYYY-MM-DD)
--	-	DateOfFluVaccineIn20202021Season (YYYY-MM-DD)
--	-	DateOfFluVaccineIn20212022Season (YYYY-MM-DD)
--  - HasCovidHospitalisation (Y/N)
--  - DateOfFirstCovidHospitalisation
--  - HasCovidDeathWithin28Days (Y/N)
--  - FirstVaccineDate
--  - SecondVaccineDate
--  - ThirdVaccineDate
--  - FourthVaccineDate
--  - FifthVaccineDate
--  - SixthVaccineDate
--  - SeventhVaccineDate
--	-	DateVaccineDeclined
--  - DateOfDeath

--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the temp end date until new legal basis
DECLARE @TEMPRQ025EndDate datetime;
SET @TEMPRQ025EndDate = '2022-06-01';

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2020-02-01';

-- Only include patients who were first registered at a GP practice prior
-- to June 2022. This is 1 month before COPI expired and so acts as a buffer.
-- If we only looked at patients who first registered before July 2022, then
-- there is a chance that their data was processed after COPI expired.
IF OBJECT_ID('tempdb..#PatientsToInclude') IS NOT NULL DROP TABLE #PatientsToInclude;
SELECT FK_Patient_Link_ID INTO #PatientsToInclude
FROM SharedCare.Patient_GP_History
GROUP BY FK_Patient_Link_ID
HAVING MIN(StartDate) < @TEMPRQ025EndDate;

-- Find all patients alive at start date
IF OBJECT_ID('tempdb..#PossiblePatients') IS NOT NULL DROP TABLE #PossiblePatients;
SELECT PK_Patient_Link_ID as FK_Patient_Link_ID, EthnicCategoryDescription, DeathDate INTO #PossiblePatients FROM [RLS].vw_Patient_Link
WHERE (DeathDate IS NULL OR (DeathDate >= @StartDate AND DeathDate < @TEMPRQ025EndDate))
AND PK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

-- Find all patients registered with a GP
IF OBJECT_ID('tempdb..#PatientsWithGP') IS NOT NULL DROP TABLE #PatientsWithGP;
SELECT DISTINCT FK_Patient_Link_ID INTO #PatientsWithGP FROM [RLS].vw_Patient
where FK_Reference_Tenancy_ID = 2
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

-- Make cohort from patients alive at start date and registered with a GP
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT pp.* INTO #Patients FROM #PossiblePatients pp
INNER JOIN #PatientsWithGP gp on gp.FK_Patient_Link_ID = pp.FK_Patient_Link_ID;

--┌───────────────┐
--│ Year of birth │
--└───────────────┘

-- OBJECTIVE: To get the year of birth for each patient.

-- INPUT: Assumes there exists a temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: A temp table as follows:
-- #PatientYearOfBirth (FK_Patient_Link_ID, YearOfBirth)
-- 	- FK_Patient_Link_ID - unique patient id
--	- YearOfBirth - INT

-- ASSUMPTIONS:
--	- Patient data is obtained from multiple sources. Where patients have multiple YOBs we determine the YOB as follows:
--	-	If the patients has a YOB in their primary care data feed we use that as most likely to be up to date
--	-	If every YOB for a patient is the same, then we use that
--	-	If there is a single most recently updated YOB in the database then we use that
--	-	Otherwise we take the highest YOB for the patient that is not in the future

-- Get all patients year of birth for the cohort
IF OBJECT_ID('tempdb..#AllPatientYearOfBirths') IS NOT NULL DROP TABLE #AllPatientYearOfBirths;
SELECT 
	FK_Patient_Link_ID,
	FK_Reference_Tenancy_ID,
	HDMModifDate,
	YEAR(Dob) AS YearOfBirth
INTO #AllPatientYearOfBirths
FROM RLS.vw_Patient p
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND Dob IS NOT NULL;


-- If patients have a tenancy id of 2 we take this as their most likely YOB
-- as this is the GP data feed and so most likely to be up to date
IF OBJECT_ID('tempdb..#PatientYearOfBirth') IS NOT NULL DROP TABLE #PatientYearOfBirth;
SELECT FK_Patient_Link_ID, MIN(YearOfBirth) as YearOfBirth INTO #PatientYearOfBirth FROM #AllPatientYearOfBirths
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_Tenancy_ID = 2
GROUP BY FK_Patient_Link_ID
HAVING MIN(YearOfBirth) = MAX(YearOfBirth);

-- Find the patients who remain unmatched
IF OBJECT_ID('tempdb..#UnmatchedYobPatients') IS NOT NULL DROP TABLE #UnmatchedYobPatients;
SELECT FK_Patient_Link_ID INTO #UnmatchedYobPatients FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientYearOfBirth;

-- If every YOB is the same for all their linked patient ids then we use that
INSERT INTO #PatientYearOfBirth
SELECT FK_Patient_Link_ID, MIN(YearOfBirth) FROM #AllPatientYearOfBirths
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedYobPatients)
GROUP BY FK_Patient_Link_ID
HAVING MIN(YearOfBirth) = MAX(YearOfBirth);

-- Find any still unmatched patients
TRUNCATE TABLE #UnmatchedYobPatients;
INSERT INTO #UnmatchedYobPatients
SELECT FK_Patient_Link_ID FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientYearOfBirth;

-- If there is a unique most recent YOB then use that
INSERT INTO #PatientYearOfBirth
SELECT p.FK_Patient_Link_ID, MIN(p.YearOfBirth) FROM #AllPatientYearOfBirths p
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(HDMModifDate) MostRecentDate FROM #AllPatientYearOfBirths
	WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedYobPatients)
	GROUP BY FK_Patient_Link_ID
) sub ON sub.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND sub.MostRecentDate = p.HDMModifDate
GROUP BY p.FK_Patient_Link_ID
HAVING MIN(YearOfBirth) = MAX(YearOfBirth);

-- Find any still unmatched patients
TRUNCATE TABLE #UnmatchedYobPatients;
INSERT INTO #UnmatchedYobPatients
SELECT FK_Patient_Link_ID FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientYearOfBirth;

-- Otherwise just use the highest value (with the exception that can't be in the future)
INSERT INTO #PatientYearOfBirth
SELECT FK_Patient_Link_ID, MAX(YearOfBirth) FROM #AllPatientYearOfBirths
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedYobPatients)
GROUP BY FK_Patient_Link_ID
HAVING MAX(YearOfBirth) <= YEAR(GETDATE());

-- Tidy up - helpful in ensuring the tempdb doesn't run out of space mid-query
DROP TABLE #AllPatientYearOfBirths;
DROP TABLE #UnmatchedYobPatients;

-- Remove patients who are currently <16
-- UPDATE RW - PI advised to remove the <16 restriction

IF OBJECT_ID('tempdb..#Temp') IS NOT NULL DROP TABLE #Temp;
SELECT p.FK_Patient_Link_ID, EthnicCategoryDescription, DeathDate INTO #Temp FROM #Patients p
	INNER JOIN #PatientYearOfBirth y ON y.FK_Patient_Link_ID = p.FK_Patient_Link_ID;
TRUNCATE TABLE #Patients;
INSERT INTO #Patients
SELECT * FROM #Temp;

--┌───────────────────────────────┐
--│ Lower level super output area │
--└───────────────────────────────┘

-- OBJECTIVE: To get the LSOA for each patient.

-- INPUT: Assumes there exists a temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: A temp table as follows:
-- #PatientLSOA (FK_Patient_Link_ID, LSOA)
-- 	- FK_Patient_Link_ID - unique patient id
--	- LSOA_Code - nationally recognised LSOA identifier

-- ASSUMPTIONS:
--	- Patient data is obtained from multiple sources. Where patients have multiple LSOAs we determine the LSOA as follows:
--	-	If the patients has an LSOA in their primary care data feed we use that as most likely to be up to date
--	-	If every LSOA for a paitent is the same, then we use that
--	-	If there is a single most recently updated LSOA in the database then we use that
--	-	Otherwise the patient's LSOA is considered unknown

-- Get all patients LSOA for the cohort
IF OBJECT_ID('tempdb..#AllPatientLSOAs') IS NOT NULL DROP TABLE #AllPatientLSOAs;
SELECT 
	FK_Patient_Link_ID,
	FK_Reference_Tenancy_ID,
	HDMModifDate,
	LSOA_Code
INTO #AllPatientLSOAs
FROM RLS.vw_Patient p
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND LSOA_Code IS NOT NULL;


-- If patients have a tenancy id of 2 we take this as their most likely LSOA_Code
-- as this is the GP data feed and so most likely to be up to date
IF OBJECT_ID('tempdb..#PatientLSOA') IS NOT NULL DROP TABLE #PatientLSOA;
SELECT FK_Patient_Link_ID, MIN(LSOA_Code) as LSOA_Code INTO #PatientLSOA FROM #AllPatientLSOAs
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_Tenancy_ID = 2
GROUP BY FK_Patient_Link_ID
HAVING MIN(LSOA_Code) = MAX(LSOA_Code);

-- Find the patients who remain unmatched
IF OBJECT_ID('tempdb..#UnmatchedLsoaPatients') IS NOT NULL DROP TABLE #UnmatchedLsoaPatients;
SELECT FK_Patient_Link_ID INTO #UnmatchedLsoaPatients FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientLSOA;
-- 38710 rows
-- 00:00:00

-- If every LSOA_Code is the same for all their linked patient ids then we use that
INSERT INTO #PatientLSOA
SELECT FK_Patient_Link_ID, MIN(LSOA_Code) FROM #AllPatientLSOAs
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedLsoaPatients)
GROUP BY FK_Patient_Link_ID
HAVING MIN(LSOA_Code) = MAX(LSOA_Code);

-- Find any still unmatched patients
TRUNCATE TABLE #UnmatchedLsoaPatients;
INSERT INTO #UnmatchedLsoaPatients
SELECT FK_Patient_Link_ID FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientLSOA;

-- If there is a unique most recent lsoa then use that
INSERT INTO #PatientLSOA
SELECT p.FK_Patient_Link_ID, MIN(p.LSOA_Code) FROM #AllPatientLSOAs p
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(HDMModifDate) MostRecentDate FROM #AllPatientLSOAs
	WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedLsoaPatients)
	GROUP BY FK_Patient_Link_ID
) sub ON sub.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND sub.MostRecentDate = p.HDMModifDate
GROUP BY p.FK_Patient_Link_ID
HAVING MIN(LSOA_Code) = MAX(LSOA_Code);

-- Tidy up - helpful in ensuring the tempdb doesn't run out of space mid-query
DROP TABLE #AllPatientLSOAs;
DROP TABLE #UnmatchedLsoaPatients;
--┌─────┐
--│ Sex │
--└─────┘

-- OBJECTIVE: To get the Sex for each patient.

-- INPUT: Assumes there exists a temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: A temp table as follows:
-- #PatientSex (FK_Patient_Link_ID, Sex)
-- 	- FK_Patient_Link_ID - unique patient id
--	- Sex - M/F

-- ASSUMPTIONS:
--	- Patient data is obtained from multiple sources. Where patients have multiple sexes we determine the sex as follows:
--	-	If the patients has a sex in their primary care data feed we use that as most likely to be up to date
--	-	If every sex for a patient is the same, then we use that
--	-	If there is a single most recently updated sex in the database then we use that
--	-	Otherwise the patient's sex is considered unknown

-- Get all patients sex for the cohort
IF OBJECT_ID('tempdb..#AllPatientSexs') IS NOT NULL DROP TABLE #AllPatientSexs;
SELECT 
	FK_Patient_Link_ID,
	FK_Reference_Tenancy_ID,
	HDMModifDate,
	Sex
INTO #AllPatientSexs
FROM RLS.vw_Patient p
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND Sex IS NOT NULL;


-- If patients have a tenancy id of 2 we take this as their most likely Sex
-- as this is the GP data feed and so most likely to be up to date
IF OBJECT_ID('tempdb..#PatientSex') IS NOT NULL DROP TABLE #PatientSex;
SELECT FK_Patient_Link_ID, MIN(Sex) as Sex INTO #PatientSex FROM #AllPatientSexs
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_Tenancy_ID = 2
GROUP BY FK_Patient_Link_ID
HAVING MIN(Sex) = MAX(Sex);

-- Find the patients who remain unmatched
IF OBJECT_ID('tempdb..#UnmatchedSexPatients') IS NOT NULL DROP TABLE #UnmatchedSexPatients;
SELECT FK_Patient_Link_ID INTO #UnmatchedSexPatients FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientSex;

-- If every Sex is the same for all their linked patient ids then we use that
INSERT INTO #PatientSex
SELECT FK_Patient_Link_ID, MIN(Sex) FROM #AllPatientSexs
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedSexPatients)
GROUP BY FK_Patient_Link_ID
HAVING MIN(Sex) = MAX(Sex);

-- Find any still unmatched patients
TRUNCATE TABLE #UnmatchedSexPatients;
INSERT INTO #UnmatchedSexPatients
SELECT FK_Patient_Link_ID FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientSex;

-- If there is a unique most recent Sex then use that
INSERT INTO #PatientSex
SELECT p.FK_Patient_Link_ID, MIN(p.Sex) FROM #AllPatientSexs p
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(HDMModifDate) MostRecentDate FROM #AllPatientSexs
	WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedSexPatients)
	GROUP BY FK_Patient_Link_ID
) sub ON sub.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND sub.MostRecentDate = p.HDMModifDate
GROUP BY p.FK_Patient_Link_ID
HAVING MIN(Sex) = MAX(Sex);

-- Tidy up - helpful in ensuring the tempdb doesn't run out of space mid-query
DROP TABLE #AllPatientSexs;
DROP TABLE #UnmatchedSexPatients;
--┌──────────────────┐
--│ Care home status │
--└──────────────────┘

-- OBJECTIVE: To get the care home status for each patient.

-- INPUT: Assumes there exists a temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: A temp table as follows:
-- #PatientCareHomeStatus (FK_Patient_Link_ID, IsCareHomeResident)
-- 	- FK_Patient_Link_ID - unique patient id
--	- IsCareHomeResident - Y/N

-- ASSUMPTIONS:
--	-	If any of the patient records suggests the patients lives in a care home we will assume that they do

-- Get all patients sex for the cohort
IF OBJECT_ID('tempdb..#PatientCareHomeStatus') IS NOT NULL DROP TABLE #PatientCareHomeStatus;
SELECT 
	FK_Patient_Link_ID,
	MAX(NursingCareHomeFlag) AS IsCareHomeResident -- max as Y > N > NULL
INTO #PatientCareHomeStatus
FROM RLS.vw_Patient p
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND NursingCareHomeFlag IS NOT NULL
GROUP BY FK_Patient_Link_ID;


--┌─────────────────────────────────────────┐
--│ Secondary admissions and length of stay │
--└─────────────────────────────────────────┘

-- OBJECTIVE: To obtain a table with every secondary care admission, along with the acute provider,
--						the date of admission, the date of discharge, and the length of stay.

-- INPUT: One parameter
--	-	all-patients: boolean - (true/false) if true, then all patients are included, otherwise only those in the pre-existing #Patients table.

-- OUTPUT: Two temp table as follows:
-- #Admissions (FK_Patient_Link_ID, AdmissionDate, AcuteProvider)
-- 	- FK_Patient_Link_ID - unique patient id
--	- AdmissionDate - date of admission (YYYY-MM-DD)
--	- AcuteProvider - Bolton, SRFT, Stockport etc..
--  (Limited to one admission per person per hospital per day, because if a patient has 2 admissions 
--   on the same day to the same hopsital then it's most likely data duplication rather than two short
--   hospital stays)
-- #LengthOfStay (FK_Patient_Link_ID, AdmissionDate)
-- 	- FK_Patient_Link_ID - unique patient id
--	- AdmissionDate - date of admission (YYYY-MM-DD)
--	- AcuteProvider - Bolton, SRFT, Stockport etc..
--	- DischargeDate - date of discharge (YYYY-MM-DD)
--	- LengthOfStay - Number of days between admission and discharge. 1 = [0,1) days, 2 = [1,2) days, etc.

-- Set the temp end date until new legal basis
DECLARE @TEMPAdmissionsEndDate datetime;
SET @TEMPAdmissionsEndDate = '2022-06-01';

-- Populate temporary table with admissions
-- Convert AdmissionDate to a date to avoid issues where a person has two admissions
-- on the same day (but only one discharge)
IF OBJECT_ID('tempdb..#Admissions') IS NOT NULL DROP TABLE #Admissions;
CREATE TABLE #Admissions (
	FK_Patient_Link_ID BIGINT,
	AdmissionDate DATE,
	AcuteProvider NVARCHAR(150)
);
BEGIN
	IF 'true'='true'
		INSERT INTO #Admissions
		SELECT DISTINCT FK_Patient_Link_ID, CONVERT(DATE, AdmissionDate) AS AdmissionDate, t.TenancyName AS AcuteProvider
		FROM [RLS].[vw_Acute_Inpatients] i
		LEFT OUTER JOIN SharedCare.Reference_Tenancy t ON t.PK_Reference_Tenancy_ID = i.FK_Reference_Tenancy_ID
		WHERE EventType = 'Admission'
		AND AdmissionDate >= @StartDate
		AND AdmissionDate <= @TEMPAdmissionsEndDate;
	ELSE
		INSERT INTO #Admissions
		SELECT DISTINCT FK_Patient_Link_ID, CONVERT(DATE, AdmissionDate) AS AdmissionDate, t.TenancyName AS AcuteProvider
		FROM [RLS].[vw_Acute_Inpatients] i
		LEFT OUTER JOIN SharedCare.Reference_Tenancy t ON t.PK_Reference_Tenancy_ID = i.FK_Reference_Tenancy_ID
		WHERE EventType = 'Admission'
		AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
		AND AdmissionDate >= @StartDate
		AND AdmissionDate <= @TEMPAdmissionsEndDate;
END

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
DECLARE @TEMPDischargesEndDate datetime;
SET @TEMPDischargesEndDate = '2022-06-01';

-- Populate temporary table with discharges
IF OBJECT_ID('tempdb..#Discharges') IS NOT NULL DROP TABLE #Discharges;
CREATE TABLE #Discharges (
	FK_Patient_Link_ID BIGINT,
	DischargeDate DATE,
	AcuteProvider NVARCHAR(150)
);
BEGIN
	IF 'true'='true'
		INSERT INTO #Discharges
    SELECT DISTINCT FK_Patient_Link_ID, CONVERT(DATE, DischargeDate) AS DischargeDate, t.TenancyName AS AcuteProvider 
    FROM [RLS].[vw_Acute_Inpatients] i
    LEFT OUTER JOIN SharedCare.Reference_Tenancy t ON t.PK_Reference_Tenancy_ID = i.FK_Reference_Tenancy_ID
    WHERE EventType = 'Discharge'
    AND DischargeDate >= @StartDate
    AND DischargeDate <= @TEMPDischargesEndDate;
  ELSE
		INSERT INTO #Discharges
    SELECT DISTINCT FK_Patient_Link_ID, CONVERT(DATE, DischargeDate) AS DischargeDate, t.TenancyName AS AcuteProvider 
    FROM [RLS].[vw_Acute_Inpatients] i
    LEFT OUTER JOIN SharedCare.Reference_Tenancy t ON t.PK_Reference_Tenancy_ID = i.FK_Reference_Tenancy_ID
    WHERE EventType = 'Discharge'
		AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
    AND DischargeDate >= @StartDate
    AND DischargeDate <= @TEMPDischargesEndDate;;
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
-- 511740 rows	511740 rows	
-- 00:00:04		00:00:05

--┌────────────────────────────────────┐
--│ COVID-related secondary admissions │
--└────────────────────────────────────┘

-- OBJECTIVE: To classify every admission to secondary care based on whether it is a COVID or non-COVID related.
--						A COVID-related admission is classed as an admission within 4 weeks after, or up to 2 weeks before
--						a positive test.

-- INPUT: Takes one parameter
--  - start-date: string - (YYYY-MM-DD) the date to count diagnoses from. Usually this should be 2020-01-01.
--	-	all-patients: boolean - (true/false) if true, then all patients are included, otherwise only those in the pre-existing #Patients table.
--	- gp-events-table: string - (table name) the name of the table containing the GP events. Usually is "RLS.vw_GP_Events" but can be anything with the columns: FK_Patient_Link_ID, EventDate, and SuppliedCode
-- And assumes there exists two temp tables as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort
-- #Admissions (FK_Patient_Link_ID, AdmissionDate, AcuteProvider)
--  A distinct list of the admissions for each patient in the cohort

-- OUTPUT: A temp table as follows:
-- #COVIDUtilisationAdmissions (FK_Patient_Link_ID, AdmissionDate, AcuteProvider, CovidHealthcareUtilisation)
--	- FK_Patient_Link_ID - unique patient id
--	- AdmissionDate - date of admission (YYYY-MM-DD)
--	- AcuteProvider - Bolton, SRFT, Stockport etc..
--	- CovidHealthcareUtilisation - 'TRUE' if admission within 4 weeks after, or up to 14 days before, a positive test

-- Get first positive covid test for each patient
--┌─────────────────────┐
--│ Patients with COVID │
--└─────────────────────┘

-- OBJECTIVE: To get tables of all patients with a COVID diagnosis in their record. This now includes a table
-- that has reinfections. This uses a 90 day cut-off to rule out patients that get multiple tests for
-- a single infection. This 90 day cut-off is also used in the government COVID dashboard. In the first wave,
-- prior to widespread COVID testing, and prior to the correct clinical codes being	available to clinicians,
-- infections were recorded in a variety of ways. We therefore take the first diagnosis from any code indicative
-- of COVID. However, for subsequent infections we insist on the presence of a positive COVID test (PCR or antigen)
-- as opposed to simply a diagnosis code. This is to avoid the situation where a hospital diagnosis code gets 
-- entered into the primary care record several months after the actual infection.

-- INPUT: Takes three parameters
--  - start-date: string - (YYYY-MM-DD) the date to count diagnoses from. Usually this should be 2020-01-01.
--	-	all-patients: boolean - (true/false) if true, then all patients are included, otherwise only those in the pre-existing #Patients table.
--	- gp-events-table: string - (table name) the name of the table containing the GP events. Usually is "RLS.vw_GP_Events" but can be anything with the columns: FK_Patient_Link_ID, EventDate, and SuppliedCode

-- OUTPUT: Three temp tables as follows:
-- #CovidPatients (FK_Patient_Link_ID, FirstCovidPositiveDate)
-- 	- FK_Patient_Link_ID - unique patient id
--	- FirstCovidPositiveDate - earliest COVID diagnosis
-- #CovidPatientsAllDiagnoses (FK_Patient_Link_ID, CovidPositiveDate)
-- 	- FK_Patient_Link_ID - unique patient id
--	- CovidPositiveDate - any COVID diagnosis
-- #CovidPatientsMultipleDiagnoses
--	-	FK_Patient_Link_ID - unique patient id
--	-	FirstCovidPositiveDate - date of first COVID diagnosis
--	-	SecondCovidPositiveDate - date of second COVID diagnosis
--	-	ThirdCovidPositiveDate - date of third COVID diagnosis
--	-	FourthCovidPositiveDate - date of fourth COVID diagnosis
--	-	FifthCovidPositiveDate - date of fifth COVID diagnosis

-- >>> Codesets required... Inserting the code set code
--
--┌────────────────────┐
--│ Clinical code sets │
--└────────────────────┘

-- OBJECTIVE: To populate temporary tables with the existing clinical code sets.
--            See the [SQL-generation-process.md](SQL-generation-process.md) for more details.

-- INPUT: No pre-requisites

-- OUTPUT: Five temp tables as follows:
--  #AllCodes (Concept, Version, Code)
--  #CodeSets (FK_Reference_Coding_ID, Concept)
--  #SnomedSets (FK_Reference_SnomedCT_ID, FK_SNOMED_ID)
--  #VersionedCodeSets (FK_Reference_Coding_ID, Concept, Version)
--  #VersionedSnomedSets (FK_Reference_SnomedCT_ID, Version, FK_SNOMED_ID)

--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
--!!! DO NOT EDIT THIS FILE MANUALLY !!!
--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

IF OBJECT_ID('tempdb..#AllCodes') IS NOT NULL DROP TABLE #AllCodes;
CREATE TABLE #AllCodes (
  [Concept] [varchar](255) NOT NULL,
  [Version] INT NOT NULL,
  [Code] [varchar](20) COLLATE Latin1_General_CS_AS NOT NULL,
  [description] [varchar] (255) NULL 
);

IF OBJECT_ID('tempdb..#codesreadv2') IS NOT NULL DROP TABLE #codesreadv2;
CREATE TABLE #codesreadv2 (
  [concept] [varchar](255) NOT NULL,
  [version] INT NOT NULL,
	[code] [varchar](20) COLLATE Latin1_General_CS_AS NOT NULL,
	[term] [varchar](20) COLLATE Latin1_General_CS_AS NULL,
	[description] [varchar](255) NULL
) ON [PRIMARY];

INSERT INTO #codesreadv2
VALUES ('severe-mental-illness',1,'E11..',NULL,'Affective psychoses'),('severe-mental-illness',1,'E11..00',NULL,'Affective psychoses'),('severe-mental-illness',1,'E110.',NULL,'Manic disorder, single episode'),('severe-mental-illness',1,'E110.00',NULL,'Manic disorder, single episode'),('severe-mental-illness',1,'Eu302',NULL,'[X]Mania with psychotic symptoms'),('severe-mental-illness',1,'Eu30200',NULL,'[X]Mania with psychotic symptoms'),('severe-mental-illness',1,'ZRby1',NULL,'mood states, bipolar'),('severe-mental-illness',1,'ZRby100',NULL,'mood states, bipolar'),('severe-mental-illness',1,'13Y3.',NULL,'Manic-depression association member'),('severe-mental-illness',1,'13Y3.00',NULL,'Manic-depression association member'),('severe-mental-illness',1,'146D.',NULL,'H/O: manic depressive disorder'),('severe-mental-illness',1,'146D.00',NULL,'H/O: manic depressive disorder'),('severe-mental-illness',1,'1S42.',NULL,'Manic mood'),('severe-mental-illness',1,'1S42.00',NULL,'Manic mood'),('severe-mental-illness',1,'212V.',NULL,'Bipolar affective disorder resolved'),('severe-mental-illness',1,'212V.00',NULL,'Bipolar affective disorder resolved'),('severe-mental-illness',1,'46P3.',NULL,'Urine lithium'),('severe-mental-illness',1,'46P3.00',NULL,'Urine lithium'),('severe-mental-illness',1,'6657.',NULL,'On lithium'),('severe-mental-illness',1,'6657.00',NULL,'On lithium'),('severe-mental-illness',1,'665B.',NULL,'Lithium stopped'),('severe-mental-illness',1,'665B.00',NULL,'Lithium stopped'),('severe-mental-illness',1,'665J.',NULL,'Lithium level checked at 3 monthly intervals'),('severe-mental-illness',1,'665J.00',NULL,'Lithium level checked at 3 monthly intervals'),('severe-mental-illness',1,'665K.',NULL,'Lithium therapy record book completed'),('severe-mental-illness',1,'665K.00',NULL,'Lithium therapy record book completed'),('severe-mental-illness',1,'9Ol5.',NULL,'Lithium monitoring first letter'),('severe-mental-illness',1,'9Ol5.00',NULL,'Lithium monitoring first letter'),('severe-mental-illness',1,'9Ol6.',NULL,'Lithium monitoring second letter'),('severe-mental-illness',1,'9Ol6.00',NULL,'Lithium monitoring second letter'),('severe-mental-illness',1,'9Ol7.',NULL,'Lithium monitoring third letter'),('severe-mental-illness',1,'9Ol7.00',NULL,'Lithium monitoring third letter'),('severe-mental-illness',1,'E1100',NULL,'Single manic episode, unspecified'),('severe-mental-illness',1,'E110000',NULL,'Single manic episode, unspecified'),('severe-mental-illness',1,'E1101',NULL,'Single manic episode, mild'),('severe-mental-illness',1,'E110100',NULL,'Single manic episode, mild'),('severe-mental-illness',1,'E1102',NULL,'Single manic episode, moderate'),('severe-mental-illness',1,'E110200',NULL,'Single manic episode, moderate'),('severe-mental-illness',1,'E1103',NULL,'Single manic episode, severe without mention of psychosis'),('severe-mental-illness',1,'E110300',NULL,'Single manic episode, severe without mention of psychosis'),('severe-mental-illness',1,'E1104',NULL,'Single manic episode, severe, with psychosis'),('severe-mental-illness',1,'E110400',NULL,'Single manic episode, severe, with psychosis'),('severe-mental-illness',1,'E1105',NULL,'Single manic episode in partial or unspecified remission'),('severe-mental-illness',1,'E110500',NULL,'Single manic episode in partial or unspecified remission'),('severe-mental-illness',1,'E1106',NULL,'Single manic episode in full remission'),('severe-mental-illness',1,'E110600',NULL,'Single manic episode in full remission'),('severe-mental-illness',1,'E110z',NULL,'Manic disorder, single episode NOS'),('severe-mental-illness',1,'E110z00',NULL,'Manic disorder, single episode NOS'),('severe-mental-illness',1,'E111.',NULL,'Recurrent manic episodes'),('severe-mental-illness',1,'E111.00',NULL,'Recurrent manic episodes'),('severe-mental-illness',1,'E1110',NULL,'Recurrent manic episodes, unspecified'),('severe-mental-illness',1,'E111000',NULL,'Recurrent manic episodes, unspecified'),('severe-mental-illness',1,'E1111',NULL,'Recurrent manic episodes, mild'),('severe-mental-illness',1,'E111100',NULL,'Recurrent manic episodes, mild'),('severe-mental-illness',1,'E1112',NULL,'Recurrent manic episodes, moderate'),('severe-mental-illness',1,'E111200',NULL,'Recurrent manic episodes, moderate'),('severe-mental-illness',1,'E1113',NULL,'Recurrent manic episodes, severe without mention psychosis'),('severe-mental-illness',1,'E111300',NULL,'Recurrent manic episodes, severe without mention psychosis'),('severe-mental-illness',1,'E1114',NULL,'Recurrent manic episodes, severe, with psychosis'),('severe-mental-illness',1,'E111400',NULL,'Recurrent manic episodes, severe, with psychosis'),('severe-mental-illness',1,'E1115',NULL,'Recurrent manic episodes, partial or unspecified remission'),('severe-mental-illness',1,'E111500',NULL,'Recurrent manic episodes, partial or unspecified remission'),('severe-mental-illness',1,'E1116',NULL,'Recurrent manic episodes, in full remission'),('severe-mental-illness',1,'E111600',NULL,'Recurrent manic episodes, in full remission'),('severe-mental-illness',1,'E111z',NULL,'Recurrent manic episode NOS'),('severe-mental-illness',1,'E111z00',NULL,'Recurrent manic episode NOS'),('severe-mental-illness',1,'E114.',NULL,'Bipolar affective disorder, currently manic'),('severe-mental-illness',1,'E114.00',NULL,'Bipolar affective disorder, currently manic'),('severe-mental-illness',1,'E1140',NULL,'Bipolar affective disorder, currently manic, unspecified'),('severe-mental-illness',1,'E114000',NULL,'Bipolar affective disorder, currently manic, unspecified'),('severe-mental-illness',1,'E1141',NULL,'Bipolar affective disorder, currently manic, mild'),('severe-mental-illness',1,'E114100',NULL,'Bipolar affective disorder, currently manic, mild'),('severe-mental-illness',1,'E1142',NULL,'Bipolar affective disorder, currently manic, moderate'),('severe-mental-illness',1,'E114200',NULL,'Bipolar affective disorder, currently manic, moderate'),('severe-mental-illness',1,'E1143',NULL,'Bipolar affect disord, currently manic, severe, no psychosis'),('severe-mental-illness',1,'E114300',NULL,'Bipolar affect disord, currently manic, severe, no psychosis'),('severe-mental-illness',1,'E1144',NULL,'Bipolar affect disord, currently manic,severe with psychosis'),('severe-mental-illness',1,'E114400',NULL,'Bipolar affect disord, currently manic,severe with psychosis'),('severe-mental-illness',1,'E1145',NULL,'Bipolar affect disord,currently manic, part/unspec remission'),('severe-mental-illness',1,'E114500',NULL,'Bipolar affect disord,currently manic, part/unspec remission'),('severe-mental-illness',1,'E1146',NULL,'Bipolar affective disorder, currently manic, full remission'),('severe-mental-illness',1,'E114600',NULL,'Bipolar affective disorder, currently manic, full remission'),('severe-mental-illness',1,'E114z',NULL,'Bipolar affective disorder, currently manic, NOS'),('severe-mental-illness',1,'E114z00',NULL,'Bipolar affective disorder, currently manic, NOS'),('severe-mental-illness',1,'E115.',NULL,'Bipolar affective disorder, currently depressed'),('severe-mental-illness',1,'E115.00',NULL,'Bipolar affective disorder, currently depressed'),('severe-mental-illness',1,'E1150',NULL,'Bipolar affective disorder, currently depressed, unspecified'),('severe-mental-illness',1,'E115000',NULL,'Bipolar affective disorder, currently depressed, unspecified'),('severe-mental-illness',1,'E1151',NULL,'Bipolar affective disorder, currently depressed, mild'),('severe-mental-illness',1,'E115100',NULL,'Bipolar affective disorder, currently depressed, mild'),('severe-mental-illness',1,'E1152',NULL,'Bipolar affective disorder, currently depressed, moderate'),('severe-mental-illness',1,'E115200',NULL,'Bipolar affective disorder, currently depressed, moderate'),('severe-mental-illness',1,'E1153',NULL,'Bipolar affect disord, now depressed, severe, no psychosis'),('severe-mental-illness',1,'E115300',NULL,'Bipolar affect disord, now depressed, severe, no psychosis'),('severe-mental-illness',1,'E1154',NULL,'Bipolar affect disord, now depressed, severe with psychosis'),('severe-mental-illness',1,'E115400',NULL,'Bipolar affect disord, now depressed, severe with psychosis'),('severe-mental-illness',1,'E1155',NULL,'Bipolar affect disord, now depressed, part/unspec remission'),('severe-mental-illness',1,'E115500',NULL,'Bipolar affect disord, now depressed, part/unspec remission'),('severe-mental-illness',1,'E1156',NULL,'Bipolar affective disorder, now depressed, in full remission'),('severe-mental-illness',1,'E115600',NULL,'Bipolar affective disorder, now depressed, in full remission'),('severe-mental-illness',1,'E115z',NULL,'Bipolar affective disorder, currently depressed, NOS'),('severe-mental-illness',1,'E115z00',NULL,'Bipolar affective disorder, currently depressed, NOS'),('severe-mental-illness',1,'E116.',NULL,'Mixed bipolar affective disorder'),('severe-mental-illness',1,'E116.00',NULL,'Mixed bipolar affective disorder'),('severe-mental-illness',1,'E1160',NULL,'Mixed bipolar affective disorder, unspecified'),('severe-mental-illness',1,'E116000',NULL,'Mixed bipolar affective disorder, unspecified'),('severe-mental-illness',1,'E1161',NULL,'Mixed bipolar affective disorder, mild'),('severe-mental-illness',1,'E116100',NULL,'Mixed bipolar affective disorder, mild'),('severe-mental-illness',1,'E1162',NULL,'Mixed bipolar affective disorder, moderate'),('severe-mental-illness',1,'E116200',NULL,'Mixed bipolar affective disorder, moderate'),('severe-mental-illness',1,'E1163',NULL,'Mixed bipolar affective disorder, severe, without psychosis'),('severe-mental-illness',1,'E116300',NULL,'Mixed bipolar affective disorder, severe, without psychosis'),('severe-mental-illness',1,'E1164',NULL,'Mixed bipolar affective disorder, severe, with psychosis'),('severe-mental-illness',1,'E116400',NULL,'Mixed bipolar affective disorder, severe, with psychosis'),('severe-mental-illness',1,'E1165',NULL,'Mixed bipolar affective disorder, partial/unspec remission'),
('severe-mental-illness',1,'E116500',NULL,'Mixed bipolar affective disorder, partial/unspec remission'),('severe-mental-illness',1,'E1166',NULL,'Mixed bipolar affective disorder, in full remission'),('severe-mental-illness',1,'E116600',NULL,'Mixed bipolar affective disorder, in full remission'),('severe-mental-illness',1,'E116z',NULL,'Mixed bipolar affective disorder, NOS'),('severe-mental-illness',1,'E116z00',NULL,'Mixed bipolar affective disorder, NOS'),('severe-mental-illness',1,'E117.',NULL,'Unspecified bipolar affective disorder'),('severe-mental-illness',1,'E117.00',NULL,'Unspecified bipolar affective disorder'),('severe-mental-illness',1,'E1170',NULL,'Unspecified bipolar affective disorder, unspecified'),('severe-mental-illness',1,'E117000',NULL,'Unspecified bipolar affective disorder, unspecified'),('severe-mental-illness',1,'E1171',NULL,'Unspecified bipolar affective disorder, mild'),('severe-mental-illness',1,'E117100',NULL,'Unspecified bipolar affective disorder, mild'),('severe-mental-illness',1,'E1172',NULL,'Unspecified bipolar affective disorder, moderate'),('severe-mental-illness',1,'E117200',NULL,'Unspecified bipolar affective disorder, moderate'),('severe-mental-illness',1,'E1173',NULL,'Unspecified bipolar affective disorder, severe, no psychosis'),('severe-mental-illness',1,'E117300',NULL,'Unspecified bipolar affective disorder, severe, no psychosis'),('severe-mental-illness',1,'E1174',NULL,'Unspecified bipolar affective disorder,severe with psychosis'),('severe-mental-illness',1,'E117400',NULL,'Unspecified bipolar affective disorder,severe with psychosis'),('severe-mental-illness',1,'E1175',NULL,'Unspecified bipolar affect disord, partial/unspec remission'),('severe-mental-illness',1,'E117500',NULL,'Unspecified bipolar affect disord, partial/unspec remission'),('severe-mental-illness',1,'E1176',NULL,'Unspecified bipolar affective disorder, in full remission'),('severe-mental-illness',1,'E117600',NULL,'Unspecified bipolar affective disorder, in full remission'),('severe-mental-illness',1,'E117z',NULL,'Unspecified bipolar affective disorder, NOS'),('severe-mental-illness',1,'E117z00',NULL,'Unspecified bipolar affective disorder, NOS'),('severe-mental-illness',1,'E11y.',NULL,'Other and unspecified manic-depressive psychoses'),('severe-mental-illness',1,'E11y.00',NULL,'Other and unspecified manic-depressive psychoses'),('severe-mental-illness',1,'E11y0',NULL,'Unspecified manic-depressive psychoses'),('severe-mental-illness',1,'E11y000',NULL,'Unspecified manic-depressive psychoses'),('severe-mental-illness',1,'E11y1',NULL,'Atypical manic disorder'),('severe-mental-illness',1,'E11y100',NULL,'Atypical manic disorder'),('severe-mental-illness',1,'E11y2',NULL,'Atypical depressive disorder'),('severe-mental-illness',1,'E11y200',NULL,'Atypical depressive disorder'),('severe-mental-illness',1,'E11y3',NULL,'Other mixed manic-depressive psychoses'),('severe-mental-illness',1,'E11y300',NULL,'Other mixed manic-depressive psychoses'),('severe-mental-illness',1,'E11yz',NULL,'Other and unspecified manic-depressive psychoses NOS'),('severe-mental-illness',1,'E11yz00',NULL,'Other and unspecified manic-depressive psychoses NOS'),('severe-mental-illness',1,'E11z.',NULL,'Other and unspecified affective psychoses'),('severe-mental-illness',1,'E11z.00',NULL,'Other and unspecified affective psychoses'),('severe-mental-illness',1,'E11z0',NULL,'Unspecified affective psychoses NOS'),('severe-mental-illness',1,'E11z000',NULL,'Unspecified affective psychoses NOS'),('severe-mental-illness',1,'E11z1',NULL,'Rebound mood swings'),('severe-mental-illness',1,'E11z100',NULL,'Rebound mood swings'),('severe-mental-illness',1,'E11z2',NULL,'Masked depression'),('severe-mental-illness',1,'E11z200',NULL,'Masked depression'),('severe-mental-illness',1,'E11zz',NULL,'Other affective psychosis NOS'),('severe-mental-illness',1,'E11zz00',NULL,'Other affective psychosis NOS'),('severe-mental-illness',1,'Eu3..',NULL,'[X]Mood - affective disorders'),('severe-mental-illness',1,'Eu3..00',NULL,'[X]Mood - affective disorders'),('severe-mental-illness',1,'Eu30.',NULL,'[X]Manic episode'),('severe-mental-illness',1,'Eu30.00',NULL,'[X]Manic episode'),('severe-mental-illness',1,'Eu300',NULL,'[X]Hypomania'),('severe-mental-illness',1,'Eu30000',NULL,'[X]Hypomania'),('severe-mental-illness',1,'Eu301',NULL,'[X]Mania without psychotic symptoms'),('severe-mental-illness',1,'Eu30100',NULL,'[X]Mania without psychotic symptoms'),('severe-mental-illness',1,'Eu30y',NULL,'[X]Other manic episodes'),('severe-mental-illness',1,'Eu30y00',NULL,'[X]Other manic episodes'),('severe-mental-illness',1,'Eu30z',NULL,'[X]Manic episode, unspecified'),('severe-mental-illness',1,'Eu30z00',NULL,'[X]Manic episode, unspecified'),('severe-mental-illness',1,'Eu31.',NULL,'[X]Bipolar affective disorder'),('severe-mental-illness',1,'Eu31.00',NULL,'[X]Bipolar affective disorder'),('severe-mental-illness',1,'Eu310',NULL,'[X]Bipolar affective disorder, current episode hypomanic'),('severe-mental-illness',1,'Eu31000',NULL,'[X]Bipolar affective disorder, current episode hypomanic'),('severe-mental-illness',1,'Eu311',NULL,'[X]Bipolar affect disorder cur epi manic wout psychotic symp'),('severe-mental-illness',1,'Eu31100',NULL,'[X]Bipolar affect disorder cur epi manic wout psychotic symp'),('severe-mental-illness',1,'Eu312',NULL,'[X]Bipolar affect disorder cur epi manic with psychotic symp'),('severe-mental-illness',1,'Eu31200',NULL,'[X]Bipolar affect disorder cur epi manic with psychotic symp'),('severe-mental-illness',1,'Eu313',NULL,'[X]Bipolar affect disorder cur epi mild or moderate depressn'),('severe-mental-illness',1,'Eu31300',NULL,'[X]Bipolar affect disorder cur epi mild or moderate depressn'),('severe-mental-illness',1,'Eu314',NULL,'[X]Bipol aff disord, curr epis sev depress, no psychot symp'),('severe-mental-illness',1,'Eu31400',NULL,'[X]Bipol aff disord, curr epis sev depress, no psychot symp'),('severe-mental-illness',1,'Eu315',NULL,'[X]Bipolar affect dis cur epi severe depres with psyc symp'),('severe-mental-illness',1,'Eu31500',NULL,'[X]Bipolar affect dis cur epi severe depres with psyc symp'),('severe-mental-illness',1,'Eu316',NULL,'[X]Bipolar affective disorder, current episode mixed'),('severe-mental-illness',1,'Eu31600',NULL,'[X]Bipolar affective disorder, current episode mixed'),('severe-mental-illness',1,'Eu317',NULL,'[X]Bipolar affective disorder, currently in remission'),('severe-mental-illness',1,'Eu31700',NULL,'[X]Bipolar affective disorder, currently in remission'),('severe-mental-illness',1,'Eu318',NULL,'[X]Bipolar affective disorder type I'),('severe-mental-illness',1,'Eu31800',NULL,'[X]Bipolar affective disorder type I'),('severe-mental-illness',1,'Eu319',NULL,'[X]Bipolar affective disorder type II'),('severe-mental-illness',1,'Eu31900',NULL,'[X]Bipolar affective disorder type II'),('severe-mental-illness',1,'Eu31y',NULL,'[X]Other bipolar affective disorders'),('severe-mental-illness',1,'Eu31y00',NULL,'[X]Other bipolar affective disorders'),('severe-mental-illness',1,'Eu31z',NULL,'[X]Bipolar affective disorder, unspecified'),('severe-mental-illness',1,'Eu31z00',NULL,'[X]Bipolar affective disorder, unspecified'),('severe-mental-illness',1,'Eu332','13','[X]Manic-depress psychosis,depressd,no psychotic symptoms'),('severe-mental-illness',1,'Eu332','13','[X]Manic-depress psychosis,depressd,no psychotic symptoms'),('severe-mental-illness',1,'Eu333','12','[X]Manic-depress psychosis,depressed type+psychotic symptoms'),('severe-mental-illness',1,'Eu333','12','[X]Manic-depress psychosis,depressed type+psychotic symptoms'),('severe-mental-illness',1,'Eu34.',NULL,'[X]Persistent mood affective disorders'),('severe-mental-illness',1,'Eu34.00',NULL,'[X]Persistent mood affective disorders'),('severe-mental-illness',1,'Eu340',NULL,'[X]Cyclothymia'),('severe-mental-illness',1,'Eu34000',NULL,'[X]Cyclothymia'),('severe-mental-illness',1,'Eu34y',NULL,'[X]Other persistent mood affective disorders'),('severe-mental-illness',1,'Eu34y00',NULL,'[X]Other persistent mood affective disorders'),('severe-mental-illness',1,'Eu34z',NULL,'[X]Persistent mood affective disorder, unspecified'),('severe-mental-illness',1,'Eu34z00',NULL,'[X]Persistent mood affective disorder, unspecified'),('severe-mental-illness',1,'Eu3y.',NULL,'[X]Other mood affective disorders'),('severe-mental-illness',1,'Eu3y.00',NULL,'[X]Other mood affective disorders'),('severe-mental-illness',1,'Eu3y0',NULL,'[X]Other single mood affective disorders'),('severe-mental-illness',1,'Eu3y000',NULL,'[X]Other single mood affective disorders'),('severe-mental-illness',1,'Eu3y1',NULL,'[X]Other recurrent mood affective disorders'),('severe-mental-illness',1,'Eu3y100',NULL,'[X]Other recurrent mood affective disorders'),('severe-mental-illness',1,'Eu3yy',NULL,'[X]Other specified mood affective disorders'),('severe-mental-illness',1,'Eu3yy00',NULL,'[X]Other specified mood affective disorders'),('severe-mental-illness',1,'Eu3z.',NULL,'[X]Unspecified mood affective disorder'),('severe-mental-illness',1,'Eu3z.00',NULL,'[X]Unspecified mood affective disorder'),('severe-mental-illness',1,'ZV111','11','[V]Personal history of manic-depressive psychosis'),('severe-mental-illness',1,'ZV111','12','[V]Personal history of manic-depressive psychosis'),('severe-mental-illness',1,'ZV111','11','[V]Personal history of manic-depressive psychosis'),('severe-mental-illness',1,'ZV111','12','[V]Personal history of manic-depressive psychosis'),('severe-mental-illness',1,'E1011',NULL,'Subchronic hebephrenic schizophrenia'),('severe-mental-illness',1,'E101100',NULL,'Subchronic hebephrenic schizophrenia'),('severe-mental-illness',1,'E1013',NULL,'Acute exacerbation of subchronic hebephrenic schizophrenia'),('severe-mental-illness',1,'E101300',NULL,'Acute exacerbation of subchronic hebephrenic schizophrenia'),('severe-mental-illness',1,'E1023',NULL,'Acute exacerbation of subchronic catatonic schizophrenia'),
('severe-mental-illness',1,'E102300',NULL,'Acute exacerbation of subchronic catatonic schizophrenia'),('severe-mental-illness',1,'E1051',NULL,'Subchronic latent schizophrenia'),('severe-mental-illness',1,'E105100',NULL,'Subchronic latent schizophrenia'),('severe-mental-illness',1,'E1053',NULL,'Acute exacerbation of subchronic latent schizophrenia'),('severe-mental-illness',1,'E105300',NULL,'Acute exacerbation of subchronic latent schizophrenia'),('severe-mental-illness',1,'E106.',NULL,'Residual schizophrenia'),('severe-mental-illness',1,'E106.00',NULL,'Residual schizophrenia'),('severe-mental-illness',1,'E1410',NULL,'Active disintegrative psychoses'),('severe-mental-illness',1,'E141000',NULL,'Active disintegrative psychoses'),('severe-mental-illness',1,'E141z',NULL,'Disintegrative psychosis NOS'),('severe-mental-illness',1,'E141z00',NULL,'Disintegrative psychosis NOS'),('severe-mental-illness',1,'Eu205',NULL,'[X]Residual schizophrenia'),('severe-mental-illness',1,'Eu20500',NULL,'[X]Residual schizophrenia'),('severe-mental-illness',1,'Eu20y',NULL,'[X]Other schizophrenia'),('severe-mental-illness',1,'Eu20y00',NULL,'[X]Other schizophrenia'),('severe-mental-illness',1,'Eu231',NULL,'[X]Acute polymorphic psychotic disorder with symptoms of schizophrenia'),('severe-mental-illness',1,'Eu23100',NULL,'[X]Acute polymorphic psychotic disorder with symptoms of schizophrenia'),('severe-mental-illness',1,'Eu600',NULL,'[X]Paranoid personality disorder'),('severe-mental-illness',1,'Eu60000',NULL,'[X]Paranoid personality disorder'),('severe-mental-illness',1,'ZS7C6','11','Schizophrenic language'),('severe-mental-illness',1,'ZS7C6','11','Schizophrenic language'),('severe-mental-illness',1,'13Y2.',NULL,'Schizophrenia association member'),('severe-mental-illness',1,'13Y2.00',NULL,'Schizophrenia association member'),('severe-mental-illness',1,'1464.',NULL,'H/O: schizophrenia'),('severe-mental-illness',1,'1464.00',NULL,'H/O: schizophrenia'),('severe-mental-illness',1,'146H.',NULL,'H/O: psychosis'),('severe-mental-illness',1,'146H.00',NULL,'H/O: psychosis'),('severe-mental-illness',1,'1BH..',NULL,'Delusions'),('severe-mental-illness',1,'1BH..00',NULL,'Delusions'),('severe-mental-illness',1,'1BH0.',NULL,'Delusion of persecution'),('severe-mental-illness',1,'1BH0.00',NULL,'Delusion of persecution'),('severe-mental-illness',1,'1BH1.',NULL,'Grandiose delusions'),('severe-mental-illness',1,'1BH1.00',NULL,'Grandiose delusions'),('severe-mental-illness',1,'1BH2.',NULL,'Ideas of reference'),('severe-mental-illness',1,'1BH2.00',NULL,'Ideas of reference'),('severe-mental-illness',1,'1BH3.',NULL,'Paranoid ideation'),('severe-mental-illness',1,'1BH3.00',NULL,'Paranoid ideation'),('severe-mental-illness',1,'212W.',NULL,'Schizophrenia resolved'),('severe-mental-illness',1,'212W.00',NULL,'Schizophrenia resolved'),('severe-mental-illness',1,'212X.',NULL,'Psychosis resolved'),('severe-mental-illness',1,'212X.00',NULL,'Psychosis resolved'),('severe-mental-illness',1,'225E.',NULL,'O/E - paranoid delusions'),('severe-mental-illness',1,'225E.00',NULL,'O/E - paranoid delusions'),('severe-mental-illness',1,'225F.',NULL,'O/E - delusion of persecution'),('severe-mental-illness',1,'225F.00',NULL,'O/E - delusion of persecution'),('severe-mental-illness',1,'285..','11','Psychotic condition, insight present'),('severe-mental-illness',1,'285..','11','Psychotic condition, insight present'),('severe-mental-illness',1,'286..','11','Poor insight into psychotic condition'),('severe-mental-illness',1,'286..','11','Poor insight into psychotic condition'),('severe-mental-illness',1,'8G131',NULL,'CBTp - cognitive behavioural therapy for psychosis'),('severe-mental-illness',1,'8G13100',NULL,'CBTp - cognitive behavioural therapy for psychosis'),('severe-mental-illness',1,'8HHs.',NULL,'Referral for minor surgery'),('severe-mental-illness',1,'8HHs.00',NULL,'Referral for minor surgery'),('severe-mental-illness',1,'E03y3',NULL,'Unspecified puerperal psychosis'),('severe-mental-illness',1,'E03y300',NULL,'Unspecified puerperal psychosis'),('severe-mental-illness',1,'E040.',NULL,'Non-alcoholic amnestic syndrome'),('severe-mental-illness',1,'E040.00',NULL,'Non-alcoholic amnestic syndrome'),('severe-mental-illness',1,'E1...',NULL,'Non-organic psychoses'),('severe-mental-illness',1,'E1...00',NULL,'Non-organic psychoses'),('severe-mental-illness',1,'E10..',NULL,'Schizophrenic disorders'),('severe-mental-illness',1,'E10..00',NULL,'Schizophrenic disorders'),('severe-mental-illness',1,'E100.',NULL,'Simple schizophrenia'),('severe-mental-illness',1,'E100.00',NULL,'Simple schizophrenia'),('severe-mental-illness',1,'E1000',NULL,'Unspecified schizophrenia'),('severe-mental-illness',1,'E100000',NULL,'Unspecified schizophrenia'),('severe-mental-illness',1,'E1001',NULL,'Subchronic schizophrenia'),('severe-mental-illness',1,'E100100',NULL,'Subchronic schizophrenia'),('severe-mental-illness',1,'E1002',NULL,'Chronic schizophrenic'),('severe-mental-illness',1,'E100200',NULL,'Chronic schizophrenic'),('severe-mental-illness',1,'E1003',NULL,'Acute exacerbation of subchronic schizophrenia'),('severe-mental-illness',1,'E100300',NULL,'Acute exacerbation of subchronic schizophrenia'),('severe-mental-illness',1,'E1004',NULL,'Acute exacerbation of chronic schizophrenia'),('severe-mental-illness',1,'E100400',NULL,'Acute exacerbation of chronic schizophrenia'),('severe-mental-illness',1,'E1005',NULL,'Schizophrenia in remission'),('severe-mental-illness',1,'E100500',NULL,'Schizophrenia in remission'),('severe-mental-illness',1,'E100z',NULL,'Simple schizophrenia NOS'),('severe-mental-illness',1,'E100z00',NULL,'Simple schizophrenia NOS'),('severe-mental-illness',1,'E101.',NULL,'Hebephrenic schizophrenia'),('severe-mental-illness',1,'E101.00',NULL,'Hebephrenic schizophrenia'),('severe-mental-illness',1,'E1010',NULL,'Unspecified hebephrenic schizophrenia'),('severe-mental-illness',1,'E101000',NULL,'Unspecified hebephrenic schizophrenia'),('severe-mental-illness',1,'E1012',NULL,'Chronic hebephrenic schizophrenia'),('severe-mental-illness',1,'E101200',NULL,'Chronic hebephrenic schizophrenia'),('severe-mental-illness',1,'E1014',NULL,'Acute exacerbation of chronic hebephrenic schizophrenia'),('severe-mental-illness',1,'E101400',NULL,'Acute exacerbation of chronic hebephrenic schizophrenia'),('severe-mental-illness',1,'E1015',NULL,'Hebephrenic schizophrenia in remission'),('severe-mental-illness',1,'E101500',NULL,'Hebephrenic schizophrenia in remission'),('severe-mental-illness',1,'E101z',NULL,'Hebephrenic schizophrenia NOS'),('severe-mental-illness',1,'E101z00',NULL,'Hebephrenic schizophrenia NOS'),('severe-mental-illness',1,'E102.',NULL,'Catatonic schizophrenia'),('severe-mental-illness',1,'E102.00',NULL,'Catatonic schizophrenia'),('severe-mental-illness',1,'E1020',NULL,'Unspecified catatonic schizophrenia'),('severe-mental-illness',1,'E102000',NULL,'Unspecified catatonic schizophrenia'),('severe-mental-illness',1,'E1021',NULL,'Subchronic catatonic schizophrenia'),('severe-mental-illness',1,'E102100',NULL,'Subchronic catatonic schizophrenia'),('severe-mental-illness',1,'E1022',NULL,'Chronic catatonic schizophrenia'),('severe-mental-illness',1,'E102200',NULL,'Chronic catatonic schizophrenia'),('severe-mental-illness',1,'E1024',NULL,'Acute exacerbation of chronic catatonic schizophrenia'),('severe-mental-illness',1,'E102400',NULL,'Acute exacerbation of chronic catatonic schizophrenia'),('severe-mental-illness',1,'E1025',NULL,'Catatonic schizophrenia in remission'),('severe-mental-illness',1,'E102500',NULL,'Catatonic schizophrenia in remission'),('severe-mental-illness',1,'E102z',NULL,'Catatonic schizophrenia NOS'),('severe-mental-illness',1,'E102z00',NULL,'Catatonic schizophrenia NOS'),('severe-mental-illness',1,'E103.',NULL,'Paranoid schizophrenia'),('severe-mental-illness',1,'E103.00',NULL,'Paranoid schizophrenia'),('severe-mental-illness',1,'E1030',NULL,'Unspecified paranoid schizophrenia'),('severe-mental-illness',1,'E103000',NULL,'Unspecified paranoid schizophrenia'),('severe-mental-illness',1,'E1031',NULL,'Subchronic paranoid schizophrenia'),('severe-mental-illness',1,'E103100',NULL,'Subchronic paranoid schizophrenia'),('severe-mental-illness',1,'E1032',NULL,'Chronic paranoid schizophrenia'),('severe-mental-illness',1,'E103200',NULL,'Chronic paranoid schizophrenia'),('severe-mental-illness',1,'E1033',NULL,'Acute exacerbation of subchronic paranoid schizophrenia'),('severe-mental-illness',1,'E103300',NULL,'Acute exacerbation of subchronic paranoid schizophrenia'),('severe-mental-illness',1,'E1034',NULL,'Acute exacerbation of chronic paranoid schizophrenia'),('severe-mental-illness',1,'E103400',NULL,'Acute exacerbation of chronic paranoid schizophrenia'),('severe-mental-illness',1,'E1035',NULL,'Paranoid schizophrenia in remission'),('severe-mental-illness',1,'E103500',NULL,'Paranoid schizophrenia in remission'),('severe-mental-illness',1,'E103z',NULL,'Paranoid schizophrenia NOS'),('severe-mental-illness',1,'E103z00',NULL,'Paranoid schizophrenia NOS'),('severe-mental-illness',1,'E104.',NULL,'Acute schizophrenic episode'),('severe-mental-illness',1,'E104.00',NULL,'Acute schizophrenic episode'),('severe-mental-illness',1,'E105.',NULL,'Latent schizophrenia'),('severe-mental-illness',1,'E105.00',NULL,'Latent schizophrenia'),('severe-mental-illness',1,'E1050',NULL,'Unspecified latent schizophrenia'),('severe-mental-illness',1,'E105000',NULL,'Unspecified latent schizophrenia'),('severe-mental-illness',1,'E1052',NULL,'Chronic latent schizophrenia'),('severe-mental-illness',1,'E105200',NULL,'Chronic latent schizophrenia'),('severe-mental-illness',1,'E1054',NULL,'Acute exacerbation of chronic latent schizophrenia'),('severe-mental-illness',1,'E105400',NULL,'Acute exacerbation of chronic latent schizophrenia'),('severe-mental-illness',1,'E1055',NULL,'Latent schizophrenia in remission'),('severe-mental-illness',1,'E105500',NULL,'Latent schizophrenia in remission'),
('severe-mental-illness',1,'E105z',NULL,'Latent schizophrenia NOS'),('severe-mental-illness',1,'E105z00',NULL,'Latent schizophrenia NOS'),('severe-mental-illness',1,'E107.',NULL,'Schizo-affective schizophrenia'),('severe-mental-illness',1,'E107.00',NULL,'Schizo-affective schizophrenia'),('severe-mental-illness',1,'E1070',NULL,'Unspecified schizo-affective schizophrenia'),('severe-mental-illness',1,'E107000',NULL,'Unspecified schizo-affective schizophrenia'),('severe-mental-illness',1,'E1071',NULL,'Subchronic schizo-affective schizophrenia'),('severe-mental-illness',1,'E107100',NULL,'Subchronic schizo-affective schizophrenia'),('severe-mental-illness',1,'E1072',NULL,'Chronic schizo-affective schizophrenia'),('severe-mental-illness',1,'E107200',NULL,'Chronic schizo-affective schizophrenia'),('severe-mental-illness',1,'E1073',NULL,'Acute exacerbation of subchronic schizo-affective schizophrenia'),('severe-mental-illness',1,'E107300',NULL,'Acute exacerbation of subchronic schizo-affective schizophrenia'),('severe-mental-illness',1,'E1074',NULL,'Acute exacerbation of chronic schizo-affective schizophrenia'),('severe-mental-illness',1,'E107400',NULL,'Acute exacerbation of chronic schizo-affective schizophrenia'),('severe-mental-illness',1,'E1075',NULL,'Schizo-affective schizophrenia in remission'),('severe-mental-illness',1,'E107500',NULL,'Schizo-affective schizophrenia in remission'),('severe-mental-illness',1,'E107z',NULL,'Schizo-affective schizophrenia NOS'),('severe-mental-illness',1,'E107z00',NULL,'Schizo-affective schizophrenia NOS'),('severe-mental-illness',1,'E10y.',NULL,'Other schizophrenia'),('severe-mental-illness',1,'E10y.00',NULL,'Other schizophrenia'),('severe-mental-illness',1,'E10y0',NULL,'Atypical schizophrenia'),('severe-mental-illness',1,'E10y000',NULL,'Atypical schizophrenia'),('severe-mental-illness',1,'E10y1',NULL,'Coenesthopathic schizophrenia'),('severe-mental-illness',1,'E10y100',NULL,'Coenesthopathic schizophrenia'),('severe-mental-illness',1,'E10yz',NULL,'Other schizophrenia NOS'),('severe-mental-illness',1,'E10yz00',NULL,'Other schizophrenia NOS'),('severe-mental-illness',1,'E10z.',NULL,'Schizophrenia NOS'),('severe-mental-illness',1,'E10z.00',NULL,'Schizophrenia NOS'),('severe-mental-illness',1,'E12..',NULL,'Paranoid states'),('severe-mental-illness',1,'E12..00',NULL,'Paranoid states'),('severe-mental-illness',1,'E120.',NULL,'Simple paranoid state'),('severe-mental-illness',1,'E120.00',NULL,'Simple paranoid state'),('severe-mental-illness',1,'E121.',NULL,'Chronic paranoid psychosis'),('severe-mental-illness',1,'E121.00',NULL,'Chronic paranoid psychosis'),('severe-mental-illness',1,'E122.',NULL,'Paraphrenia'),('severe-mental-illness',1,'E122.00',NULL,'Paraphrenia'),('severe-mental-illness',1,'E123.',NULL,'Shared paranoid disorder'),('severe-mental-illness',1,'E123.00',NULL,'Shared paranoid disorder'),('severe-mental-illness',1,'E12y.',NULL,'Other paranoid states'),('severe-mental-illness',1,'E12y.00',NULL,'Other paranoid states'),('severe-mental-illness',1,'E12y0',NULL,'Paranoia querulans'),('severe-mental-illness',1,'E12y000',NULL,'Paranoia querulans'),('severe-mental-illness',1,'E12yz',NULL,'Other paranoid states NOS'),('severe-mental-illness',1,'E12yz00',NULL,'Other paranoid states NOS'),('severe-mental-illness',1,'E12z.',NULL,'Paranoid psychosis NOS'),('severe-mental-illness',1,'E12z.00',NULL,'Paranoid psychosis NOS'),('severe-mental-illness',1,'E13..',NULL,'Other nonorganic psychoses'),('severe-mental-illness',1,'E13..00',NULL,'Other nonorganic psychoses'),('severe-mental-illness',1,'E131.',NULL,'Acute hysterical psychosis'),('severe-mental-illness',1,'E131.00',NULL,'Acute hysterical psychosis'),('severe-mental-illness',1,'E132.',NULL,'Reactive confusion'),('severe-mental-illness',1,'E132.00',NULL,'Reactive confusion'),('severe-mental-illness',1,'E133.',NULL,'Acute paranoid reaction'),('severe-mental-illness',1,'E133.00',NULL,'Acute paranoid reaction'),('severe-mental-illness',1,'E134.',NULL,'Psychogenic paranoid psychosis'),('severe-mental-illness',1,'E134.00',NULL,'Psychogenic paranoid psychosis'),('severe-mental-illness',1,'E13y.',NULL,'Other reactive psychoses'),('severe-mental-illness',1,'E13y.00',NULL,'Other reactive psychoses'),('severe-mental-illness',1,'E13y0',NULL,'Psychogenic stupor'),('severe-mental-illness',1,'E13y000',NULL,'Psychogenic stupor'),('severe-mental-illness',1,'E13y1',NULL,'Brief reactive psychosis'),('severe-mental-illness',1,'E13y100',NULL,'Brief reactive psychosis'),('severe-mental-illness',1,'E13yz',NULL,'Other reactive psychoses NOS'),('severe-mental-illness',1,'E13yz00',NULL,'Other reactive psychoses NOS'),('severe-mental-illness',1,'E13z.',NULL,'Nonorganic psychosis NOS'),('severe-mental-illness',1,'E13z.00',NULL,'Nonorganic psychosis NOS'),('severe-mental-illness',1,'E14..',NULL,'Psychoses with origin in childhood'),('severe-mental-illness',1,'E14..00',NULL,'Psychoses with origin in childhood'),('severe-mental-illness',1,'E141.',NULL,'Disintegrative psychosis'),('severe-mental-illness',1,'E141.00',NULL,'Disintegrative psychosis'),('severe-mental-illness',1,'E1411',NULL,'Residual disintegrative psychoses'),('severe-mental-illness',1,'E141100',NULL,'Residual disintegrative psychoses'),('severe-mental-illness',1,'E14y.',NULL,'Other childhood psychoses'),('severe-mental-illness',1,'E14y.00',NULL,'Other childhood psychoses'),('severe-mental-illness',1,'E14y0',NULL,'Atypical childhood psychoses'),('severe-mental-illness',1,'E14y000',NULL,'Atypical childhood psychoses'),('severe-mental-illness',1,'E14y1',NULL,'Borderline psychosis of childhood'),('severe-mental-illness',1,'E14y100',NULL,'Borderline psychosis of childhood'),('severe-mental-illness',1,'E14yz',NULL,'Other childhood psychoses NOS'),('severe-mental-illness',1,'E14yz00',NULL,'Other childhood psychoses NOS'),('severe-mental-illness',1,'E14z.',NULL,'Child psychosis NOS'),('severe-mental-illness',1,'E14z.00',NULL,'Child psychosis NOS'),('severe-mental-illness',1,'E1y..',NULL,'Other specified non-organic psychoses'),('severe-mental-illness',1,'E1y..00',NULL,'Other specified non-organic psychoses'),('severe-mental-illness',1,'E1z..',NULL,'Non-organic psychosis NOS'),('severe-mental-illness',1,'E1z..00',NULL,'Non-organic psychosis NOS'),('severe-mental-illness',1,'E210.',NULL,'Paranoid personality disorder'),('severe-mental-illness',1,'E210.00',NULL,'Paranoid personality disorder'),('severe-mental-illness',1,'E212.',NULL,'Schizoid personality disorder'),('severe-mental-illness',1,'E212.00',NULL,'Schizoid personality disorder'),('severe-mental-illness',1,'E2120',NULL,'Unspecified schizoid personality disorder'),('severe-mental-illness',1,'E212000',NULL,'Unspecified schizoid personality disorder'),('severe-mental-illness',1,'E2122',NULL,'Schizotypal personality'),('severe-mental-illness',1,'E212200',NULL,'Schizotypal personality'),('severe-mental-illness',1,'E212z',NULL,'Schizoid personality disorder NOS'),('severe-mental-illness',1,'E212z00',NULL,'Schizoid personality disorder NOS'),('severe-mental-illness',1,'Eu03.','11','[X]Korsakovs psychosis, nonalcoholic'),('severe-mental-illness',1,'Eu03.','11','[X]Korsakovs psychosis, nonalcoholic'),('severe-mental-illness',1,'Eu04.',NULL,'[X]Delirium, not induced by alcohol and other psychoactive subs'),('severe-mental-illness',1,'Eu04.00',NULL,'[X]Delirium, not induced by alcohol and other psychoactive subs'),('severe-mental-illness',1,'Eu052','12','[X]Schizophrenia-like psychosis in epilepsy'),('severe-mental-illness',1,'Eu052','12','[X]Schizophrenia-like psychosis in epilepsy'),('severe-mental-illness',1,'Eu05y','11','[X]Epileptic psychosis NOS'),('severe-mental-illness',1,'Eu05y','11','[X]Epileptic psychosis NOS'),('severe-mental-illness',1,'Eu0z.','12','[X]Symptomatic psychosis NOS'),('severe-mental-illness',1,'Eu0z.','12','[X]Symptomatic psychosis NOS'),('severe-mental-illness',1,'Eu2..',NULL,'[X]Schizophrenia, schizotypal and delusional disorders'),('severe-mental-illness',1,'Eu2..00',NULL,'[X]Schizophrenia, schizotypal and delusional disorders'),('severe-mental-illness',1,'Eu20.',NULL,'[X]Schizophrenia'),('severe-mental-illness',1,'Eu20.00',NULL,'[X]Schizophrenia'),('severe-mental-illness',1,'Eu200',NULL,'[X]Paranoid schizophrenia'),('severe-mental-illness',1,'Eu20000',NULL,'[X]Paranoid schizophrenia'),('severe-mental-illness',1,'Eu201',NULL,'[X]Hebephrenic schizophrenia'),('severe-mental-illness',1,'Eu20100',NULL,'[X]Hebephrenic schizophrenia'),('severe-mental-illness',1,'Eu202',NULL,'[X]Catatonic schizophrenia'),('severe-mental-illness',1,'Eu20200',NULL,'[X]Catatonic schizophrenia'),('severe-mental-illness',1,'Eu203',NULL,'[X]Undifferentiated schizophrenia'),('severe-mental-illness',1,'Eu20300',NULL,'[X]Undifferentiated schizophrenia'),('severe-mental-illness',1,'Eu204',NULL,'[X]Post-schizophrenic depression'),('severe-mental-illness',1,'Eu20400',NULL,'[X]Post-schizophrenic depression'),('severe-mental-illness',1,'Eu206',NULL,'[X]Simple schizophrenia'),('severe-mental-illness',1,'Eu20600',NULL,'[X]Simple schizophrenia'),('severe-mental-illness',1,'Eu20z',NULL,'[X]Schizophrenia, unspecified'),('severe-mental-illness',1,'Eu20z00',NULL,'[X]Schizophrenia, unspecified'),('severe-mental-illness',1,'Eu21.',NULL,'[X]Schizotypal disorder'),('severe-mental-illness',1,'Eu21.00',NULL,'[X]Schizotypal disorder'),('severe-mental-illness',1,'Eu22.',NULL,'[X]Persistent delusional disorders'),('severe-mental-illness',1,'Eu22.00',NULL,'[X]Persistent delusional disorders'),('severe-mental-illness',1,'Eu220',NULL,'[X]Delusional disorder'),('severe-mental-illness',1,'Eu22000',NULL,'[X]Delusional disorder'),('severe-mental-illness',1,'Eu221',NULL,'[X]Delusional misidentification syndrome'),('severe-mental-illness',1,'Eu22100',NULL,'[X]Delusional misidentification syndrome'),('severe-mental-illness',1,'Eu222',NULL,'[X]Cotard syndrome'),('severe-mental-illness',1,'Eu22200',NULL,'[X]Cotard syndrome'),
('severe-mental-illness',1,'Eu223',NULL,'[X]Paranoid state in remission'),('severe-mental-illness',1,'Eu22300',NULL,'[X]Paranoid state in remission'),('severe-mental-illness',1,'Eu22y',NULL,'[X]Other persistent delusional disorders'),('severe-mental-illness',1,'Eu22y00',NULL,'[X]Other persistent delusional disorders'),('severe-mental-illness',1,'Eu22z',NULL,'[X]Persistent delusional disorder, unspecified'),('severe-mental-illness',1,'Eu22z00',NULL,'[X]Persistent delusional disorder, unspecified'),('severe-mental-illness',1,'Eu230',NULL,'[X]Acute polymorphic psychotic disorder without symptoms of schizophrenia'),('severe-mental-illness',1,'Eu23000',NULL,'[X]Acute polymorphic psychotic disorder without symptoms of schizophrenia'),('severe-mental-illness',1,'Eu232',NULL,'[X]Acute schizophrenia-like psychotic disorder'),('severe-mental-illness',1,'Eu23200',NULL,'[X]Acute schizophrenia-like psychotic disorder'),('severe-mental-illness',1,'Eu233',NULL,'[X]Other acute predominantly delusional psychotic disorders'),('severe-mental-illness',1,'Eu23300',NULL,'[X]Other acute predominantly delusional psychotic disorders'),('severe-mental-illness',1,'Eu23z','11','[X]Brief reactive psychosis NOS'),('severe-mental-illness',1,'Eu23z','12','[X]Reactive psychosis'),('severe-mental-illness',1,'Eu23z','11','[X]Brief reactive psychosis NOS'),('severe-mental-illness',1,'Eu23z','12','[X]Reactive psychosis'),('severe-mental-illness',1,'Eu24.','11','[X]Folie a deux'),('severe-mental-illness',1,'Eu24.','11','[X]Folie a deux'),('severe-mental-illness',1,'Eu25.',NULL,'[X]Schizoaffective disorders'),('severe-mental-illness',1,'Eu25.00',NULL,'[X]Schizoaffective disorders'),('severe-mental-illness',1,'Eu250',NULL,'[X]Schizoaffective disorder, manic type'),('severe-mental-illness',1,'Eu25000',NULL,'[X]Schizoaffective disorder, manic type'),('severe-mental-illness',1,'Eu251',NULL,'[X]Schizoaffective disorder, depressive type'),('severe-mental-illness',1,'Eu25100',NULL,'[X]Schizoaffective disorder, depressive type'),('severe-mental-illness',1,'Eu252',NULL,'[X]Schizoaffective disorder, mixed type'),('severe-mental-illness',1,'Eu25200',NULL,'[X]Schizoaffective disorder, mixed type'),('severe-mental-illness',1,'Eu25y',NULL,'[X]Other schizoaffective disorders'),('severe-mental-illness',1,'Eu25y00',NULL,'[X]Other schizoaffective disorders'),('severe-mental-illness',1,'Eu25z',NULL,'[X]Schizoaffective disorder, unspecified'),('severe-mental-illness',1,'Eu25z00',NULL,'[X]Schizoaffective disorder, unspecified'),('severe-mental-illness',1,'Eu26.',NULL,'[X]Nonorganic psychosis in remission'),('severe-mental-illness',1,'Eu26.00',NULL,'[X]Nonorganic psychosis in remission'),('severe-mental-illness',1,'Eu2y.',NULL,'[X]Other nonorganic psychotic disorders'),('severe-mental-illness',1,'Eu2y.00',NULL,'[X]Other nonorganic psychotic disorders'),('severe-mental-illness',1,'Eu2z.',NULL,'[X]Unspecified nonorganic psychosis'),('severe-mental-illness',1,'Eu2z.00',NULL,'[X]Unspecified nonorganic psychosis'),('severe-mental-illness',1,'Eu44.','11','[X]Conversion hysteria'),('severe-mental-illness',1,'Eu44.','13','[X]Hysteria'),('severe-mental-illness',1,'Eu44.','14','[X]Hysterical psychosis'),('severe-mental-illness',1,'Eu44.','11','[X]Conversion hysteria'),('severe-mental-illness',1,'Eu44.','13','[X]Hysteria'),('severe-mental-illness',1,'Eu44.','14','[X]Hysterical psychosis'),('severe-mental-illness',1,'Eu531','11','[X]Puerperal psychosis NOS'),('severe-mental-illness',1,'Eu531','11','[X]Puerperal psychosis NOS'),('severe-mental-illness',1,'Eu601',NULL,'[X]Schizoid personality disorder'),('severe-mental-illness',1,'Eu60100',NULL,'[X]Schizoid personality disorder'),('severe-mental-illness',1,'Eu840','13','[X]Infantile psychosis'),('severe-mental-illness',1,'Eu840','13','[X]Infantile psychosis'),('severe-mental-illness',1,'Eu841','11','[X]Atypical childhood psychosis'),('severe-mental-illness',1,'Eu841','11','[X]Atypical childhood psychosis'),('severe-mental-illness',1,'Eu843','12','[X]Disintegrative psychosis'),('severe-mental-illness',1,'Eu843','13','[X]Hellers syndrome'),('severe-mental-illness',1,'Eu843','14','[X]Symbiotic psychosis'),('severe-mental-illness',1,'Eu843','12','[X]Disintegrative psychosis'),('severe-mental-illness',1,'Eu843','13','[X]Hellers syndrome'),('severe-mental-illness',1,'Eu843','14','[X]Symbiotic psychosis'),('severe-mental-illness',1,'Eu845','12','[X]Schizoid disorder of childhood'),('severe-mental-illness',1,'Eu845','12','[X]Schizoid disorder of childhood'),('severe-mental-illness',1,'ZV110',NULL,'[V]Personal history of schizophrenia'),('severe-mental-illness',1,'ZV11000',NULL,'[V]Personal history of schizophrenia'),('severe-mental-illness',1,'9H8..',NULL,'On severe mental illness register'),('severe-mental-illness',1,'9H8..00',NULL,'On severe mental illness register'),('severe-mental-illness',1,'E0...',NULL,'Organic psychotic conditions'),('severe-mental-illness',1,'E0...00',NULL,'Organic psychotic conditions'),('severe-mental-illness',1,'E00..',NULL,'Senile and presenile organic psychotic conditions'),('severe-mental-illness',1,'E00..00',NULL,'Senile and presenile organic psychotic conditions'),('severe-mental-illness',1,'E00y.',NULL,'Other senile and presenile organic psychoses'),('severe-mental-illness',1,'E00y.00',NULL,'Other senile and presenile organic psychoses'),('severe-mental-illness',1,'E00z.',NULL,'Senile or presenile psychoses NOS'),('severe-mental-illness',1,'E00z.00',NULL,'Senile or presenile psychoses NOS'),('severe-mental-illness',1,'E010.',NULL,'Delirium tremens'),('severe-mental-illness',1,'E010.00',NULL,'Delirium tremens'),('severe-mental-illness',1,'E011.',NULL,'Alcohol amnestic syndrome'),('severe-mental-illness',1,'E011.00',NULL,'Alcohol amnestic syndrome'),('severe-mental-illness',1,'E0110',NULL,'Korsakovs alcoholic psychosis'),('severe-mental-illness',1,'E011000',NULL,'Korsakovs alcoholic psychosis'),('severe-mental-illness',1,'E0111',NULL,'Korsakovs alcoholic psychosis with peripheral neuritis'),('severe-mental-illness',1,'E011100',NULL,'Korsakovs alcoholic psychosis with peripheral neuritis'),('severe-mental-illness',1,'E0112',NULL,'Wernicke-Korsakov syndrome'),('severe-mental-illness',1,'E011200',NULL,'Wernicke-Korsakov syndrome'),('severe-mental-illness',1,'E012.',NULL,'Alcoholic dementia NOS'),('severe-mental-illness',1,'E012.00',NULL,'Alcoholic dementia NOS'),('severe-mental-illness',1,'E02..',NULL,'Drug psychoses'),('severe-mental-illness',1,'E02..00',NULL,'Drug psychoses'),('severe-mental-illness',1,'E021.',NULL,'Drug-induced paranoia or hallucinatory states'),('severe-mental-illness',1,'E021.00',NULL,'Drug-induced paranoia or hallucinatory states'),('severe-mental-illness',1,'E0210',NULL,'Drug-induced paranoid state'),('severe-mental-illness',1,'E021000',NULL,'Drug-induced paranoid state'),('severe-mental-illness',1,'E0211',NULL,'Drug-induced hallucinosis'),('severe-mental-illness',1,'E021100',NULL,'Drug-induced hallucinosis'),('severe-mental-illness',1,'E021z',NULL,'Drug-induced paranoia or hallucinatory state NOS'),('severe-mental-illness',1,'E021z00',NULL,'Drug-induced paranoia or hallucinatory state NOS'),('severe-mental-illness',1,'E02y.',NULL,'Other drug psychoses'),('severe-mental-illness',1,'E02y.00',NULL,'Other drug psychoses'),('severe-mental-illness',1,'E02y0',NULL,'Drug-induced delirium'),('severe-mental-illness',1,'E02y000',NULL,'Drug-induced delirium'),('severe-mental-illness',1,'E02y3',NULL,'Drug-induced depressive state'),('severe-mental-illness',1,'E02y300',NULL,'Drug-induced depressive state'),('severe-mental-illness',1,'E02y4',NULL,'Drug-induced personality disorder'),('severe-mental-illness',1,'E02y400',NULL,'Drug-induced personality disorder'),('severe-mental-illness',1,'E02z.',NULL,'Drug psychosis NOS'),('severe-mental-illness',1,'E02z.00',NULL,'Drug psychosis NOS'),('severe-mental-illness',1,'E03..',NULL,'Transient organic psychoses'),('severe-mental-illness',1,'E03..00',NULL,'Transient organic psychoses'),('severe-mental-illness',1,'E03y.',NULL,'Other transient organic psychoses'),('severe-mental-illness',1,'E03y.00',NULL,'Other transient organic psychoses'),('severe-mental-illness',1,'E03z.',NULL,'Transient organic psychoses NOS'),('severe-mental-illness',1,'E03z.00',NULL,'Transient organic psychoses NOS'),('severe-mental-illness',1,'E04..',NULL,'Other chronic organic psychoses'),('severe-mental-illness',1,'E04..00',NULL,'Other chronic organic psychoses'),('severe-mental-illness',1,'E04y.',NULL,'Other specified chronic organic psychoses'),('severe-mental-illness',1,'E04y.00',NULL,'Other specified chronic organic psychoses'),('severe-mental-illness',1,'E04z.',NULL,'Chronic organic psychosis NOS'),('severe-mental-illness',1,'E04z.00',NULL,'Chronic organic psychosis NOS'),('severe-mental-illness',1,'E0y..',NULL,'Other specified organic psychoses'),('severe-mental-illness',1,'E0y..00',NULL,'Other specified organic psychoses'),('severe-mental-illness',1,'E0z..',NULL,'Organic psychoses NOS'),('severe-mental-illness',1,'E0z..00',NULL,'Organic psychoses NOS'),('severe-mental-illness',1,'E1124',NULL,'Single major depressive episode, severe, with psychosis'),('severe-mental-illness',1,'E112400',NULL,'Single major depressive episode, severe, with psychosis'),('severe-mental-illness',1,'E1134',NULL,'Recurrent major depressive episodes, severe, with psychosis'),('severe-mental-illness',1,'E113400',NULL,'Recurrent major depressive episodes, severe, with psychosis'),('severe-mental-illness',1,'E211.',NULL,'Affective personality disorder'),('severe-mental-illness',1,'E211.00',NULL,'Affective personality disorder'),('severe-mental-illness',1,'E2110',NULL,'Unspecified affective personality disorder'),('severe-mental-illness',1,'E211000',NULL,'Unspecified affective personality disorder'),('severe-mental-illness',1,'E2113',NULL,'Cyclothymic personality disorder'),('severe-mental-illness',1,'E211300',NULL,'Cyclothymic personality disorder'),
('severe-mental-illness',1,'E211z',NULL,'Affective personality disorder NOS'),('severe-mental-illness',1,'E211z00',NULL,'Affective personality disorder NOS'),('severe-mental-illness',1,'Eu02z',NULL,'[X] Presenile dementia NOS'),('severe-mental-illness',1,'Eu02z00',NULL,'[X] Presenile dementia NOS'),('severe-mental-illness',1,'Eu104',NULL,'[X]Mental and behavioural disorders due to use of alcohol: withdrawal state with delirium'),('severe-mental-illness',1,'Eu10400',NULL,'[X]Mental and behavioural disorders due to use of alcohol: withdrawal state with delirium'),('severe-mental-illness',1,'Eu106',NULL,'[X]Korsakovs psychosis, alcohol induced'),('severe-mental-illness',1,'Eu10600',NULL,'[X]Korsakovs psychosis, alcohol induced'),('severe-mental-illness',1,'Eu107',NULL,'[X]Mental and behavioural disorders due to use of alcohol: residual and late-onset psychotic disorder'),('severe-mental-illness',1,'Eu10700',NULL,'[X]Mental and behavioural disorders due to use of alcohol: residual and late-onset psychotic disorder'),('severe-mental-illness',1,'Eu115',NULL,'[X]Mental and behavioural disorders due to use of opioids: psychotic disorder'),('severe-mental-illness',1,'Eu11500',NULL,'[X]Mental and behavioural disorders due to use of opioids: psychotic disorder'),('severe-mental-illness',1,'Eu125',NULL,'[X]Mental and behavioural disorders due to use of cannabinoids: psychotic disorder'),('severe-mental-illness',1,'Eu12500',NULL,'[X]Mental and behavioural disorders due to use of cannabinoids: psychotic disorder'),('severe-mental-illness',1,'Eu135',NULL,'[X]Mental and behavioural disorders due to use of sedatives or hypnotics: psychotic disorder'),('severe-mental-illness',1,'Eu13500',NULL,'[X]Mental and behavioural disorders due to use of sedatives or hypnotics: psychotic disorder'),('severe-mental-illness',1,'Eu145',NULL,'[X]Mental and behavioural disorders due to use of cocaine: psychotic disorder'),('severe-mental-illness',1,'Eu14500',NULL,'[X]Mental and behavioural disorders due to use of cocaine: psychotic disorder'),('severe-mental-illness',1,'Eu155',NULL,'[X]Mental and behavioural disorders due to use of other stimulants, including caffeine: psychotic disorder'),('severe-mental-illness',1,'Eu15500',NULL,'[X]Mental and behavioural disorders due to use of other stimulants, including caffeine: psychotic disorder'),('severe-mental-illness',1,'Eu195',NULL,'[X]Mental and behavioural disorders due to multiple drug use and use of other psychoactive substances: psychotic disorder'),('severe-mental-illness',1,'Eu19500',NULL,'[X]Mental and behavioural disorders due to multiple drug use and use of other psychoactive substances: psychotic disorder'),('severe-mental-illness',1,'Eu23.',NULL,'[X]Acute and transient psychotic disorders'),('severe-mental-illness',1,'Eu23.00',NULL,'[X]Acute and transient psychotic disorders'),('severe-mental-illness',1,'Eu323',NULL,'[X]Severe depressive episode with psychotic symptoms'),('severe-mental-illness',1,'Eu32300',NULL,'[X]Severe depressive episode with psychotic symptoms');
INSERT INTO #codesreadv2
VALUES ('flu-vaccine',1,'n47..',NULL,'INFLUENZA VACCINES'),('flu-vaccine',1,'n47..00',NULL,'INFLUENZA VACCINES'),('flu-vaccine',1,'n471.',NULL,'FLUVIRIN prefilled syringe 0.5mL'),('flu-vaccine',1,'n471.00',NULL,'FLUVIRIN prefilled syringe 0.5mL'),('flu-vaccine',1,'n472.',NULL,'INFLUVAC SUB-UNIT prefilled syringe 0.5mL'),('flu-vaccine',1,'n472.00',NULL,'INFLUVAC SUB-UNIT prefilled syringe 0.5mL'),('flu-vaccine',1,'n473.',NULL,'INFLUVAC SUB-UNIT prefilled syringe 0.5mL'),('flu-vaccine',1,'n473.00',NULL,'INFLUVAC SUB-UNIT prefilled syringe 0.5mL'),('flu-vaccine',1,'n474.',NULL,'*INFLUVAC SUB-UNIT vials 5mL'),('flu-vaccine',1,'n474.00',NULL,'*INFLUVAC SUB-UNIT vials 5mL'),('flu-vaccine',1,'n475.',NULL,'*INFLUVAC SUB-UNIT vials 25mL'),('flu-vaccine',1,'n475.00',NULL,'*INFLUVAC SUB-UNIT vials 25mL'),('flu-vaccine',1,'n476.',NULL,'MFV-JECT prefilled syringe 0.5mL'),('flu-vaccine',1,'n476.00',NULL,'MFV-JECT prefilled syringe 0.5mL'),('flu-vaccine',1,'n477.',NULL,'INACTIVATED INFLUENZA VACCINE injection 0.5mL'),('flu-vaccine',1,'n477.00',NULL,'INACTIVATED INFLUENZA VACCINE injection 0.5mL'),('flu-vaccine',1,'n478.',NULL,'INACTIVATED INFLUENZA VACCINE prefilled syringe 0.5mL'),('flu-vaccine',1,'n478.00',NULL,'INACTIVATED INFLUENZA VACCINE prefilled syringe 0.5mL'),('flu-vaccine',1,'n479.',NULL,'*INFLUENZA VACCINE vials 5mL'),('flu-vaccine',1,'n479.00',NULL,'*INFLUENZA VACCINE vials 5mL'),('flu-vaccine',1,'n47A.',NULL,'PANDEMRIX INFLUENZA A VACCINE (H1N1v) 2009 injection'),('flu-vaccine',1,'n47A.00',NULL,'PANDEMRIX INFLUENZA A VACCINE (H1N1v) 2009 injection'),('flu-vaccine',1,'n47B.',NULL,'CELVAPAN INFLUENZA A VACCINE (H1N1v) 2009 injection'),('flu-vaccine',1,'n47B.00',NULL,'CELVAPAN INFLUENZA A VACCINE (H1N1v) 2009 injection'),('flu-vaccine',1,'n47C.',NULL,'PREFLUCEL suspension for injection prefilled syringe 0.5mL'),('flu-vaccine',1,'n47C.00',NULL,'PREFLUCEL suspension for injection prefilled syringe 0.5mL'),('flu-vaccine',1,'n47D.',NULL,'*FLUENZ nasal suspension 0.2mL'),('flu-vaccine',1,'n47D.00',NULL,'*FLUENZ nasal suspension 0.2mL'),('flu-vaccine',1,'n47E.',NULL,'INFLUENZA VACCINE (LIVE ATTENUATED) nasal suspension 0.2mL'),('flu-vaccine',1,'n47E.00',NULL,'INFLUENZA VACCINE (LIVE ATTENUATED) nasal suspension 0.2mL'),('flu-vaccine',1,'n47F.',NULL,'OPTAFLU suspension for injection prefilled syringe 0.5mL'),('flu-vaccine',1,'n47F.00',NULL,'OPTAFLU suspension for injection prefilled syringe 0.5mL'),('flu-vaccine',1,'n47G.',NULL,'INFLUVAC DESU suspension for injection prefill syringe 0.5mL'),('flu-vaccine',1,'n47G.00',NULL,'INFLUVAC DESU suspension for injection prefill syringe 0.5mL'),('flu-vaccine',1,'n47H.',NULL,'FLUARIX TETRA suspension for injection prefill syringe 0.5mL'),('flu-vaccine',1,'n47H.00',NULL,'FLUARIX TETRA suspension for injection prefill syringe 0.5mL'),('flu-vaccine',1,'n47I.',NULL,'FLUENZ TETRA nasal spray suspension 0.2mL'),('flu-vaccine',1,'n47I.00',NULL,'FLUENZ TETRA nasal spray suspension 0.2mL'),('flu-vaccine',1,'n47a.',NULL,'*INFLUENZA VACCINE vials 25mL'),('flu-vaccine',1,'n47a.00',NULL,'*INFLUENZA VACCINE vials 25mL'),('flu-vaccine',1,'n47b.',NULL,'FLUZONE prefilled syringe 0.5mL'),('flu-vaccine',1,'n47b.00',NULL,'FLUZONE prefilled syringe 0.5mL'),('flu-vaccine',1,'n47c.',NULL,'*FLUZONE vials 5mL'),('flu-vaccine',1,'n47c.00',NULL,'*FLUZONE vials 5mL'),('flu-vaccine',1,'n47d.',NULL,'FLUARIX VACCINE prefilled syringe'),('flu-vaccine',1,'n47d.00',NULL,'FLUARIX VACCINE prefilled syringe'),('flu-vaccine',1,'n47e.',NULL,'BEGRIVAC VACCINE prefilled syringe 0.5mL'),('flu-vaccine',1,'n47e.00',NULL,'BEGRIVAC VACCINE prefilled syringe 0.5mL'),('flu-vaccine',1,'n47f.',NULL,'AGRIPPAL VACCINE prefilled syringe 0.5mL'),('flu-vaccine',1,'n47f.00',NULL,'AGRIPPAL VACCINE prefilled syringe 0.5mL'),('flu-vaccine',1,'n47g.',NULL,'INACTIVATED INFLUENZA VACCINE (SPLIT VIRION) prefilled syringe 0.5mL'),('flu-vaccine',1,'n47g.00',NULL,'INACTIVATED INFLUENZA VACCINE (SPLIT VIRION) prefilled syringe 0.5mL'),('flu-vaccine',1,'n47h.',NULL,'INACTIVATED INFLUENZA VACCINE (SURFACE ANTIGEN SUB-UNIT) prefilled syringe 0.5mL'),('flu-vaccine',1,'n47h.00',NULL,'INACTIVATED INFLUENZA VACCINE (SURFACE ANTIGEN SUB-UNIT) prefilled syringe 0.5mL'),('flu-vaccine',1,'n47i.',NULL,'INFLEXAL BERNA V prefilled syringe 0.5mL'),('flu-vaccine',1,'n47i.00',NULL,'INFLEXAL BERNA V prefilled syringe 0.5mL'),('flu-vaccine',1,'n47j.',NULL,'MASTAFLU prefilled syringe 0.5mL'),('flu-vaccine',1,'n47j.00',NULL,'MASTAFLU prefilled syringe 0.5mL'),('flu-vaccine',1,'n47k.',NULL,'INFLEXAL V prefilled syringe 0.5mL'),('flu-vaccine',1,'n47k.00',NULL,'INFLEXAL V prefilled syringe 0.5mL'),('flu-vaccine',1,'n47l.',NULL,'INVIVAC prefilled syringe 0.5mL'),('flu-vaccine',1,'n47l.00',NULL,'INVIVAC prefilled syringe 0.5mL'),('flu-vaccine',1,'n47m.',NULL,'ENZIRA prefilled syringe 0.5mL'),('flu-vaccine',1,'n47m.00',NULL,'ENZIRA prefilled syringe 0.5mL'),('flu-vaccine',1,'n47n.',NULL,'VIROFLU prefilled syringe 0.5mL'),('flu-vaccine',1,'n47n.00',NULL,'VIROFLU prefilled syringe 0.5mL'),('flu-vaccine',1,'n47o.',NULL,'IMUVAC prefilled syringe 0.5mL'),('flu-vaccine',1,'n47o.00',NULL,'IMUVAC prefilled syringe 0.5mL'),('flu-vaccine',1,'n47p.',NULL,'INTANZA 15micrograms/strain susp for inj pfs 0.1mL'),('flu-vaccine',1,'n47p.00',NULL,'INTANZA 15micrograms/strain susp for inj pfs 0.1mL'),('flu-vaccine',1,'n47q.',NULL,'INACT INFLUENZA VACC (SPLIT VIRION) 15mcg/strain pfs 0.1mL'),('flu-vaccine',1,'n47q.00',NULL,'INACT INFLUENZA VACC (SPLIT VIRION) 15mcg/strain pfs 0.1mL'),('flu-vaccine',1,'n47r.',NULL,'CELVAPAN (H1N1) suspension for injection vials 5mL'),('flu-vaccine',1,'n47r.00',NULL,'CELVAPAN (H1N1) suspension for injection vials 5mL'),('flu-vaccine',1,'n47s.',NULL,'CELVAPAN (H5N1) suspension for injection vials 5mL'),('flu-vaccine',1,'n47s.00',NULL,'CELVAPAN (H5N1) suspension for injection vials 5mL'),('flu-vaccine',1,'n47t.',NULL,'PANDEMRIX (H5N1) injection vials'),('flu-vaccine',1,'n47t.00',NULL,'PANDEMRIX (H5N1) injection vials'),('flu-vaccine',1,'n47u.',NULL,'INTANZA 9micrograms/strain susp for inj pfs 0.1mL'),('flu-vaccine',1,'n47u.00',NULL,'INTANZA 9micrograms/strain susp for inj pfs 0.1mL'),('flu-vaccine',1,'n47v.',NULL,'INACT INFLUENZA VACC (SPLIT VIRION) 9mcg/strain pfs 0.1mL'),('flu-vaccine',1,'n47v.00',NULL,'INACT INFLUENZA VACC (SPLIT VIRION) 9mcg/strain pfs 0.1mL'),('flu-vaccine',1,'n47y.',NULL,'INACTIVATED INFLUENZA VACCINE (SPLIT VIRION) prefilled syringe 0.25mL'),('flu-vaccine',1,'n47y.00',NULL,'INACTIVATED INFLUENZA VACCINE (SPLIT VIRION) prefilled syringe 0.25mL'),('flu-vaccine',1,'n47z.',NULL,'INACTIVATED INFLUENZA VACCINE (SURFACE ANTIGEN VIROSOME) prefilled syringe 0.5mL'),('flu-vaccine',1,'n47z.00',NULL,'INACTIVATED INFLUENZA VACCINE (SURFACE ANTIGEN VIROSOME) prefilled syringe 0.5mL');
INSERT INTO #codesreadv2
VALUES ('covid-vaccine-declined',1,'8IAI.',NULL,'2019-nCoV (novel coronavirus) vaccination declined'),('covid-vaccine-declined',1,'8IAI.00',NULL,'2019-nCoV (novel coronavirus) vaccination declined'),('covid-vaccine-declined',1,'8IAI1',NULL,'SARS-CoV-2 immun course declin'),('covid-vaccine-declined',1,'8IAI100',NULL,'SARS-CoV-2 immun course declin'),('covid-vaccine-declined',1,'8IAI2',NULL,'SARS-CoV-2 vac first dose declined'),('covid-vaccine-declined',1,'8IAI200',NULL,'SARS-CoV-2 vac first dose declined'),('covid-vaccine-declined',1,'8IAI3',NULL,'SARS-CoV-2 vac second dose dec'),('covid-vaccine-declined',1,'8IAI300',NULL,'SARS-CoV-2 vac second dose dec');
INSERT INTO #codesreadv2
VALUES ('high-clinical-vulnerability',1,'14Or.',NULL,'High risk category for developing complications from COVID-19 severe acute respiratory syndrome coronavirus infection (finding)'),('high-clinical-vulnerability',1,'14Or.00',NULL,'High risk category for developing complications from COVID-19 severe acute respiratory syndrome coronavirus infection (finding)'),('high-clinical-vulnerability',1,'9d44.',NULL,'Risk of exposure to communicable disease (situation)'),('high-clinical-vulnerability',1,'9d44.00',NULL,'Risk of exposure to communicable disease (situation)');
INSERT INTO #codesreadv2
VALUES ('moderate-clinical-vulnerability',1,'14Oq.',NULL,'Moderate risk category for developing complications from COVID-19'),('moderate-clinical-vulnerability',1,'14Oq.00',NULL,'Moderate risk category for developing complications from COVID-19');
INSERT INTO #codesreadv2
VALUES ('covid-vaccination',1,'65F0.',NULL,'2019-nCoV (novel coronavirus) vaccination'),('covid-vaccination',1,'65F0.00',NULL,'2019-nCoV (novel coronavirus) vaccination'),('covid-vaccination',1,'65F01',NULL,'Administration of first dose of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccine'),('covid-vaccination',1,'65F0100',NULL,'Administration of first dose of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccine'),('covid-vaccination',1,'65F02',NULL,'2019-nCoV (novel coronavirus) vaccination'),('covid-vaccination',1,'65F0200',NULL,'2019-nCoV (novel coronavirus) vaccination'),('covid-vaccination',1,'65F06',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccination'),('covid-vaccination',1,'65F0600',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccination'),('covid-vaccination',1,'65F07',NULL,'Immunisation course to achieve immunity against SARS-CoV-2'),('covid-vaccination',1,'65F0700',NULL,'Immunisation course to achieve immunity against SARS-CoV-2'),('covid-vaccination',1,'65F08',NULL,'Immunisation course to maintain protection against SARS-CoV-2'),('covid-vaccination',1,'65F0800',NULL,'Immunisation course to maintain protection against SARS-CoV-2'),('covid-vaccination',1,'65F09',NULL,'Administration of third dose of SARS-CoV-2 vaccine'),('covid-vaccination',1,'65F0900',NULL,'Administration of third dose of SARS-CoV-2 vaccine'),('covid-vaccination',1,'65F0A',NULL,'Administration of fourth dose of SARS-CoV-2 vaccine'),('covid-vaccination',1,'65F0A00',NULL,'Administration of fourth dose of SARS-CoV-2 vaccine'),('covid-vaccination',1,'9bJ..',NULL,'COVID-19 mRNA Vaccine BNT162b2 30micrograms/0.3ml dose concentrate for suspension for injection multidose vials (Pfizer-BioNTech)'),('covid-vaccination',1,'9bJ..00',NULL,'COVID-19 mRNA Vaccine BNT162b2 30micrograms/0.3ml dose concentrate for suspension for injection multidose vials (Pfizer-BioNTech)');
INSERT INTO #codesreadv2
VALUES ('flu-vaccination',1,'65E..',NULL,'Influenza vaccination'),('flu-vaccination',1,'65E..00',NULL,'Influenza vaccination'),('flu-vaccination',1,'65E0.',NULL,'First pandemic influenza vaccination'),('flu-vaccination',1,'65E0.00',NULL,'First pandemic influenza vaccination'),('flu-vaccination',1,'65E00',NULL,'Administration of first intranasal pandemic influenza vaccination'),('flu-vaccination',1,'65E0000',NULL,'Administration of first intranasal pandemic influenza vaccination'),('flu-vaccination',1,'65E1.',NULL,'Second pandemic influenza vaccination'),('flu-vaccination',1,'65E1.00',NULL,'Second pandemic influenza vaccination'),('flu-vaccination',1,'65E10',NULL,'Administration of second intranasal pandemic influenza vaccination'),('flu-vaccination',1,'65E1000',NULL,'Administration of second intranasal pandemic influenza vaccination'),('flu-vaccination',1,'65E2.',NULL,'Influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'65E2.00',NULL,'Influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'65E20',NULL,'Seasonal influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'65E2000',NULL,'Seasonal influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'65E21',NULL,'First intranasal seasonal influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'65E2100',NULL,'First intranasal seasonal influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'65E22',NULL,'Second intranasal seasonal influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'65E2200',NULL,'Second intranasal seasonal influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'65E23',NULL,'Second intramuscular seasonal influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'65E2300',NULL,'Second intramuscular seasonal influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'65E24',NULL,'First intramuscular seasonal influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'65E2400',NULL,'First intramuscular seasonal influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'65E3.',NULL,'First pandemic influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'65E3.00',NULL,'First pandemic influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'65E30',NULL,'First intranasal pandemic influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'65E3000',NULL,'First intranasal pandemic influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'65E4.',NULL,'Second pandemic influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'65E4.00',NULL,'Second pandemic influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'65E40',NULL,'Second intranasal pandemic influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'65E4000',NULL,'Second intranasal pandemic influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'65E5.',NULL,'CELVAPAN - first influenza A (H1N1v) 2009 vaccination given'),('flu-vaccination',1,'65E5.00',NULL,'CELVAPAN - first influenza A (H1N1v) 2009 vaccination given'),('flu-vaccination',1,'65E6.',NULL,'CELVAPAN - second influenza A (H1N1v) 2009 vaccination given'),('flu-vaccination',1,'65E6.00',NULL,'CELVAPAN - second influenza A (H1N1v) 2009 vaccination given'),('flu-vaccination',1,'65E7.',NULL,'CELVAPAN - first influenza A (H1N1v) 2009 vaccination given by other healthcare provider'),('flu-vaccination',1,'65E7.00',NULL,'CELVAPAN - first influenza A (H1N1v) 2009 vaccination given by other healthcare provider'),('flu-vaccination',1,'65E8.',NULL,'CELVAPAN - second influenza A (H1N1v) 2009 vaccination given by other healthcare provider'),('flu-vaccination',1,'65E8.00',NULL,'CELVAPAN - second influenza A (H1N1v) 2009 vaccination given by other healthcare provider'),('flu-vaccination',1,'65E9.',NULL,'PANDEMRIX - first influenza A (H1N1v) 2009 vaccination given'),('flu-vaccination',1,'65E9.00',NULL,'PANDEMRIX - first influenza A (H1N1v) 2009 vaccination given'),('flu-vaccination',1,'65EA.',NULL,'PANDEMRIX - second influenza A (H1N1v) 2009 vaccination given'),('flu-vaccination',1,'65EA.00',NULL,'PANDEMRIX - second influenza A (H1N1v) 2009 vaccination given'),('flu-vaccination',1,'65EB.',NULL,'PANDEMRIX - first influenza A (H1N1v) 2009 vaccination given by other healthcare provider'),('flu-vaccination',1,'65EB.00',NULL,'PANDEMRIX - first influenza A (H1N1v) 2009 vaccination given by other healthcare provider'),('flu-vaccination',1,'65EC.',NULL,'PANDEMRIX - second influenza A (H1N1v) 2009 vaccination given by other healthcare provider'),('flu-vaccination',1,'65EC.00',NULL,'PANDEMRIX - second influenza A (H1N1v) 2009 vaccination given by other healthcare provider'),('flu-vaccination',1,'65ED.',NULL,'Seasonal influenza vaccination'),('flu-vaccination',1,'65ED.00',NULL,'Seasonal influenza vaccination'),('flu-vaccination',1,'65ED0',NULL,'Seasonal influenza vaccination given by pharmacist'),('flu-vaccination',1,'65ED000',NULL,'Seasonal influenza vaccination given by pharmacist'),('flu-vaccination',1,'65ED1',NULL,'Administration of first intranasal seasonal influenza vaccination'),('flu-vaccination',1,'65ED100',NULL,'Administration of first intranasal seasonal influenza vaccination'),('flu-vaccination',1,'65ED2',NULL,'Seasonal influenza vaccination given while hospital inpatient'),('flu-vaccination',1,'65ED200',NULL,'Seasonal influenza vaccination given while hospital inpatient'),('flu-vaccination',1,'65ED3',NULL,'Administration of second intranasal seasonal influenza vaccination'),('flu-vaccination',1,'65ED300',NULL,'Administration of second intranasal seasonal influenza vaccination'),('flu-vaccination',1,'65ED4',NULL,'Administration of first inactivated seasonal influenza vaccination'),('flu-vaccination',1,'65ED400',NULL,'Administration of first inactivated seasonal influenza vaccination'),('flu-vaccination',1,'65ED5',NULL,'Administration of second inactivated seasonal influenza vaccination'),('flu-vaccination',1,'65ED500',NULL,'Administration of second inactivated seasonal influenza vaccination'),('flu-vaccination',1,'65ED6',NULL,'First intranasal seasonal influenza vaccination given by pharmacist'),('flu-vaccination',1,'65ED600',NULL,'First intranasal seasonal influenza vaccination given by pharmacist'),('flu-vaccination',1,'65ED7',NULL,'Second intranasal seasonal influenza vaccination given by pharmacist'),('flu-vaccination',1,'65ED700',NULL,'Second intranasal seasonal influenza vaccination given by pharmacist'),('flu-vaccination',1,'65ED8',NULL,'First inactivated seasonal influenza vaccination given by pharmacist'),('flu-vaccination',1,'65ED800',NULL,'First inactivated seasonal influenza vaccination given by pharmacist'),('flu-vaccination',1,'65ED9',NULL,'Second inactivated seasonal influenza vaccination given by pharmacist'),('flu-vaccination',1,'65ED900',NULL,'Second inactivated seasonal influenza vaccination given by pharmacist'),('flu-vaccination',1,'65EE.',NULL,'Administration of intranasal influenza vaccination'),('flu-vaccination',1,'65EE.00',NULL,'Administration of intranasal influenza vaccination'),('flu-vaccination',1,'65EE0',NULL,'Administration of first intranasal influenza vaccination'),('flu-vaccination',1,'65EE000',NULL,'Administration of first intranasal influenza vaccination'),('flu-vaccination',1,'65EE1',NULL,'Administration of second intranasal influenza vaccination'),('flu-vaccination',1,'65EE100',NULL,'Administration of second intranasal influenza vaccination'),('flu-vaccination',1,'ZV048',NULL,'[V]Influenza vaccination'),('flu-vaccination',1,'ZV04800',NULL,'[V]Influenza vaccination');
INSERT INTO #codesreadv2
VALUES ('covid-positive-antigen-test',1,'43kB1',NULL,'SARS-CoV-2 antigen positive'),('covid-positive-antigen-test',1,'43kB100',NULL,'SARS-CoV-2 antigen positive');
INSERT INTO #codesreadv2
VALUES ('covid-positive-pcr-test',1,'4J3R6',NULL,'SARS-CoV-2 RNA pos lim detect'),('covid-positive-pcr-test',1,'4J3R600',NULL,'SARS-CoV-2 RNA pos lim detect'),('covid-positive-pcr-test',1,'A7952',NULL,'COVID-19 confirmed by laboratory test'),('covid-positive-pcr-test',1,'A795200',NULL,'COVID-19 confirmed by laboratory test'),('covid-positive-pcr-test',1,'43hF.',NULL,'Detection of SARS-CoV-2 by PCR'),('covid-positive-pcr-test',1,'43hF.00',NULL,'Detection of SARS-CoV-2 by PCR');
INSERT INTO #codesreadv2
VALUES ('covid-positive-test-other',1,'4J3R1',NULL,'2019-nCoV (novel coronavirus) detected'),('covid-positive-test-other',1,'4J3R100',NULL,'2019-nCoV (novel coronavirus) detected')

INSERT INTO #AllCodes
SELECT [concept], [version], [code], [description] from #codesreadv2;

IF OBJECT_ID('tempdb..#codesctv3') IS NOT NULL DROP TABLE #codesctv3;
CREATE TABLE #codesctv3 (
  [concept] [varchar](255) NOT NULL,
  [version] INT NOT NULL,
	[code] [varchar](20) COLLATE Latin1_General_CS_AS NOT NULL,
	[term] [varchar](20) COLLATE Latin1_General_CS_AS NULL,
	[description] [varchar](255) NULL
) ON [PRIMARY];

INSERT INTO #codesctv3
VALUES ('severe-mental-illness',1,'E1...',NULL,'Non-organic psychoses'),('severe-mental-illness',1,'E10..',NULL,'Schizophrenic disorders'),('severe-mental-illness',1,'E100.',NULL,'Simple schizophrenia'),('severe-mental-illness',1,'E1000',NULL,'Unspecified schizophrenia'),('severe-mental-illness',1,'E1001',NULL,'Subchronic schizophrenia'),('severe-mental-illness',1,'E1002',NULL,'Chronic schizophrenic'),('severe-mental-illness',1,'E1003',NULL,'Acute exacerbation of subchronic schizophrenia'),('severe-mental-illness',1,'E1004',NULL,'Acute exacerbation of chronic schizophrenia'),('severe-mental-illness',1,'E1005',NULL,'Schizophrenia in remission'),('severe-mental-illness',1,'E100z',NULL,'Simple schizophrenia NOS'),('severe-mental-illness',1,'E101.',NULL,'Hebephrenic schizophrenia'),('severe-mental-illness',1,'E1010',NULL,'Unspecified hebephrenic schizophrenia'),('severe-mental-illness',1,'E1011',NULL,'Subchronic hebephrenic schizophrenia'),('severe-mental-illness',1,'E1012',NULL,'Chronic hebephrenic schizophrenia'),('severe-mental-illness',1,'E1013',NULL,'Acute exacerbation of subchronic hebephrenic schizophrenia'),('severe-mental-illness',1,'E1014',NULL,'Acute exacerbation of chronic hebephrenic schizophrenia'),('severe-mental-illness',1,'E1015',NULL,'Hebephrenic schizophrenia in remission'),('severe-mental-illness',1,'E101z',NULL,'Hebephrenic schizophrenia NOS'),('severe-mental-illness',1,'E102.',NULL,'Catatonic schizophrenia'),('severe-mental-illness',1,'E1020',NULL,'Unspecified catatonic schizophrenia'),('severe-mental-illness',1,'E1021',NULL,'Subchronic catatonic schizophrenia'),('severe-mental-illness',1,'E1022',NULL,'Chronic catatonic schizophrenia'),('severe-mental-illness',1,'E1023',NULL,'Acute exacerbation of subchronic catatonic schizophrenia'),('severe-mental-illness',1,'E1024',NULL,'Acute exacerbation of chronic catatonic schizophrenia'),('severe-mental-illness',1,'E1025',NULL,'Catatonic schizophrenia in remission'),('severe-mental-illness',1,'E102z',NULL,'Catatonic schizophrenia NOS'),('severe-mental-illness',1,'E103.',NULL,'Paranoid schizophrenia'),('severe-mental-illness',1,'E1030',NULL,'Unspecified paranoid schizophrenia'),('severe-mental-illness',1,'E1031',NULL,'Subchronic paranoid schizophrenia'),('severe-mental-illness',1,'E1032',NULL,'Chronic paranoid schizophrenia'),('severe-mental-illness',1,'E1033',NULL,'Acute exacerbation of subchronic paranoid schizophrenia'),('severe-mental-illness',1,'E1034',NULL,'Acute exacerbation of chronic paranoid schizophrenia'),('severe-mental-illness',1,'E1035',NULL,'Paranoid schizophrenia in remission'),('severe-mental-illness',1,'E103z',NULL,'Paranoid schizophrenia NOS'),('severe-mental-illness',1,'E105.',NULL,'Latent schizophrenia'),('severe-mental-illness',1,'E1050',NULL,'Unspecified latent schizophrenia'),('severe-mental-illness',1,'E1051',NULL,'Subchronic latent schizophrenia'),('severe-mental-illness',1,'E1052',NULL,'Chronic latent schizophrenia'),('severe-mental-illness',1,'E1053',NULL,'Acute exacerbation of subchronic latent schizophrenia'),('severe-mental-illness',1,'E1054',NULL,'Acute exacerbation of chronic latent schizophrenia'),('severe-mental-illness',1,'E1055',NULL,'Latent schizophrenia in remission'),('severe-mental-illness',1,'E105z',NULL,'Latent schizophrenia NOS'),('severe-mental-illness',1,'E106.',NULL,'Residual schizophrenia'),('severe-mental-illness',1,'E107.',NULL,'Schizoaffective schizophrenia'),('severe-mental-illness',1,'E1070',NULL,'Unspecified schizoaffective schizophrenia'),('severe-mental-illness',1,'E1071',NULL,'Subchronic schizoaffective schizophrenia'),('severe-mental-illness',1,'E1072',NULL,'Chronic schizoaffective schizophrenia'),('severe-mental-illness',1,'E1073',NULL,'Acute exacerbation subchronic schizoaffective schizophrenia'),('severe-mental-illness',1,'E1074',NULL,'Acute exacerbation of chronic schizoaffective schizophrenia'),('severe-mental-illness',1,'E1075',NULL,'Schizoaffective schizophrenia in remission'),('severe-mental-illness',1,'E107z',NULL,'Schizoaffective schizophrenia NOS'),('severe-mental-illness',1,'E10y.',NULL,'Schizophrenia: [other] or [cenesthopathic]'),('severe-mental-illness',1,'E10y0',NULL,'Atypical schizophrenia'),('severe-mental-illness',1,'E10y1',NULL,'Cenesthopathic schizophrenia'),('severe-mental-illness',1,'E10yz',NULL,'Other schizophrenia NOS'),('severe-mental-illness',1,'E10z.',NULL,'Schizophrenia NOS'),('severe-mental-illness',1,'E1100',NULL,'Single manic episode, unspecified'),('severe-mental-illness',1,'E1101',NULL,'Single manic episode, mild'),('severe-mental-illness',1,'E1102',NULL,'Single manic episode, moderate'),('severe-mental-illness',1,'E1103',NULL,'Single manic episode, severe without mention of psychosis'),('severe-mental-illness',1,'E1104',NULL,'Single manic episode, severe, with psychosis'),('severe-mental-illness',1,'E1105',NULL,'Single manic episode in partial or unspecified remission'),('severe-mental-illness',1,'E1106',NULL,'Single manic episode in full remission'),('severe-mental-illness',1,'E110z',NULL,'Manic disorder, single episode NOS'),('severe-mental-illness',1,'E111.',NULL,'Recurrent manic episodes'),('severe-mental-illness',1,'E1110',NULL,'Recurrent manic episodes, unspecified'),('severe-mental-illness',1,'E1111',NULL,'Recurrent manic episodes, mild'),('severe-mental-illness',1,'E1112',NULL,'Recurrent manic episodes, moderate'),('severe-mental-illness',1,'E1113',NULL,'Recurrent manic episodes, severe without mention psychosis'),('severe-mental-illness',1,'E1114',NULL,'Recurrent manic episodes, severe, with psychosis'),('severe-mental-illness',1,'E1115',NULL,'Recurrent manic episodes, partial or unspecified remission'),('severe-mental-illness',1,'E1116',NULL,'Recurrent manic episodes, in full remission'),('severe-mental-illness',1,'E111z',NULL,'Recurrent manic episode NOS'),('severe-mental-illness',1,'E1124',NULL,'Single major depressive episode, severe, with psychosis'),('severe-mental-illness',1,'E1134',NULL,'Recurrent major depressive episodes, severe, with psychosis'),('severe-mental-illness',1,'E114.',NULL,'Bipolar affective disorder, current episode manic'),('severe-mental-illness',1,'E1140',NULL,'Bipolar affective disorder, currently manic, unspecified'),('severe-mental-illness',1,'E1141',NULL,'Bipolar affective disorder, currently manic, mild'),('severe-mental-illness',1,'E1142',NULL,'Bipolar affective disorder, currently manic, moderate'),('severe-mental-illness',1,'E1143',NULL,'Bipolar affect disord, currently manic, severe, no psychosis'),('severe-mental-illness',1,'E1144',NULL,'Bipolar affect disord, currently manic,severe with psychosis'),('severe-mental-illness',1,'E1145',NULL,'Bipolar affect disord,currently manic, part/unspec remission'),('severe-mental-illness',1,'E1146',NULL,'Bipolar affective disorder, currently manic, full remission'),('severe-mental-illness',1,'E114z',NULL,'Bipolar affective disorder, currently manic, NOS'),('severe-mental-illness',1,'E115.',NULL,'Bipolar affective disorder, current episode depression'),('severe-mental-illness',1,'E1150',NULL,'Bipolar affective disorder, currently depressed, unspecified'),('severe-mental-illness',1,'E1151',NULL,'Bipolar affective disorder, currently depressed, mild'),('severe-mental-illness',1,'E1152',NULL,'Bipolar affective disorder, currently depressed, moderate'),('severe-mental-illness',1,'E1153',NULL,'Bipolar affect disord, now depressed, severe, no psychosis'),('severe-mental-illness',1,'E1154',NULL,'Bipolar affect disord, now depressed, severe with psychosis'),('severe-mental-illness',1,'E1156',NULL,'Bipolar affective disorder, now depressed, in full remission'),('severe-mental-illness',1,'E115z',NULL,'Bipolar affective disorder, currently depressed, NOS'),('severe-mental-illness',1,'E116.',NULL,'Mixed bipolar affective disorder'),('severe-mental-illness',1,'E1160',NULL,'Mixed bipolar affective disorder, unspecified'),('severe-mental-illness',1,'E1161',NULL,'Mixed bipolar affective disorder, mild'),('severe-mental-illness',1,'E1162',NULL,'Mixed bipolar affective disorder, moderate'),('severe-mental-illness',1,'E1163',NULL,'Mixed bipolar affective disorder, severe, without psychosis'),('severe-mental-illness',1,'E1164',NULL,'Mixed bipolar affective disorder, severe, with psychosis'),('severe-mental-illness',1,'E1165',NULL,'Mixed bipolar affective disorder, partial/unspec remission'),('severe-mental-illness',1,'E1166',NULL,'Mixed bipolar affective disorder, in full remission'),('severe-mental-illness',1,'E116z',NULL,'Mixed bipolar affective disorder, NOS'),('severe-mental-illness',1,'E117.',NULL,'Unspecified bipolar affective disorder'),('severe-mental-illness',1,'E1170',NULL,'Unspecified bipolar affective disorder, unspecified'),('severe-mental-illness',1,'E1171',NULL,'Unspecified bipolar affective disorder, mild'),('severe-mental-illness',1,'E1172',NULL,'Unspecified bipolar affective disorder, moderate'),('severe-mental-illness',1,'E1173',NULL,'Unspecified bipolar affective disorder, severe, no psychosis'),('severe-mental-illness',1,'E1174',NULL,'Unspecified bipolar affective disorder,severe with psychosis'),('severe-mental-illness',1,'E1176',NULL,'Unspecified bipolar affective disorder, in full remission'),('severe-mental-illness',1,'E117z',NULL,'Unspecified bipolar affective disorder, NOS'),('severe-mental-illness',1,'E11y.',NULL,'Other and unspecified manic-depressive psychoses'),('severe-mental-illness',1,'E11y0',NULL,'Unspecified manic-depressive psychoses'),('severe-mental-illness',1,'E11y1',NULL,'Atypical manic disorder'),('severe-mental-illness',1,'E11y3',NULL,'Other mixed manic-depressive psychoses'),('severe-mental-illness',1,'E11yz',NULL,'Other and unspecified manic-depressive psychoses NOS'),('severe-mental-illness',1,'E11z.',NULL,'Other and unspecified affective psychoses'),('severe-mental-illness',1,'E11z0',NULL,'Unspecified affective psychoses NOS'),('severe-mental-illness',1,'E11zz',NULL,'Other affective psychosis NOS'),
('severe-mental-illness',1,'E120.',NULL,'Simple paranoid state'),('severe-mental-illness',1,'E121.',NULL,'[Chronic paranoid psychosis] or [Sanders disease]'),('severe-mental-illness',1,'E122.',NULL,'Paraphrenia'),('severe-mental-illness',1,'E123.',NULL,'Shared paranoid disorder'),('severe-mental-illness',1,'E12y0',NULL,'Paranoia querulans'),('severe-mental-illness',1,'E13..',NULL,'Psychoses: [other nonorganic] or [reactive]'),('severe-mental-illness',1,'E130.',NULL,'Reactive depressive psychosis'),('severe-mental-illness',1,'E131.',NULL,'Acute hysterical psychosis'),('severe-mental-illness',1,'E134.',NULL,'Psychogenic paranoid psychosis'),('severe-mental-illness',1,'E13y.',NULL,'Other reactive psychoses'),('severe-mental-illness',1,'E13y0',NULL,'Psychogenic stupor'),('severe-mental-illness',1,'E13y1',NULL,'Brief reactive psychosis'),('severe-mental-illness',1,'E13yz',NULL,'Other reactive psychoses NOS'),('severe-mental-illness',1,'E13z.',NULL,'Psychosis: [nonorganic NOS] or [episode NOS]'),('severe-mental-illness',1,'E1y..',NULL,'Other specified non-organic psychoses'),('severe-mental-illness',1,'E2122',NULL,'Schizotypal personality disorder'),('severe-mental-illness',1,'Eu2..',NULL,'[X]Schizophrenia, schizotypal and delusional disorders'),('severe-mental-illness',1,'Eu20.',NULL,'Schizophrenia'),('severe-mental-illness',1,'Eu202',NULL,'[X](Cat schiz)(cat stupor)(schiz catalep)(schiz flex cerea)'),('severe-mental-illness',1,'Eu203',NULL,'[X]Undifferentiated schizophrenia'),('severe-mental-illness',1,'Eu20y',NULL,'[X](Schizophr:[cenes][oth])(schizoform dis [& psychos] NOS)'),('severe-mental-illness',1,'Eu20z',NULL,'[X]Schizophrenia, unspecified'),('severe-mental-illness',1,'Eu22y',NULL,'[X](Oth pers delusion dis)(del dysm)(inv paranoid)(par quer)'),('severe-mental-illness',1,'Eu22z',NULL,'[X]Persistent delusional disorder, unspecified'),('severe-mental-illness',1,'Eu230',NULL,'[X]Ac polym psych dis, no schiz (& [bouf del][cycl psychos])'),('severe-mental-illness',1,'Eu231',NULL,'[X]Acute polymorphic psychot disord with symp of schizophren'),('severe-mental-illness',1,'Eu232',NULL,'[X]Ac schizophrenia-like psychot disord (& [named variants])'),('severe-mental-illness',1,'Eu233',NULL,'[X](Oth ac delusn psychot dis) or (psychogen paran psychos)'),('severe-mental-illness',1,'Eu23y',NULL,'[X]Other acute and transient psychotic disorders'),('severe-mental-illness',1,'Eu23z',NULL,'[X]Ac trans psych dis, unsp (& [reac psychos (& brief NOS)])'),('severe-mental-illness',1,'Eu24.',NULL,'Induced delusional disorder'),('severe-mental-illness',1,'Eu25.',NULL,'Schizoaffective disorder'),('severe-mental-illness',1,'Eu252',NULL,'[X](Mix schizoaff dis)(cycl schizo)(mix schiz/affect psych)'),('severe-mental-illness',1,'Eu25y',NULL,'[X]Other schizoaffective disorders'),('severe-mental-illness',1,'Eu25z',NULL,'[X]Schizoaffective disorder, unspecified'),('severe-mental-illness',1,'Eu2z.',NULL,'[X] Psychosis: [unspecified nonorganic] or [NOS]'),('severe-mental-illness',1,'Eu30.',NULL,'[X]Manic episode (& [bipolar disord, single manic episode])'),('severe-mental-illness',1,'Eu301',NULL,'[X]Mania without psychotic symptoms'),('severe-mental-illness',1,'Eu302',NULL,'[X](Mania+psych sym (& mood [congr][incong]))/(manic stupor)'),('severe-mental-illness',1,'Eu30y',NULL,'[X]Other manic episodes'),('severe-mental-illness',1,'Eu30z',NULL,'[X] Mania: [episode, unspecified] or [NOS]'),('severe-mental-illness',1,'Eu310',NULL,'Bipolar affective disorder, current episode hypomanic'),('severe-mental-illness',1,'Eu311',NULL,'[X]Bipolar affect disorder cur epi manic wout psychotic symp'),('severe-mental-illness',1,'Eu312',NULL,'[X]Bipolar affect disorder cur epi manic with psychotic symp'),('severe-mental-illness',1,'Eu313',NULL,'[X]Bipolar affect disorder cur epi mild or moderate depressn'),('severe-mental-illness',1,'Eu314',NULL,'[X]Bipol aff disord, curr epis sev depress, no psychot symp'),('severe-mental-illness',1,'Eu316',NULL,'Bipolar affective disorder , current episode mixed'),('severe-mental-illness',1,'Eu317',NULL,'[X]Bipolar affective disorder, currently in remission'),('severe-mental-illness',1,'Eu31y',NULL,'[X](Bipol affect disord:[II][other]) or (recur manic episod)'),('severe-mental-illness',1,'Eu31z',NULL,'[X]Bipolar affective disorder, unspecified'),('severe-mental-illness',1,'Eu323',NULL,'[X]Sev depress epis + psych symp:(& singl epis [named vars])'),('severe-mental-illness',1,'Eu333',NULL,'[X]Depress with psych sympt: [recurr: (named vars)][endogen]'),('severe-mental-illness',1,'X00Qx',NULL,'Psychotic episode NOS'),('severe-mental-illness',1,'X00Qy',NULL,'Reactive psychoses'),('severe-mental-illness',1,'X00RU',NULL,'Epileptic psychosis'),('severe-mental-illness',1,'X00S6',NULL,'Psychotic disorder'),('severe-mental-illness',1,'X00S8',NULL,'Post-schizophrenic depression'),('severe-mental-illness',1,'X00SA',NULL,'Persistent delusional disorder'),('severe-mental-illness',1,'X00SC',NULL,'Acute transient psychotic disorder'),('severe-mental-illness',1,'X00SD',NULL,'Schizophreniform disorder'),('severe-mental-illness',1,'X00SJ',NULL,'Mania'),('severe-mental-illness',1,'X00SK',NULL,'Manic stupor'),('severe-mental-illness',1,'X00SL',NULL,'Hypomania'),('severe-mental-illness',1,'X00SM',NULL,'Bipolar disorder'),('severe-mental-illness',1,'X00SN',NULL,'Bipolar II disorder'),('severe-mental-illness',1,'X50GE',NULL,'Cutaneous monosymptomatic delusional psychosis'),('severe-mental-illness',1,'X50GF',NULL,'Delusions of parasitosis'),('severe-mental-illness',1,'X50GG',NULL,'Delusions of infestation'),('severe-mental-illness',1,'X50GH',NULL,'Delusion of foul odour'),('severe-mental-illness',1,'X50GJ',NULL,'Delusional hyperhidrosis'),('severe-mental-illness',1,'X761M',NULL,'Schizophrenic prodrome'),('severe-mental-illness',1,'XE1Xw',NULL,'Acute schizophrenic episode'),('severe-mental-illness',1,'XE1Xx',NULL,'Other schizophrenia'),('severe-mental-illness',1,'XE1Xz',NULL,'Manic disorder, single episode'),('severe-mental-illness',1,'XE1Y2',NULL,'Chronic paranoid psychosis'),('severe-mental-illness',1,'XE1Y3',NULL,'Other non-organic psychoses'),('severe-mental-illness',1,'XE1Y4',NULL,'Acute paranoid reaction'),('severe-mental-illness',1,'XE1Y5',NULL,'Non-organic psychosis NOS'),('severe-mental-illness',1,'XE1ZM',NULL,'[X]Other schizophrenia'),('severe-mental-illness',1,'XE1ZN',NULL,'[X]Schizotypal disorder'),('severe-mental-illness',1,'XE1ZO',NULL,'Delusional disorder'),('severe-mental-illness',1,'XE1ZP',NULL,'[X]Other persistent delusional disorders'),('severe-mental-illness',1,'XE1ZQ',NULL,'[X]Acute polymorphic psychot disord without symp of schizoph'),('severe-mental-illness',1,'XE1ZR',NULL,'[X]Other acute predominantly delusional psychotic disorders'),('severe-mental-illness',1,'XE1ZS',NULL,'[X]Acute and transient psychotic disorder, unspecified'),('severe-mental-illness',1,'XE1ZT',NULL,'[X]Other non-organic psychotic disorders'),('severe-mental-illness',1,'XE1ZU',NULL,'[X]Unspecified nonorganic psychosis'),('severe-mental-illness',1,'XE1ZV',NULL,'[X]Mania with psychotic symptoms'),('severe-mental-illness',1,'XE1ZW',NULL,'[X]Manic episode, unspecified'),('severe-mental-illness',1,'XE1ZX',NULL,'[X]Other bipolar affective disorders'),('severe-mental-illness',1,'XE1ZZ',NULL,'[X]Severe depressive episode with psychotic symptoms'),('severe-mental-illness',1,'XE1Ze',NULL,'[X]Recurrent depress disorder cur epi severe with psyc symp'),('severe-mental-illness',1,'XE1aM',NULL,'Schizophrenic psychoses (& [paranoid schizophrenia])'),('severe-mental-illness',1,'XE1aU',NULL,'(Paranoid states) or (delusion: [paranoid] or [persecution])'),('severe-mental-illness',1,'XE2b8',NULL,'Schizoaffective disorder, mixed type'),('severe-mental-illness',1,'XE2uT',NULL,'Schizoaffective disorder, manic type'),('severe-mental-illness',1,'XE2un',NULL,'Schizoaffective disorder, depressive type'),('severe-mental-illness',1,'XM1GG',NULL,'Borderline schizophrenia'),('severe-mental-illness',1,'XM1GH',NULL,'Acute polymorphic psychotic disorder'),('severe-mental-illness',1,'XSGon',NULL,'Severe major depression with psychotic features'),('severe-mental-illness',1,'Xa0lD',NULL,'Involutional paranoid state'),('severe-mental-illness',1,'Xa0lF',NULL,'Delusional dysmorphophobia'),('severe-mental-illness',1,'Xa0s9',NULL,'Acute schizophrenia-like psychotic disorder'),('severe-mental-illness',1,'Xa0tC',NULL,'Late paraphrenia'),('severe-mental-illness',1,'Xa1aD',NULL,'Monosymptomatic hypochondriacal psychosis'),('severe-mental-illness',1,'Xa1aF',NULL,'Erotomania'),('severe-mental-illness',1,'Xa1bS',NULL,'Othello syndrome'),('severe-mental-illness',1,'XaB5u',NULL,'Bouffee delirante'),('severe-mental-illness',1,'XaB5v',NULL,'Cycloid psychosis'),('severe-mental-illness',1,'XaB8j',NULL,'Oneirophrenia'),('severe-mental-illness',1,'XaB95',NULL,'Other manic-depressive psychos'),('severe-mental-illness',1,'XaK4Y',NULL,'[X]Erotomania'),('severe-mental-illness',1,'XaX52',NULL,'Non-organic psychosis in remission'),('severe-mental-illness',1,'XaX53',NULL,'Single major depress ep, severe with psych, psych in remissn'),('severe-mental-illness',1,'XaX54',NULL,'Recurr major depress ep, severe with psych, psych in remissn'),('severe-mental-illness',1,'XaY1Y',NULL,'Bipolar I disorder'),('severe-mental-illness',1,'XagU1',NULL,'Recurrent reactiv depressiv episodes, severe, with psychosis'),('severe-mental-illness',1,'1464.',NULL,'H/O: schizophrenia'),('severe-mental-illness',1,'665B.',NULL,'Lithium stopped'),('severe-mental-illness',1,'E0...',NULL,'Organic psychotic condition'),('severe-mental-illness',1,'E00..',NULL,'Senile and presenile organic psychotic conditions (& dementia)'),('severe-mental-illness',1,'E00y.',NULL,'(Other senile and presenile organic psychoses) or (presbyophrenic psychosis)'),('severe-mental-illness',1,'E00z.',NULL,'Senile or presenile psychoses NOS'),('severe-mental-illness',1,'E010.',NULL,'Delirium tremens'),
('severe-mental-illness',1,'E011.',NULL,'Korsakoff psychosis'),('severe-mental-illness',1,'E0111',NULL,'Korsakovs alcoholic psychosis with peripheral neuritis'),('severe-mental-illness',1,'E0112',NULL,'Wernicke-Korsakov syndrome'),('severe-mental-illness',1,'E012.',NULL,'Alcoholic dementia NOS'),('severe-mental-illness',1,'E02..',NULL,'Drug-induced psychosis'),('severe-mental-illness',1,'E021.',NULL,'Drug-induced paranoia or hallucinatory states'),('severe-mental-illness',1,'E0210',NULL,'Drug-induced paranoid state'),('severe-mental-illness',1,'E0211',NULL,'Drug-induced hallucinosis'),('severe-mental-illness',1,'E021z',NULL,'Drug-induced paranoia or hallucinatory state NOS'),('severe-mental-illness',1,'E02y.',NULL,'Other drug psychoses'),('severe-mental-illness',1,'E02y0',NULL,'Drug-induced delirium'),('severe-mental-illness',1,'E02y3',NULL,'Drug-induced depressive state'),('severe-mental-illness',1,'E02y4',NULL,'Drug-induced personality disorder'),('severe-mental-illness',1,'E02z.',NULL,'Drug psychosis NOS'),('severe-mental-illness',1,'E03..',NULL,'Transient organic psychoses'),('severe-mental-illness',1,'E03y.',NULL,'Other transient organic psychoses'),('severe-mental-illness',1,'E03z.',NULL,'Transient organic psychoses NOS'),('severe-mental-illness',1,'E04..',NULL,'Other chronic organic psychoses'),('severe-mental-illness',1,'E04y.',NULL,'Other specified chronic organic psychoses'),('severe-mental-illness',1,'E04z.',NULL,'Chronic organic psychosis NOS'),('severe-mental-illness',1,'E0y..',NULL,'Other specified organic psychoses'),('severe-mental-illness',1,'E0z..',NULL,'Organic psychoses NOS'),('severe-mental-illness',1,'E11..',NULL,'Affective psychoses (& [bipolar] or [depressive] or [manic])'),('severe-mental-illness',1,'E11y2',NULL,'Atypical depressive disorder'),('severe-mental-illness',1,'E11z1',NULL,'Rebound mood swings'),('severe-mental-illness',1,'E12..',NULL,'Paranoid disorder'),('severe-mental-illness',1,'E12y.',NULL,'Other paranoid states'),('severe-mental-illness',1,'E12yz',NULL,'Other paranoid states NOS'),('severe-mental-illness',1,'E12z.',NULL,'Paranoid psychosis NOS'),('severe-mental-illness',1,'E141.',NULL,'Childhood disintegrative disorder'),('severe-mental-illness',1,'E141z',NULL,'Disintegrative psychosis NOS'),('severe-mental-illness',1,'E2110',NULL,'Unspecified affective personality disorder'),('severe-mental-illness',1,'E2113',NULL,'Affective personality disorder'),('severe-mental-illness',1,'E211z',NULL,'Affective personality disorder NOS'),('severe-mental-illness',1,'E212.',NULL,'Schizoid personality disorder'),('severe-mental-illness',1,'E2120',NULL,'Unspecified schizoid personality disorder'),('severe-mental-illness',1,'E212z',NULL,'Schizoid personality disorder NOS'),('severe-mental-illness',1,'Eu02z',NULL,'[X] Dementia: [unspecif] or [presenile NOS (including presenile psychosis NOS)] or [primary degenerative NOS] or [senile NOS (including senile psychosis NOS)] or [senile depressed or paranoid type]'),('severe-mental-illness',1,'Eu104',NULL,'[X]Mental and behavioural disorders due to use of alcohol: withdrawal state with delirium'),('severe-mental-illness',1,'Eu106',NULL,'[X]Mental and behavioural disorders due to use of alcohol: amnesic syndrome'),('severe-mental-illness',1,'Eu107',NULL,'[X] (Mental and behavioural disorders due to use of alcohol: residual and late-onset psychotic disorder) or (chronic alcoholic brain syndrome [& dementia NOS])'),('severe-mental-illness',1,'Eu115',NULL,'[X]Mental and behavioural disorders due to use of opioids: psychotic disorder'),('severe-mental-illness',1,'Eu125',NULL,'[X]Mental and behavioural disorders due to use of cannabinoids: psychotic disorder'),('severe-mental-illness',1,'Eu135',NULL,'[X]Mental and behavioural disorders due to use of sedatives or hypnotics: psychotic disorder'),('severe-mental-illness',1,'Eu145',NULL,'[X]Mental and behavioural disorders due to use of cocaine: psychotic disorder'),('severe-mental-illness',1,'Eu155',NULL,'[X]Mental and behavioural disorders due to use of other stimulants, including caffeine: psychotic disorder'),('severe-mental-illness',1,'Eu195',NULL,'[X]Mental and behavioural disorders due to multiple drug use and use of other psychoactive substances: psychotic disorder'),('severe-mental-illness',1,'Eu332',NULL,'[X]Depression without psychotic symptoms: [recurrent: [major] or [manic-depressive psychosis, depressed type] or [vital] or [current severe episode]] or [endogenous]'),('severe-mental-illness',1,'Eu34.',NULL,'[X]Persistent mood affective disorders'),('severe-mental-illness',1,'Eu3y.',NULL,'[X]Other mood affective disorders'),('severe-mental-illness',1,'Eu3y0',NULL,'[X] Mood affective disorders: [other single] or [mixed episode]'),('severe-mental-illness',1,'Eu44.',NULL,'[X]Dissociative [conversion] disorders'),('severe-mental-illness',1,'X00Rk',NULL,'Alcoholic dementia NOS'),('severe-mental-illness',1,'X40Do',NULL,'Mild postnatal psychosis'),('severe-mental-illness',1,'X40Dp',NULL,'Severe postnatal psychosis'),('severe-mental-illness',1,'Xa25J',NULL,'Alcoholic dementia'),('severe-mental-illness',1,'Xa9B0',NULL,'Puerperal psychosis'),('severe-mental-illness',1,'XaIWQ',NULL,'On severe mental illness register'),('severe-mental-illness',1,'XE1Xr',NULL,'Senile and presenile organic psychotic conditions'),('severe-mental-illness',1,'XE1Xt',NULL,'Other senile and presenile organic psychoses'),('severe-mental-illness',1,'XE1Xu',NULL,'Other alcoholic dementia'),('severe-mental-illness',1,'ZV110',NULL,'[V]Personal history of schizophrenia'),('severe-mental-illness',1,'ZV111',NULL,'[V]Personal history of affective disorder');
INSERT INTO #codesctv3
VALUES ('flu-vaccine',1,'n47..',NULL,'FLU - Influenza vaccine'),('flu-vaccine',1,'n471.',NULL,'Fluvirin prefilled syringe 0.5mL'),('flu-vaccine',1,'n473.',NULL,'Influvac sub-unit prefilled syringe 0.5mL'),('flu-vaccine',1,'n474.',NULL,'Influvac sub-unit Vials 5mL'),('flu-vaccine',1,'n475.',NULL,'Influvac sub-unit Vials 25mL'),('flu-vaccine',1,'n476.',NULL,'MFV-Ject prefilled syringe 0.5mL'),('flu-vaccine',1,'n477.',NULL,'Inactivated Influenza vaccine injection 0.5mL'),('flu-vaccine',1,'n478.',NULL,'Inactivated Influenza vaccine prefilled syringe 0.5mL'),('flu-vaccine',1,'n479.',NULL,'Influenza vaccine Vials 5mL'),('flu-vaccine',1,'n47a.',NULL,'Influenza vaccine Vials 25mL'),('flu-vaccine',1,'n47A.',NULL,'PANDEMRIX INFLUENZA A VACCINE (H1N1v) 2009 injection'),('flu-vaccine',1,'n47B.',NULL,'CELVAPAN INFLUENZA A VACCINE (H1N1v) 2009 injection'),('flu-vaccine',1,'n47b.',NULL,'Fluzone prefilled syringe 0.5mL'),('flu-vaccine',1,'n47c.',NULL,'Fluzone Vials 5mL'),('flu-vaccine',1,'n47C.',NULL,'PREFLUCEL suspension for injection prefilled syringe 0.5mL'),('flu-vaccine',1,'n47d.',NULL,'Fluarix vaccine prefilled syringe'),('flu-vaccine',1,'n47D.',NULL,'FLUENZ nasal suspension 0.2mL'),('flu-vaccine',1,'n47e.',NULL,'Begrivac vaccine pre-filled syringe 0.5mL'),('flu-vaccine',1,'n47E.',NULL,'INFLUENZA VACCINE (LIVE ATTENUATED) nasal suspension 0.2mL'),('flu-vaccine',1,'n47f.',NULL,'Agrippal vaccine prefilled syringe 0.5mL'),('flu-vaccine',1,'n47F.',NULL,'OPTAFLU suspension for injection prefilled syringe 0.5mL'),('flu-vaccine',1,'n47g.',NULL,'Inactivated Influenza vaccine (split virion) prefilled syringe 0.5mL'),('flu-vaccine',1,'n47G.',NULL,'INFLUVAC DESU suspension for injection prefill syringe 0.5mL'),('flu-vaccine',1,'n47H.',NULL,'FLUARIX TETRA suspension for injection prefill syringe 0.5mL'),('flu-vaccine',1,'n47h.',NULL,'Inactivated Influenza vaccine (surface antigen) prefilled syringe 0.5mL'),('flu-vaccine',1,'n47I.',NULL,'FLUENZ TETRA nasal spray suspension 0.2mL'),('flu-vaccine',1,'n47i.',NULL,'Inflexal Berna V prefilled syringe 0.5mL'),('flu-vaccine',1,'n47j.',NULL,'MASTAFLU prefilled syringe 0.5mL'),('flu-vaccine',1,'n47k.',NULL,'Inflexal V prefilled syringe 0.5mL'),('flu-vaccine',1,'n47l.',NULL,'Invivac prefilled syringe 0.5mL'),('flu-vaccine',1,'n47m.',NULL,'Enzira prefilled syringe 0.5mL'),('flu-vaccine',1,'n47n.',NULL,'Viroflu prefilled syringe 0.5mL'),('flu-vaccine',1,'n47o.',NULL,'IMUVAC prefilled syringe 0.5mL'),('flu-vaccine',1,'n47p.',NULL,'INTANZA 15micrograms/strain susp for inj pfs 0.1mL'),('flu-vaccine',1,'n47q.',NULL,'INACT INFLUENZA VACC (SPLIT VIRION) 15mcg/strain pfs 0.1mL'),('flu-vaccine',1,'n47r.',NULL,'CELVAPAN (H1N1) suspension for injection vials 5mL'),('flu-vaccine',1,'n47s.',NULL,'CELVAPAN (H5N1) suspension for injection vials 5mL'),('flu-vaccine',1,'n47t.',NULL,'PANDEMRIX (H5N1) injection vials'),('flu-vaccine',1,'n47u.',NULL,'INTANZA 9micrograms/strain susp for inj pfs 0.1mL'),('flu-vaccine',1,'n47v.',NULL,'INACT INFLUENZA VACC (SPLIT VIRION) 9mcg/strain pfs 0.1mL'),('flu-vaccine',1,'n47y.',NULL,'Inactivated Influenza vaccine (split virion) prefilled syringe 0.25mL'),('flu-vaccine',1,'n47z.',NULL,'Inactivated Influenza vaccine (surface antigen virosome) prefilled syringe 0.5mL'),('flu-vaccine',1,'x006a',NULL,'Inactivated Influenza surface antigen sub-unit vaccine'),('flu-vaccine',1,'x006Z',NULL,'Inactivated Influenza split virion vaccine'),('flu-vaccine',1,'x00Yd',NULL,'Fluvirin vaccine prefilled syringe'),('flu-vaccine',1,'x00Ye',NULL,'Fluzone vaccine prefilled syringe'),('flu-vaccine',1,'x00Yi',NULL,'Inactivated Influenza (split virion) vaccine prefilled syringe'),('flu-vaccine',1,'x00Yj',NULL,'Inactivated Influenza (surface antigen sub-unit ) vaccine prefilled syringe'),('flu-vaccine',1,'x00Yk',NULL,'Influvac Sub-unit vaccine prefilled syringe'),('flu-vaccine',1,'x00Yp',NULL,'MFV-Ject vaccine prefilled syringe'),('flu-vaccine',1,'x01LF',NULL,'Influvac Sub-unit injection'),('flu-vaccine',1,'x01LG',NULL,'Fluzone injection vial'),('flu-vaccine',1,'x02d0',NULL,'Fluarix'),('flu-vaccine',1,'x03qt',NULL,'Begrivac vaccine prefilled syringe'),('flu-vaccine',1,'x03qu',NULL,'Begrivac'),('flu-vaccine',1,'x03zt',NULL,'Fluvirin'),('flu-vaccine',1,'x03zu',NULL,'Fluzone'),('flu-vaccine',1,'x0453',NULL,'Influvac Sub-unit'),('flu-vaccine',1,'x05cg',NULL,'Inflexal Berna V prefilled syringe'),('flu-vaccine',1,'x05cj',NULL,'Inflexal Berna V'),('flu-vaccine',1,'x05oa',NULL,'MASTAFLU prefilled syringe'),('flu-vaccine',1,'x05ob',NULL,'MASTAFLU'),('flu-vaccine',1,'x05pi',NULL,'Inflexal V'),('flu-vaccine',1,'x05pY',NULL,'Inflexal V prefilled syringe'),('flu-vaccine',1,'x05vU',NULL,'Invivac vaccine prefilled syringe'),('flu-vaccine',1,'x05vV',NULL,'Invivac'),('flu-vaccine',1,'x05Y1',NULL,'Agrippal vaccine prefilled syringe'),('flu-vaccine',1,'x05yK',NULL,'Enzira vaccine prefilled syringe'),('flu-vaccine',1,'x05yL',NULL,'Enzira'),('flu-vaccine',1,'x05yO',NULL,'Inactivated Influenza surface antigen virosome vaccine prefilled syringe'),('flu-vaccine',1,'x05yP',NULL,'Inactivated Influenza surface antigen virosome vaccine'),('flu-vaccine',1,'x05zC',NULL,'Viroflu prefilled syringe'),('flu-vaccine',1,'x05zD',NULL,'Viroflu');
INSERT INTO #codesctv3
VALUES ('covid-vaccine-declined',1,'Y29ed',NULL,'SARS-CoV-2 vaccination first dose declined'),('covid-vaccine-declined',1,'Y29ec',NULL,'SARS-CoV-2 vaccination dose declined'),('covid-vaccine-declined',1,'Y29ee',NULL,'SARS-CoV-2 vaccination second dose declined'),('covid-vaccine-declined',1,'Y211e',NULL,'SARS-CoV-2 immunisation course declined');
INSERT INTO #codesctv3
VALUES ('high-clinical-vulnerability',1,'Y228a',NULL,'High risk category for developing complications from COVID-19 severe acute respiratory syndrome coronavirus infection');
INSERT INTO #codesctv3
VALUES ('moderate-clinical-vulnerability',1,'Y228b',NULL,'Moderate risk category for developing complication from coronavirus disease 19 caused by severe acute respiratory syndrome coronavirus 2 infection (finding)');
INSERT INTO #codesctv3
VALUES ('covid-vaccination',1,'Y210d',NULL,'2019-nCoV (novel coronavirus) vaccination'),('covid-vaccination',1,'Y29e7',NULL,'Administration of first dose of SARS-CoV-2 vaccine'),('covid-vaccination',1,'Y29e8',NULL,'Administration of second dose of SARS-CoV-2 vaccine'),('covid-vaccination',1,'Y2a0e',NULL,'SARS-2 Coronavirus vaccine'),('covid-vaccination',1,'Y2a0f',NULL,'COVID-19 mRNA Vaccine BNT162b2 30micrograms/0.3ml dose concentrate for suspension for injection multidose vials (Pfizer-BioNTech) part 1'),('covid-vaccination',1,'Y2a3a',NULL,'COVID-19 mRNA Vaccine BNT162b2 30micrograms/0.3ml dose concentrate for suspension for injection multidose vials (Pfizer-BioNTech) part 2'),('covid-vaccination',1,'65F06',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccination'),('covid-vaccination',1,'65F09',NULL,'Administration of third dose of SARS-CoV-2 vaccine'),('covid-vaccination',1,'65F0A',NULL,'Administration of fourth dose of SARS-CoV-2 vaccine'),('covid-vaccination',1,'9bJ..',NULL,'COVID-19 mRNA Vaccine BNT162b2 30micrograms/0.3ml dose concentrate for suspension for injection multidose vials (Pfizer-BioNTech)'),('covid-vaccination',1,'Y2a10',NULL,'COVID-19 Vac AstraZeneca (ChAdOx1 S recomb) 5x10000000000 viral particles/0.5ml dose sol for inj MDV part 1'),('covid-vaccination',1,'Y2a39',NULL,'COVID-19 Vac AstraZeneca (ChAdOx1 S recomb) 5x10000000000 viral particles/0.5ml dose sol for inj MDV part 2'),('covid-vaccination',1,'Y2b9d',NULL,'COVID-19 mRNA (nucleoside modified) Vaccine Moderna 0.1mg/0.5mL dose dispersion for injection multidose vials part 2'),('covid-vaccination',1,'Y2f45',NULL,'Administration of third dose of SARS-CoV-2 vaccine'),('covid-vaccination',1,'Y2f48',NULL,'Administration of fourth dose of SARS-CoV-2 vaccine'),('covid-vaccination',1,'Y2f57',NULL,'COVID-19 mRNA Vaccine BNT162b2 30micrograms/0.3ml dose concentrate for suspension for injection multidose vials (Pfizer-BioNTech) booster'),('covid-vaccination',1,'Y31cc',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) antigen vaccination'),('covid-vaccination',1,'Y31e6',NULL,'Administration of SARS-CoV-2 mRNA vaccine'),('covid-vaccination',1,'Y31e7',NULL,'Administration of first dose of SARS-CoV-2 mRNA vaccine'),('covid-vaccination',1,'Y31e8',NULL,'Administration of second dose of SARS-CoV-2 mRNA vaccine');
INSERT INTO #codesctv3
VALUES ('flu-vaccination',1,'65E..',NULL,'Influenza vaccination'),('flu-vaccination',1,'Xaa9G',NULL,'Administration of intranasal influenza vaccination'),('flu-vaccination',1,'Xaac1',NULL,'Administration of first intranasal pandemic influenza vaccination'),('flu-vaccination',1,'Xaac2',NULL,'Administration of second intranasal pandemic influenza vaccination'),('flu-vaccination',1,'Xaac3',NULL,'Administration of first intranasal seasonal influenza vaccination'),('flu-vaccination',1,'Xaac4',NULL,'Administration of second intranasal seasonal influenza vaccination'),('flu-vaccination',1,'Xaac5',NULL,'First intranasal pandemic influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'Xaac6',NULL,'Second intranasal pandemic influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'Xaac7',NULL,'First intranasal seasonal influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'Xaac8',NULL,'Second intranasal seasonal influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'XaaED',NULL,'Administration of first intranasal influenza vaccination'),('flu-vaccination',1,'XaaEF',NULL,'Administration of second intranasal influenza vaccination'),('flu-vaccination',1,'XaaZp',NULL,'Seasonal influenza vaccination given while hospital inpatient'),('flu-vaccination',1,'XabvT',NULL,'Second intramuscular seasonal influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'Xac5J',NULL,'First intramuscular seasonal influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'Xad9j',NULL,'Administration of first inactivated seasonal influenza vaccination'),('flu-vaccination',1,'Xad9k',NULL,'Administration of second inactivated seasonal influenza vaccination'),('flu-vaccination',1,'Xaeet',NULL,'First intranasal seasonal influenza vaccination given by pharmacist'),('flu-vaccination',1,'Xaeeu',NULL,'Second intranasal seasonal influenza vaccination given by pharmacist'),('flu-vaccination',1,'Xaeev',NULL,'First inactivated seasonal influenza vaccination given by pharmacist'),('flu-vaccination',1,'Xaeew',NULL,'Second inactivated seasonal influenza vaccination given by pharmacist'),('flu-vaccination',1,'XafhP',NULL,'Seasonal influenza vaccination given by midwife'),('flu-vaccination',1,'XafhQ',NULL,'First inactivated seasonal influenza vaccination given by midwife'),('flu-vaccination',1,'XafhR',NULL,'Second inactivated seasonal influenza vaccination given by midwife'),('flu-vaccination',1,'XaLK4',NULL,'Booster influenza vaccination'),('flu-vaccination',1,'XaLNG',NULL,'First pandemic influenza vaccination'),('flu-vaccination',1,'XaLNH',NULL,'Second pandemic influenza vaccination'),('flu-vaccination',1,'XaPwi',NULL,'First pandemic influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'XaPwj',NULL,'Second pandemic influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'XaPyT',NULL,'Influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'XaQhk',NULL,'CELVAPAN - first influenza A (H1N1v) 2009 vaccination given'),('flu-vaccination',1,'XaQhl',NULL,'CELVAPAN - second influenza A (H1N1v) 2009 vaccination given'),('flu-vaccination',1,'XaQhm',NULL,'PANDEMRIX - first influenza A (H1N1v) 2009 vaccination given'),('flu-vaccination',1,'XaQhn',NULL,'PANDEMRIX - second influenza A (H1N1v) 2009 vaccination given'),('flu-vaccination',1,'XaQho',NULL,'CELVAPAN - first influenza A (H1N1v) 2009 vaccination given by other healthcare provider'),('flu-vaccination',1,'XaQhp',NULL,'CELVAPAN - second influenza A (H1N1v) 2009 vaccination given by other healthcare provider'),('flu-vaccination',1,'XaQhq',NULL,'PANDEMRIX - first influenza A (H1N1v) 2009 vaccination given by other healthcare provider'),('flu-vaccination',1,'XaQhr',NULL,'PANDEMRIX - second influenza A (H1N1v) 2009 vaccination given by other healthcare provider'),('flu-vaccination',1,'XaZ0d',NULL,'Seasonal influenza vaccination'),('flu-vaccination',1,'XaZ0e',NULL,'Seasonal influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'XaZfY',NULL,'Seasonal influenza vaccination given by pharmacist'),('flu-vaccination',1,'ZV048',NULL,'[V]Flu - influenza vaccination'),('flu-vaccination',1,'Y0c3f',NULL,'First influenza A (H1N1v) 2009 vaccination given'),('flu-vaccination',1,'Y0c40',NULL,'Second influenza A (H1N1v) 2009 vaccination given');
INSERT INTO #codesctv3
VALUES ('covid-positive-antigen-test',1,'Y269d',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) antigen detection result positive'),('covid-positive-antigen-test',1,'43kB1',NULL,'SARS-CoV-2 antigen positive');
INSERT INTO #codesctv3
VALUES ('covid-positive-pcr-test',1,'4J3R6',NULL,'SARS-CoV-2 RNA pos lim detect'),('covid-positive-pcr-test',1,'Y240b',NULL,'Severe acute respiratory syndrome coronavirus 2 qualitative existence in specimen (observable entity)'),('covid-positive-pcr-test',1,'Y2a3b',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) RNA (ribonucleic acid) detection result positive'),('covid-positive-pcr-test',1,'A7952',NULL,'COVID-19 confirmed by laboratory test'),('covid-positive-pcr-test',1,'Y228d',NULL,'Coronavirus disease 19 caused by severe acute respiratory syndrome coronavirus 2 confirmed by laboratory test (situation)'),('covid-positive-pcr-test',1,'Y210e',NULL,'Detection of 2019-nCoV (novel coronavirus) using polymerase chain reaction technique'),('covid-positive-pcr-test',1,'43hF.',NULL,'Detection of SARS-CoV-2 by PCR'),('covid-positive-pcr-test',1,'Y2a3d',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) RNA (ribonucleic acid) detection result positive at the limit of detection');
INSERT INTO #codesctv3
VALUES ('covid-positive-test-other',1,'4J3R1',NULL,'2019-nCoV (novel coronavirus) detected'),('covid-positive-test-other',1,'Y20d1',NULL,'Confirmed 2019-nCov (Wuhan) infection'),('covid-positive-test-other',1,'Y23f7',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) detection result positive')

INSERT INTO #AllCodes
SELECT [concept], [version], [code], [description] from #codesctv3;

IF OBJECT_ID('tempdb..#codessnomed') IS NOT NULL DROP TABLE #codessnomed;
CREATE TABLE #codessnomed (
  [concept] [varchar](255) NOT NULL,
  [version] INT NOT NULL,
	[code] [varchar](20) COLLATE Latin1_General_CS_AS NOT NULL,
	[term] [varchar](20) COLLATE Latin1_General_CS_AS NULL,
	[description] [varchar](255) NULL
) ON [PRIMARY];

INSERT INTO #codessnomed
VALUES ('severe-mental-illness',1,'391193001',NULL,'On severe mental illness register (finding)'),('severe-mental-illness',1,'69322001',NULL,'Psychotic disorder (disorder)'),('severe-mental-illness',1,'10760421000119102',NULL,'Psychotic disorder in mother complicating childbirth (disorder)'),('severe-mental-illness',1,'10760461000119107',NULL,'Psychotic disorder in mother complicating pregnancy (disorder)'),('severe-mental-illness',1,'1089691000000105',NULL,'Acute predominantly delusional psychotic disorder (disorder)'),('severe-mental-illness',1,'129602009',NULL,'Simbiotic infantile psychosis (disorder)'),('severe-mental-illness',1,'15921731000119106',NULL,'Psychotic disorder caused by methamphetamine (disorder)'),('severe-mental-illness',1,'17262008',NULL,'Non-alcoholic Korsakoffs psychosis (disorder)'),('severe-mental-illness',1,'18260003',NULL,'Postpartum psychosis (disorder)'),('severe-mental-illness',1,'191447007',NULL,'Organic psychotic condition (disorder)'),('severe-mental-illness',1,'191483003',NULL,'Drug-induced psychosis (disorder)'),('severe-mental-illness',1,'191525009',NULL,'Non-organic psychoses (disorder)'),('severe-mental-illness',1,'191676002',NULL,'Reactive depressive psychosis (disorder)'),('severe-mental-illness',1,'191680007',NULL,'Psychogenic paranoid psychosis (disorder)'),('severe-mental-illness',1,'21831000119109',NULL,'Phencyclidine psychosis (disorder)'),('severe-mental-illness',1,'231437006',NULL,'Reactive psychoses (disorder)'),('severe-mental-illness',1,'231438001',NULL,'Presbyophrenic psychosis (disorder)'),('severe-mental-illness',1,'231449007',NULL,'Epileptic psychosis (disorder)'),('severe-mental-illness',1,'231450007',NULL,'Psychosis associated with intensive care (disorder)'),('severe-mental-illness',1,'231489001',NULL,'Acute transient psychotic disorder (disorder)'),('severe-mental-illness',1,'238972008',NULL,'Cutaneous monosymptomatic delusional psychosis (disorder)'),('severe-mental-illness',1,'26530004',NULL,'Severe bipolar disorder with psychotic features, mood-incongruent (disorder)'),('severe-mental-illness',1,'268623006',NULL,'Other non-organic psychoses (disorder)'),('severe-mental-illness',1,'268625004',NULL,'Non-organic psychosis NOS (disorder)'),('severe-mental-illness',1,'274953007',NULL,'Acute polymorphic psychotic disorder (disorder)'),('severe-mental-illness',1,'278853003',NULL,'Acute schizophrenia-like psychotic disorder (disorder)'),('severe-mental-illness',1,'32358001',NULL,'Amphetamine delusional disorder (disorder)'),('severe-mental-illness',1,'357705009',NULL,'Cotards syndrome (disorder)'),('severe-mental-illness',1,'371026009',NULL,'Senile dementia with psychosis (disorder)'),('severe-mental-illness',1,'408858002',NULL,'Infantile psychosis (disorder)'),('severe-mental-illness',1,'441704009',NULL,'Affective psychosis (disorder)'),('severe-mental-illness',1,'473452003',NULL,'Atypical psychosis (disorder)'),('severe-mental-illness',1,'50933003',NULL,'Hallucinogen delusional disorder (disorder)'),('severe-mental-illness',1,'5464005',NULL,'Brief reactive psychosis (disorder)'),('severe-mental-illness',1,'58214004',NULL,'Schizophrenia (disorder)'),('severe-mental-illness',1,'58647003',NULL,'Severe mood disorder with psychotic features, mood-congruent (disorder)'),('severe-mental-illness',1,'59617007',NULL,'Severe depressed bipolar I disorder with psychotic features (disorder)'),('severe-mental-illness',1,'61831009',NULL,'Induced psychotic disorder (disorder)'),('severe-mental-illness',1,'68890003',NULL,'Schizoaffective disorder (disorder)'),('severe-mental-illness',1,'69482004',NULL,'Korsakoffs psychosis (disorder)'),('severe-mental-illness',1,'70546001',NULL,'Severe bipolar disorder with psychotic features, mood-congruent (disorder)'),('severe-mental-illness',1,'719717006',NULL,'Psychosis co-occurrent and due to Parkinsons disease (disorder)'),('severe-mental-illness',1,'723936000',NULL,'Psychotic disorder caused by cannabis (disorder)'),('severe-mental-illness',1,'724655005',NULL,'Psychotic disorder caused by opioid (disorder)'),('severe-mental-illness',1,'724689006',NULL,'Psychotic disorder caused by cocaine (disorder)'),('severe-mental-illness',1,'724696008',NULL,'Psychotic disorder caused by hallucinogen (disorder)'),('severe-mental-illness',1,'724702008',NULL,'Psychotic disorder caused by volatile inhalant (disorder)'),('severe-mental-illness',1,'724706006',NULL,'Psychotic disorder caused by methylenedioxymethamphetamine (disorder)'),('severe-mental-illness',1,'724718002',NULL,'Psychotic disorder caused by dissociative drug (disorder)'),('severe-mental-illness',1,'724719005',NULL,'Psychotic disorder caused by ketamine (disorder)'),('severe-mental-illness',1,'724729003',NULL,'Psychotic disorder caused by psychoactive substance (disorder)'),('severe-mental-illness',1,'724755002',NULL,'Positive symptoms co-occurrent and due to primary psychotic disorder (disorder)'),('severe-mental-illness',1,'724756001',NULL,'Negative symptoms co-occurrent and due to primary psychotic disorder (disorder)'),('severe-mental-illness',1,'724757005',NULL,'Depressive symptoms co-occurrent and due to primary psychotic disorder (disorder)'),('severe-mental-illness',1,'724758000',NULL,'Manic symptoms co-occurrent and due to primary psychotic disorder (disorder)'),('severe-mental-illness',1,'724759008',NULL,'Psychomotor symptom co-occurrent and due to psychotic disorder (disorder)'),('severe-mental-illness',1,'724760003',NULL,'Cognitive impairment co-occurrent and due to primary psychotic disorder (disorder)'),('severe-mental-illness',1,'735750005',NULL,'Psychotic disorder with schizophreniform symptoms caused by cocaine (disorder)'),('severe-mental-illness',1,'762325009',NULL,'Psychotic disorder caused by stimulant (disorder)'),('severe-mental-illness',1,'762327001',NULL,'Psychotic disorder with delusions caused by stimulant (disorder)'),('severe-mental-illness',1,'762507003',NULL,'Psychotic disorder caused by synthetic cathinone (disorder)'),('severe-mental-illness',1,'762509000',NULL,'Psychotic disorder with delusions caused by synthetic cathinone (disorder)'),('severe-mental-illness',1,'765176007',NULL,'Psychosis and severe depression co-occurrent and due to bipolar affective disorder (disorder)'),('severe-mental-illness',1,'7761000119106',NULL,'Psychotic disorder due to amphetamine use (disorder)'),('severe-mental-illness',1,'786120041000132108',NULL,'Psychotic disorder caused by substance (disorder)'),('severe-mental-illness',1,'191498001',NULL,'Drug psychosis NOS (disorder)'),('severe-mental-illness',1,'191524008',NULL,'Organic psychoses NOS (disorder)'),('severe-mental-illness',1,'191683009',NULL,'Psychogenic stupor (disorder)'),('severe-mental-illness',1,'191700002',NULL,'Other specified non-organic psychoses (disorder)'),('severe-mental-illness',1,'268694007',NULL,'[X]Acute polymorphic psychotic disorder without symptoms of schizophrenia (disorder)'),('severe-mental-illness',1,'270901009',NULL,'Schizoaffective disorder, mixed type (disorder)'),('severe-mental-illness',1,'278852008',NULL,'Paranoid-hallucinatory epileptic psychosis (disorder)'),('severe-mental-illness',1,'426321000000107',NULL,'[X]Other schizophrenia (disorder)'),('severe-mental-illness',1,'452061000000102',NULL,'[X]Acute polymorphic psychotic disorder without symptoms of schizophrenia (disorder)'),('severe-mental-illness',1,'470311000000103',NULL,'[X]Other acute and transient psychotic disorders (disorder)'),('severe-mental-illness',1,'4926007',NULL,'Schizophrenia in remission (disorder)'),('severe-mental-illness',1,'54761006',NULL,'Severe depressed bipolar I disorder with psychotic features, mood-congruent (disorder)'),('severe-mental-illness',1,'75122001',NULL,'Inhalant-induced psychotic disorder with delusions (disorder)'),('severe-mental-illness',1,'84760002',NULL,'Schizoaffective disorder, depressive type (disorder)'),('severe-mental-illness',1,'191473002',NULL,'Alcohol amnestic syndrome NOS (disorder)'),('severe-mental-illness',1,'191523002',NULL,'Other specified organic psychoses (disorder)'),('severe-mental-illness',1,'231436002',NULL,'Psychotic episode NOS (disorder)'),('severe-mental-illness',1,'237352005',NULL,'Severe postnatal psychosis (disorder)'),('severe-mental-illness',1,'416340002',NULL,'Late onset schizophrenia (disorder)'),('severe-mental-illness',1,'63649001',NULL,'Cannabis delusional disorder (disorder)'),('severe-mental-illness',1,'191491007',NULL,'Other drug psychoses (disorder)'),('severe-mental-illness',1,'191579000',NULL,'Schizophrenia NOS (disorder)'),('severe-mental-illness',1,'191678001',NULL,'Reactive confusion (disorder)'),('severe-mental-illness',1,'1973000',NULL,'Sedative, hypnotic AND/OR anxiolytic-induced psychotic disorder with delusions (disorder)'),('severe-mental-illness',1,'268624000',NULL,'Acute paranoid reaction (disorder)'),('severe-mental-illness',1,'479991000000101',NULL,'[X]Other acute predominantly delusional psychotic disorders (disorder)'),('severe-mental-illness',1,'589321000000104',NULL,'Organic psychoses NOS (disorder)'),('severe-mental-illness',1,'645451000000101',NULL,'Schizophrenia NOS (disorder)'),('severe-mental-illness',1,'762510005',NULL,'Psychotic disorder with schizophreniform symptoms caused by synthetic cathinone (disorder)'),('severe-mental-illness',1,'191495003',NULL,'Drug-induced depressive state (disorder)'),('severe-mental-illness',1,'191515004',NULL,'Unspecified puerperal psychosis (disorder)'),('severe-mental-illness',1,'191542003',NULL,'Catatonic schizophrenia (disorder)'),('severe-mental-illness',1,'191577003',NULL,'Cenesthopathic schizophrenia (disorder)'),('severe-mental-illness',1,'237351003',NULL,'Mild postnatal psychosis (disorder)'),('severe-mental-illness',1,'238977002',NULL,'Delusional hyperhidrosis (disorder)'),('severe-mental-illness',1,'26472000',NULL,'Paraphrenia (disorder)'),('severe-mental-illness',1,'410341000000107',NULL,'[X]Other schizoaffective disorders (disorder)'),
('severe-mental-illness',1,'50722006',NULL,'PCP delusional disorder (disorder)'),('severe-mental-illness',1,'943071000000104',NULL,'Opioid-induced psychosis (disorder)'),('severe-mental-illness',1,'1087461000000107',NULL,'Late onset substance-induced psychosis (disorder)'),('severe-mental-illness',1,'20385005',NULL,'Opioid-induced psychotic disorder with delusions (disorder)'),('severe-mental-illness',1,'238979004',NULL,'Hyposchemazia (disorder)'),('severe-mental-illness',1,'268612007',NULL,'Senile and presenile organic psychotic conditions (disorder)'),('severe-mental-illness',1,'268618006',NULL,'Other schizophrenia (disorder)'),('severe-mental-illness',1,'35252006',NULL,'Disorganized schizophrenia (disorder)'),('severe-mental-illness',1,'558811000000104',NULL,'Other non-organic psychoses (disorder)'),('severe-mental-illness',1,'63204009',NULL,'Bouff├⌐e d├⌐lirante (disorder)'),('severe-mental-illness',1,'1087501000000107',NULL,'Late onset cannabinoid-induced psychosis (disorder)'),('severe-mental-illness',1,'191499009',NULL,'Transient organic psychoses (disorder)'),('severe-mental-illness',1,'191567000',NULL,'Schizoaffective schizophrenia (disorder)'),('severe-mental-illness',1,'192327003',NULL,'[X]Schizophrenia, unspecified (disorder)'),('severe-mental-illness',1,'192339006',NULL,'[X]Other acute and transient psychotic disorders (disorder)'),('severe-mental-illness',1,'26203008',NULL,'Severe depressed bipolar I disorder with psychotic features, mood-incongruent (disorder)'),('severe-mental-illness',1,'268617001',NULL,'Acute schizophrenic episode (disorder)'),('severe-mental-illness',1,'268695008',NULL,'[X]Other acute predominantly delusional psychotic disorders (disorder)'),('severe-mental-illness',1,'288751000119101',NULL,'Reactive depressive psychosis, single episode (disorder)'),('severe-mental-illness',1,'38368003',NULL,'Schizoaffective disorder, bipolar type (disorder)'),('severe-mental-illness',1,'403595006',NULL,'Pinocchio syndrome (disorder)'),('severe-mental-illness',1,'442891000000100',NULL,'[X]Acute polymorphic psychotic disorder with symptoms of schizophrenia (disorder)'),('severe-mental-illness',1,'551651000000107',NULL,'Other specified organic psychoses (disorder)'),('severe-mental-illness',1,'620141000000103',NULL,'Other reactive psychoses (disorder)'),('severe-mental-illness',1,'943101000000108',NULL,'Cocaine-induced psychosis (disorder)'),('severe-mental-illness',1,'1087481000000103',NULL,'Late onset cocaine-induced psychosis (disorder)'),('severe-mental-illness',1,'191484009',NULL,'Drug-induced paranoia or hallucinatory states (disorder)'),('severe-mental-illness',1,'191526005',NULL,'Schizophrenic disorders (disorder)'),('severe-mental-illness',1,'30491001',NULL,'Cocaine delusional disorder (disorder)'),('severe-mental-illness',1,'33380008',NULL,'Severe manic bipolar I disorder with psychotic features, mood-incongruent (disorder)'),('severe-mental-illness',1,'439911000000108',NULL,'[X]Schizoaffective disorder, unspecified (disorder)'),('severe-mental-illness',1,'558801000000101',NULL,'Other schizophrenia (disorder)'),('severe-mental-illness',1,'623951000000105',NULL,'Alcohol amnestic syndrome NOS (disorder)'),('severe-mental-illness',1,'64731001',NULL,'Severe mixed bipolar I disorder with psychotic features, mood-congruent (disorder)'),('severe-mental-illness',1,'64905009',NULL,'Paranoid schizophrenia (disorder)'),('severe-mental-illness',1,'712824002',NULL,'Acute polymorphic psychotic disorder without symptoms of schizophrenia (disorder)'),('severe-mental-illness',1,'737340007',NULL,'Psychotic disorder caused by synthetic cannabinoid (disorder)'),('severe-mental-illness',1,'762508008',NULL,'Psychotic disorder with hallucinations caused by synthetic cathinone (disorder)'),('severe-mental-illness',1,'1086471000000103',NULL,'Recurrent reactive depressive episodes, severe, with psychosis (disorder)'),('severe-mental-illness',1,'1087491000000101',NULL,'Late onset lysergic acid diethylamide-induced psychosis (disorder)'),('severe-mental-illness',1,'191496002',NULL,'Drug-induced personality disorder (disorder)'),('severe-mental-illness',1,'238974009',NULL,'Delusions of infestation (disorder)'),('severe-mental-illness',1,'589311000000105',NULL,'Other chronic organic psychoses (disorder)'),('severe-mental-illness',1,'755311000000100',NULL,'Non-organic psychosis in remission (disorder)'),('severe-mental-illness',1,'88975006',NULL,'Schizophreniform disorder (disorder)'),('severe-mental-illness',1,'191492000',NULL,'Drug-induced delirium (disorder)'),('severe-mental-illness',1,'191493005',NULL,'Drug-induced dementia (disorder)'),('severe-mental-illness',1,'268691004',NULL,'[X]Other schizophrenia (disorder)'),('severe-mental-illness',1,'307417003',NULL,'Cycloid psychosis (disorder)'),('severe-mental-illness',1,'466791000000100',NULL,'[X]Acute and transient psychotic disorder, unspecified (disorder)'),('severe-mental-illness',1,'558821000000105',NULL,'Non-organic psychosis NOS (disorder)'),('severe-mental-illness',1,'621181000000100',NULL,'Drug psychosis NOS (disorder)'),('severe-mental-illness',1,'712850003',NULL,'Acute polymorphic psychotic disorder co-occurrent with symptoms of schizophrenia (disorder)'),('severe-mental-illness',1,'83746006',NULL,'Chronic schizophrenia (disorder)'),('severe-mental-illness',1,'191494004',NULL,'Drug-induced amnestic syndrome (disorder)'),('severe-mental-illness',1,'231451006',NULL,'Drug-induced intensive care psychosis (disorder)'),('severe-mental-illness',1,'238978007',NULL,'Hyperschemazia (disorder)'),('severe-mental-illness',1,'26025008',NULL,'Residual schizophrenia (disorder)'),('severe-mental-illness',1,'268696009',NULL,'[X]Acute and transient psychotic disorder, unspecified (disorder)'),('severe-mental-illness',1,'470301000000100',NULL,'[X]Schizophrenia, unspecified (disorder)'),('severe-mental-illness',1,'762326005',NULL,'Psychotic disorder with hallucinations caused by stimulant (disorder)'),('severe-mental-illness',1,'943081000000102',NULL,'Cannabis-induced psychosis (disorder)'),('severe-mental-illness',1,'943091000000100',NULL,'Sedative-induced psychosis (disorder)'),('severe-mental-illness',1,'10875004',NULL,'Severe mixed bipolar I disorder with psychotic features, mood-incongruent (disorder)'),('severe-mental-illness',1,'1087511000000109',NULL,'Late onset amphetamine-induced psychosis (disorder)'),('severe-mental-illness',1,'191471000',NULL,'Korsakovs alcoholic psychosis with peripheral neuritis (disorder)'),('severe-mental-illness',1,'191682004',NULL,'Other reactive psychoses (disorder)'),('severe-mental-illness',1,'192345003',NULL,'[X]Schizoaffective disorder, unspecified (disorder)'),('severe-mental-illness',1,'238973003',NULL,'Delusions of parasitosis (disorder)'),('severe-mental-illness',1,'238975005',NULL,'Delusion of foul odor (disorder)'),('severe-mental-illness',1,'551591000000100',NULL,'Unspecified puerperal psychosis (disorder)'),('severe-mental-illness',1,'737225007',NULL,'Secondary psychotic syndrome with hallucinations and delusions (disorder)'),('severe-mental-illness',1,'78640000',NULL,'Severe manic bipolar I disorder with psychotic features, mood-congruent (disorder)'),('severe-mental-illness',1,'943131000000102',NULL,'Hallucinogen-induced psychosis (disorder)'),('severe-mental-illness',1,'111484002',NULL,'Undifferentiated schizophrenia (disorder)'),('severe-mental-illness',1,'191518002',NULL,'Other chronic organic psychoses (disorder)'),('severe-mental-illness',1,'191527001',NULL,'Simple schizophrenia (disorder)'),('severe-mental-illness',1,'192335000',NULL,'[X]Acute polymorphic psychotic disorder with symptoms of schizophrenia (disorder)'),('severe-mental-illness',1,'192344004',NULL,'[X]Other schizoaffective disorders (disorder)'),('severe-mental-illness',1,'247804008',NULL,'Schizophrenic prodrome (disorder)'),('severe-mental-illness',1,'271428004',NULL,'Schizoaffective disorder, manic type (disorder)'),('severe-mental-illness',1,'60401000119104',NULL,'Postpartum psychosis in remission (disorder)'),('severe-mental-illness',1,'624001000000107',NULL,'Other drug psychoses (disorder)'),('severe-mental-illness',1,'111483008',NULL,'Catatonic schizophrenia in remission (disorder)'),('severe-mental-illness',1,'191486006',NULL,'Drug-induced hallucinosis (disorder)'),('severe-mental-illness',1,'191487002',NULL,'Drug-induced paranoia or hallucinatory state NOS (disorder)'),('severe-mental-illness',1,'191538001',NULL,'Acute exacerbation of subchronic hebephrenic schizophrenia (disorder)'),('severe-mental-illness',1,'191540006',NULL,'Hebephrenic schizophrenia in remission (disorder)'),('severe-mental-illness',1,'191543008',NULL,'Unspecified catatonic schizophrenia (disorder)'),('severe-mental-illness',1,'191548004',NULL,'Acute exacerbation of chronic catatonic schizophrenia (disorder)'),('severe-mental-illness',1,'191551006',NULL,'Unspecified paranoid schizophrenia (disorder)'),('severe-mental-illness',1,'31658008',NULL,'Chronic paranoid schizophrenia (disorder)'),('severe-mental-illness',1,'551581000000102',NULL,'Other drug psychoses NOS (disorder)'),('severe-mental-illness',1,'551641000000109',NULL,'Chronic organic psychosis NOS (disorder)'),('severe-mental-illness',1,'71103003',NULL,'Chronic residual schizophrenia (disorder)'),('severe-mental-illness',1,'46721000',NULL,'Psychoactive substance-induced organic personality disorder (disorder)'),('severe-mental-illness',1,'63181006',NULL,'Paranoid schizophrenia in remission (disorder)'),('severe-mental-illness',1,'762345001',NULL,'Mood disorder with depressive symptoms caused by dissociative drug (disorder)'),('severe-mental-illness',1,'762512002',NULL,'Mood disorder with depressive symptoms caused by synthetic cathinone (disorder)'),('severe-mental-illness',1,'8635005',NULL,'Alcohol withdrawal delirium (disorder)'),('severe-mental-illness',1,'8837000',NULL,'Amphetamine delirium (disorder)'),('severe-mental-illness',1,'111480006',NULL,'Psychoactive substance-induced organic dementia (disorder)'),
('severe-mental-illness',1,'12939007',NULL,'Chronic disorganized schizophrenia (disorder)'),('severe-mental-illness',1,'191570001',NULL,'Chronic schizoaffective schizophrenia (disorder)'),('severe-mental-illness',1,'302507002',NULL,'Sedative amnestic disorder (disorder)'),('severe-mental-illness',1,'551611000000108',NULL,'Transient organic psychoses NOS (disorder)'),('severe-mental-illness',1,'68995007',NULL,'Chronic catatonic schizophrenia (disorder)'),('severe-mental-illness',1,'70328006',NULL,'Cocaine delirium (disorder)'),('severe-mental-illness',1,'762506007',NULL,'Delirium caused by synthetic cathinone (disorder)'),('severe-mental-illness',1,'191536002',NULL,'Subchronic hebephrenic schizophrenia (disorder)'),('severe-mental-illness',1,'191554003',NULL,'Acute exacerbation of subchronic paranoid schizophrenia (disorder)'),('severe-mental-illness',1,'39807006',NULL,'Cannabis intoxication delirium (disorder)'),('severe-mental-illness',1,'579811000000105',NULL,'Paranoid schizophrenia NOS (disorder)'),('severe-mental-illness',1,'589341000000106',NULL,'Simple schizophrenia NOS (disorder)'),('severe-mental-illness',1,'589361000000107',NULL,'Unspecified catatonic schizophrenia (disorder)'),('severe-mental-illness',1,'632271000000100',NULL,'Psychotic episode NOS (disorder)'),('severe-mental-illness',1,'633401000000100',NULL,'Unspecified paranoid schizophrenia (disorder)'),('severe-mental-illness',1,'68772007',NULL,'Stauders lethal catatonia (disorder)'),('severe-mental-illness',1,'762342003',NULL,'Mood disorder with depressive symptoms caused by ecstasy type drug (disorder)'),('severe-mental-illness',1,'191522007',NULL,'Chronic organic psychosis NOS (disorder)'),('severe-mental-illness',1,'191531007',NULL,'Acute exacerbation of chronic schizophrenia (disorder)'),('severe-mental-illness',1,'191550007',NULL,'Catatonic schizophrenia NOS (disorder)'),('severe-mental-illness',1,'724675001',NULL,'Psychotic disorder caused by anxiolytic (disorder)'),('severe-mental-illness',1,'762336002',NULL,'Mood disorder with depressive symptoms caused by hallucinogen (disorder)'),('severe-mental-illness',1,'191530008',NULL,'Acute exacerbation of subchronic schizophrenia (disorder)'),('severe-mental-illness',1,'191537006',NULL,'Chronic hebephrenic schizophrenia (disorder)'),('severe-mental-illness',1,'39003006',NULL,'Psychoactive substance-induced organic delirium (disorder)'),('severe-mental-illness',1,'42868002',NULL,'Subchronic catatonic schizophrenia (disorder)'),('severe-mental-illness',1,'645441000000104',NULL,'Other schizophrenia NOS (disorder)'),('severe-mental-illness',1,'724705005',NULL,'Delirium caused by methylenedioxymethamphetamine (disorder)'),('severe-mental-illness',1,'762321000',NULL,'Mood disorder with depressive symptoms caused by opioid (disorder)'),('severe-mental-illness',1,'76566000',NULL,'Subchronic residual schizophrenia (disorder)'),('severe-mental-illness',1,'191528006',NULL,'Unspecified schizophrenia (disorder)'),('severe-mental-illness',1,'191539009',NULL,'Acute exacerbation of chronic hebephrenic schizophrenia (disorder)'),('severe-mental-illness',1,'191555002',NULL,'Acute exacerbation of chronic paranoid schizophrenia (disorder)'),('severe-mental-illness',1,'191569002',NULL,'Subchronic schizoaffective schizophrenia (disorder)'),('severe-mental-illness',1,'301643003',NULL,'Sedative, hypnotic AND/OR anxiolytic-induced persisting amnestic disorder (disorder)'),('severe-mental-illness',1,'31715000',NULL,'PCP delirium (disorder)'),('severe-mental-illness',1,'1089481000000106',NULL,'Cataleptic schizophrenia (disorder)'),('severe-mental-illness',1,'191485005',NULL,'Drug-induced paranoid state (disorder)'),('severe-mental-illness',1,'191521000',NULL,'Other specified chronic organic psychoses (disorder)'),('severe-mental-illness',1,'191541005',NULL,'Hebephrenic schizophrenia NOS (disorder)'),('severe-mental-illness',1,'191575006',NULL,'Schizoaffective schizophrenia NOS (disorder)'),('severe-mental-illness',1,'29599000',NULL,'Chronic undifferentiated schizophrenia (disorder)'),('severe-mental-illness',1,'32875003',NULL,'Inhalant-induced persisting dementia (disorder)'),('severe-mental-illness',1,'39610001',NULL,'Undifferentiated schizophrenia in remission (disorder)'),('severe-mental-illness',1,'441833000',NULL,'Lethal catatonia (disorder)'),('severe-mental-illness',1,'551621000000102',NULL,'Other reactive psychoses NOS (disorder)'),('severe-mental-illness',1,'589381000000103',NULL,'Unspecified schizoaffective schizophrenia (disorder)'),('severe-mental-illness',1,'762324008',NULL,'Delirium caused by stimulant (disorder)'),('severe-mental-illness',1,'762329003',NULL,'Mood disorder with depressive symptoms caused by stimulant (disorder)'),('severe-mental-illness',1,'191514000',NULL,'Other transient organic psychoses (disorder)'),('severe-mental-illness',1,'191534004',NULL,'Simple schizophrenia NOS (disorder)'),('severe-mental-illness',1,'191568005',NULL,'Unspecified schizoaffective schizophrenia (disorder)'),('severe-mental-illness',1,'26847009',NULL,'Chronic schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'268614008',NULL,'Other senile and presenile organic psychoses (disorder)'),('severe-mental-illness',1,'442251000000107',NULL,'[X]Undifferentiated schizophrenia (disorder)'),('severe-mental-illness',1,'551631000000100',NULL,'Other specified chronic organic psychoses (disorder)'),('severe-mental-illness',1,'589301000000108',NULL,'Other transient organic psychoses (disorder)'),('severe-mental-illness',1,'589331000000102',NULL,'Unspecified schizophrenia (disorder)'),('severe-mental-illness',1,'623941000000107',NULL,'Senile or presenile psychoses NOS (disorder)'),('severe-mental-illness',1,'85861002',NULL,'Subchronic undifferentiated schizophrenia (disorder)'),('severe-mental-illness',1,'191469000',NULL,'Senile or presenile psychoses NOS (disorder)'),('severe-mental-illness',1,'191547009',NULL,'Acute exacerbation of subchronic catatonic schizophrenia (disorder)'),('severe-mental-illness',1,'191572009',NULL,'Acute exacerbation of chronic schizoaffective schizophrenia (disorder)'),('severe-mental-illness',1,'191574005',NULL,'Schizoaffective schizophrenia in remission (disorder)'),('severe-mental-illness',1,'191578008',NULL,'Other schizophrenia NOS (disorder)'),('severe-mental-illness',1,'191685002',NULL,'Other reactive psychoses NOS (disorder)'),('severe-mental-illness',1,'192322009',NULL,'[X]Undifferentiated schizophrenia (disorder)'),('severe-mental-illness',1,'36158005',NULL,'Schizophreniform disorder with good prognostic features (disorder)'),('severe-mental-illness',1,'55736003',NULL,'Schizophreniform disorder without good prognostic features (disorder)'),('severe-mental-illness',1,'724674002',NULL,'Psychotic disorder caused by hypnotic (disorder)'),('severe-mental-illness',1,'724690002',NULL,'Mood disorder with depressive symptoms caused by cocaine (disorder)'),('severe-mental-illness',1,'724716003',NULL,'Delirium caused by ketamine (disorder)'),('severe-mental-illness',1,'762339009',NULL,'Mood disorder with depressive symptoms caused by volatile inhalant (disorder)'),('severe-mental-illness',1,'191497006',NULL,'Other drug psychoses NOS (disorder)'),('severe-mental-illness',1,'191517007',NULL,'Transient organic psychoses NOS (disorder)'),('severe-mental-illness',1,'191535003',NULL,'Unspecified hebephrenic schizophrenia (disorder)'),('severe-mental-illness',1,'191557005',NULL,'Paranoid schizophrenia NOS (disorder)'),('severe-mental-illness',1,'191571002',NULL,'Acute exacerbation of subchronic schizoaffective schizophrenia (disorder)'),('severe-mental-illness',1,'27387000',NULL,'Subchronic disorganized schizophrenia (disorder)'),('severe-mental-illness',1,'281004',NULL,'Dementia associated with alcoholism (disorder)'),('severe-mental-illness',1,'31373002',NULL,'Disorganized schizophrenia in remission (disorder)'),('severe-mental-illness',1,'38295006',NULL,'Involutional paraphrenia (disorder)'),('severe-mental-illness',1,'621261000000102',NULL,'Other specified non-organic psychoses (disorder)'),('severe-mental-illness',1,'623991000000102',NULL,'Drug-induced paranoia or hallucinatory state NOS (disorder)'),('severe-mental-illness',1,'724676000',NULL,'Mood disorder with depressive symptoms caused by sedative (disorder)'),('severe-mental-illness',1,'724678004',NULL,'Mood disorder with depressive symptoms caused by anxiolytic (disorder)'),('severe-mental-illness',1,'724717007',NULL,'Delirium caused by dissociative drug (disorder)'),('severe-mental-illness',1,'16990005',NULL,'Subchronic schizophrenia (disorder)'),('severe-mental-illness',1,'51133006',NULL,'Residual schizophrenia in remission (disorder)'),('severe-mental-illness',1,'544861000000109',NULL,'Other senile and presenile organic psychoses (disorder)'),('severe-mental-illness',1,'589351000000109',NULL,'Hebephrenic schizophrenia NOS (disorder)'),('severe-mental-illness',1,'633351000000106',NULL,'Unspecified hebephrenic schizophrenia (disorder)'),('severe-mental-illness',1,'633391000000103',NULL,'Catatonic schizophrenia NOS (disorder)'),('severe-mental-illness',1,'645431000000108',NULL,'Schizoaffective schizophrenia NOS (disorder)'),('severe-mental-illness',1,'724673008',NULL,'Psychotic disorder caused by sedative (disorder)'),('severe-mental-illness',1,'724677009',NULL,'Mood disorder with depressive symptoms caused by hypnotic (disorder)'),('severe-mental-illness',1,'79866005',NULL,'Subchronic paranoid schizophrenia (disorder)'),('severe-mental-illness',1,'59651006',NULL,'Sedative, hypnotic AND/OR anxiolytic-induced persisting dementia (disorder)'),('severe-mental-illness',1,'41521002',NULL,'Subchronic paranoid schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'5444000',NULL,'Sedative, hypnotic AND/OR anxiolytic intoxication delirium (disorder)'),('severe-mental-illness',1,'551601000000106',NULL,'Other transient organic psychoses NOS (disorder)'),
('severe-mental-illness',1,'7025000',NULL,'Subchronic undifferentiated schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'86817004',NULL,'Subchronic catatonic schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'111482003',NULL,'Subchronic schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'30336007',NULL,'Chronic residual schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'17435002',NULL,'Chronic paranoid schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'14291003',NULL,'Subchronic disorganized schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'21894002',NULL,'Chronic catatonic schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'70814008',NULL,'Subchronic residual schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'191516003',NULL,'Other transient organic psychoses NOS (disorder)'),('severe-mental-illness',1,'35218008',NULL,'Chronic disorganized schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'737339005',NULL,'Delirium caused by synthetic cannabinoid (disorder)'),('severe-mental-illness',1,'79204003',NULL,'Chronic undifferentiated schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'191563001',NULL,'Acute exacerbation of subchronic latent schizophrenia (disorder)'),('severe-mental-illness',1,'13746004',NULL,'Bipolar disorder (disorder)'),('severe-mental-illness',1,'12969000',NULL,'Severe bipolar II disorder, most recent episode major depressive, in full remission (disorder)'),('severe-mental-illness',1,'13313007',NULL,'Mild bipolar disorder (disorder)'),('severe-mental-illness',1,'16506000',NULL,'Mixed bipolar I disorder (disorder)'),('severe-mental-illness',1,'191618007',NULL,'Bipolar affective disorder, current episode manic (disorder)'),('severe-mental-illness',1,'191627008',NULL,'Bipolar affective disorder, current episode depression (disorder)'),('severe-mental-illness',1,'191636007',NULL,'Mixed bipolar affective disorder (disorder)'),('severe-mental-illness',1,'191646009',NULL,'Unspecified bipolar affective disorder (disorder)'),('severe-mental-illness',1,'191656008',NULL,'Other and unspecified manic-depressive psychoses (disorder)'),('severe-mental-illness',1,'192356003',NULL,'[X]Bipolar affective disorder, current episode manic without psychotic symptoms (disorder)'),('severe-mental-illness',1,'192357007',NULL,'[X]Bipolar affective disorder, current episode manic with psychotic symptoms (disorder)'),('severe-mental-illness',1,'192358002',NULL,'[X]Bipolar affective disorder, current episode mild or moderate depression (disorder)'),('severe-mental-illness',1,'192359005',NULL,'[X]Bipolar affective disorder, current episode severe depression without psychotic symptoms (disorder)'),('severe-mental-illness',1,'192363003',NULL,'[X]Bipolar affective disorder, currently in remission (disorder)'),('severe-mental-illness',1,'192365005',NULL,'[X]Bipolar affective disorder, unspecified (disorder)'),('severe-mental-illness',1,'231444002',NULL,'Organic bipolar disorder (disorder)'),('severe-mental-illness',1,'268701002',NULL,'[X]Other bipolar affective disorders (disorder)'),('severe-mental-illness',1,'30520009',NULL,'Severe bipolar II disorder, most recent episode major depressive with psychotic features (disorder)'),('severe-mental-illness',1,'31446002',NULL,'Bipolar I disorder, most recent episode hypomanic (disorder)'),('severe-mental-illness',1,'35722002',NULL,'Severe bipolar II disorder, most recent episode major depressive, in remission (disorder)'),('severe-mental-illness',1,'35846004',NULL,'Moderate bipolar II disorder, most recent episode major depressive (disorder)'),('severe-mental-illness',1,'371596008',NULL,'Bipolar I disorder (disorder)'),('severe-mental-illness',1,'371600003',NULL,'Severe bipolar disorder (disorder)'),('severe-mental-illness',1,'38368003',NULL,'Schizoaffective disorder, bipolar type (disorder)'),('severe-mental-illness',1,'417731000000103',NULL,'[X]Bipolar affective disorder, unspecified (disorder)'),('severe-mental-illness',1,'41836007',NULL,'Bipolar disorder in full remission (disorder)'),('severe-mental-illness',1,'426091000000108',NULL,'[X]Other bipolar affective disorders (disorder)'),('severe-mental-illness',1,'431661000000104',NULL,'[X]Bipolar affective disorder, current episode manic with psychotic symptoms (disorder)'),('severe-mental-illness',1,'443561000000100',NULL,'[X]Bipolar affective disorder, current episode manic without psychotic symptoms (disorder)'),('severe-mental-illness',1,'4441000',NULL,'Severe bipolar disorder with psychotic features (disorder)'),('severe-mental-illness',1,'454161000000105',NULL,'[X]Bipolar affective disorder, currently in remission (disorder)'),('severe-mental-illness',1,'465911000000102',NULL,'[X]Bipolar affective disorder, current episode severe depression without psychotic symptoms (disorder)'),('severe-mental-illness',1,'467121000000100',NULL,'[X]Bipolar affective disorder, current episode mild or moderate depression (disorder)'),('severe-mental-illness',1,'53049002',NULL,'Severe bipolar disorder without psychotic features (disorder)'),('severe-mental-illness',1,'5703000',NULL,'Bipolar disorder in partial remission (disorder)'),('severe-mental-illness',1,'602491000000105',NULL,'Unspecified bipolar affective disorder (disorder)'),('severe-mental-illness',1,'613621000000102',NULL,'Other and unspecified manic-depressive psychoses (disorder)'),('severe-mental-illness',1,'67002003',NULL,'Severe bipolar II disorder, most recent episode major depressive, in partial remission (disorder)'),('severe-mental-illness',1,'75360000',NULL,'Bipolar I disorder, single manic episode, in remission (disorder)'),('severe-mental-illness',1,'76105009',NULL,'Cyclothymia (disorder)'),('severe-mental-illness',1,'767631007',NULL,'Bipolar disorder, most recent episode depression (disorder)'),('severe-mental-illness',1,'767632000',NULL,'Bipolar disorder, most recent episode manic (disorder)'),('severe-mental-illness',1,'79584002',NULL,'Moderate bipolar disorder (disorder)'),('severe-mental-illness',1,'83225003',NULL,'Bipolar II disorder (disorder)'),('severe-mental-illness',1,'85248005',NULL,'Bipolar disorder in remission (disorder)'),('severe-mental-illness',1,'9340000',NULL,'Bipolar I disorder, single manic episode (disorder)'),('severe-mental-illness',1,'191638008',NULL,'Mixed bipolar affective disorder, mild (disorder)'),('severe-mental-illness',1,'191648005',NULL,'Unspecified bipolar affective disorder, mild (disorder)'),('severe-mental-illness',1,'26530004',NULL,'Severe bipolar disorder with psychotic features, mood-incongruent (disorder)'),('severe-mental-illness',1,'530311000000107',NULL,'Bipolar affective disorder, currently depressed, severe, without mention of psychosis (disorder)'),('severe-mental-illness',1,'602561000000100',NULL,'Unspecified bipolar affective disorder, in full remission (disorder)'),('severe-mental-illness',1,'615921000000105',NULL,'Bipolar affective disorder, currently manic, in partial or unspecified remission (disorder)'),('severe-mental-illness',1,'624011000000109',NULL,'Other and unspecified manic-depressive psychoses NOS (disorder)'),('severe-mental-illness',1,'66631006',NULL,'Moderate depressed bipolar I disorder (disorder)'),('severe-mental-illness',1,'73471000',NULL,'Bipolar I disorder, most recent episode mixed with catatonic features (disorder)'),('severe-mental-illness',1,'14495005',NULL,'Severe bipolar I disorder, single manic episode without psychotic features (disorder)'),('severe-mental-illness',1,'191623007',NULL,'Bipolar affective disorder, currently manic, severe, with psychosis (disorder)'),('severe-mental-illness',1,'191626004',NULL,'Bipolar affective disorder, currently manic, NOS (disorder)'),('severe-mental-illness',1,'191660006',NULL,'Other mixed manic-depressive psychoses (disorder)'),('severe-mental-illness',1,'48937005',NULL,'Bipolar II disorder, most recent episode hypomanic (disorder)'),('severe-mental-illness',1,'602521000000108',NULL,'Unspecified bipolar affective disorder, mild (disorder)'),('severe-mental-illness',1,'613511000000109',NULL,'Bipolar affective disorder, currently depressed, NOS (disorder)'),('severe-mental-illness',1,'613631000000100',NULL,'Unspecified manic-depressive psychoses (disorder)'),('severe-mental-illness',1,'65042007',NULL,'Bipolar I disorder, most recent episode mixed with postpartum onset (disorder)'),('severe-mental-illness',1,'767635003',NULL,'Bipolar I disorder, most recent episode manic (disorder)'),('severe-mental-illness',1,'767636002',NULL,'Bipolar I disorder, most recent episode depression (disorder)'),('severe-mental-illness',1,'10981006',NULL,'Severe mixed bipolar I disorder with psychotic features (disorder)'),('severe-mental-illness',1,'1196001',NULL,'Chronic bipolar II disorder, most recent episode major depressive (disorder)'),('severe-mental-illness',1,'191624001',NULL,'Bipolar affective disorder, currently manic, in partial or unspecified remission (disorder)'),('severe-mental-illness',1,'191630001',NULL,'Bipolar affective disorder, currently depressed, moderate (disorder)'),('severe-mental-illness',1,'21900002',NULL,'Bipolar I disorder, most recent episode depressed with catatonic features (disorder)'),('severe-mental-illness',1,'371604007',NULL,'Severe bipolar II disorder (disorder)'),('severe-mental-illness',1,'46229002',NULL,'Severe mixed bipolar I disorder without psychotic features (disorder)'),('severe-mental-illness',1,'49512000',NULL,'Depressed bipolar I disorder in partial remission (disorder)'),('severe-mental-illness',1,'51637008',NULL,'Chronic bipolar I disorder, most recent episode depressed (disorder)'),('severe-mental-illness',1,'530301000000105',NULL,'Bipolar affective disorder, currently manic, severe, without mention of psychosis (disorder)'),
('severe-mental-illness',1,'589391000000101',NULL,'Unspecified affective personality disorder (disorder)'),('severe-mental-illness',1,'615931000000107',NULL,'Bipolar affective disorder, currently manic, NOS (disorder)'),('severe-mental-illness',1,'623971000000101',NULL,'Unspecified bipolar affective disorder, NOS (disorder)'),('severe-mental-illness',1,'68569003',NULL,'Manic bipolar I disorder (disorder)'),('severe-mental-illness',1,'70546001',NULL,'Severe bipolar disorder with psychotic features, mood-congruent (disorder)'),('severe-mental-illness',1,'191619004',NULL,'Bipolar affective disorder, currently manic, unspecified (disorder)'),('severe-mental-illness',1,'191650002',NULL,'Unspecified bipolar affective disorder, severe, without mention of psychosis (disorder)'),('severe-mental-illness',1,'20960007',NULL,'Severe bipolar II disorder, most recent episode major depressive with psychotic features, mood-incongruent (disorder)'),('severe-mental-illness',1,'307525004',NULL,'Other manic-depressive psychos (disorder)'),('severe-mental-illness',1,'30935000',NULL,'Manic bipolar I disorder in full remission (disorder)'),('severe-mental-illness',1,'3530005',NULL,'Bipolar I disorder, single manic episode, in full remission (disorder)'),('severe-mental-illness',1,'40926005',NULL,'Moderate mixed bipolar I disorder (disorder)'),('severe-mental-illness',1,'55516002',NULL,'Bipolar I disorder, most recent episode manic with postpartum onset (disorder)'),('severe-mental-illness',1,'59617007',NULL,'Severe depressed bipolar I disorder with psychotic features (disorder)'),('severe-mental-illness',1,'87203005',NULL,'Bipolar I disorder, most recent episode depressed with postpartum onset (disorder)'),('severe-mental-illness',1,'133091000119105',NULL,'Rapid cycling bipolar I disorder (disorder)'),('severe-mental-illness',1,'191632009',NULL,'Bipolar affective disorder, currently depressed, severe, with psychosis (disorder)'),('severe-mental-illness',1,'191661005',NULL,'Other and unspecified manic-depressive psychoses NOS (disorder)'),('severe-mental-illness',1,'192362008',NULL,'Bipolar affective disorder , current episode mixed (disorder)'),('severe-mental-illness',1,'271000119101',NULL,'Severe mixed bipolar I disorder (disorder)'),('severe-mental-illness',1,'29929003',NULL,'Bipolar I disorder, most recent episode depressed with atypical features (disorder)'),('severe-mental-illness',1,'36583000',NULL,'Mixed bipolar I disorder in partial remission (disorder)'),('severe-mental-illness',1,'41552001',NULL,'Mild bipolar I disorder, single manic episode (disorder)'),('severe-mental-illness',1,'43769008',NULL,'Mild mixed bipolar I disorder (disorder)'),('severe-mental-illness',1,'13581000',NULL,'Severe bipolar I disorder, single manic episode with psychotic features, mood-congruent (disorder)'),('severe-mental-illness',1,'16295005',NULL,'Bipolar II disorder, most recent episode major depressive (disorder)'),('severe-mental-illness',1,'191629006',NULL,'Bipolar affective disorder, currently depressed, mild (disorder)'),('severe-mental-illness',1,'22121000',NULL,'Depressed bipolar I disorder in full remission (disorder)'),('severe-mental-illness',1,'35481005',NULL,'Mixed bipolar I disorder in remission (disorder)'),('severe-mental-illness',1,'41832009',NULL,'Severe bipolar I disorder, single manic episode with psychotic features (disorder)'),('severe-mental-illness',1,'602541000000101',NULL,'Unspecified bipolar affective disorder, severe, with psychosis (disorder)'),('severe-mental-illness',1,'615951000000100',NULL,'Bipolar affective disorder, currently depressed, in partial or unspecified remission (disorder)'),('severe-mental-illness',1,'63249007',NULL,'Manic bipolar I disorder in partial remission (disorder)'),('severe-mental-illness',1,'633731000000103',NULL,'Bipolar affective disorder, currently manic, unspecified (disorder)'),('severe-mental-illness',1,'702251000000106',NULL,'Other manic-depressive psychos (disorder)'),('severe-mental-illness',1,'767633005',NULL,'Bipolar affective disorder, most recent episode mixed (disorder)'),('severe-mental-illness',1,'81319007',NULL,'Severe bipolar II disorder, most recent episode major depressive without psychotic features (disorder)'),('severe-mental-illness',1,'86058007',NULL,'Severe bipolar I disorder, single manic episode with psychotic features, mood-incongruent (disorder)'),('severe-mental-illness',1,'87950005',NULL,'Bipolar I disorder, single manic episode with catatonic features (disorder)'),('severe-mental-illness',1,'111485001',NULL,'Mixed bipolar I disorder in full remission (disorder)'),('severe-mental-illness',1,'191653000',NULL,'Unspecified bipolar affective disorder, in full remission (disorder)'),('severe-mental-illness',1,'45479006',NULL,'Manic bipolar I disorder in remission (disorder)'),('severe-mental-illness',1,'589401000000103',NULL,'Affective personality disorder NOS (disorder)'),('severe-mental-illness',1,'602531000000105',NULL,'Unspecified bipolar affective disorder, moderate (disorder)'),('severe-mental-illness',1,'613611000000108',NULL,'Unspecified bipolar affective disorder, severe, without mention of psychosis (disorder)'),('severe-mental-illness',1,'615941000000103',NULL,'Bipolar affective disorder, currently depressed, unspecified (disorder)'),('severe-mental-illness',1,'698946008',NULL,'Cyclothymia in remission (disorder)'),('severe-mental-illness',1,'75752004',NULL,'Bipolar I disorder, most recent episode depressed with melancholic features (disorder)'),('severe-mental-illness',1,'191622002',NULL,'Bipolar affective disorder, currently manic, severe, without mention of psychosis (disorder)'),('severe-mental-illness',1,'191625000',NULL,'Bipolar affective disorder, currently manic, in full remission (disorder)'),('severe-mental-illness',1,'191631002',NULL,'Bipolar affective disorder, currently depressed, severe, without mention of psychosis (disorder)'),('severe-mental-illness',1,'191633004',NULL,'Bipolar affective disorder, currently depressed, in partial or unspecified remission (disorder)'),('severe-mental-illness',1,'191635006',NULL,'Bipolar affective disorder, currently depressed, NOS (disorder)'),('severe-mental-illness',1,'191649002',NULL,'Unspecified bipolar affective disorder, moderate (disorder)'),('severe-mental-illness',1,'191651003',NULL,'Unspecified bipolar affective disorder, severe, with psychosis (disorder)'),('severe-mental-illness',1,'371599001',NULL,'Severe bipolar I disorder (disorder (disorder)'),('severe-mental-illness',1,'53607008',NULL,'Depressed bipolar I disorder in remission (disorder)'),('severe-mental-illness',1,'602551000000103',NULL,'Unspecified bipolar affective disorder, in partial or unspecified remission (disorder)'),('severe-mental-illness',1,'61771000119106',NULL,'Bipolar II disorder, most recent episode rapid cycling (disorder)'),('severe-mental-illness',1,'1499003',NULL,'Bipolar I disorder, single manic episode with postpartum onset (disorder)'),('severe-mental-illness',1,'17782008',NULL,'Bipolar I disorder, most recent episode manic with catatonic features (disorder)'),('severe-mental-illness',1,'191620005',NULL,'Bipolar affective disorder, currently manic, mild (disorder)'),('severe-mental-illness',1,'191755004',NULL,'Affective personality disorder NOS (disorder)'),('severe-mental-illness',1,'19300006',NULL,'Severe bipolar II disorder, most recent episode major depressive with psychotic features, mood-congruent (disorder)'),('severe-mental-illness',1,'49468007',NULL,'Depressed bipolar I disorder (disorder)'),('severe-mental-illness',1,'61403008',NULL,'Severe depressed bipolar I disorder without psychotic features (disorder)'),('severe-mental-illness',1,'191647000',NULL,'Unspecified bipolar affective disorder, unspecified (disorder)'),('severe-mental-illness',1,'191654006',NULL,'Unspecified bipolar affective disorder, NOS (disorder)'),('severe-mental-illness',1,'191657004',NULL,'Unspecified manic-depressive psychoses (disorder)'),('severe-mental-illness',1,'191752001',NULL,'Unspecified affective personality disorder (disorder)'),('severe-mental-illness',1,'28663008',NULL,'Severe manic bipolar I disorder with psychotic features (disorder)'),('severe-mental-illness',1,'613641000000109',NULL,'Other mixed manic-depressive psychoses (disorder)'),('severe-mental-illness',1,'71294008',NULL,'Mild bipolar II disorder, most recent episode major depressive (disorder)'),('severe-mental-illness',1,'191621009',NULL,'Bipolar affective disorder, currently manic, moderate (disorder)'),('severe-mental-illness',1,'191634005',NULL,'Bipolar affective disorder, currently depressed, in full remission (disorder)'),('severe-mental-illness',1,'191652005',NULL,'Unspecified bipolar affective disorder, in partial or unspecified remission (disorder)'),('severe-mental-illness',1,'71984005',NULL,'Mild manic bipolar I disorder (disorder)'),('severe-mental-illness',1,'723903001',NULL,'Bipolar type I disorder currently in full remission (disorder)'),('severe-mental-illness',1,'723905008',NULL,'Bipolar type II disorder currently in full remission (disorder)'),('severe-mental-illness',1,'74686005',NULL,'Mild depressed bipolar I disorder (disorder)'),('severe-mental-illness',1,'765176007',NULL,'Psychosis and severe depression co-occurrent and due to bipolar affective disorder (disorder)'),('severe-mental-illness',1,'78269000',NULL,'Bipolar I disorder, single manic episode, in partial remission (disorder)'),('severe-mental-illness',1,'162004',NULL,'Severe manic bipolar I disorder without psychotic features (disorder)'),('severe-mental-illness',1,'191628003',NULL,'Bipolar affective disorder, currently depressed, unspecified (disorder)'),('severe-mental-illness',1,'191643001',NULL,'Mixed bipolar affective disorder, in full remission (disorder)'),('severe-mental-illness',1,'602511000000102',NULL,'Unspecified bipolar affective disorder, unspecified (disorder)'),('severe-mental-illness',1,'82998009',NULL,'Moderate manic bipolar I disorder (disorder)'),
('severe-mental-illness',1,'54761006',NULL,'Severe depressed bipolar I disorder with psychotic features, mood-congruent (disorder)'),('severe-mental-illness',1,'191642006',NULL,'Mixed bipolar affective disorder, in partial or unspecified remission (disorder)'),('severe-mental-illness',1,'10875004',NULL,'Severe mixed bipolar I disorder with psychotic features, mood-incongruent (disorder)'),('severe-mental-illness',1,'191641004',NULL,'Mixed bipolar affective disorder, severe, with psychosis (disorder)'),('severe-mental-illness',1,'602481000000108',NULL,'Mixed bipolar affective disorder, NOS (disorder)'),('severe-mental-illness',1,'78640000',NULL,'Severe manic bipolar I disorder with psychotic features, mood-congruent (disorder)'),('severe-mental-illness',1,'191644007',NULL,'Mixed bipolar affective disorder, NOS (disorder)'),('severe-mental-illness',1,'23741000119105',NULL,'Severe manic bipolar I disorder (disorder)'),('severe-mental-illness',1,'34315001',NULL,'Bipolar II disorder, most recent episode major depressive with melancholic features (disorder)'),('severe-mental-illness',1,'602471000000106',NULL,'Mixed bipolar affective disorder, in partial or unspecified remission (disorder)'),('severe-mental-illness',1,'760721000000109',NULL,'Mixed bipolar affective disorder, in partial remission (disorder)'),('severe-mental-illness',1,'26203008',NULL,'Severe depressed bipolar I disorder with psychotic features, mood-incongruent (disorder)'),('severe-mental-illness',1,'191640003',NULL,'Mixed bipolar affective disorder, severe, without mention of psychosis (disorder)'),('severe-mental-illness',1,'22407005',NULL,'Bipolar II disorder, most recent episode major depressive with catatonic features (disorder)'),('severe-mental-illness',1,'28884001',NULL,'Moderate bipolar I disorder, single manic episode (disorder)'),('severe-mental-illness',1,'613581000000102',NULL,'Mixed bipolar affective disorder, unspecified (disorder)'),('severe-mental-illness',1,'191637003',NULL,'Mixed bipolar affective disorder, unspecified (disorder)'),('severe-mental-illness',1,'191639000',NULL,'Mixed bipolar affective disorder, moderate (disorder)'),('severe-mental-illness',1,'30687003',NULL,'Bipolar II disorder, most recent episode major depressive with postpartum onset (disorder)'),('severe-mental-illness',1,'33380008',NULL,'Severe manic bipolar I disorder with psychotic features, mood-incongruent (disorder)'),('severe-mental-illness',1,'43568002',NULL,'Bipolar II disorder, most recent episode major depressive with atypical features (disorder)'),('severe-mental-illness',1,'64731001',NULL,'Severe mixed bipolar I disorder with psychotic features, mood-congruent (disorder)'),('severe-mental-illness',1,'261000119107',NULL,'Severe depressed bipolar I disorder (disorder)'),('severe-mental-illness',1,'764591000000108',NULL,'Mixed bipolar affective disorder, severe (disorder)'),('severe-mental-illness',1,'529851000000108',NULL,'Mixed bipolar affective disorder, severe, without mention of psychosis (disorder)'),('severe-mental-illness',1,'58214004',NULL,'Schizophrenia (disorder)'),('severe-mental-illness',1,'111484002',NULL,'Undifferentiated schizophrenia (disorder)'),('severe-mental-illness',1,'191526005',NULL,'Schizophrenic disorders (disorder)'),('severe-mental-illness',1,'191527001',NULL,'Simple schizophrenia (disorder)'),('severe-mental-illness',1,'191542003',NULL,'Catatonic schizophrenia (disorder)'),('severe-mental-illness',1,'191577003',NULL,'Cenesthopathic schizophrenia (disorder)'),('severe-mental-illness',1,'191579000',NULL,'Schizophrenia NOS (disorder)'),('severe-mental-illness',1,'192327003',NULL,'[X]Schizophrenia, unspecified (disorder)'),('severe-mental-illness',1,'247804008',NULL,'Schizophrenic prodrome (disorder)'),('severe-mental-illness',1,'26025008',NULL,'Residual schizophrenia (disorder)'),('severe-mental-illness',1,'26472000',NULL,'Paraphrenia (disorder)'),('severe-mental-illness',1,'268617001',NULL,'Acute schizophrenic episode (disorder)'),('severe-mental-illness',1,'268618006',NULL,'Other schizophrenia (disorder)'),('severe-mental-illness',1,'268691004',NULL,'[X]Other schizophrenia (disorder)'),('severe-mental-illness',1,'35252006',NULL,'Disorganized schizophrenia (disorder)'),('severe-mental-illness',1,'416340002',NULL,'Late onset schizophrenia (disorder)'),('severe-mental-illness',1,'426321000000107',NULL,'[X]Other schizophrenia (disorder)'),('severe-mental-illness',1,'470301000000100',NULL,'[X]Schizophrenia, unspecified (disorder)'),('severe-mental-illness',1,'4926007',NULL,'Schizophrenia in remission (disorder)'),('severe-mental-illness',1,'558801000000101',NULL,'Other schizophrenia (disorder)'),('severe-mental-illness',1,'645451000000101',NULL,'Schizophrenia NOS (disorder)'),('severe-mental-illness',1,'64905009',NULL,'Paranoid schizophrenia (disorder)'),('severe-mental-illness',1,'83746006',NULL,'Chronic schizophrenia (disorder)'),('severe-mental-illness',1,'1089481000000106',NULL,'Cataleptic schizophrenia (disorder)'),('severe-mental-illness',1,'191541005',NULL,'Hebephrenic schizophrenia NOS (disorder)'),('severe-mental-illness',1,'29599000',NULL,'Chronic undifferentiated schizophrenia (disorder)'),('severe-mental-illness',1,'39610001',NULL,'Undifferentiated schizophrenia in remission (disorder)'),('severe-mental-illness',1,'441833000',NULL,'Lethal catatonia (disorder)'),('severe-mental-illness',1,'16990005',NULL,'Subchronic schizophrenia (disorder)'),('severe-mental-illness',1,'51133006',NULL,'Residual schizophrenia in remission (disorder)'),('severe-mental-illness',1,'589351000000109',NULL,'Hebephrenic schizophrenia NOS (disorder)'),('severe-mental-illness',1,'633351000000106',NULL,'Unspecified hebephrenic schizophrenia (disorder)'),('severe-mental-illness',1,'633391000000103',NULL,'Catatonic schizophrenia NOS (disorder)'),('severe-mental-illness',1,'79866005',NULL,'Subchronic paranoid schizophrenia (disorder)'),('severe-mental-illness',1,'191534004',NULL,'Simple schizophrenia NOS (disorder)'),('severe-mental-illness',1,'26847009',NULL,'Chronic schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'442251000000107',NULL,'[X]Undifferentiated schizophrenia (disorder)'),('severe-mental-illness',1,'589331000000102',NULL,'Unspecified schizophrenia (disorder)'),('severe-mental-illness',1,'85861002',NULL,'Subchronic undifferentiated schizophrenia (disorder)'),('severe-mental-illness',1,'111483008',NULL,'Catatonic schizophrenia in remission (disorder)'),('severe-mental-illness',1,'191538001',NULL,'Acute exacerbation of subchronic hebephrenic schizophrenia (disorder)'),('severe-mental-illness',1,'191540006',NULL,'Hebephrenic schizophrenia in remission (disorder)'),('severe-mental-illness',1,'191543008',NULL,'Unspecified catatonic schizophrenia (disorder)'),('severe-mental-illness',1,'191548004',NULL,'Acute exacerbation of chronic catatonic schizophrenia (disorder)'),('severe-mental-illness',1,'191551006',NULL,'Unspecified paranoid schizophrenia (disorder)'),('severe-mental-illness',1,'31658008',NULL,'Chronic paranoid schizophrenia (disorder)'),('severe-mental-illness',1,'71103003',NULL,'Chronic residual schizophrenia (disorder)'),('severe-mental-illness',1,'63181006',NULL,'Paranoid schizophrenia in remission (disorder)'),('severe-mental-illness',1,'191547009',NULL,'Acute exacerbation of subchronic catatonic schizophrenia (disorder)'),('severe-mental-illness',1,'191578008',NULL,'Other schizophrenia NOS (disorder)'),('severe-mental-illness',1,'192322009',NULL,'[X]Undifferentiated schizophrenia (disorder)'),('severe-mental-illness',1,'191536002',NULL,'Subchronic hebephrenic schizophrenia (disorder)'),('severe-mental-illness',1,'191554003',NULL,'Acute exacerbation of subchronic paranoid schizophrenia (disorder)'),('severe-mental-illness',1,'579811000000105',NULL,'Paranoid schizophrenia NOS (disorder)'),('severe-mental-illness',1,'589341000000106',NULL,'Simple schizophrenia NOS (disorder)'),('severe-mental-illness',1,'589361000000107',NULL,'Unspecified catatonic schizophrenia (disorder)'),('severe-mental-illness',1,'633401000000100',NULL,'Unspecified paranoid schizophrenia (disorder)'),('severe-mental-illness',1,'68772007',NULL,'Stauders lethal catatonia (disorder)'),('severe-mental-illness',1,'191531007',NULL,'Acute exacerbation of chronic schizophrenia (disorder)'),('severe-mental-illness',1,'191550007',NULL,'Catatonic schizophrenia NOS (disorder)'),('severe-mental-illness',1,'191528006',NULL,'Unspecified schizophrenia (disorder)'),('severe-mental-illness',1,'191539009',NULL,'Acute exacerbation of chronic hebephrenic schizophrenia (disorder)'),('severe-mental-illness',1,'191555002',NULL,'Acute exacerbation of chronic paranoid schizophrenia (disorder)'),('severe-mental-illness',1,'12939007',NULL,'Chronic disorganized schizophrenia (disorder)'),('severe-mental-illness',1,'68995007',NULL,'Chronic catatonic schizophrenia (disorder)'),('severe-mental-illness',1,'191530008',NULL,'Acute exacerbation of subchronic schizophrenia (disorder)'),('severe-mental-illness',1,'191537006',NULL,'Chronic hebephrenic schizophrenia (disorder)'),('severe-mental-illness',1,'42868002',NULL,'Subchronic catatonic schizophrenia (disorder)'),('severe-mental-illness',1,'645441000000104',NULL,'Other schizophrenia NOS (disorder)'),('severe-mental-illness',1,'76566000',NULL,'Subchronic residual schizophrenia (disorder)'),('severe-mental-illness',1,'191535003',NULL,'Unspecified hebephrenic schizophrenia (disorder)'),('severe-mental-illness',1,'191557005',NULL,'Paranoid schizophrenia NOS (disorder)'),('severe-mental-illness',1,'27387000',NULL,'Subchronic disorganized schizophrenia (disorder)'),('severe-mental-illness',1,'31373002',NULL,'Disorganized schizophrenia in remission (disorder)'),('severe-mental-illness',1,'38295006',NULL,'Involutional paraphrenia (disorder)'),('severe-mental-illness',1,'86817004',NULL,'Subchronic catatonic schizophrenia with acute exacerbations (disorder)'),
('severe-mental-illness',1,'7025000',NULL,'Subchronic undifferentiated schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'17435002',NULL,'Chronic paranoid schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'41521002',NULL,'Subchronic paranoid schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'111482003',NULL,'Subchronic schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'14291003',NULL,'Subchronic disorganized schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'30336007',NULL,'Chronic residual schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'21894002',NULL,'Chronic catatonic schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'70814008',NULL,'Subchronic residual schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'35218008',NULL,'Chronic disorganized schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'79204003',NULL,'Chronic undifferentiated schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'191563001',NULL,'Acute exacerbation of subchronic latent schizophrenia (disorder)');
INSERT INTO #codessnomed
VALUES ('covid-vaccine-declined',1,'1324721000000108',NULL,'Severe acute respiratory syndrome coronavirus 2 vaccination dose declined (situation)'),('covid-vaccine-declined',1,'1324811000000107',NULL,'Severe acute respiratory syndrome coronavirus 2 immunisation course declined (situation)'),('covid-vaccine-declined',1,'1324741000000101',NULL,'Severe acute respiratory syndrome coronavirus 2 vaccination first dose declined (situation)'),('covid-vaccine-declined',1,'1324751000000103',NULL,'Severe acute respiratory syndrome coronavirus 2 vaccination second dose declined (situation)');
INSERT INTO #codessnomed
VALUES ('high-clinical-vulnerability',1,'1300561000000107',NULL,'High risk category for developing complication from coronavirus disease caused by severe acute respiratory syndrome coronavirus infection (finding)');
INSERT INTO #codessnomed
VALUES ('moderate-clinical-vulnerability',1,'1300571000000100',NULL,'Moderate risk category for developing complication from coronavirus disease caused by severe acute respiratory syndrome coronavirus infection (finding)');
INSERT INTO #codessnomed
VALUES ('covid-vaccination',1,'1240491000000103',NULL,'2019-nCoV (novel coronavirus) vaccination'),('covid-vaccination',1,'2807821000000115',NULL,'2019-nCoV (novel coronavirus) vaccination'),('covid-vaccination',1,'840534001',NULL,'Severe acute respiratory syndrome coronavirus 2 vaccination (procedure)');
INSERT INTO #codessnomed
VALUES ('flu-vaccination',1,'1037311000000106',NULL,'First intranasal seasonal influenza vaccination given by pharmacist'),('flu-vaccination',1,'1037331000000103',NULL,'Second intranasal seasonal influenza vaccination given by pharmacist'),('flu-vaccination',1,'1037351000000105',NULL,'First inactivated seasonal influenza vaccination given by pharmacist'),('flu-vaccination',1,'1037371000000101',NULL,'Second inactivated seasonal influenza vaccination given by pharmacist'),('flu-vaccination',1,'1066171000000108',NULL,'Seasonal influenza vaccination given by midwife (situation)'),('flu-vaccination',1,'1066181000000105',NULL,'First inactivated seasonal influenza vaccination given by midwife (situation)'),('flu-vaccination',1,'1066191000000107',NULL,'Second inactivated seasonal influenza vaccination given by midwife (situation)'),('flu-vaccination',1,'1239861000000100',NULL,'Seasonal influenza vaccination given in school'),('flu-vaccination',1,'201391000000106',NULL,'Booster influenza vaccination'),('flu-vaccination',1,'202301000000106',NULL,'First pandemic flu vaccination'),('flu-vaccination',1,'202311000000108',NULL,'Second pandemic influenza vaccination'),('flu-vaccination',1,'325631000000101',NULL,'Annual influenza vaccination (finding)'),('flu-vaccination',1,'346524008',NULL,'Inactivated Influenza split virion vaccine'),('flu-vaccination',1,'346525009',NULL,'Inactivated Influenza surface antigen sub-unit vaccine'),('flu-vaccination',1,'348046004',NULL,'Influenza (split virion) vaccine injection suspension prefilled syringe'),('flu-vaccination',1,'348047008',NULL,'Inactivated Influenza surface antigen sub-unit vaccine prefilled syringe'),('flu-vaccination',1,'380741000000101',NULL,'First pandemic influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'380771000000107',NULL,'Second pandemic influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'396425006',NULL,'FLU - Influenza vaccine'),('flu-vaccination',1,'400564003',NULL,'Influenza virus vaccine trivalent 45mcg/0.5mL injection solution 5mL vial'),('flu-vaccination',1,'400788004',NULL,'Influenza virus vaccine triv 45mcg/0.5mL injection'),('flu-vaccination',1,'408752008',NULL,'Inactivated influenza split virion vaccine'),('flu-vaccination',1,'409269001',NULL,'Intranasal influenza live virus vaccine'),('flu-vaccination',1,'418707004',NULL,'Inactivated Influenza surface antigen virosome vaccine prefilled syringe'),('flu-vaccination',1,'419456007',NULL,'Influenza surface antigen vaccine'),('flu-vaccination',1,'419562000',NULL,'Inactivated Influenza surface antigen virosome vaccine'),('flu-vaccination',1,'419826009',NULL,'Influenza split virion vaccine'),('flu-vaccination',1,'426849008',NULL,'Influenza virus H5N1 vaccine'),('flu-vaccination',1,'427036009',NULL,'Influenza virus H5N1 vaccine'),('flu-vaccination',1,'427077008',NULL,'Influenza virus H5N1 vaccine injection solution 5mL multi-dose vial'),('flu-vaccination',1,'428771000',NULL,'Swine influenza virus vaccine'),('flu-vaccination',1,'430410002',NULL,'Product containing Influenza virus vaccine in nasal dosage form'),('flu-vaccination',1,'442315004',NULL,'Influenza A virus subtype H1N1 vaccine (substance)'),('flu-vaccination',1,'442333005',NULL,'Influenza A virus subtype H1N1 vaccination (procedure)'),('flu-vaccination',1,'443161002',NULL,'Influenza A virus subtype H1N1 monovalent vaccine 0.5mL injection solution'),('flu-vaccination',1,'443651005',NULL,'Influenza A virus subtype H1N1 vaccine'),('flu-vaccination',1,'448897007',NULL,'Inactivated Influenza split virion subtype H1N1v-like strain adjuvant vaccine'),('flu-vaccination',1,'451022006',NULL,'Inactivated Influenza split virion subtype H1N1v-like strain unadjuvanted vaccine'),('flu-vaccination',1,'46233009',NULL,'Influenza vaccine'),('flu-vaccination',1,'515281000000108',NULL,'PANDEMRIX - first influenza A (H1N1v) 2009 vaccination given'),('flu-vaccination',1,'515291000000105',NULL,'CELVAPAN - first influenza A (H1N1v) 2009 vaccination given'),('flu-vaccination',1,'515301000000109',NULL,'PANDEMRIX - second influenza A (H1N1v) 2009 vaccination given'),('flu-vaccination',1,'515321000000100',NULL,'CELVAPAN - second influenza A (H1N1v) 2009 vaccination given'),('flu-vaccination',1,'515331000000103',NULL,'CELVAPAN - first influenza A (H1N1v) 2009 vaccination given by other healthcare provider'),('flu-vaccination',1,'515341000000107',NULL,'PANDEMRIX - first influenza A (H1N1v) 2009 vaccination given by other healthcare provider'),('flu-vaccination',1,'515351000000105',NULL,'CELVAPAN - second influenza A (H1N1v) 2009 vaccination given by other healthcare provider'),('flu-vaccination',1,'515361000000108',NULL,'PANDEMRIX - second influenza A (H1N1v) 2009 vaccination given by other healthcare provider'),('flu-vaccination',1,'73701000119109',NULL,'Influenza vaccination given'),('flu-vaccination',1,'81970008',NULL,'Swine influenza virus vaccine (product)'),('flu-vaccination',1,'822851000000102',NULL,'Seasonal influenza vaccination'),('flu-vaccination',1,'86198006',NULL,'Influenza vaccination (procedure)'),('flu-vaccination',1,'868241000000109',NULL,'Administration of intranasal influenza vaccination'),('flu-vaccination',1,'871751000000104',NULL,'Administration of first intranasal influenza vaccination'),('flu-vaccination',1,'871781000000105',NULL,'Administration of second intranasal influenza vaccination'),('flu-vaccination',1,'884821000000108',NULL,'Administration of first intranasal pandemic influenza vaccination'),('flu-vaccination',1,'884841000000101',NULL,'Administration of second intranasal pandemic influenza vaccination'),('flu-vaccination',1,'884861000000100',NULL,'Administration of first intranasal seasonal influenza vaccination'),('flu-vaccination',1,'884881000000109',NULL,'Administration of second intranasal seasonal influenza vaccination'),('flu-vaccination',1,'884901000000107',NULL,'First intranasal pandemic influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'884921000000103',NULL,'Second intranasal pandemic influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'945831000000105',NULL,'First intramuscular seasonal influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'955641000000103',NULL,'Influenza vaccination given by other healthcare provider (situation)'),('flu-vaccination',1,'955651000000100',NULL,'Seasonal influenza vaccination given by other healthcare provider (situation)'),('flu-vaccination',1,'955661000000102',NULL,'First intranasal seasonal influenza vaccination given by other healthcare provider (situation)'),('flu-vaccination',1,'955671000000109',NULL,'Second intramuscular seasonal influenza vaccination given by other healthcare provider (situation)'),('flu-vaccination',1,'955681000000106',NULL,'Second intranasal seasonal influenza vaccination given by other healthcare provider (situation)'),('flu-vaccination',1,'955691000000108',NULL,'Seasonal influenza vaccination given by pharmacist (situation)'),('flu-vaccination',1,'955701000000108',NULL,'Seasonal influenza vaccination given while hospital inpatient (situation)'),('flu-vaccination',1,'985151000000100',NULL,'Administration of first inactivated seasonal influenza vaccination'),('flu-vaccination',1,'985171000000109',NULL,'Administration of second inactivated seasonal influenza vaccination')

INSERT INTO #AllCodes
SELECT [concept], [version], [code], [description] from #codessnomed;

IF OBJECT_ID('tempdb..#codesemis') IS NOT NULL DROP TABLE #codesemis;
CREATE TABLE #codesemis (
  [concept] [varchar](255) NOT NULL,
  [version] INT NOT NULL,
	[code] [varchar](20) COLLATE Latin1_General_CS_AS NOT NULL,
	[term] [varchar](20) COLLATE Latin1_General_CS_AS NULL,
	[description] [varchar](255) NULL
) ON [PRIMARY];

INSERT INTO #codesemis
VALUES ('flu-vaccine',1,'^ESCT1173898',NULL,'Fluad vaccine suspension for injection 0.5ml pre-filled syringes (Seqirus Vaccines Ltd)'),('flu-vaccine',1,'FLVA127091NEMIS',NULL,'Fluad vaccine suspension for injection 0.5ml pre-filled syringes (Seqirus Vaccines Ltd)'),('flu-vaccine',1,'FLVA137918NEMIS',NULL,'Fluad Tetra vaccine suspension for injection 0.5ml pre-filled syringes (Seqirus Vaccines Ltd)'),('flu-vaccine',1,'^ESCT1188861',NULL,'Influvac Sub-unit vaccine suspension for injection 0.5ml pre-filled syringes (Mylan)'),('flu-vaccine',1,'^ESCT1199425',NULL,'Influvac sub-unit Tetra vaccine suspension for injection 0.5ml pre-filled syringes (Mylan) 1 pre-filled disposable injection'),('flu-vaccine',1,'ININ1468',NULL,'Influvac Sub-unit vaccine suspension for injection 0.5ml pre-filled syringes (Mylan)'),('flu-vaccine',1,'INSU82033NEMIS',NULL,'Influvac Desu  Suspension For Injection  0.5 ml pre-filled syringe'),('flu-vaccine',1,'INSU82033NEMIS',NULL,'Influvac Desu vaccine suspension for injection 0.5ml pre-filled syringes (Abbott Healthcare Products Ltd)'),('flu-vaccine',1,'INVA127171NEMIS',NULL,'Influvac sub-unit Tetra vaccine suspension for injection 0.5ml pre-filled syringes (Mylan)'),('flu-vaccine',1,'AVVA5297NEMIS',NULL,'Influenza vaccine (split virion, inactivated) suspension for injection 0.5ml pre-filled syringes (sanofi pasteur MSD Ltd)'),('flu-vaccine',1,'AVVA5297NEMIS',NULL,'Influenza vaccine (split virion, inactivated) suspension for injection 0.5ml pre-filled syringes (Sanofi Pasteur)'),('flu-vaccine',1,'ININ27868EMIS',NULL,'Inactivated Influenza Vaccine, Surface Antigen  Injection  0.5 ml pre-filled syringe'),('flu-vaccine',1,'ININ27868EMIS',NULL,'Influenza vaccine (surface antigen, inactivated) suspension for injection 0.5ml pre-filled syringes'),('flu-vaccine',1,'INNA52407NEMIS',NULL,'Influenza vaccine (live attenuated) nasal suspension 0.2ml unit dose'),('flu-vaccine',1,'INSU127173NEMIS',NULL,'Influenza Vaccine Tetra Myl Suspension For Injection 0.5 ml pre-filled syringe'),('flu-vaccine',1,'INSU23004NEMIS',NULL,'Inactivated Influenza Vaccine, Surface Antigen, Virosome  Suspension For Injection  0.5 ml pre-filled syringe'),('flu-vaccine',1,'INSU23004NEMIS',NULL,'Influenza vaccine (surface antigen, inactivated, virosome) suspension for injection 0.5ml pre-filled syringes'),('flu-vaccine',1,'INVA30366EMIS',NULL,'Influenza vaccine (split virion, inactivated) suspension for injection 0.5ml pre-filled syringes'),('flu-vaccine',1,'INVA36706NEMIS',NULL,'Influenza vaccine (split virion, inactivated) 15microgram strain suspension for injection 0.1ml pre-filled syringes'),('flu-vaccine',1,'PAVA19010EMIS',NULL,'Pasteur Merieux Inactivated Influenza Vaccine 0.5 ml'),('flu-vaccine',1,'PFVA95151NEMIS',NULL,'Influenza vaccine (split virion, inactivated) suspension for injection 0.5ml pre-filled syringes (Pfizer Ltd)'),('flu-vaccine',1,'QUVA124210NEMIS',NULL,'Quadrivalent influenza vaccine (split virion, inactivated) suspension for injection 0.5ml pre-filled syringes (Sanofi Pasteur)'),('flu-vaccine',1,'SAVA131918NEMIS',NULL,'Trivalent influenza vaccine (split virion, inactivated) High Dose suspension for injection 0.5ml pre-filled syringes (Sanofi Pasteur)'),('flu-vaccine',1,'SEVA133336NEMIS',NULL,'Adjuvanted trivalent influenza vaccine (surface antigen, inactivated) suspension for injection 0.5ml pre-filled syringes (Seqirus Vaccines Ltd)'),('flu-vaccine',1,'FLIN9810BRIDL',NULL,'Fluvirin vaccine suspension for injection 0.5ml pre-filled syringes (Novartis Vaccines and Diagnostics Ltd)'),('flu-vaccine',1,'FLNA52410NEMIS',NULL,'Fluenz  Vaccine Nasal Suspension  0.2 ml unit dose'),('flu-vaccine',1,'FLNA52410NEMIS',NULL,'Fluenz vaccine nasal suspension 0.2ml unit dose (AstraZeneca UK Ltd)'),('flu-vaccine',1,'FLVA90951NEMIS',NULL,'Fluenz Tetra vaccine nasal suspension 0.2ml unit dose (AstraZeneca UK Ltd)'),('flu-vaccine',1,'FLVA105396NEMIS',NULL,'FluMist Quadrivalent vaccine nasal suspension 0.2ml unit dose (AstraZeneca UK Ltd)'),('flu-vaccine',1,'FLVA130397NEMIS',NULL,'Flucelvax Tetra vaccine suspension for injection 0.5ml pre-filled syringes (Seqirus Vaccines Ltd)'),('flu-vaccine',1,'FLVA19006EMIS',NULL,'Fluzone Vaccine 0.5 ml'),('flu-vaccine',1,'FLVA24698EMIS',NULL,'Fluarix vaccine suspension for injection 0.5ml pre-filled syringes (GlaxoSmithKline UK Ltd)'),('flu-vaccine',1,'FLVA82448NEMIS',NULL,'Fluarix Tetra vaccine suspension for injection 0.5ml pre-filled syringes (GlaxoSmithKline UK Ltd)'),('flu-vaccine',1,'INSU127173NEMIS',NULL,'Influenza Tetra MYL vaccine suspension for injection 0.5ml pre-filled syringes (Mylan)'),('flu-vaccine',1,'MASU15057NEMIS',NULL,'Mastaflu vaccine suspension for injection 0.5ml pre-filled syringes (Masta Ltd)'),('flu-vaccine',1,'OPSU76843NEMIS',NULL,'Optaflu vaccine suspension for injection 0.5ml pre-filled syringes (Novartis Vaccines and Diagnostics Ltd)'),('flu-vaccine',1,'OPSU76843NEMIS',NULL,'Optaflu vaccine suspension for injection 0.5ml pre-filled syringes (Seqirus Vaccines Ltd)'),('flu-vaccine',1,'PRSU51924NEMIS',NULL,'Preflucel vaccine suspension for injection 0.5ml pre-filled syringes (Baxter Healthcare Ltd)'),('flu-vaccine',1,'VISU23002NEMIS',NULL,'Viroflu vaccine suspension for injection 0.5ml pre-filled syringes (Janssen-Cilag Ltd)'),('flu-vaccine',1,'ENSU20871NEMIS',NULL,'Enzira  Suspension For Injection  0.5 ml pre-filled syringe'),('flu-vaccine',1,'IMSU22976NEMIS',NULL,'Imuvac  Suspension For Injection  0.5 ml pre-filled syringe'),('flu-vaccine',1,'INVA36708NEMIS',NULL,'Intanza  Vaccine  15 microgram strain, 0.1 ml pre-filled syringe'),('flu-vaccine',1,'INVA40484NEMIS',NULL,'Intanza  Vaccine  9 microgram strain, 0.1 ml pre-filled syringe'),('flu-vaccine',1,'AGIN11649NEMIS',NULL,'Agrippal  Injection'),('flu-vaccine',1,'BEVA30364EMIS',NULL,'Begrivac  Vaccine'),('flu-vaccine',1,'AGIN11649NEMIS',NULL,'Agrippal  Injection'),('flu-vaccine',1,'BEVA30364EMIS',NULL,'Begrivac  Vaccine'),('flu-vaccine',1,'CESU38013NEMIS',NULL,'Celvapan (H1N1) Vaccine  Suspension For Injection'),('flu-vaccine',1,'ININ12704NEMIS',NULL,'Inflexal Berna V  Injection  0.5 ml pre-filled syringe'),('flu-vaccine',1,'ININ18889NEMIS',NULL,'Invivac  Injection  0.5 ml pre-filled syringe');
INSERT INTO #codesemis
VALUES ('covid-vaccine-declined',1,'^ESCT1348329',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccination dose declined'),('covid-vaccine-declined',1,'^ESCT1348345',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) immunisation course declined'),('covid-vaccine-declined',1,'^ESCT1348333',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccination first dose declined'),('covid-vaccine-declined',1,'^ESCT1348335',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccination second dose declined'),('covid-vaccine-declined',1,'^ESCT1301234',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccination declined'),('covid-vaccine-declined',1,'^ESCT1299086',NULL,'2019-nCoV (novel coronavirus) Vaccination declined');
INSERT INTO #codesemis
VALUES ('high-clinical-vulnerability',1,'^ESCT1300222',NULL,'High risk category for developing complications from COVID-19 infection');
INSERT INTO #codesemis
VALUES ('moderate-clinical-vulnerability',1,'^ESCT1300223',NULL,'Moderate risk category for developing complications from COVID-19 infection');
INSERT INTO #codesemis
VALUES ('covid-vaccination',1,'^ESCT1348323',NULL,'Administration of first dose of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccine'),('covid-vaccination',1,'^ESCT1348324',NULL,'Administration of first dose of 2019-nCoV (novel coronavirus) vaccine'),('covid-vaccination',1,'COCO138186NEMIS',NULL,'COVID-19 mRNA Vaccine BNT162b2 30micrograms/0.3ml dose concentrate for suspension for injection multidose vials (Pfizer-BioNTech) (Pfizer-BioNTech)'),('covid-vaccination',1,'^ESCT1348325',NULL,'Administration of second dose of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccine'),('covid-vaccination',1,'^ESCT1348326',NULL,'Administration of second dose of 2019-nCoV (novel coronavirus) vaccine'),('covid-vaccination',1,'^ESCT1428354',NULL,'Administration of third dose of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccine'),('covid-vaccination',1,'^ESCT1428342',NULL,'Administration of fourth dose of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccine'),('covid-vaccination',1,'^ESCT1428348',NULL,'Administration of fifth dose of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccine'),('covid-vaccination',1,'^ESCT1348298',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccination'),('covid-vaccination',1,'^ESCT1348301',NULL,'COVID-19 vaccination'),('covid-vaccination',1,'^ESCT1299050',NULL,'2019-nCoV (novel coronavirus) vaccination'),('covid-vaccination',1,'^ESCT1301222',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccination'),('covid-vaccination',1,'CODI138564NEMIS',NULL,'Covid-19 mRna (nucleoside modified) Vaccine Moderna  Dispersion for injection  0.1 mg/0.5 ml dose, multidose vial'),('covid-vaccination',1,'TASO138184NEMIS',NULL,'Covid-19 Vaccine AstraZeneca (ChAdOx1 S recombinant)  Solution for injection  5x10 billion viral particle/0.5 ml multidose vial'),('covid-vaccination',1,'PCSDT18491_1375',NULL,'Administration of first dose of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccine'),('covid-vaccination',1,'PCSDT18491_1376',NULL,'Administration of second dose of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccine'),('covid-vaccination',1,'PCSDT18491_716',NULL,'Administration of second dose of SARS-CoV-2 vacc'),('covid-vaccination',1,'PCSDT18491_903',NULL,'Administration of first dose of SARS-CoV-2 vacccine'),('covid-vaccination',1,'PCSDT3370_2254',NULL,'2019-nCoV (novel coronavirus) vaccination'),('covid-vaccination',1,'PCSDT3919_2185',NULL,'Administration of first dose of SARS-CoV-2 vacccine'),('covid-vaccination',1,'PCSDT3919_662',NULL,'Administration of second dose of SARS-CoV-2 vacc'),('covid-vaccination',1,'PCSDT4803_1723',NULL,'2019-nCoV (novel coronavirus) vaccination'),('covid-vaccination',1,'PCSDT5823_2264',NULL,'Administration of second dose of SARS-CoV-2 vacc'),('covid-vaccination',1,'PCSDT5823_2757',NULL,'Administration of second dose of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccine'),('covid-vaccination',1,'PCSDT5823_2902',NULL,'Administration of first dose of SARS-CoV-2 vacccine'),('covid-vaccination',1,'^ESCT1348300',NULL,'Severe acute respiratory syndrome coronavirus 2 vaccination'),('covid-vaccination',1,'ASSO138368NEMIS',NULL,'COVID-19 Vaccine Janssen (Ad26.COV2-S [recombinant]) 0.5ml dose suspension for injection multidose vials (Janssen-Cilag Ltd)'),('covid-vaccination',1,'COCO141057NEMIS',NULL,'Comirnaty Children 5-11 years COVID-19 mRNA Vaccine 10micrograms/0.2ml dose concentrate for dispersion for injection multidose vials (Pfizer Ltd)'),('covid-vaccination',1,'COSO141059NEMIS',NULL,'COVID-19 Vaccine Covishield (ChAdOx1 S [recombinant]) 5x10,000,000,000 viral particles/0.5ml dose solution for injection multidose vials (Serum Institute of India)'),('covid-vaccination',1,'COSU138776NEMIS',NULL,'COVID-19 Vaccine Valneva (inactivated adjuvanted whole virus) 40antigen units/0.5ml dose suspension for injection multidose vials (Valneva UK Ltd)'),('covid-vaccination',1,'COSU138943NEMIS',NULL,'COVID-19 Vaccine Novavax (adjuvanted) 5micrograms/0.5ml dose suspension for injection multidose vials (Baxter Oncology GmbH)'),('covid-vaccination',1,'COSU141008NEMIS',NULL,'CoronaVac COVID-19 Vaccine (adjuvanted) 600U/0.5ml dose suspension for injection vials (Sinovac Life Sciences)'),('covid-vaccination',1,'COSU141037NEMIS',NULL,'COVID-19 Vaccine Sinopharm BIBP (inactivated adjuvanted) 6.5U/0.5ml dose suspension for injection vials (Beijing Institute of Biological Products)');
INSERT INTO #codesemis
VALUES ('flu-vaccination',1,'^ESCT1300221',NULL,'Seasonal influenza vaccination given in school'),('flu-vaccination',1,'^ESCTFI843902',NULL,'First inactivated seasonal influenza vaccination given by midwife'),('flu-vaccination',1,'^ESCTIN802297',NULL,'Influenza vaccination given'),('flu-vaccination',1,'^ESCTSE843901',NULL,'Seasonal influenza vaccination given by midwife'),('flu-vaccination',1,'EMISNQAD138',NULL,'Administration of first quadrivalent (QIV) inactivated seasonal influenza vaccination'),('flu-vaccination',1,'EMISNQAD139',NULL,'Administration of first non adjuvanted trivalent (TIV) inactivated seasonal influenza vaccination'),('flu-vaccination',1,'EMISNQAD142',NULL,'Administration of adjuvanted trivalent (aTIV) inactivated seasonal influenza vaccination'),('flu-vaccination',1,'EMISNQAD144',NULL,'Administration of first quadrivalent (QIV) inactivated seasonal influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'EMISNQAD145',NULL,'Administration of first non adjuvanted trivalent (TIV) inactivated seasonal influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'EMISNQAD147',NULL,'Administration of adjuvanted trivalent (aTIV) inactivated seasonal influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'EMISNQAD148',NULL,'Administration of second quadrivalent (QIV) inactivated seasonal influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'EMISNQAD149',NULL,'Adjuvanted trivalent (aTIV) inactivated seasonal influenza vaccination given by pharmacist'),('flu-vaccination',1,'EMISNQAD150',NULL,'Administration of second non adjuvanted trivalent (TIV) inactivated seasonal influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'EMISNQAD151',NULL,'Administration of second quadrivalent (QIV) inactivated seasonal influenza vaccination'),('flu-vaccination',1,'EMISNQFI45',NULL,'First quadrivalent (QIV) inactivated seasonal influenza vaccination given by pharmacist'),('flu-vaccination',1,'EMISNQFI46',NULL,'First non adjuvanted trivalent (TIV) inactivated seasonal influenza vaccination given by pharmacist'),('flu-vaccination',1,'EMISNQIN160',NULL,'Intranasal influenza vaccination'),('flu-vaccination',1,'EMISNQSE164',NULL,'Second quadrivalent (QIV) inactivated seasonal influenza vaccination given by pharmacist'),('flu-vaccination',1,'PCSDT18434_779',NULL,'First intranasal seasonal influenza vacc given by pharmacist'),('flu-vaccination',1,'PCSDT18439_1184',NULL,'First intranasal seasonal influenza vacc given by pharmacist'),('flu-vaccination',1,'PCSDT18439_711',NULL,'Second intranasal seasonal influenza vacc givn by pharmacist'),('flu-vaccination',1,'PCSDT28849_483',NULL,'First intranasal seasonal influenza vacc given by pharmacist'),('flu-vaccination',1,'PCSDT7022_652',NULL,'First intranasal seasonal influenza vacc given by pharmacist'),('flu-vaccination',1,'^ESCTSE843903',NULL,'Second inactivated seasonal influenza vaccination given by midwife');
INSERT INTO #codesemis
VALUES ('covid-positive-antigen-test',1,'^ESCT1305304',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) antigen detection result positive'),('covid-positive-antigen-test',1,'^ESCT1348538',NULL,'Detection of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) antigen');
INSERT INTO #codesemis
VALUES ('covid-positive-pcr-test',1,'^ESCT1305238',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) RNA (ribonucleic acid) qualitative existence in specimen'),('covid-positive-pcr-test',1,'^ESCT1348314',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) RNA (ribonucleic acid) detection result positive'),('covid-positive-pcr-test',1,'^ESCT1305235',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) RNA (ribonucleic acid) detection result positive'),('covid-positive-pcr-test',1,'^ESCT1300228',NULL,'COVID-19 confirmed by laboratory test GP COVID-19'),('covid-positive-pcr-test',1,'^ESCT1348316',NULL,'2019-nCoV (novel coronavirus) ribonucleic acid detected'),('covid-positive-pcr-test',1,'^ESCT1301223',NULL,'Detection of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) using polymerase chain reaction technique'),('covid-positive-pcr-test',1,'^ESCT1348359',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) RNA (ribonucleic acid) detection result positive at the limit of detection'),('covid-positive-pcr-test',1,'^ESCT1299053',NULL,'Detection of 2019-nCoV (novel coronavirus) using polymerase chain reaction technique'),('covid-positive-pcr-test',1,'^ESCT1300228',NULL,'COVID-19 confirmed by laboratory test'),('covid-positive-pcr-test',1,'^ESCT1348359',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) RNA (ribonucleic acid) detection result positive at the limit of detection');
INSERT INTO #codesemis
VALUES ('covid-positive-test-other',1,'^ESCT1303928',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) detection result positive'),('covid-positive-test-other',1,'^ESCT1299074',NULL,'2019-nCoV (novel coronavirus) detected'),('covid-positive-test-other',1,'^ESCT1301230',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) detected'),('covid-positive-test-other',1,'EMISNQCO303',NULL,'Confirmed 2019-nCoV (Wuhan) infectio'),('covid-positive-test-other',1,'^ESCT1299075',NULL,'Wuhan 2019-nCoV (novel coronavirus) detected'),('covid-positive-test-other',1,'^ESCT1300229',NULL,'COVID-19 confirmed using clinical diagnostic criteria'),('covid-positive-test-other',1,'^ESCT1348575',NULL,'Detection of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2)'),('covid-positive-test-other',1,'^ESCT1299074',NULL,'2019-nCoV (novel coronavirus) detected'),('covid-positive-test-other',1,'^ESCT1300229',NULL,'COVID-19 confirmed using clinical diagnostic criteria'),('covid-positive-test-other',1,'EMISNQCO303',NULL,'Confirmed 2019-nCoV (novel coronavirus) infection'),('covid-positive-test-other',1,'EMISNQCO303',NULL,'Confirmed 2019-nCoV (novel coronavirus) infection'),('covid-positive-test-other',1,'^ESCT1348575',NULL,'Detection of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2)')

INSERT INTO #AllCodes
SELECT [concept], [version], [code], [description] from #codesemis;


IF OBJECT_ID('tempdb..#TempRefCodes') IS NOT NULL DROP TABLE #TempRefCodes;
CREATE TABLE #TempRefCodes (FK_Reference_Coding_ID BIGINT NOT NULL, concept VARCHAR(255) NOT NULL, version INT NOT NULL, [description] VARCHAR(255));

-- Read v2 codes
INSERT INTO #TempRefCodes
SELECT PK_Reference_Coding_ID, dcr.concept, dcr.[version], dcr.[description]
FROM [SharedCare].[Reference_Coding] rc
INNER JOIN #codesreadv2 dcr on dcr.code = rc.MainCode
WHERE CodingType='ReadCodeV2'
AND (dcr.term IS NULL OR dcr.term = rc.Term)
and PK_Reference_Coding_ID != -1;

-- CTV3 codes
INSERT INTO #TempRefCodes
SELECT PK_Reference_Coding_ID, dcc.concept, dcc.[version], dcc.[description]
FROM [SharedCare].[Reference_Coding] rc
INNER JOIN #codesctv3 dcc on dcc.code = rc.MainCode
WHERE CodingType='CTV3'
and PK_Reference_Coding_ID != -1;

-- EMIS codes with a FK Reference Coding ID
INSERT INTO #TempRefCodes
SELECT FK_Reference_Coding_ID, ce.concept, ce.[version], ce.[description]
FROM [SharedCare].[Reference_Local_Code] rlc
INNER JOIN #codesemis ce on ce.code = rlc.LocalCode
WHERE FK_Reference_Coding_ID != -1;

IF OBJECT_ID('tempdb..#TempSNOMEDRefCodes') IS NOT NULL DROP TABLE #TempSNOMEDRefCodes;
CREATE TABLE #TempSNOMEDRefCodes (FK_Reference_SnomedCT_ID BIGINT NOT NULL, concept VARCHAR(255) NOT NULL, [version] INT NOT NULL, [description] VARCHAR(255));

-- SNOMED codes
INSERT INTO #TempSNOMEDRefCodes
SELECT PK_Reference_SnomedCT_ID, dcs.concept, dcs.[version], dcs.[description]
FROM SharedCare.Reference_SnomedCT rs
INNER JOIN #codessnomed dcs on dcs.code = rs.ConceptID;

-- EMIS codes with a FK SNOMED ID but without a FK Reference Coding ID
INSERT INTO #TempSNOMEDRefCodes
SELECT FK_Reference_SnomedCT_ID, ce.concept, ce.[version], ce.[description]
FROM [SharedCare].[Reference_Local_Code] rlc
INNER JOIN #codesemis ce on ce.code = rlc.LocalCode
WHERE FK_Reference_Coding_ID = -1
AND FK_Reference_SnomedCT_ID != -1;

-- De-duped tables
IF OBJECT_ID('tempdb..#CodeSets') IS NOT NULL DROP TABLE #CodeSets;
CREATE TABLE #CodeSets (FK_Reference_Coding_ID BIGINT NOT NULL, concept VARCHAR(255) NOT NULL, [description] VARCHAR(255));

IF OBJECT_ID('tempdb..#SnomedSets') IS NOT NULL DROP TABLE #SnomedSets;
CREATE TABLE #SnomedSets (FK_Reference_SnomedCT_ID BIGINT NOT NULL, concept VARCHAR(255) NOT NULL, [description] VARCHAR(255));

IF OBJECT_ID('tempdb..#VersionedCodeSets') IS NOT NULL DROP TABLE #VersionedCodeSets;
CREATE TABLE #VersionedCodeSets (FK_Reference_Coding_ID BIGINT NOT NULL, Concept VARCHAR(255), [Version] INT, [description] VARCHAR(255));

IF OBJECT_ID('tempdb..#VersionedSnomedSets') IS NOT NULL DROP TABLE #VersionedSnomedSets;
CREATE TABLE #VersionedSnomedSets (FK_Reference_SnomedCT_ID BIGINT NOT NULL, Concept VARCHAR(255), [Version] INT, [description] VARCHAR(255));

INSERT INTO #VersionedCodeSets
SELECT DISTINCT * FROM #TempRefCodes;

INSERT INTO #VersionedSnomedSets
SELECT DISTINCT * FROM #TempSNOMEDRefCodes;

INSERT INTO #CodeSets
SELECT FK_Reference_Coding_ID, c.concept, [description]
FROM #VersionedCodeSets c
INNER JOIN (
  SELECT concept, MAX(version) AS maxVersion FROM #VersionedCodeSets
  GROUP BY concept)
sub ON sub.concept = c.concept AND c.version = sub.maxVersion;

INSERT INTO #SnomedSets
SELECT FK_Reference_SnomedCT_ID, c.concept, [description]
FROM #VersionedSnomedSets c
INNER JOIN (
  SELECT concept, MAX(version) AS maxVersion FROM #VersionedSnomedSets
  GROUP BY concept)
sub ON sub.concept = c.concept AND c.version = sub.maxVersion;

-- >>> Following code sets injected: covid-positive-antigen-test v1/covid-positive-pcr-test v1/covid-positive-test-other v1


-- Set the temp end date until new legal basis
DECLARE @TEMPWithCovidEndDate datetime;
SET @TEMPWithCovidEndDate = '2022-06-01';

IF OBJECT_ID('tempdb..#CovidPatientsAllDiagnoses') IS NOT NULL DROP TABLE #CovidPatientsAllDiagnoses;
CREATE TABLE #CovidPatientsAllDiagnoses (
	FK_Patient_Link_ID BIGINT,
	CovidPositiveDate DATE
);
BEGIN
	IF 'true'='true'
		INSERT INTO #CovidPatientsAllDiagnoses
		SELECT DISTINCT FK_Patient_Link_ID, CONVERT(DATE, [EventDate]) AS CovidPositiveDate
		FROM [RLS].[vw_COVID19]
		WHERE (
			(GroupDescription = 'Confirmed' AND SubGroupDescription != 'Negative') OR
			(GroupDescription = 'Tested' AND SubGroupDescription = 'Positive')
		)
		AND EventDate > '2020-02-01'
		--AND EventDate <= GETDATE();
		AND EventDate <= @TEMPWithCovidEndDate
		AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);
	ELSE 
		INSERT INTO #CovidPatientsAllDiagnoses
		SELECT DISTINCT FK_Patient_Link_ID, CONVERT(DATE, [EventDate]) AS CovidPositiveDate
		FROM [RLS].[vw_COVID19]
		WHERE (
			(GroupDescription = 'Confirmed' AND SubGroupDescription != 'Negative') OR
			(GroupDescription = 'Tested' AND SubGroupDescription = 'Positive')
		)
		AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
		AND EventDate > '2020-02-01'
		--AND EventDate <= GETDATE();
		AND EventDate <= @TEMPWithCovidEndDate;
END

-- We can rely on the GraphNet table for first diagnosis.
IF OBJECT_ID('tempdb..#CovidPatients') IS NOT NULL DROP TABLE #CovidPatients;
SELECT FK_Patient_Link_ID, MIN(CovidPositiveDate) AS FirstCovidPositiveDate INTO #CovidPatients
FROM #CovidPatientsAllDiagnoses
GROUP BY FK_Patient_Link_ID;

-- Now let's get the dates of any positive test (i.e. not things like suspected, or historic)
IF OBJECT_ID('tempdb..#AllPositiveTestsTemp') IS NOT NULL DROP TABLE #AllPositiveTestsTemp;
CREATE TABLE #AllPositiveTestsTemp (
	FK_Patient_Link_ID BIGINT,
	TestDate DATE
);
BEGIN
	IF 'true'='true'
		INSERT INTO #AllPositiveTestsTemp
		SELECT DISTINCT FK_Patient_Link_ID, CAST(EventDate AS DATE) AS TestDate
		FROM RLS.vw_GP_Events
		WHERE SuppliedCode IN (
			select Code from #AllCodes 
			where Concept in ('covid-positive-antigen-test','covid-positive-pcr-test','covid-positive-test-other') 
			AND Version = 1
		)
		AND EventDate <= @TEMPWithCovidEndDate
		AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);
	ELSE 
		INSERT INTO #AllPositiveTestsTemp
		SELECT DISTINCT FK_Patient_Link_ID, CAST(EventDate AS DATE) AS TestDate
		FROM RLS.vw_GP_Events
		WHERE SuppliedCode IN (
			select Code from #AllCodes 
			where Concept in ('covid-positive-antigen-test','covid-positive-pcr-test','covid-positive-test-other') 
			AND Version = 1
		)
		AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
		AND EventDate <= @TEMPWithCovidEndDate;
END

IF OBJECT_ID('tempdb..#CovidPatientsMultipleDiagnoses') IS NOT NULL DROP TABLE #CovidPatientsMultipleDiagnoses;
CREATE TABLE #CovidPatientsMultipleDiagnoses (
	FK_Patient_Link_ID BIGINT,
	FirstCovidPositiveDate DATE,
	SecondCovidPositiveDate DATE,
	ThirdCovidPositiveDate DATE,
	FourthCovidPositiveDate DATE,
	FifthCovidPositiveDate DATE
);

-- Populate first diagnosis
INSERT INTO #CovidPatientsMultipleDiagnoses (FK_Patient_Link_ID, FirstCovidPositiveDate)
SELECT FK_Patient_Link_ID, MIN(FirstCovidPositiveDate) FROM
(
	SELECT * FROM #CovidPatients
	UNION
	SELECT * FROM #AllPositiveTestsTemp
) sub
GROUP BY FK_Patient_Link_ID;

-- Now let's get second tests.
UPDATE t1
SET t1.SecondCovidPositiveDate = NextTestDate
FROM #CovidPatientsMultipleDiagnoses AS t1
INNER JOIN (
SELECT cp.FK_Patient_Link_ID, MIN(apt.TestDate) AS NextTestDate FROM #CovidPatients cp
INNER JOIN #AllPositiveTestsTemp apt ON cp.FK_Patient_Link_ID = apt.FK_Patient_Link_ID AND apt.TestDate >= DATEADD(day, 90, FirstCovidPositiveDate)
GROUP BY cp.FK_Patient_Link_ID) AS sub ON sub.FK_Patient_Link_ID = t1.FK_Patient_Link_ID;

-- Now let's get third tests.
UPDATE t1
SET t1.ThirdCovidPositiveDate = NextTestDate
FROM #CovidPatientsMultipleDiagnoses AS t1
INNER JOIN (
SELECT cp.FK_Patient_Link_ID, MIN(apt.TestDate) AS NextTestDate FROM #CovidPatientsMultipleDiagnoses cp
INNER JOIN #AllPositiveTestsTemp apt ON cp.FK_Patient_Link_ID = apt.FK_Patient_Link_ID AND apt.TestDate >= DATEADD(day, 90, SecondCovidPositiveDate)
GROUP BY cp.FK_Patient_Link_ID) AS sub ON sub.FK_Patient_Link_ID = t1.FK_Patient_Link_ID;

-- Now let's get fourth tests.
UPDATE t1
SET t1.FourthCovidPositiveDate = NextTestDate
FROM #CovidPatientsMultipleDiagnoses AS t1
INNER JOIN (
SELECT cp.FK_Patient_Link_ID, MIN(apt.TestDate) AS NextTestDate FROM #CovidPatientsMultipleDiagnoses cp
INNER JOIN #AllPositiveTestsTemp apt ON cp.FK_Patient_Link_ID = apt.FK_Patient_Link_ID AND apt.TestDate >= DATEADD(day, 90, ThirdCovidPositiveDate)
GROUP BY cp.FK_Patient_Link_ID) AS sub ON sub.FK_Patient_Link_ID = t1.FK_Patient_Link_ID;

-- Now let's get fifth tests.
UPDATE t1
SET t1.FifthCovidPositiveDate = NextTestDate
FROM #CovidPatientsMultipleDiagnoses AS t1
INNER JOIN (
SELECT cp.FK_Patient_Link_ID, MIN(apt.TestDate) AS NextTestDate FROM #CovidPatientsMultipleDiagnoses cp
INNER JOIN #AllPositiveTestsTemp apt ON cp.FK_Patient_Link_ID = apt.FK_Patient_Link_ID AND apt.TestDate >= DATEADD(day, 90, FourthCovidPositiveDate)
GROUP BY cp.FK_Patient_Link_ID) AS sub ON sub.FK_Patient_Link_ID = t1.FK_Patient_Link_ID;

IF OBJECT_ID('tempdb..#COVIDUtilisationAdmissions') IS NOT NULL DROP TABLE #COVIDUtilisationAdmissions;
SELECT 
	a.*, 
	CASE
		WHEN c.FK_Patient_Link_ID IS NOT NULL THEN 'TRUE'
		ELSE 'FALSE'
	END AS CovidHealthcareUtilisation
INTO #COVIDUtilisationAdmissions 
FROM #Admissions a
LEFT OUTER join #CovidPatients c ON 
	a.FK_Patient_Link_ID = c.FK_Patient_Link_ID 
	AND a.AdmissionDate <= DATEADD(WEEK, 4, c.FirstCovidPositiveDate)
	AND a.AdmissionDate >= DATEADD(DAY, -14, c.FirstCovidPositiveDate);

--┌────────────────────┐
--│ COVID vaccinations │
--└────────────────────┘

-- OBJECTIVE: To obtain a table with first, second, third... etc vaccine doses per patient.

-- ASSUMPTIONS:
--	-	GP records can often be duplicated. The assumption is that if a patient receives
--    two vaccines within 14 days of each other then it is likely that both codes refer
--    to the same vaccine.
--  - The vaccine can appear as a procedure or as a medication. We assume that the
--    presence of either represents a vaccination

-- INPUT: Takes two parameters:
--	- gp-events-table: string - (table name) the name of the table containing the GP events. Usually is "RLS.vw_GP_Events" but can be anything with the columns: FK_Patient_Link_ID, EventDate, and SuppliedCode
--	- gp-medications-table: string - (table name) the name of the table containing the GP medications. Usually is "RLS.vw_GP_Medications" but can be anything with the columns: FK_Patient_Link_ID, EventDate, and SuppliedCode

-- OUTPUT: A temp table as follows:
-- #COVIDVaccinations (FK_Patient_Link_ID, VaccineDate, DaysSinceFirstVaccine)
-- 	- FK_Patient_Link_ID - unique patient id
--	- VaccineDose1Date - date of first vaccine (YYYY-MM-DD)
--	-	VaccineDose2Date - date of second vaccine (YYYY-MM-DD)
--	-	VaccineDose3Date - date of third vaccine (YYYY-MM-DD)
--	-	VaccineDose4Date - date of fourth vaccine (YYYY-MM-DD)
--	-	VaccineDose5Date - date of fifth vaccine (YYYY-MM-DD)
--	-	VaccineDose6Date - date of sixth vaccine (YYYY-MM-DD)
--	-	VaccineDose7Date - date of seventh vaccine (YYYY-MM-DD)

-- Get patients with covid vaccine and earliest and latest date
-- >>> Following code sets injected: covid-vaccination v1


IF OBJECT_ID('tempdb..#VacEvents') IS NOT NULL DROP TABLE #VacEvents;
SELECT FK_Patient_Link_ID, CONVERT(DATE, EventDate) AS EventDate into #VacEvents
FROM RLS.vw_GP_Events
WHERE SuppliedCode IN (
	SELECT [Code] FROM #AllCodes WHERE [Concept] = 'covid-vaccination' AND [Version] = 1
)
AND EventDate > '2020-12-01'
AND EventDate < '2022-06-01'; --TODO temp addition for COPI expiration

IF OBJECT_ID('tempdb..#VacMeds') IS NOT NULL DROP TABLE #VacMeds;
SELECT FK_Patient_Link_ID, CONVERT(DATE, MedicationDate) AS EventDate into #VacMeds
FROM RLS.vw_GP_Medications
WHERE SuppliedCode IN (
	SELECT [Code] FROM #AllCodes WHERE [Concept] = 'covid-vaccination' AND [Version] = 1
)
AND MedicationDate > '2020-12-01'
AND MedicationDate < '2022-06-01';--TODO temp addition for COPI expiration

IF OBJECT_ID('tempdb..#COVIDVaccines') IS NOT NULL DROP TABLE #COVIDVaccines;
SELECT FK_Patient_Link_ID, EventDate into #COVIDVaccines FROM #VacEvents
UNION
SELECT FK_Patient_Link_ID, EventDate FROM #VacMeds;
--4426892 5m03

-- Tidy up
DROP TABLE #VacEvents;
DROP TABLE #VacMeds;

-- Get first vaccine dose
IF OBJECT_ID('tempdb..#VacTemp1') IS NOT NULL DROP TABLE #VacTemp1;
select FK_Patient_Link_ID, MIN(EventDate) AS VaccineDoseDate
into #VacTemp1
from #COVIDVaccines
group by FK_Patient_Link_ID;
--2046837

-- Get second vaccine dose (if exists) - assume dose within 14 days is same dose
IF OBJECT_ID('tempdb..#VacTemp2') IS NOT NULL DROP TABLE #VacTemp2;
select c.FK_Patient_Link_ID, MIN(c.EventDate) AS VaccineDoseDate
into #VacTemp2
from #VacTemp1 v
inner join #COVIDVaccines c on c.EventDate > DATEADD(day, 14, v.VaccineDoseDate) and c.FK_Patient_Link_ID = v.FK_Patient_Link_ID
group by c.FK_Patient_Link_ID;
--1810762

-- Get third vaccine dose (if exists) - assume dose within 14 days is same dose
IF OBJECT_ID('tempdb..#VacTemp3') IS NOT NULL DROP TABLE #VacTemp3;
select c.FK_Patient_Link_ID, MIN(c.EventDate) AS VaccineDoseDate
into #VacTemp3
from #VacTemp2 v
inner join #COVIDVaccines c on c.EventDate > DATEADD(day, 14, v.VaccineDoseDate) and c.FK_Patient_Link_ID = v.FK_Patient_Link_ID
group by c.FK_Patient_Link_ID;
--578468

-- Get fourth vaccine dose (if exists) - assume dose within 14 days is same dose
IF OBJECT_ID('tempdb..#VacTemp4') IS NOT NULL DROP TABLE #VacTemp4;
select c.FK_Patient_Link_ID, MIN(c.EventDate) AS VaccineDoseDate
into #VacTemp4
from #VacTemp3 v
inner join #COVIDVaccines c on c.EventDate > DATEADD(day, 14, v.VaccineDoseDate) and c.FK_Patient_Link_ID = v.FK_Patient_Link_ID
group by c.FK_Patient_Link_ID;
--1860

-- Get fifth vaccine dose (if exists) - assume dose within 14 days is same dose
IF OBJECT_ID('tempdb..#VacTemp5') IS NOT NULL DROP TABLE #VacTemp5;
select c.FK_Patient_Link_ID, MIN(c.EventDate) AS VaccineDoseDate
into #VacTemp5
from #VacTemp4 v
inner join #COVIDVaccines c on c.EventDate > DATEADD(day, 14, v.VaccineDoseDate) and c.FK_Patient_Link_ID = v.FK_Patient_Link_ID
group by c.FK_Patient_Link_ID;
--39

-- Get sixth vaccine dose (if exists) - assume dose within 14 days is same dose
IF OBJECT_ID('tempdb..#VacTemp6') IS NOT NULL DROP TABLE #VacTemp6;
select c.FK_Patient_Link_ID, MIN(c.EventDate) AS VaccineDoseDate
into #VacTemp6
from #VacTemp5 v
inner join #COVIDVaccines c on c.EventDate > DATEADD(day, 14, v.VaccineDoseDate) and c.FK_Patient_Link_ID = v.FK_Patient_Link_ID
group by c.FK_Patient_Link_ID;
--2

-- Get seventh vaccine dose (if exists) - assume dose within 14 days is same dose
IF OBJECT_ID('tempdb..#VacTemp7') IS NOT NULL DROP TABLE #VacTemp7;
select c.FK_Patient_Link_ID, MIN(c.EventDate) AS VaccineDoseDate
into #VacTemp7
from #VacTemp6 v
inner join #COVIDVaccines c on c.EventDate > DATEADD(day, 14, v.VaccineDoseDate) and c.FK_Patient_Link_ID = v.FK_Patient_Link_ID
group by c.FK_Patient_Link_ID;
--2

IF OBJECT_ID('tempdb..#COVIDVaccinations') IS NOT NULL DROP TABLE #COVIDVaccinations;
SELECT v1.FK_Patient_Link_ID, v1.VaccineDoseDate AS VaccineDose1Date,
v2.VaccineDoseDate AS VaccineDose2Date,
v3.VaccineDoseDate AS VaccineDose3Date,
v4.VaccineDoseDate AS VaccineDose4Date,
v5.VaccineDoseDate AS VaccineDose5Date,
v6.VaccineDoseDate AS VaccineDose6Date,
v7.VaccineDoseDate AS VaccineDose7Date
INTO #COVIDVaccinations
FROM #VacTemp1 v1
LEFT OUTER JOIN #VacTemp2 v2 ON v2.FK_Patient_Link_ID = v1.FK_Patient_Link_ID
LEFT OUTER JOIN #VacTemp3 v3 ON v3.FK_Patient_Link_ID = v1.FK_Patient_Link_ID
LEFT OUTER JOIN #VacTemp4 v4 ON v4.FK_Patient_Link_ID = v1.FK_Patient_Link_ID
LEFT OUTER JOIN #VacTemp5 v5 ON v5.FK_Patient_Link_ID = v1.FK_Patient_Link_ID
LEFT OUTER JOIN #VacTemp6 v6 ON v6.FK_Patient_Link_ID = v1.FK_Patient_Link_ID
LEFT OUTER JOIN #VacTemp7 v7 ON v7.FK_Patient_Link_ID = v1.FK_Patient_Link_ID;

-- Tidy up
DROP TABLE #VacTemp1;
DROP TABLE #VacTemp2;
DROP TABLE #VacTemp3;
DROP TABLE #VacTemp4;
DROP TABLE #VacTemp5;
DROP TABLE #VacTemp6;
DROP TABLE #VacTemp7;



--┌─────────────────────────────────────────────────────┐
--│ Patient received flu vaccine in a given time period │
--└─────────────────────────────────────────────────────┘

-- OBJECTIVE: To find patients who received a flu vaccine in a given time period

-- INPUT: Takes three parameters
--  - date-from: YYYY-MM-DD - the start date of the time period (inclusive)
--  - date-to: YYYY-MM-DD - the end date of the time period (inclusive)
-- 	- id: string - an id flag to enable multiple temp tables to be created
-- Requires one temp table to exist as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: A temp table as follows:
-- #PatientHadFluVaccine{id} (FK_Patient_Link_ID, FluVaccineDate)
--	- FK_Patient_Link_ID - unique patient id
--	- FluVaccineDate - YYYY-MM-DD (first date of flu vaccine in given time period)

-- ASSUMPTIONS:
--	- We look for codes related to the administration of flu vaccines and codes for the vaccine itself

-- >>> Following code sets injected: flu-vaccination v1
-- First get all patients from the GP_Events table who have a flu vaccination (procedure) code
IF OBJECT_ID('tempdb..#PatientsWithFluVacConcept2015') IS NOT NULL DROP TABLE #PatientsWithFluVacConcept2015;
SELECT FK_Patient_Link_ID, CAST(EventDate AS DATE) AS FluVaccineDate
INTO #PatientsWithFluVacConcept2015
FROM RLS.[vw_GP_Events]
WHERE (
	FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'flu-vaccination' AND [Version] = 1) OR
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'flu-vaccination' AND [Version] = 1)
)
AND EventDate >= '2015-07-01'
AND EventDate <= '2016-06-30';

-- >>> Following code sets injected: flu-vaccine v1
-- Then get all patients from the GP_Medications table who have a flu vaccine (medication) code
INSERT INTO #PatientsWithFluVacConcept2015
SELECT FK_Patient_Link_ID, CAST(MedicationDate AS DATE) FROM RLS.vw_GP_Medications
WHERE (
	FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'flu-vaccine' AND [Version] = 1) OR
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'flu-vaccine' AND [Version] = 1)
)
and MedicationDate >= '2015-07-01'
and MedicationDate <= '2016-06-30';

-- Bring all together in final table
IF OBJECT_ID('tempdb..#PatientHadFluVaccine2015') IS NOT NULL DROP TABLE #PatientHadFluVaccine2015;
SELECT 
	FK_Patient_Link_ID,
	MIN(FluVaccineDate) AS FluVaccineDate
INTO #PatientHadFluVaccine2015 FROM #PatientsWithFluVacConcept2015
GROUP BY FK_Patient_Link_ID;

--┌─────────────────────────────────────────────────────┐
--│ Patient received flu vaccine in a given time period │
--└─────────────────────────────────────────────────────┘

-- OBJECTIVE: To find patients who received a flu vaccine in a given time period

-- INPUT: Takes three parameters
--  - date-from: YYYY-MM-DD - the start date of the time period (inclusive)
--  - date-to: YYYY-MM-DD - the end date of the time period (inclusive)
-- 	- id: string - an id flag to enable multiple temp tables to be created
-- Requires one temp table to exist as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: A temp table as follows:
-- #PatientHadFluVaccine{id} (FK_Patient_Link_ID, FluVaccineDate)
--	- FK_Patient_Link_ID - unique patient id
--	- FluVaccineDate - YYYY-MM-DD (first date of flu vaccine in given time period)

-- ASSUMPTIONS:
--	- We look for codes related to the administration of flu vaccines and codes for the vaccine itself

-- >>> Following code sets injected: flu-vaccination v1
-- First get all patients from the GP_Events table who have a flu vaccination (procedure) code
IF OBJECT_ID('tempdb..#PatientsWithFluVacConcept2016') IS NOT NULL DROP TABLE #PatientsWithFluVacConcept2016;
SELECT FK_Patient_Link_ID, CAST(EventDate AS DATE) AS FluVaccineDate
INTO #PatientsWithFluVacConcept2016
FROM RLS.[vw_GP_Events]
WHERE (
	FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'flu-vaccination' AND [Version] = 1) OR
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'flu-vaccination' AND [Version] = 1)
)
AND EventDate >= '2016-07-01'
AND EventDate <= '2017-06-30';

-- >>> Following code sets injected: flu-vaccine v1
-- Then get all patients from the GP_Medications table who have a flu vaccine (medication) code
INSERT INTO #PatientsWithFluVacConcept2016
SELECT FK_Patient_Link_ID, CAST(MedicationDate AS DATE) FROM RLS.vw_GP_Medications
WHERE (
	FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'flu-vaccine' AND [Version] = 1) OR
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'flu-vaccine' AND [Version] = 1)
)
and MedicationDate >= '2016-07-01'
and MedicationDate <= '2017-06-30';

-- Bring all together in final table
IF OBJECT_ID('tempdb..#PatientHadFluVaccine2016') IS NOT NULL DROP TABLE #PatientHadFluVaccine2016;
SELECT 
	FK_Patient_Link_ID,
	MIN(FluVaccineDate) AS FluVaccineDate
INTO #PatientHadFluVaccine2016 FROM #PatientsWithFluVacConcept2016
GROUP BY FK_Patient_Link_ID;

--┌─────────────────────────────────────────────────────┐
--│ Patient received flu vaccine in a given time period │
--└─────────────────────────────────────────────────────┘

-- OBJECTIVE: To find patients who received a flu vaccine in a given time period

-- INPUT: Takes three parameters
--  - date-from: YYYY-MM-DD - the start date of the time period (inclusive)
--  - date-to: YYYY-MM-DD - the end date of the time period (inclusive)
-- 	- id: string - an id flag to enable multiple temp tables to be created
-- Requires one temp table to exist as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: A temp table as follows:
-- #PatientHadFluVaccine{id} (FK_Patient_Link_ID, FluVaccineDate)
--	- FK_Patient_Link_ID - unique patient id
--	- FluVaccineDate - YYYY-MM-DD (first date of flu vaccine in given time period)

-- ASSUMPTIONS:
--	- We look for codes related to the administration of flu vaccines and codes for the vaccine itself

-- >>> Following code sets injected: flu-vaccination v1
-- First get all patients from the GP_Events table who have a flu vaccination (procedure) code
IF OBJECT_ID('tempdb..#PatientsWithFluVacConcept2017') IS NOT NULL DROP TABLE #PatientsWithFluVacConcept2017;
SELECT FK_Patient_Link_ID, CAST(EventDate AS DATE) AS FluVaccineDate
INTO #PatientsWithFluVacConcept2017
FROM RLS.[vw_GP_Events]
WHERE (
	FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'flu-vaccination' AND [Version] = 1) OR
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'flu-vaccination' AND [Version] = 1)
)
AND EventDate >= '2017-07-01'
AND EventDate <= '2018-06-30';

-- >>> Following code sets injected: flu-vaccine v1
-- Then get all patients from the GP_Medications table who have a flu vaccine (medication) code
INSERT INTO #PatientsWithFluVacConcept2017
SELECT FK_Patient_Link_ID, CAST(MedicationDate AS DATE) FROM RLS.vw_GP_Medications
WHERE (
	FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'flu-vaccine' AND [Version] = 1) OR
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'flu-vaccine' AND [Version] = 1)
)
and MedicationDate >= '2017-07-01'
and MedicationDate <= '2018-06-30';

-- Bring all together in final table
IF OBJECT_ID('tempdb..#PatientHadFluVaccine2017') IS NOT NULL DROP TABLE #PatientHadFluVaccine2017;
SELECT 
	FK_Patient_Link_ID,
	MIN(FluVaccineDate) AS FluVaccineDate
INTO #PatientHadFluVaccine2017 FROM #PatientsWithFluVacConcept2017
GROUP BY FK_Patient_Link_ID;

--┌─────────────────────────────────────────────────────┐
--│ Patient received flu vaccine in a given time period │
--└─────────────────────────────────────────────────────┘

-- OBJECTIVE: To find patients who received a flu vaccine in a given time period

-- INPUT: Takes three parameters
--  - date-from: YYYY-MM-DD - the start date of the time period (inclusive)
--  - date-to: YYYY-MM-DD - the end date of the time period (inclusive)
-- 	- id: string - an id flag to enable multiple temp tables to be created
-- Requires one temp table to exist as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: A temp table as follows:
-- #PatientHadFluVaccine{id} (FK_Patient_Link_ID, FluVaccineDate)
--	- FK_Patient_Link_ID - unique patient id
--	- FluVaccineDate - YYYY-MM-DD (first date of flu vaccine in given time period)

-- ASSUMPTIONS:
--	- We look for codes related to the administration of flu vaccines and codes for the vaccine itself

-- >>> Following code sets injected: flu-vaccination v1
-- First get all patients from the GP_Events table who have a flu vaccination (procedure) code
IF OBJECT_ID('tempdb..#PatientsWithFluVacConcept2018') IS NOT NULL DROP TABLE #PatientsWithFluVacConcept2018;
SELECT FK_Patient_Link_ID, CAST(EventDate AS DATE) AS FluVaccineDate
INTO #PatientsWithFluVacConcept2018
FROM RLS.[vw_GP_Events]
WHERE (
	FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'flu-vaccination' AND [Version] = 1) OR
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'flu-vaccination' AND [Version] = 1)
)
AND EventDate >= '2018-07-01'
AND EventDate <= '2019-06-30';

-- >>> Following code sets injected: flu-vaccine v1
-- Then get all patients from the GP_Medications table who have a flu vaccine (medication) code
INSERT INTO #PatientsWithFluVacConcept2018
SELECT FK_Patient_Link_ID, CAST(MedicationDate AS DATE) FROM RLS.vw_GP_Medications
WHERE (
	FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'flu-vaccine' AND [Version] = 1) OR
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'flu-vaccine' AND [Version] = 1)
)
and MedicationDate >= '2018-07-01'
and MedicationDate <= '2019-06-30';

-- Bring all together in final table
IF OBJECT_ID('tempdb..#PatientHadFluVaccine2018') IS NOT NULL DROP TABLE #PatientHadFluVaccine2018;
SELECT 
	FK_Patient_Link_ID,
	MIN(FluVaccineDate) AS FluVaccineDate
INTO #PatientHadFluVaccine2018 FROM #PatientsWithFluVacConcept2018
GROUP BY FK_Patient_Link_ID;

--┌─────────────────────────────────────────────────────┐
--│ Patient received flu vaccine in a given time period │
--└─────────────────────────────────────────────────────┘

-- OBJECTIVE: To find patients who received a flu vaccine in a given time period

-- INPUT: Takes three parameters
--  - date-from: YYYY-MM-DD - the start date of the time period (inclusive)
--  - date-to: YYYY-MM-DD - the end date of the time period (inclusive)
-- 	- id: string - an id flag to enable multiple temp tables to be created
-- Requires one temp table to exist as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: A temp table as follows:
-- #PatientHadFluVaccine{id} (FK_Patient_Link_ID, FluVaccineDate)
--	- FK_Patient_Link_ID - unique patient id
--	- FluVaccineDate - YYYY-MM-DD (first date of flu vaccine in given time period)

-- ASSUMPTIONS:
--	- We look for codes related to the administration of flu vaccines and codes for the vaccine itself

-- >>> Following code sets injected: flu-vaccination v1
-- First get all patients from the GP_Events table who have a flu vaccination (procedure) code
IF OBJECT_ID('tempdb..#PatientsWithFluVacConcept2019') IS NOT NULL DROP TABLE #PatientsWithFluVacConcept2019;
SELECT FK_Patient_Link_ID, CAST(EventDate AS DATE) AS FluVaccineDate
INTO #PatientsWithFluVacConcept2019
FROM RLS.[vw_GP_Events]
WHERE (
	FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'flu-vaccination' AND [Version] = 1) OR
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'flu-vaccination' AND [Version] = 1)
)
AND EventDate >= '2019-07-01'
AND EventDate <= '2020-06-30';

-- >>> Following code sets injected: flu-vaccine v1
-- Then get all patients from the GP_Medications table who have a flu vaccine (medication) code
INSERT INTO #PatientsWithFluVacConcept2019
SELECT FK_Patient_Link_ID, CAST(MedicationDate AS DATE) FROM RLS.vw_GP_Medications
WHERE (
	FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'flu-vaccine' AND [Version] = 1) OR
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'flu-vaccine' AND [Version] = 1)
)
and MedicationDate >= '2019-07-01'
and MedicationDate <= '2020-06-30';

-- Bring all together in final table
IF OBJECT_ID('tempdb..#PatientHadFluVaccine2019') IS NOT NULL DROP TABLE #PatientHadFluVaccine2019;
SELECT 
	FK_Patient_Link_ID,
	MIN(FluVaccineDate) AS FluVaccineDate
INTO #PatientHadFluVaccine2019 FROM #PatientsWithFluVacConcept2019
GROUP BY FK_Patient_Link_ID;

--┌─────────────────────────────────────────────────────┐
--│ Patient received flu vaccine in a given time period │
--└─────────────────────────────────────────────────────┘

-- OBJECTIVE: To find patients who received a flu vaccine in a given time period

-- INPUT: Takes three parameters
--  - date-from: YYYY-MM-DD - the start date of the time period (inclusive)
--  - date-to: YYYY-MM-DD - the end date of the time period (inclusive)
-- 	- id: string - an id flag to enable multiple temp tables to be created
-- Requires one temp table to exist as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: A temp table as follows:
-- #PatientHadFluVaccine{id} (FK_Patient_Link_ID, FluVaccineDate)
--	- FK_Patient_Link_ID - unique patient id
--	- FluVaccineDate - YYYY-MM-DD (first date of flu vaccine in given time period)

-- ASSUMPTIONS:
--	- We look for codes related to the administration of flu vaccines and codes for the vaccine itself

-- >>> Following code sets injected: flu-vaccination v1
-- First get all patients from the GP_Events table who have a flu vaccination (procedure) code
IF OBJECT_ID('tempdb..#PatientsWithFluVacConcept2020') IS NOT NULL DROP TABLE #PatientsWithFluVacConcept2020;
SELECT FK_Patient_Link_ID, CAST(EventDate AS DATE) AS FluVaccineDate
INTO #PatientsWithFluVacConcept2020
FROM RLS.[vw_GP_Events]
WHERE (
	FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'flu-vaccination' AND [Version] = 1) OR
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'flu-vaccination' AND [Version] = 1)
)
AND EventDate >= '2020-07-01'
AND EventDate <= '2021-06-30';

-- >>> Following code sets injected: flu-vaccine v1
-- Then get all patients from the GP_Medications table who have a flu vaccine (medication) code
INSERT INTO #PatientsWithFluVacConcept2020
SELECT FK_Patient_Link_ID, CAST(MedicationDate AS DATE) FROM RLS.vw_GP_Medications
WHERE (
	FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'flu-vaccine' AND [Version] = 1) OR
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'flu-vaccine' AND [Version] = 1)
)
and MedicationDate >= '2020-07-01'
and MedicationDate <= '2021-06-30';

-- Bring all together in final table
IF OBJECT_ID('tempdb..#PatientHadFluVaccine2020') IS NOT NULL DROP TABLE #PatientHadFluVaccine2020;
SELECT 
	FK_Patient_Link_ID,
	MIN(FluVaccineDate) AS FluVaccineDate
INTO #PatientHadFluVaccine2020 FROM #PatientsWithFluVacConcept2020
GROUP BY FK_Patient_Link_ID;

--┌─────────────────────────────────────────────────────┐
--│ Patient received flu vaccine in a given time period │
--└─────────────────────────────────────────────────────┘

-- OBJECTIVE: To find patients who received a flu vaccine in a given time period

-- INPUT: Takes three parameters
--  - date-from: YYYY-MM-DD - the start date of the time period (inclusive)
--  - date-to: YYYY-MM-DD - the end date of the time period (inclusive)
-- 	- id: string - an id flag to enable multiple temp tables to be created
-- Requires one temp table to exist as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: A temp table as follows:
-- #PatientHadFluVaccine{id} (FK_Patient_Link_ID, FluVaccineDate)
--	- FK_Patient_Link_ID - unique patient id
--	- FluVaccineDate - YYYY-MM-DD (first date of flu vaccine in given time period)

-- ASSUMPTIONS:
--	- We look for codes related to the administration of flu vaccines and codes for the vaccine itself

-- >>> Following code sets injected: flu-vaccination v1
-- First get all patients from the GP_Events table who have a flu vaccination (procedure) code
IF OBJECT_ID('tempdb..#PatientsWithFluVacConcept2021') IS NOT NULL DROP TABLE #PatientsWithFluVacConcept2021;
SELECT FK_Patient_Link_ID, CAST(EventDate AS DATE) AS FluVaccineDate
INTO #PatientsWithFluVacConcept2021
FROM RLS.[vw_GP_Events]
WHERE (
	FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'flu-vaccination' AND [Version] = 1) OR
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'flu-vaccination' AND [Version] = 1)
)
AND EventDate >= '2021-07-01'
AND EventDate <= '2022-06-01';

-- >>> Following code sets injected: flu-vaccine v1
-- Then get all patients from the GP_Medications table who have a flu vaccine (medication) code
INSERT INTO #PatientsWithFluVacConcept2021
SELECT FK_Patient_Link_ID, CAST(MedicationDate AS DATE) FROM RLS.vw_GP_Medications
WHERE (
	FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'flu-vaccine' AND [Version] = 1) OR
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'flu-vaccine' AND [Version] = 1)
)
and MedicationDate >= '2021-07-01'
and MedicationDate <= '2022-06-01';

-- Bring all together in final table
IF OBJECT_ID('tempdb..#PatientHadFluVaccine2021') IS NOT NULL DROP TABLE #PatientHadFluVaccine2021;
SELECT 
	FK_Patient_Link_ID,
	MIN(FluVaccineDate) AS FluVaccineDate
INTO #PatientHadFluVaccine2021 FROM #PatientsWithFluVacConcept2021
GROUP BY FK_Patient_Link_ID;


--┌────────────────────────────────┐
--│ Flu vaccine eligibile patients │
--└────────────────────────────────┘

-- OBJECTIVE: To obtain a table with a list of patients who are currently entitled
--            to a flu vaccine.

-- INPUT: No pre-requisites

-- OUTPUT: A temp table as follows:
-- #FluVaccPatients (FK_Patient_Link_ID)
-- 	- FK_Patient_Link_ID - unique patient id

-- Populate temporary table with patients elibigle for a flu vaccine
IF OBJECT_ID('tempdb..#FluVaccPatients') IS NOT NULL DROP TABLE #FluVaccPatients;
SELECT DISTINCT FK_Patient_Link_ID
INTO #FluVaccPatients
FROM [RLS].[vw_Cohort_Patient_Registers]
WHERE FK_Cohort_Register_ID IN (
	SELECT PK_Cohort_Register_ID FROM SharedCare.Cohort_Register
	WHERE FK_Cohort_Category_ID IN (
		SELECT PK_Cohort_Category_ID FROM SharedCare.Cohort_Category
		WHERE CategoryName = 'Flu Immunisation' -- Description is "Registers related to identification of at risk patients requiring Flu Immunisation";
	)
)


-- Get patients with moderate covid vulnerability defined as
-- 	-	eligible for a flu vaccine
--	-	has a severe mental illness
--	-	has a moderate clinical vulnerability to COVID code in their record
-- >>> Following code sets injected: moderate-clinical-vulnerability v1/severe-mental-illness v1
SELECT FK_Patient_Link_ID INTO #ModerateVulnerabilityPatients FROM [RLS].[vw_GP_Events]
WHERE SuppliedCode IN (
	SELECT [Code] FROM #AllCodes WHERE [Concept] IN ('moderate-clinical-vulnerability','severe-mental-illness') AND [Version] = 1
)
AND EventDate < @TEMPRQ025EndDate
UNION
SELECT FK_Patient_Link_ID FROM #FluVaccPatients;

-- Get patients with high covid vulnerability flag and date of first entry
-- >>> Following code sets injected: high-clinical-vulnerability v1
SELECT FK_Patient_Link_ID, MIN(EventDate) AS HighVulnerabilityCodeDate INTO #HighVulnerabilityPatients FROM [RLS].[vw_GP_Events]
WHERE SuppliedCode IN (SELECT [Code] FROM #AllCodes WHERE [Concept] = 'high-clinical-vulnerability' AND [Version] = 1)
AND EventDate < @TEMPRQ025EndDate
GROUP BY FK_Patient_Link_ID;

-- Get patients with covid vaccine refusal
-- >>> Following code sets injected: covid-vaccine-declined v1
SELECT FK_Patient_Link_ID, MIN(EventDate) AS DateVaccineDeclined INTO #VaccineDeclinedPatients FROM [RLS].[vw_GP_Events]
WHERE SuppliedCode IN (SELECT [Code] FROM #AllCodes WHERE [Concept] = 'covid-vaccine-declined' AND [Version] = 1)
AND EventDate < @TEMPRQ025EndDate
GROUP BY FK_Patient_Link_ID;

-- Get first COVID admission rather than all admissions
IF OBJECT_ID('tempdb..#FirstCOVIDAdmission') IS NOT NULL DROP TABLE #FirstCOVIDAdmission;
SELECT p.FK_Patient_Link_ID, MIN(AdmissionDate) AS DateOfFirstCovidHospitalisation INTO #FirstCOVIDAdmission FROM #Patients p
INNER JOIN #COVIDUtilisationAdmissions c ON c.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE CovidHealthcareUtilisation = 'TRUE'
AND AdmissionDate < @TEMPRQ025EndDate
GROUP BY p.FK_Patient_Link_ID;

-- Get patient list of those with COVID death within 28 days of positive test
IF OBJECT_ID('tempdb..#COVIDDeath') IS NOT NULL DROP TABLE #COVIDDeath;
SELECT DISTINCT FK_Patient_Link_ID INTO #COVIDDeath FROM RLS.vw_COVID19
WHERE DeathWithin28Days = 'Y'
AND EventDate < @TEMPRQ025EndDate;

-- Bring it all together for output
SELECT 
	p.FK_Patient_Link_ID AS PatientId,
	2020 - YearOfBirth AS AgeAtIndexDate,
	Sex,
	EthnicCategoryDescription AS Ethnicity,
	LSOA_Code AS LSOA,
	IsCareHomeResident,
	CASE WHEN HighVulnerabilityCodeDate IS NOT NULL THEN 'Y' ELSE 'N' END AS HasHighClinicalVulnerabilityIndicator,
	HighVulnerabilityCodeDate AS DateOfHighClinicalVulnerabilityIndicator,
	CASE WHEN mv.FK_Patient_Link_ID IS NOT NULL THEN 'Y' ELSE 'N' END AS HasModerateClinicalVulnerability,
	CASE WHEN flu.FK_Patient_Link_ID IS NOT NULL THEN 'Y' ELSE 'N' END AS IsClinicallyEligibleForFluVaccine,
	fluvac2015.FluVaccineDate AS DateOfFluVaccineIn20152016Season,
	fluvac2016.FluVaccineDate AS DateOfFluVaccineIn20162017Season,
	fluvac2017.FluVaccineDate AS DateOfFluVaccineIn20172018Season,
	fluvac2018.FluVaccineDate AS DateOfFluVaccineIn20182019Season,
	fluvac2019.FluVaccineDate AS DateOfFluVaccineIn20192020Season,
	fluvac2020.FluVaccineDate AS DateOfFluVaccineIn20202021Season,
	fluvac2021.FluVaccineDate AS DateOfFluVaccineIn20212022Season,
	CASE WHEN DateOfFirstCovidHospitalisation IS NOT NULL THEN 'Y' ELSE 'N' END AS HasCovidHospitalisation,
	DateOfFirstCovidHospitalisation,
	CASE WHEN cd.FK_Patient_Link_ID IS NOT NULL THEN 'Y' ELSE 'N' END AS HasCovidDeathWithin28Days,
	VaccineDose1Date AS FirstVaccineDate,
	VaccineDose2Date AS SecondVaccineDate,
	VaccineDose3Date AS ThirdVaccineDate,
	VaccineDose4Date AS FourthVaccineDate,
	VaccineDose5Date AS FifthVaccineDate,
	VaccineDose6Date AS SixthVaccineDate,
	VaccineDose7Date AS SeventhVaccineDate,
	DateVaccineDeclined,
	DeathDate AS DateOfDeath
FROM #Patients p
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientLSOA l ON l.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientCareHomeStatus chs ON chs.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #HighVulnerabilityPatients hv ON hv.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #ModerateVulnerabilityPatients mv ON mv.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #FirstCOVIDAdmission ca ON ca.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDDeath cd ON cd.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDVaccinations v ON v.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #VaccineDeclinedPatients vd ON vd.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #FluVaccPatients flu ON flu.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientHadFluVaccine2015 fluvac2015 ON fluvac2015.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientHadFluVaccine2016 fluvac2016 ON fluvac2016.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientHadFluVaccine2017 fluvac2017 ON fluvac2017.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientHadFluVaccine2018 fluvac2018 ON fluvac2018.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientHadFluVaccine2019 fluvac2019 ON fluvac2019.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientHadFluVaccine2020 fluvac2020 ON fluvac2020.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientHadFluVaccine2021 fluvac2021 ON fluvac2021.FK_Patient_Link_ID = p.FK_Patient_Link_ID;
