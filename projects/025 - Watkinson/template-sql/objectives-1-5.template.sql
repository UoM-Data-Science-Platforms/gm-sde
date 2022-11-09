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

--> EXECUTE query-patient-year-of-birth.sql

-- Remove patients who are currently <16
-- UPDATE RW - PI advised to remove the <16 restriction

IF OBJECT_ID('tempdb..#Temp') IS NOT NULL DROP TABLE #Temp;
SELECT p.FK_Patient_Link_ID, EthnicCategoryDescription, DeathDate INTO #Temp FROM #Patients p
	INNER JOIN #PatientYearOfBirth y ON y.FK_Patient_Link_ID = p.FK_Patient_Link_ID;
TRUNCATE TABLE #Patients;
INSERT INTO #Patients
SELECT * FROM #Temp;

--> EXECUTE query-patient-lsoa.sql
--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-care-home-resident.sql

--> EXECUTE query-get-admissions-and-length-of-stay.sql all-patients:true
--> EXECUTE query-admissions-covid-utilisation.sql start-date:2020-02-01 all-patients:true gp-events-table:RLS.vw_GP_Events

--> EXECUTE query-get-covid-vaccines.sql gp-events-table:RLS.vw_GP_Events gp-medications-table:RLS.vw_GP_Medications

--> EXECUTE query-received-flu-vaccine.sql date-from:2015-07-01 date-to:2016-06-30 id:2015
--> EXECUTE query-received-flu-vaccine.sql date-from:2016-07-01 date-to:2017-06-30 id:2016
--> EXECUTE query-received-flu-vaccine.sql date-from:2017-07-01 date-to:2018-06-30 id:2017
--> EXECUTE query-received-flu-vaccine.sql date-from:2018-07-01 date-to:2019-06-30 id:2018
--> EXECUTE query-received-flu-vaccine.sql date-from:2019-07-01 date-to:2020-06-30 id:2019
--> EXECUTE query-received-flu-vaccine.sql date-from:2020-07-01 date-to:2021-06-30 id:2020
--> EXECUTE query-received-flu-vaccine.sql date-from:2021-07-01 date-to:2022-06-01 id:2021

--> EXECUTE query-get-flu-vaccine-eligible.sql

-- Get patients with moderate covid vulnerability defined as
-- 	-	eligible for a flu vaccine
--	-	has a severe mental illness
--	-	has a moderate clinical vulnerability to COVID code in their record
--> CODESET moderate-clinical-vulnerability:1 severe-mental-illness:1
SELECT FK_Patient_Link_ID INTO #ModerateVulnerabilityPatients FROM [RLS].[vw_GP_Events]
WHERE SuppliedCode IN (
	SELECT [Code] FROM #AllCodes WHERE [Concept] IN ('moderate-clinical-vulnerability','severe-mental-illness') AND [Version] = 1
)
AND EventDate < @TEMPRQ025EndDate
UNION
SELECT FK_Patient_Link_ID FROM #FluVaccPatients;

-- Get patients with high covid vulnerability flag and date of first entry
--> CODESET high-clinical-vulnerability:1
SELECT FK_Patient_Link_ID, MIN(EventDate) AS HighVulnerabilityCodeDate INTO #HighVulnerabilityPatients FROM [RLS].[vw_GP_Events]
WHERE SuppliedCode IN (SELECT [Code] FROM #AllCodes WHERE [Concept] = 'high-clinical-vulnerability' AND [Version] = 1)
AND EventDate < @TEMPRQ025EndDate
GROUP BY FK_Patient_Link_ID;

-- Get patients with covid vaccine refusal
--> CODESET covid-vaccine-declined:1
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
