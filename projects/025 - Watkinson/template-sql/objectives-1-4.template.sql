--┌────────────────────────────────────┐
--│ An example SQL generation template │
--└────────────────────────────────────┘

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
--  - DateOfModerateClinicalVulnerabilityIndicator
--  - HasCovidHospitalisation (Y/N)
--  - HasCovidDeathWithin28Days (Y/N)
--  - HasCovidVaccine1stDose (Y/N)
--  - HasCovidVaccine2ndDose (Y/N)
--  - DistanceFromHomeTo1stVaccine
--  - DistanceFromHomeTo2ndVaccine
--  - DistanceFromHomeToNearestVaccineHub
--  - DateOfFirstCovidHospitalisation
--  - DateOfDeath
--  - DateOfEntry
--  - DateOfExit

--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2020-02-01';

-- Get all patients
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT PK_Patient_Link_ID as FK_Patient_Link_ID, EthnicMainGroup, DeathDate INTO #Patients FROM [RLS].vw_Patient_Link;

--> EXECUTE query-patient-year-of-birth.sql

-- Remove patients who were <16 on 1st Feb 2020
DELETE FROM #PatientYearOfBirth WHERE 2020 - YearOfBirth <= 16;
IF OBJECT_ID('tempdb..#Temp') IS NOT NULL DROP TABLE #Temp;
SELECT p.FK_Patient_Link_ID, EthnicMainGroup INTO #Temp FROM #Patients p
	INNER JOIN #PatientYearOfBirth y ON y.FK_Patient_Link_ID = p.FK_Patient_Link_ID;
TRUNCATE TABLE #Patients;
INSERT INTO #Patients
SELECT * FROM #Temp;

--> EXECUTE query-patient-lsoa.sql
--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-care-home-resident.sql

--> EXECUTE query-get-admissions-and-length-of-stay.sql
--> EXECUTE query-admissions-covid-utilisation.sql

--> EXECUTE load-code-sets.sql

--> EXECUTE query-get-covid-vaccines.sql

-- Get patients with high covid vulnerability flag and date of first entry
SELECT FK_Patient_Link_ID, MIN(EventDate) AS HighVulnerabilityCodeDate INTO #HighVulnerabilityPatients FROM [RLS].[vw_GP_Events]
WHERE SuppliedCode IN (SELECT [code] FROM #AllCodes WHERE [concept] = 'high-clinical-vulnerability' AND [version] = 1)
GROUP BY FK_Patient_Link_ID;

-- Get first COVID admission rather than all admissions
IF OBJECT_ID('tempdb..#FirstCOVIDAdmission') IS NOT NULL DROP TABLE #FirstCOVIDAdmission;
SELECT p.FK_Patient_Link_ID, MIN(AdmissionDate) AS DateOfFirstCovidHospitalisation INTO #FirstCOVIDAdmission FROM #Patients p
INNER JOIN #COVIDUtilisationAdmissions c ON c.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE CovidHealthcareUtilisation = 'TRUE'
GROUP BY p.FK_Patient_Link_ID;

-- Get patient list of those with COVID death within 28 days of positive test
IF OBJECT_ID('tempdb..#COVIDDeath') IS NOT NULL DROP TABLE #COVIDDeath;
SELECT FK_Patient_Link_ID INTO #COVIDDeath FROM RLS.vw_COVID19
WHERE DeathWithin28Days = 'Y';

-- Bring it all together for output
PRINT 'PatientId,AgeAtIndexDate,Sex,Ethnicity,LSOA,IsCareHomeResident,HasHighClinicalVulnerabilityIndicator,DateOfHighClinicalVulnerabilityIndicator,HasCovidHospitalisation,DateOfFirstCovidHospitalisation,HasCovidDeathWithin28Days,FirstVaccineDate,SecondVaccineDate,DateOfDeath';
SELECT 
	p.FK_Patient_Link_ID AS PatientId,
	2020 - YearOfBirth AS AgeAtIndexDate,
	Sex,
	EthnicMainGroup AS Ethnicity,
	LSOA_Code AS LSOA,
	IsCareHomeResident,
	CASE WHEN HighVulnerabilityCodeDate IS NOT NULL THEN 'Y' ELSE 'N' END AS HasHighClinicalVulnerabilityIndicator,
	HighVulnerabilityCodeDate AS DateOfHighClinicalVulnerabilityIndicator,
	CASE WHEN DateOfFirstCovidHospitalisation IS NOT NULL THEN 'Y' ELSE 'N' END AS HasCovidHospitalisation,
	DateOfFirstCovidHospitalisation,
	CASE WHEN cd.FK_Patient_Link_ID IS NOT NULL THEN 'Y' ELSE 'N' END AS HasCovidDeathWithin28Days,
	FirstVaccineDate,
	CASE WHEN SecondVaccineDate > FirstVaccineDate THEN SecondVaccineDate ELSE NULL END AS SecondVaccineDate,
	DeathDate AS DateOfDeath
FROM #Patients p
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientLSOA l ON l.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientCareHomeStatus chs ON chs.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #HighVulnerabilityPatients hv ON hv.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #FirstCOVIDAdmission ca ON ca.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDDeath cd ON cd.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDVaccines v ON v.FK_Patient_Link_ID = p.FK_Patient_Link_ID;

