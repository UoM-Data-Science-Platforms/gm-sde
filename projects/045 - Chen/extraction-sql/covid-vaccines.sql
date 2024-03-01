--┌────────────────────────────────────┐
--│ Covid vaccination dates            │
--└────────────────────────────────────┘

-- OBJECTIVE: To find patients' covid vaccine dates (1 row per patient)

-- OUTPUT: Data with the following fields
---- PatientId
---- VaccineDose1_YearAndMonth
---- VaccineDose2_YearAndMonth
---- VaccineDose3_YearAndMonth
---- VaccineDose4_YearAndMonth
---- VaccineDose5_YearAndMonth
---- VaccineDose6_YearAndMonth
---- VaccineDose7_YearAndMonth

--┌──────────────────────────────────────────────────────────────────────┐
--│ Define Cohort for RQ045: COVID-19 vaccine hesitancy and acceptance   │
--└──────────────────────────────────────────────────────────────────────┘

-- OBJECTIVE: To build the cohort of patients needed for RQ045. This reduces
--						duplication of code in the template scripts. The cohort is any
--						patient who have no missing data for YOB, sex, LSOA and ethnicity

-- OUTPUT: A temp tables as follows:
-- #Patients
-- - PatientID
-- - Sex
-- - YOB
-- - LSOA
-- - Ethnicity


DECLARE @StudyStartDate datetime;
SET @StudyStartDate = '2020-01-01';

--┌───────────────────────────────────────────────────────────┐
--│ Create table of patients who are registered with a GM GP  │
--└───────────────────────────────────────────────────────────┘

-- INPUT REQUIREMENTS: @StudyStartDate

-- Find all patients alive at start date
IF OBJECT_ID('tempdb..#PossiblePatients') IS NOT NULL DROP TABLE #PossiblePatients;
SELECT PK_Patient_Link_ID as FK_Patient_Link_ID, EthnicMainGroup, EthnicGroupDescription, DeathDate INTO #PossiblePatients FROM [SharedCare].Patient_Link
WHERE 
	(DeathDate IS NULL OR (DeathDate >= @StudyStartDate))

-- Find all patients registered with a GP
IF OBJECT_ID('tempdb..#PatientsWithGP') IS NOT NULL DROP TABLE #PatientsWithGP;
SELECT DISTINCT FK_Patient_Link_ID INTO #PatientsWithGP FROM [SharedCare].Patient
where FK_Reference_Tenancy_ID = 2
AND GPPracticeCode NOT LIKE 'ZZZ%';

-- Make cohort from patients alive at start date and registered with a GP
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT pp.* INTO #Patients FROM #PossiblePatients pp
INNER JOIN #PatientsWithGP gp on gp.FK_Patient_Link_ID = pp.FK_Patient_Link_ID;

------------------------------------------

-- OUTPUT: #Patients
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
FROM SharedCare.Patient p
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
FROM SharedCare.Patient p
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
FROM SharedCare.Patient p
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

-- The cohort table========================================================================================================================================
IF OBJECT_ID('tempdb..#Cohort') IS NOT NULL DROP TABLE #Cohort;
SELECT
  p.FK_Patient_Link_ID,
  Sex,
  YearOfBirth,
  LSOA_Code,
  Ethnicity = EthnicGroupDescription,
  DeathDate
INTO #Cohort
FROM #Patients p
LEFT OUTER JOIN #PatientYearOfBirth y ON p.FK_Patient_Link_ID = y.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientLSOA l ON l.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE y.YearOfBirth IS NOT NULL AND sex.Sex IS NOT NULL AND l.LSOA_Code IS NOT NULL
	AND YEAR(GETDATE()) - y.YearOfBirth >= 18;


-- Filter #Patients table to cohort only - for other reusable queries ===========================================================================
DELETE FROM #Patients
WHERE FK_Patient_Link_ID NOT IN 
	(SELECT FK_Patient_Link_ID FROM #Cohort);
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

--#region Clinical code sets

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
VALUES ('covid-vaccination',1,'65F0.',NULL,'2019-nCoV (novel coronavirus) vaccination'),('covid-vaccination',1,'65F0.00',NULL,'2019-nCoV (novel coronavirus) vaccination'),('covid-vaccination',1,'65F01',NULL,'Administration of first dose of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccine'),('covid-vaccination',1,'65F0100',NULL,'Administration of first dose of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccine'),('covid-vaccination',1,'65F02',NULL,'2019-nCoV (novel coronavirus) vaccination'),('covid-vaccination',1,'65F0200',NULL,'2019-nCoV (novel coronavirus) vaccination'),('covid-vaccination',1,'65F06',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccination'),('covid-vaccination',1,'65F0600',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccination'),('covid-vaccination',1,'65F07',NULL,'Immunisation course to achieve immunity against SARS-CoV-2'),('covid-vaccination',1,'65F0700',NULL,'Immunisation course to achieve immunity against SARS-CoV-2'),('covid-vaccination',1,'65F08',NULL,'Immunisation course to maintain protection against SARS-CoV-2'),('covid-vaccination',1,'65F0800',NULL,'Immunisation course to maintain protection against SARS-CoV-2'),('covid-vaccination',1,'65F09',NULL,'Administration of third dose of SARS-CoV-2 vaccine'),('covid-vaccination',1,'65F0900',NULL,'Administration of third dose of SARS-CoV-2 vaccine'),('covid-vaccination',1,'65F0A',NULL,'Administration of fourth dose of SARS-CoV-2 vaccine'),('covid-vaccination',1,'65F0A00',NULL,'Administration of fourth dose of SARS-CoV-2 vaccine'),('covid-vaccination',1,'9bJ..',NULL,'COVID-19 mRNA Vaccine BNT162b2 30micrograms/0.3ml dose concentrate for suspension for injection multidose vials (Pfizer-BioNTech)'),('covid-vaccination',1,'9bJ..00',NULL,'COVID-19 mRNA Vaccine BNT162b2 30micrograms/0.3ml dose concentrate for suspension for injection multidose vials (Pfizer-BioNTech)')

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
VALUES ('covid-vaccination',1,'Y210d',NULL,'2019-nCoV (novel coronavirus) vaccination'),('covid-vaccination',1,'Y29e7',NULL,'Administration of first dose of SARS-CoV-2 vaccine'),('covid-vaccination',1,'Y29e8',NULL,'Administration of second dose of SARS-CoV-2 vaccine'),('covid-vaccination',1,'Y2a0e',NULL,'SARS-2 Coronavirus vaccine'),('covid-vaccination',1,'Y2a0f',NULL,'COVID-19 mRNA Vaccine BNT162b2 30micrograms/0.3ml dose concentrate for suspension for injection multidose vials (Pfizer-BioNTech) part 1'),('covid-vaccination',1,'Y2a3a',NULL,'COVID-19 mRNA Vaccine BNT162b2 30micrograms/0.3ml dose concentrate for suspension for injection multidose vials (Pfizer-BioNTech) part 2'),('covid-vaccination',1,'65F06',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccination'),('covid-vaccination',1,'65F09',NULL,'Administration of third dose of SARS-CoV-2 vaccine'),('covid-vaccination',1,'65F0A',NULL,'Administration of fourth dose of SARS-CoV-2 vaccine'),('covid-vaccination',1,'9bJ..',NULL,'COVID-19 mRNA Vaccine BNT162b2 30micrograms/0.3ml dose concentrate for suspension for injection multidose vials (Pfizer-BioNTech)'),('covid-vaccination',1,'Y2a10',NULL,'COVID-19 Vac AstraZeneca (ChAdOx1 S recomb) 5x10000000000 viral particles/0.5ml dose sol for inj MDV part 1'),('covid-vaccination',1,'Y2a39',NULL,'COVID-19 Vac AstraZeneca (ChAdOx1 S recomb) 5x10000000000 viral particles/0.5ml dose sol for inj MDV part 2'),('covid-vaccination',1,'Y2b9d',NULL,'COVID-19 mRNA (nucleoside modified) Vaccine Moderna 0.1mg/0.5mL dose dispersion for injection multidose vials part 2'),('covid-vaccination',1,'Y2f45',NULL,'Administration of third dose of SARS-CoV-2 vaccine'),('covid-vaccination',1,'Y2f48',NULL,'Administration of fourth dose of SARS-CoV-2 vaccine'),('covid-vaccination',1,'Y2f57',NULL,'COVID-19 mRNA Vaccine BNT162b2 30micrograms/0.3ml dose concentrate for suspension for injection multidose vials (Pfizer-BioNTech) booster'),('covid-vaccination',1,'Y31cc',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) antigen vaccination'),('covid-vaccination',1,'Y31e6',NULL,'Administration of SARS-CoV-2 mRNA vaccine'),('covid-vaccination',1,'Y31e7',NULL,'Administration of first dose of SARS-CoV-2 mRNA vaccine'),('covid-vaccination',1,'Y31e8',NULL,'Administration of second dose of SARS-CoV-2 mRNA vaccine')

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
VALUES ('covid-vaccination',1,'1240491000000103',NULL,'2019-nCoV (novel coronavirus) vaccination'),('covid-vaccination',1,'2807821000000115',NULL,'2019-nCoV (novel coronavirus) vaccination'),('covid-vaccination',1,'90640007',NULL,'Coronavirus vaccination (procedure)'),('covid-vaccination',1,'1324691000000104',NULL,'Administration of second dose of severe acute respiratory syndrome coronavirus 2 vaccine (procedure)'),('covid-vaccination',1,'1324681000000101',NULL,'Administration of first dose of severe acute respiratory syndrome coronavirus 2 vaccine (procedure)'),('covid-vaccination',1,'39330711000001103',NULL,'COVID-19 vaccine (product)'),('covid-vaccination',1,'41823011000001100',NULL,'Generic COVID-19 Vaccine Moderna (mRNA-1273.222) 50micrograms/0.5ml dose solution for injection vials (product)'),('covid-vaccination',1,'41822811000001103',NULL,'COVID-19 Vaccine Moderna (mRNA-1273.222) 50micrograms/0.5ml dose solution for injection vials (Moderna, Inc) (product)'),('covid-vaccination',1,'41823411000001109',NULL,'Generic COVID-19 Vaccine Moderna (mRNA-1283.222) 10micrograms/0.2ml dose solution for injection vials (product)'),('covid-vaccination',1,'41823211000001105',NULL,'COVID-19 Vaccine Moderna (mRNA-1283.222) 10micrograms/0.2ml dose solution for injection vials (Moderna, Inc) (product)'),('covid-vaccination',1,'42118311000001108',NULL,'Generic Comirnaty Omicron XBB.1.5 Children 6 months - 4 years COVID-19 mRNA Vaccine 3micrograms/0.2ml dose concentrate for dispersion for injection multidose vials (product)'),('covid-vaccination',1,'42098911000001101',NULL,'Comirnaty Omicron XBB.1.5 Children 6 months - 4 years COVID-19 mRNA Vaccine 3micrograms/0.2ml dose concentrate for dispersion for injection multidose vials (Pfizer Ltd) (product)'),('covid-vaccination',1,'42118211000001100',NULL,'Generic Comirnaty Omicron XBB.1.5 Children 5-11 years COVID-19 mRNA Vaccine 10micrograms/0.3ml dose dispersion for injection multidose vials (product)'),('covid-vaccination',1,'42098011000001100',NULL,'Comirnaty Omicron XBB.1.5 Children 5-11 years COVID-19 mRNA Vaccine 10micrograms/0.3ml dose dispersion for injection multidose vials (Pfizer Ltd) (product)'),('covid-vaccination',1,'39828011000001104',NULL,'Generic COVID-19 Vaccine Medicago (CoVLP) 3.75micrograms/0.5ml dose emulsion for injection multidose vials (product)'),('covid-vaccination',1,'39826711000001101',NULL,'COVID-19 Vaccine Medicago (CoVLP) 3.75micrograms/0.5ml dose emulsion for injection multidose vials (Medicago Inc) (product)'),('covid-vaccination',1,'40872611000001106',NULL,'Generic COVID-19 Vaccine Sanofi (CoV2 preS dTM bivalent D614+B.1.351 [recombinant adjuvanted]) 2.5micrograms/2.5micrograms/0.5ml dose emulsion for injection multidose vials (product)'),('covid-vaccination',1,'40872311000001101',NULL,'COVID-19 Vaccine Sanofi (CoV2 preS dTM bivalent D614+B.1.351 [recombinant adjuvanted]) 2.5micrograms/2.5micrograms/0.5ml dose emulsion for injection multidose vials (Sanofi) (product)'),('covid-vaccination',1,'40872511000001107',NULL,'Generic COVID-19 Vaccine VidPrevtyn Beta (CoV2 preS dTM monovalent B.1.351 [recombinant adjuvanted]) 5micrograms/0.5ml dose solution and emulsion for emulsion for injection multidose vials (product)'),('covid-vaccination',1,'40872011000001104',NULL,'COVID-19 Vaccine VidPrevtyn Beta (CoV2 preS dTM monovalent B.1.351 [recombinant adjuvanted]) 5micrograms/0.5ml dose solution and emulsion for emulsion for injection multidose vials (Sanofi) (product)'),('covid-vaccination',1,'40859611000001101',NULL,'Generic Comirnaty Original/Omicron BA.1 COVID-19 mRNA Vaccine 15micrograms/15micrograms/0.3ml dose dispersion for injection multidose vials (product)'),('covid-vaccination',1,'40851611000001102',NULL,'Comirnaty Original/Omicron BA.1 COVID-19 mRNA Vaccine 15micrograms/15micrograms/0.3ml dose dispersion for injection multidose vials (Pfizer Ltd) (product)'),('covid-vaccination',1,'39375211000001103',NULL,'Generic COVID-19 Vaccine Valneva (inactivated adjuvanted whole virus) 40antigen units/0.5ml dose suspension for injection multidose vials (product)'),('covid-vaccination',1,'39373511000001104',NULL,'COVID-19 Vaccine Valneva (inactivated adjuvanted whole virus) 40antigen units/0.5ml dose suspension for injection multidose vials (Valneva UK Ltd) (product)'),('covid-vaccination',1,'41238811000001106',NULL,'Generic Comirnaty Original/Omicron BA.4-5 COVID-19 mRNA Vaccine 15micrograms/15micrograms/0.3ml dose dispersion for injection multidose vials (product)'),('covid-vaccination',1,'41239511000001102',NULL,'Comirnaty Original/Omicron BA.4-5 COVID-19 mRNA Vaccine 15micrograms/15micrograms/0.3ml dose dispersion for injection multidose vials (Pfizer Ltd) (product)'),('covid-vaccination',1,'40813111000001102',NULL,'Generic COVID-19 Vaccine Spikevax 0 (Zero)/O (Omicron) 0.1mg/ml dispersion for injection multidose vials (product)'),('covid-vaccination',1,'40801911000001102',NULL,'COVID-19 Vaccine Spikevax 0 (Zero)/O (Omicron) 0.1mg/ml dispersion for injection multidose vials (Moderna, Inc) (product)'),('covid-vaccination',1,'40713711000001104',NULL,'Generic COVID-19 Vaccine Convidecia (Adenovirus Type 5 Vector [recombinant]) 40,000,000,000 viral particles/0.5ml dose solution for injection vials (product)'),('covid-vaccination',1,'40712911000001109',NULL,'COVID-19 Vaccine Convidecia (Adenovirus Type 5 Vector [recombinant]) 40,000,000,000 viral particles/0.5ml dose solution for injection vials (CanSino Biologics Inc) (product)'),('covid-vaccination',1,'41344311000001100',NULL,'Generic COVID-19 Vaccine Spikevax Original/Omicron BA.4/BA.5 dispersion for injection 0.1mg/ml multidose vials (product)'),('covid-vaccination',1,'41343811000001106',NULL,'COVID-19 Vaccine Spikevax Original/Omicron BA.4/BA.5 dispersion for injection 0.1mg/ml multidose vials (Moderna, Inc) (product)'),('covid-vaccination',1,'40520611000001105',NULL,'Generic COVID-19 Vaccine Moderna (mRNA-1273.529) 50micrograms/0.25ml dose solution for injection multidose vials (product)'),('covid-vaccination',1,'40520411000001107',NULL,'COVID-19 Vaccine Moderna (mRNA-1273.529) 50micrograms/0.25ml dose solution for injection multidose vials (Moderna, Inc) (product)'),('covid-vaccination',1,'42029111000001101',NULL,'Generic Spikevax XBB.1.5 COVID-19 mRNA Vaccine 0.1mg/1ml dispersion for injection multidose vials (product)'),('covid-vaccination',1,'42023311000001102',NULL,'Spikevax XBB.1.5 COVID-19 mRNA Vaccine 0.1mg/1ml dispersion for injection multidose vials (Moderna, Inc) (product)'),('covid-vaccination',1,'39116211000001106',NULL,'Generic COVID-19 Vaccine Vaxzevria (ChAdOx1 S [recombinant]) not less than 2.5x100,000,000 infectious units/0.5ml dose suspension for injection multidose vials (product)'),('covid-vaccination',1,'39114911000001105',NULL,'COVID-19 Vaccine Vaxzevria (ChAdOx1 S [recombinant]) not less than 2.5x100,000,000 infectious units/0.5ml dose suspension for injection multidose vials (AstraZeneca UK Ltd) (product)'),('covid-vaccination',1,'39326811000001106',NULL,'Generic Spikevax COVID-19 mRNA (nucleoside modified) Vaccine 0.1mg/0.5ml dose dispersion for injection multidose vials (product)'),('covid-vaccination',1,'39326911000001101',NULL,'Spikevax COVID-19 mRNA (nucleoside modified) Vaccine 0.1mg/0.5ml dose dispersion for injection multidose vials (Moderna, Inc) (product)'),('covid-vaccination',1,'39233911000001100',NULL,'Generic COVID-19 Vaccine Janssen (Ad26.COV2-S [recombinant]) 0.5ml dose suspension for injection multidose vials (product)'),('covid-vaccination',1,'39230211000001104',NULL,'COVID-19 Vaccine Janssen (Ad26.COV2-S [recombinant]) 0.5ml dose suspension for injection multidose vials (Janssen-Cilag Ltd) (product)'),('covid-vaccination',1,'39116111000001100',NULL,'Generic Comirnaty COVID-19 mRNA Vaccine 30micrograms/0.3ml dose concentrate for dispersion for injection multidose vials (product)'),('covid-vaccination',1,'39115611000001103',NULL,'Comirnaty COVID-19 mRNA Vaccine 30micrograms/0.3ml dose concentrate for dispersion for injection multidose vials (Pfizer Ltd) (product)'),('covid-vaccination',1,'40557211000001108',NULL,'Generic Comirnaty COVID-19 mRNA Vaccine ready to use 30micrograms/0.3ml dose dispersion for injection multidose vials (product)'),('covid-vaccination',1,'40556911000001102',NULL,'Comirnaty COVID-19 mRNA Vaccine ready to use 30micrograms/0.3ml dose dispersion for injection multidose vials (Pfizer Ltd) (product)'),('covid-vaccination',1,'41179211000001100',NULL,'Generic Comirnaty Children 6 months - 4 years COVID-19 mRNA Vaccine 3micrograms/0.2ml dose concentrate for dispersion for injection multidose vials (product)'),('covid-vaccination',1,'41178911000001101',NULL,'Comirnaty Children 6 months - 4 years COVID-19 mRNA Vaccine 3micrograms/0.2ml dose concentrate for dispersion for injection multidose vials (Pfizer Ltd) (product)'),('covid-vaccination',1,'40506711000001109',NULL,'Generic COVID-19 Vaccine Sanofi (CoV2 preS dTM monovalent D614 [recombinant]) 5micrograms/0.5ml dose suspension for injection multidose vials (product)'),('covid-vaccination',1,'40506311000001105',NULL,'COVID-19 Vaccine Sanofi (CoV2 preS dTM monovalent D614 [recombinant]) 5micrograms/0.5ml dose suspension for injection multidose vials (Sanofi) (product)'),('covid-vaccination',1,'40411511000001102',NULL,'Generic COVID-19 Vaccine AZD2816 AstraZeneca (ChAdOx1 nCOV-19) 3.5x10,000,000,000 viral particles/0.5ml dose solution for injection multidose vials (product)'),('covid-vaccination',1,'40402411000001109',NULL,'COVID-19 Vaccine AZD2816 AstraZeneca (ChAdOx1 nCOV-19) 3.5x10,000,000,000 viral particles/0.5ml dose solution for injection multidose vials (AstraZeneca AB) (product)'),('covid-vaccination',1,'40389011000001100',NULL,'Generic Comirnaty Children 5-11 years COVID-19 mRNA Vaccine 10micrograms/0.2ml dose concentrate for dispersion for injection multidose vials (product)'),('covid-vaccination',1,'40384611000001108',NULL,'Comirnaty Children 5-11 years COVID-19 mRNA Vaccine 10micrograms/0.2ml dose concentrate for dispersion for injection multidose vials (Pfizer Ltd) (product)'),
('covid-vaccination',1,'40388611000001103',NULL,'Generic COVID-19 Vaccine Sputnik V Component I (recombinant serotype 26 adenoviral particles) 100,000,000,000 viral particles/0.5ml dose solution for injection multidose vials (product)'),('covid-vaccination',1,'40387411000001100',NULL,'COVID-19 Vaccine Sputnik V Component I (recombinant serotype 26 adenoviral particles) 100,000,000,000 viral particles/0.5ml dose solution for injection multidose vials (Gamaleya NRCEM) (product)'),('covid-vaccination',1,'40388811000001104',NULL,'Generic COVID-19 Vaccine Sputnik V Component II (recombinant serotype 5 adenoviral particles) 100,000,000,000 viral particles/0.5ml dose solution for injection multidose vials (product)'),('covid-vaccination',1,'40387711000001106',NULL,'COVID-19 Vaccine Sputnik V Component II (recombinant serotype 5 adenoviral particles) 100,000,000,000 viral particles/0.5ml dose solution for injection multidose vials (Gamaleya NRCEM) (product)'),('covid-vaccination',1,'40388711000001107',NULL,'Generic COVID-19 Vaccine Sputnik V Component I (recombinant serotype 26 adenoviral particles) 100,000,000,000 viral particles/0.5ml dose solution for injection vials (product)'),('covid-vaccination',1,'40385711000001100',NULL,'COVID-19 Vaccine Sputnik V Component I (recombinant serotype 26 adenoviral particles) 100,000,000,000 viral particles/0.5ml dose solution for injection vials (Gamaleya NRCEM) (product)'),('covid-vaccination',1,'40388911000001109',NULL,'Generic COVID-19 Vaccine Sputnik V Component II (recombinant serotype 5 adenoviral particles) 100,000,000,000 viral particles/0.5ml dose solution for injection vials (product)'),('covid-vaccination',1,'40387111000001105',NULL,'COVID-19 Vaccine Sputnik V Component II (recombinant serotype 5 adenoviral particles) 100,000,000,000 viral particles/0.5ml dose solution for injection vials (Gamaleya NRCEM) (product)'),('covid-vaccination',1,'40335311000001107',NULL,'Generic COVID-19 Vaccine Covaxin (NIV-2020-770 inactivated) 6micrograms/0.5ml dose suspension for injection multidose vials (product)'),('covid-vaccination',1,'40332311000001101',NULL,'COVID-19 Vaccine Covaxin (NIV-2020-770 inactivated) 6micrograms/0.5ml dose suspension for injection multidose vials (Bharat Biotech International Ltd) (product)'),('covid-vaccination',1,'40366311000001107',NULL,'Generic COVID-19 Vaccine Covishield (ChAdOx1 S [recombinant]) 5x10,000,000,000 viral particles/0.5ml dose solution for injection multidose vials (product)'),('covid-vaccination',1,'40348011000001102',NULL,'COVID-19 Vaccine Covishield (ChAdOx1 S [recombinant]) 5x10,000,000,000 viral particles/0.5ml dose solution for injection multidose vials (Serum Institute of India) (product)'),('covid-vaccination',1,'40335411000001100',NULL,'Generic COVID-19 Vaccine Covaxin (NIV-2020-770 inactivated) 6micrograms/0.5ml dose suspension for injection vials (product)'),('covid-vaccination',1,'40332711000001102',NULL,'COVID-19 Vaccine Covaxin (NIV-2020-770 inactivated) 6micrograms/0.5ml dose suspension for injection vials (Bharat Biotech International Ltd) (product)'),('covid-vaccination',1,'40335611000001102',NULL,'Generic COVID-19 Vaccine Sinopharm BIBP (inactivated adjuvanted) 6.5U/0.5ml dose suspension for injection vials (product)'),('covid-vaccination',1,'40331611000001100',NULL,'COVID-19 Vaccine Sinopharm BIBP (inactivated adjuvanted) 6.5U/0.5ml dose suspension for injection vials (Beijing Institute of Biological Products) (product)'),('covid-vaccination',1,'40335511000001101',NULL,'Generic COVID-19 Vaccine Sinopharm BIBP (inactivated adjuvanted) 6.5U/0.5ml dose suspension for injection pre-filled syringes (product)'),('covid-vaccination',1,'40331911000001106',NULL,'COVID-19 Vaccine Sinopharm BIBP (inactivated adjuvanted) 6.5U/0.5ml dose suspension for injection pre-filled syringes (Beijing Institute of Biological Products) (product)'),('covid-vaccination',1,'40366411000001100',NULL,'Generic COVID-19 Vaccine Covishield (ChAdOx1 S [recombinant]) 5x10,000,000,000 viral particles/0.5ml dose solution for injection vials (product)'),('covid-vaccination',1,'40362511000001102',NULL,'COVID-19 Vaccine Covishield (ChAdOx1 S [recombinant]) 5x10,000,000,000 viral particles/0.5ml dose solution for injection vials (Serum Institute of India) (product)'),('covid-vaccination',1,'40329811000001103',NULL,'Generic CoronaVac COVID-19 Vaccine (adjuvanted) 600U/0.5ml dose suspension for injection vials (product)'),('covid-vaccination',1,'40306411000001101',NULL,'CoronaVac COVID-19 Vaccine (adjuvanted) 600U/0.5ml dose suspension for injection vials (Sinovac Life Sciences) (product)'),('covid-vaccination',1,'41779711000001103',NULL,'Generic COVID-19 Vaccine Bimervax (recombinant, adjuvanted) 40micrograms/0.5ml dose emulsion for injection multidose vials (product)'),('covid-vaccination',1,'41780111000001104',NULL,'COVID-19 Vaccine Bimervax (recombinant, adjuvanted) 40micrograms/0.5ml dose emulsion for injection multidose vials (Hipra Human Health S.L.U.) (product)'),('covid-vaccination',1,'42029211000001107',NULL,'Generic Comirnaty Omicron XBB.1.5 COVID-19 mRNA Vaccine 30micrograms/0.3ml dose dispersion for injection multidose vials (product)'),('covid-vaccination',1,'42020711000001107',NULL,'Comirnaty Omicron XBB.1.5 COVID-19 mRNA Vaccine 30micrograms/0.3ml dose dispersion for injection multidose vials (Pfizer Ltd) (product)'),('covid-vaccination',1,'39478211000001100',NULL,'Generic COVID-19 Vaccine Nuvaxovid (recombinant, adjuvanted) 5micrograms/0.5ml dose dispersion for injection multidose vials (product)'),('covid-vaccination',1,'40483111000001109',NULL,'COVID-19 Vaccine Covovax (adjuvanted) 5micrograms/0.5ml dose suspension for injection multidose vials (Serum Institute of India) (product)'),('covid-vaccination',1,'39473011000001103',NULL,'COVID-19 Vaccine Nuvaxovid (recombinant, adjuvanted) 5micrograms/0.5ml dose dispersion for injection multidose vials (Novavax CZ a.s.) (product)'),('covid-vaccination',1,'40658411000001104',NULL,'Generic COVID-19 Vaccine Moderna (mRNA-1273.214) 50micrograms/0.5ml dose dispersion for injection vials (product)'),('covid-vaccination',1,'40658111000001109',NULL,'COVID-19 Vaccine Moderna (mRNA-1273.214) 50micrograms/0.5ml dose dispersion for injection vials (Moderna, Inc) (product)'),('covid-vaccination',1,'1156257007',NULL,'Administration of vaccine product against severe acute respiratory syndrome coronavirus 2 (procedure)'),('covid-vaccination',1,'1324681000000101',NULL,'Administration of first dose of severe acute respiratory syndrome coronavirus 2 vaccine (procedure)'),('covid-vaccination',1,'1363831000000108',NULL,'Administration of fifth dose of severe acute respiratory syndrome coronavirus 2 vaccine (procedure)'),('covid-vaccination',1,'1363861000000103',NULL,'Administration of third dose of severe acute respiratory syndrome coronavirus 2 vaccine (procedure)'),('covid-vaccination',1,'1363791000000101',NULL,'Administration of fourth dose of severe acute respiratory syndrome coronavirus 2 vaccine (procedure)'),('covid-vaccination',1,'1324691000000104',NULL,'Administration of second dose of severe acute respiratory syndrome coronavirus 2 vaccine (procedure)'),('covid-vaccination',1,'1193583000',NULL,'Administration of vaccine product containing only severe acute respiratory syndrome coronavirus 2 deoxyribonucleic acid plasmid encoding spike protein (procedure)'),('covid-vaccination',1,'1157107003',NULL,'Administration of vaccine product containing only recombinant non-replicating viral vector encoding severe acute respiratory syndrome coronavirus 2 spike protein (procedure)'),('covid-vaccination',1,'1157108008',NULL,'Administration of second dose vaccine product containing only recombinant non-replicating viral vector encoding severe acute respiratory syndrome coronavirus 2 spike protein (procedure)'),('covid-vaccination',1,'1119350007',NULL,'Administration of vaccine product containing only severe acute respiratory syndrome coronavirus 2 messenger ribonucleic acid (procedure)'),('covid-vaccination',1,'1144998002',NULL,'Administration of second dose of vaccine product containing only severe acute respiratory syndrome coronavirus 2 messenger ribonucleic acid (procedure)'),('covid-vaccination',1,'1144997007',NULL,'Administration of first dose of vaccine product containing only severe acute respiratory syndrome coronavirus 2 messenger ribonucleic acid (procedure)'),('covid-vaccination',1,'840534001',NULL,'Administration of vaccine product containing only severe acute respiratory syndrome coronavirus 2 antigen (procedure)'),('covid-vaccination',1,'1179496000',NULL,'Administration of vaccine product containing only severe acute respiratory syndrome coronavirus 2 virus-like particle antigen (procedure)'),('covid-vaccination',1,'1179497009',NULL,'Administration of second dose of vaccine product containing only severe acute respiratory syndrome coronavirus 2 virus-like particle antigen (procedure)'),('covid-vaccination',1,'1162645008',NULL,'Administration of vaccine product containing only severe acute respiratory syndrome coronavirus 2 recombinant spike protein antigen (procedure)'),('covid-vaccination',1,'1162646009',NULL,'Administration of second dose of vaccine product containing only severe acute respiratory syndrome coronavirus 2 recombinant spike protein antigen (procedure)'),('covid-vaccination',1,'1157196000',NULL,'Administration of vaccine product containing only inactivated whole severe acute respiratory syndrome coronavirus 2 antigen (procedure)'),('covid-vaccination',1,'1157197009',NULL,'Administration of second dose of vaccine product containing only inactivated whole severe acute respiratory syndrome coronavirus 2 antigen (procedure)'),('covid-vaccination',1,'1362591000000103',NULL,'Immunisation course to maintain protection against severe acute respiratory syndrome coronavirus 2 (regime/therapy)'),('covid-vaccination',1,'1324671000000103',NULL,'Immunisation course to achieve immunity against severe acute respiratory syndrome coronavirus 2 (regime/therapy)'),
('covid-vaccination',1,'1362611000000106',NULL,'Severe acute respiratory syndrome coronavirus 2 immunisation course done (situation)')

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
VALUES ('covid-vaccination',1,'^ESCT1348323',NULL,'Administration of first dose of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccine'),('covid-vaccination',1,'^ESCT1348324',NULL,'Administration of first dose of 2019-nCoV (novel coronavirus) vaccine'),('covid-vaccination',1,'COCO138186NEMIS',NULL,'COVID-19 mRNA Vaccine BNT162b2 30micrograms/0.3ml dose concentrate for suspension for injection multidose vials (Pfizer-BioNTech) (Pfizer-BioNTech)'),('covid-vaccination',1,'^ESCT1348325',NULL,'Administration of second dose of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccine'),('covid-vaccination',1,'^ESCT1348326',NULL,'Administration of second dose of 2019-nCoV (novel coronavirus) vaccine'),('covid-vaccination',1,'^ESCT1428354',NULL,'Administration of third dose of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccine'),('covid-vaccination',1,'^ESCT1428342',NULL,'Administration of fourth dose of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccine'),('covid-vaccination',1,'^ESCT1428348',NULL,'Administration of fifth dose of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccine'),('covid-vaccination',1,'^ESCT1348298',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccination'),('covid-vaccination',1,'^ESCT1348301',NULL,'COVID-19 vaccination'),('covid-vaccination',1,'^ESCT1299050',NULL,'2019-nCoV (novel coronavirus) vaccination'),('covid-vaccination',1,'^ESCT1301222',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccination'),('covid-vaccination',1,'CODI138564NEMIS',NULL,'Covid-19 mRna (nucleoside modified) Vaccine Moderna  Dispersion for injection  0.1 mg/0.5 ml dose, multidose vial'),('covid-vaccination',1,'TASO138184NEMIS',NULL,'Covid-19 Vaccine AstraZeneca (ChAdOx1 S recombinant)  Solution for injection  5x10 billion viral particle/0.5 ml multidose vial'),('covid-vaccination',1,'PCSDT18491_1375',NULL,'Administration of first dose of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccine'),('covid-vaccination',1,'PCSDT18491_1376',NULL,'Administration of second dose of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccine'),('covid-vaccination',1,'PCSDT18491_716',NULL,'Administration of second dose of SARS-CoV-2 vacc'),('covid-vaccination',1,'PCSDT18491_903',NULL,'Administration of first dose of SARS-CoV-2 vacccine'),('covid-vaccination',1,'PCSDT3370_2254',NULL,'2019-nCoV (novel coronavirus) vaccination'),('covid-vaccination',1,'PCSDT3919_2185',NULL,'Administration of first dose of SARS-CoV-2 vacccine'),('covid-vaccination',1,'PCSDT3919_662',NULL,'Administration of second dose of SARS-CoV-2 vacc'),('covid-vaccination',1,'PCSDT4803_1723',NULL,'2019-nCoV (novel coronavirus) vaccination'),('covid-vaccination',1,'PCSDT5823_2264',NULL,'Administration of second dose of SARS-CoV-2 vacc'),('covid-vaccination',1,'PCSDT5823_2757',NULL,'Administration of second dose of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccine'),('covid-vaccination',1,'PCSDT5823_2902',NULL,'Administration of first dose of SARS-CoV-2 vacccine'),('covid-vaccination',1,'^ESCT1348300',NULL,'Severe acute respiratory syndrome coronavirus 2 vaccination'),('covid-vaccination',1,'ASSO138368NEMIS',NULL,'COVID-19 Vaccine Janssen (Ad26.COV2-S [recombinant]) 0.5ml dose suspension for injection multidose vials (Janssen-Cilag Ltd)'),('covid-vaccination',1,'COCO141057NEMIS',NULL,'Comirnaty Children 5-11 years COVID-19 mRNA Vaccine 10micrograms/0.2ml dose concentrate for dispersion for injection multidose vials (Pfizer Ltd)'),('covid-vaccination',1,'COSO141059NEMIS',NULL,'COVID-19 Vaccine Covishield (ChAdOx1 S [recombinant]) 5x10,000,000,000 viral particles/0.5ml dose solution for injection multidose vials (Serum Institute of India)'),('covid-vaccination',1,'COSU138776NEMIS',NULL,'COVID-19 Vaccine Valneva (inactivated adjuvanted whole virus) 40antigen units/0.5ml dose suspension for injection multidose vials (Valneva UK Ltd)'),('covid-vaccination',1,'COSU138943NEMIS',NULL,'COVID-19 Vaccine Novavax (adjuvanted) 5micrograms/0.5ml dose suspension for injection multidose vials (Baxter Oncology GmbH)'),('covid-vaccination',1,'COSU141008NEMIS',NULL,'CoronaVac COVID-19 Vaccine (adjuvanted) 600U/0.5ml dose suspension for injection vials (Sinovac Life Sciences)'),('covid-vaccination',1,'COSU141037NEMIS',NULL,'COVID-19 Vaccine Sinopharm BIBP (inactivated adjuvanted) 6.5U/0.5ml dose suspension for injection vials (Beijing Institute of Biological Products)'),('covid-vaccination',1,'^ESCT1299051',NULL,'Wuhan 2019-nCoV (novel coronavirus) vaccination'),('covid-vaccination',1,'^ESCT1299052',NULL,'2019 novel coronavirus vaccination'),('covid-vaccination',1,'^ESCT1348299',NULL,'2019 novel coronavirus vaccination'),('covid-vaccination',1,'^ESCT1348302',NULL,'2019-nCoV (novel coronavirus) vaccination'),('covid-vaccination',1,'^ESCT1402904',NULL,'COVID-19 Vaccine AstraZeneca (ChAdOx1 S [recombinant]) 5x10,000,000,000 viral particles/0.5ml dose solution for injection multidose vials (AstraZeneca UK Ltd)'),('covid-vaccination',1,'^ESCT1402911',NULL,'COVID-19 mRNA Vaccine Pfizer-BioNTech BNT162b2 30micrograms/0.3ml dose concentrate for suspension for injection multidose vials (Pfizer Ltd)'),('covid-vaccination',1,'^ESCT1402916',NULL,'Generic COVID-19 mRNA Vaccine Pfizer-BioNTech BNT162b2 30micrograms/0.3ml dose concentrate for suspension for injection multidose vials'),('covid-vaccination',1,'^ESCT1402917',NULL,'Generic COVID-19 Vaccine AstraZeneca (ChAdOx1 S [recombinant]) 5x10,000,000,000 viral particles/0.5ml dose solution for injection multidose vials'),('covid-vaccination',1,'^ESCT1403901',NULL,'Astute 100,000,000,000 (100 billion) viral particles/0.5ml dose solution for injection multidose vials (Janssen-Cilag Ltd)'),('covid-vaccination',1,'^ESCT1403935',NULL,'Generic Astute 100,000,000,000 (100 billion) viral particles/0.5ml dose solution for injection multidose vials'),('covid-vaccination',1,'^ESCT1404735',NULL,'Generic COVID-19 mRNA (nucleoside modified) Vaccine Moderna 0.1mg/0.5mL dose dispersion for injection multidose vials'),('covid-vaccination',1,'^ESCT1404736',NULL,'COVID-19 mRNA (nucleoside modified) Vaccine Moderna 0.1mg/0.5mL dose dispersion for injection multidose vials (Moderna, Inc)'),('covid-vaccination',1,'^ESCT1404768',NULL,'COVID-19 vaccine'),('covid-vaccination',1,'^ESCT1405128',NULL,'COVID-19 Vaccine Valneva (inactivated adjuvanted whole virus) 40antigen units/0.5mL dose suspension for injection multidose vials (Valneva UK Ltd)'),('covid-vaccination',1,'^ESCT1405145',NULL,'Generic COVID-19 Vaccine Valneva (inactivated adjuvanted whole virus) 40antigen units/0.5mL dose suspension for injection multidose vials'),('covid-vaccination',1,'^ESCT1416911',NULL,'Administration of SARS-CoV-2 mRNA vaccine'),('covid-vaccination',1,'^ESCT1416912',NULL,'COVID-19 mRNA vaccination'),('covid-vaccination',1,'^ESCT1416913',NULL,'COVID-19 mRNA immunisation'),('covid-vaccination',1,'^ESCT1416914',NULL,'2019-nCoV mRNA immunisation'),('covid-vaccination',1,'^ESCT1416915',NULL,'2019-nCoV mRNA vaccination'),('covid-vaccination',1,'^ESCT1416916',NULL,'SARS-CoV-2 mRNA vaccination'),('covid-vaccination',1,'^ESCT1416917',NULL,'SARS-CoV-2 mRNA immunisation'),('covid-vaccination',1,'^ESCT1416918',NULL,'2019 novel coronavirus mRNA immunisation'),('covid-vaccination',1,'^ESCT1416919',NULL,'Severe acute respiratory syndrome coronavirus 2 mRNA vaccination'),('covid-vaccination',1,'^ESCT1416920',NULL,'2019 novel coronavirus mRNA vaccination'),('covid-vaccination',1,'^ESCT1416921',NULL,'Administration of vaccine product containing only Severe acute respiratory syndrome coronavirus 2 messenger ribonucleic acid'),('covid-vaccination',1,'^ESCT1417030',NULL,'Administration of first dose of SARS-CoV-2 mRNA vaccine'),('covid-vaccination',1,'^ESCT1417031',NULL,'First 2019 novel coronavirus mRNA vaccination'),('covid-vaccination',1,'^ESCT1417032',NULL,'First 2019-nCoV mRNA vaccination'),('covid-vaccination',1,'^ESCT1417033',NULL,'First SARS-CoV-2 mRNA immunisation'),('covid-vaccination',1,'^ESCT1417034',NULL,'First COVID-19 mRNA vaccination'),('covid-vaccination',1,'^ESCT1417035',NULL,'First Severe acute respiratory syndrome coronavirus 2 mRNA vaccination'),('covid-vaccination',1,'^ESCT1417036',NULL,'First COVID-19 mRNA immunisation'),('covid-vaccination',1,'^ESCT1417037',NULL,'First 2019 novel coronavirus mRNA immunisation'),('covid-vaccination',1,'^ESCT1417038',NULL,'Administration of first dose of vaccine product containing only Severe acute respiratory syndrome coronavirus 2 messenger ribonucleic acid'),('covid-vaccination',1,'^ESCT1417039',NULL,'First 2019-nCoV mRNA immunisation'),('covid-vaccination',1,'^ESCT1417040',NULL,'First SARS-CoV-2 mRNA vaccination'),('covid-vaccination',1,'^ESCT1417041',NULL,'Administration of second dose of SARS-CoV-2 mRNA vaccine'),('covid-vaccination',1,'^ESCT1417042',NULL,'Second 2019-nCoV mRNA immunisation'),('covid-vaccination',1,'^ESCT1417043',NULL,'Second COVID-19 mRNA vaccination'),('covid-vaccination',1,'^ESCT1417044',NULL,'Second Severe acute respiratory syndrome coronavirus 2 mRNA vaccination'),('covid-vaccination',1,'^ESCT1417045',NULL,'Second 2019-nCoV mRNA vaccination'),('covid-vaccination',1,'^ESCT1417046',NULL,'Administration of second dose of vaccine product containing only Severe acute respiratory syndrome coronavirus 2 messenger ribonucleic acid'),('covid-vaccination',1,'^ESCT1417047',NULL,'Second 2019 novel coronavirus mRNA immunisation'),('covid-vaccination',1,'^ESCT1417048',NULL,'Second 2019 novel coronavirus mRNA vaccination'),('covid-vaccination',1,'^ESCT1417049',NULL,'Second SARS-CoV-2 mRNA immunisation'),('covid-vaccination',1,'^ESCT1417050',NULL,'Second COVID-19 mRNA immunisation'),('covid-vaccination',1,'^ESCT1417051',NULL,'Second SARS-CoV-2 mRNA vaccination'),('covid-vaccination',1,'^ESCT1418812',NULL,'COVID-19 Vaccine Novavax (adjuvanted) 5micrograms/0.5ml dose suspension for injection multidose vials (Baxter Oncology GmbH)'),
('covid-vaccination',1,'^ESCT1418854',NULL,'Generic COVID-19 Vaccine Novavax (adjuvanted) 5micrograms/0.5ml dose suspension for injection multidose vials'),('covid-vaccination',1,'^ESCT1421492',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) antigen vaccination'),('covid-vaccination',1,'^ESCT1421493',NULL,'COVID-19 antigen immunisation'),('covid-vaccination',1,'^ESCT1421494',NULL,'2019 novel coronavirus antigen immunisation'),('covid-vaccination',1,'^ESCT1421495',NULL,'2019 novel coronavirus antigen vaccination'),('covid-vaccination',1,'^ESCT1421496',NULL,'COVID-19 antigen vaccination'),('covid-vaccination',1,'^ESCT1421497',NULL,'Severe acute respiratory syndrome coronavirus 2 antigen vaccination'),('covid-vaccination',1,'^ESCT1421498',NULL,'Administration of vaccine product containing only Severe acute respiratory syndrome coronavirus 2 antigen'),('covid-vaccination',1,'^ESCT1421499',NULL,'2019-nCoV (novel coronavirus) antigen vaccination'),('covid-vaccination',1,'^ESCT1423115',NULL,'Generic COVID-19 mRNA (nucleoside modified) Vaccine Moderna 0.1mg/0.5ml dose dispersion for injection multidose vials'),('covid-vaccination',1,'^ESCT1423116',NULL,'COVID-19 mRNA (nucleoside modified) Vaccine Moderna 0.1mg/0.5ml dose dispersion for injection multidose vials (Moderna, Inc)'),('covid-vaccination',1,'^ESCT1423124',NULL,'COVID-19 Vaccine Valneva (inactivated adjuvanted whole virus) 40antigen units/0.5ml dose suspension for injection multidose vials (Valneva UK Ltd)'),('covid-vaccination',1,'^ESCT1423127',NULL,'Generic COVID-19 Vaccine Valneva (inactivated adjuvanted whole virus) 40antigen units/0.5ml dose suspension for injection multidose vials'),('covid-vaccination',1,'^ESCT1425452',NULL,'COVID-19 Vaccine Medicago (CoVLP) 3.75micrograms/0.5ml dose emulsion for injection multidose vials (Medicago Inc)'),('covid-vaccination',1,'^ESCT1425457',NULL,'Generic COVID-19 Vaccine Medicago (CoVLP) 3.75micrograms/0.5ml dose emulsion for injection multidose vials'),('covid-vaccination',1,'^ESCT1428110',NULL,'COVID-19 Vaccine Janssen (Ad26.COV2-S [recombinant]) 0.5ml dose solution for injection multidose vials (Janssen-Cilag Ltd)'),('covid-vaccination',1,'^ESCT1428113',NULL,'Generic COVID-19 Vaccine Janssen (Ad26.COV2-S [recombinant]) 0.5ml dose solution for injection multidose vials'),('covid-vaccination',1,'^ESCT1428343',NULL,'Administration of fourth dose of 2019-nCoV (novel coronavirus) vaccine'),('covid-vaccination',1,'^ESCT1428349',NULL,'Administration of fifth dose of 2019-nCoV (novel coronavirus) vaccine'),('covid-vaccination',1,'^ESCT1428355',NULL,'Administration of third dose of 2019-nCoV (novel coronavirus) vaccine'),('covid-vaccination',1,'^ESCT1431765',NULL,'COVID-19 Vaccine AstraZeneca (ChAdOx1 S [recombinant]) 5x10,000,000,000 viral particles/0.5ml dose suspension for injection multidose vials (AstraZeneca UK Ltd)'),('covid-vaccination',1,'^ESCT1431769',NULL,'Comirnaty COVID-19 mRNA Vaccine 30micrograms/0.3ml dose concentrate for dispersion for injection multidose vials (Pfizer Ltd)'),('covid-vaccination',1,'^ESCT1431771',NULL,'Generic Comirnaty COVID-19 mRNA Vaccine 30micrograms/0.3ml dose concentrate for dispersion for injection multidose vials'),('covid-vaccination',1,'^ESCT1431772',NULL,'Generic COVID-19 Vaccine AstraZeneca (ChAdOx1 S [recombinant]) 5x10,000,000,000 viral particles/0.5ml dose suspension for injection multidose vials'),('covid-vaccination',1,'^ESCT1431777',NULL,'COVID-19 Vaccine Janssen (Ad26.COV2-S [recombinant]) 0.5ml dose suspension for injection multidose vials (Janssen-Cilag Ltd)'),('covid-vaccination',1,'^ESCT1431780',NULL,'Generic COVID-19 Vaccine Janssen (Ad26.COV2-S [recombinant]) 0.5ml dose suspension for injection multidose vials'),('covid-vaccination',1,'^ESCT1431786',NULL,'Generic Spikevax COVID-19 mRNA (nucleoside modified) Vaccine 0.1mg/0.5ml dose dispersion for injection multidose vials'),('covid-vaccination',1,'^ESCT1431787',NULL,'Spikevax COVID-19 mRNA (nucleoside modified) Vaccine 0.1mg/0.5ml dose dispersion for injection multidose vials (Moderna, Inc)'),('covid-vaccination',1,'^ESCT1434508',NULL,'CoronaVac COVID-19 Vaccine (adjuvanted) 600U/0.5ml dose suspension for injection vials (Sinovac Life Sciences)'),('covid-vaccination',1,'^ESCT1434581',NULL,'Generic CoronaVac COVID-19 Vaccine (adjuvanted) 600U/0.5ml dose suspension for injection vials'),('covid-vaccination',1,'^ESCT1434594',NULL,'COVID-19 Vaccine Sinopharm BIBP (inactivated adjuvanted) 6.5U/0.5ml dose suspension for injection vials (Beijing Institute of Biological Products)'),('covid-vaccination',1,'^ESCT1434597',NULL,'COVID-19 Vaccine Sinopharm BIBP (inactivated adjuvanted) 6.5U/0.5ml dose suspension for injection pre-filled syringes (Beijing Institute of Biological Products)'),('covid-vaccination',1,'^ESCT1434601',NULL,'COVID-19 Vaccine Covaxin (NIV-2020-770 inactivated) 6micrograms/0.5ml dose suspension for injection multidose vials (Bharat Biotech International Ltd)'),('covid-vaccination',1,'^ESCT1434605',NULL,'COVID-19 Vaccine Covaxin (NIV-2020-770 inactivated) 6micrograms/0.5ml dose suspension for injection vials (Bharat Biotech International Ltd)'),('covid-vaccination',1,'^ESCT1434622',NULL,'Generic COVID-19 Vaccine Covaxin (NIV-2020-770 inactivated) 6micrograms/0.5ml dose suspension for injection multidose vials'),('covid-vaccination',1,'^ESCT1434623',NULL,'Generic COVID-19 Vaccine Covaxin (NIV-2020-770 inactivated) 6micrograms/0.5ml dose suspension for injection vials'),('covid-vaccination',1,'^ESCT1434624',NULL,'Generic COVID-19 Vaccine Sinopharm BIBP (inactivated adjuvanted) 6.5U/0.5ml dose suspension for injection pre-filled syringes'),('covid-vaccination',1,'^ESCT1434625',NULL,'Generic COVID-19 Vaccine Sinopharm BIBP (inactivated adjuvanted) 6.5U/0.5ml dose suspension for injection vials'),('covid-vaccination',1,'^ESCT1434687',NULL,'COVID-19 Vaccine Covishield (ChAdOx1 S [recombinant]) 5x10,000,000,000 viral particles/0.5ml dose solution for injection multidose vials (Serum Institute of India)'),('covid-vaccination',1,'^ESCT1434739',NULL,'COVID-19 Vaccine Covishield (ChAdOx1 S [recombinant]) 5x10,000,000,000 viral particles/0.5ml dose solution for injection vials (Serum Institute of India)'),('covid-vaccination',1,'^ESCT1434769',NULL,'Generic COVID-19 Vaccine Covishield (ChAdOx1 S [recombinant]) 5x10,000,000,000 viral particles/0.5ml dose solution for injection multidose vials'),('covid-vaccination',1,'^ESCT1434770',NULL,'Generic COVID-19 Vaccine Covishield (ChAdOx1 S [recombinant]) 5x10,000,000,000 viral particles/0.5ml dose solution for injection vials'),('covid-vaccination',1,'^ESCT1435624',NULL,'Comirnaty Children 5-11 years COVID-19 mRNA Vaccine 10micrograms/0.2ml dose concentrate for dispersion for injection multidose vials (Pfizer Ltd)'),('covid-vaccination',1,'^ESCT1435629',NULL,'COVID-19 Vaccine Sputnik V Component I (recombinant serotype 26 adenoviral particles) 100,000,000,000 viral particles/0.5ml dose solution for injection vials (Gamaleya NRCEM)'),('covid-vaccination',1,'^ESCT1435639',NULL,'COVID-19 Vaccine Sputnik V Component II (recombinant serotype 5 adenoviral particles) 100,000,000,000 viral particles/0.5ml dose solution for injection vials (Gamaleya NRCEM)'),('covid-vaccination',1,'^ESCT1435642',NULL,'COVID-19 Vaccine Sputnik V Component I (recombinant serotype 26 adenoviral particles) 100,000,000,000 viral particles/0.5ml dose solution for injection multidose vials (Gamaleya NRCEM)'),('covid-vaccination',1,'^ESCT1435645',NULL,'COVID-19 Vaccine Sputnik V Component II (recombinant serotype 5 adenoviral particles) 100,000,000,000 viral particles/0.5ml dose solution for injection multidose vials (Gamaleya NRCEM)'),('covid-vaccination',1,'^ESCT1435654',NULL,'Generic COVID-19 Vaccine Sputnik V Component I (recombinant serotype 26 adenoviral particles) 100,000,000,000 viral particles/0.5ml dose solution for injection multidose vials'),('covid-vaccination',1,'^ESCT1435655',NULL,'Generic COVID-19 Vaccine Sputnik V Component I (recombinant serotype 26 adenoviral particles) 100,000,000,000 viral particles/0.5ml dose solution for injection vials'),('covid-vaccination',1,'^ESCT1435656',NULL,'Generic COVID-19 Vaccine Sputnik V Component II (recombinant serotype 5 adenoviral particles) 100,000,000,000 viral particles/0.5ml dose solution for injection multidose vials'),('covid-vaccination',1,'^ESCT1435657',NULL,'Generic COVID-19 Vaccine Sputnik V Component II (recombinant serotype 5 adenoviral particles) 100,000,000,000 viral particles/0.5ml dose solution for injection vials'),('covid-vaccination',1,'^ESCT1435658',NULL,'Generic Comirnaty Children 5-11 years COVID-19 mRNA Vaccine 10micrograms/0.2ml dose concentrate for dispersion for injection multidose vials'),('covid-vaccination',1,'^ESCT1435705',NULL,'COVID-19 Vaccine AZD2816 AstraZeneca (ChAdOx1 nCOV-19) 3.5x10,000,000,000 viral particles/0.5ml dose solution for injection multidose vials (AstraZeneca AB)'),('covid-vaccination',1,'^ESCT1435707',NULL,'Generic COVID-19 Vaccine AZD2816 AstraZeneca (ChAdOx1 nCOV-19) 3.5x10,000,000,000 viral particles/0.5ml dose solution for injection multidose vials'),('covid-vaccination',1,'^ESCT1436694',NULL,'COVID-19 Vaccine Covovax (adjuvanted) 5micrograms/0.5ml dose suspension for injection multidose vials (Serum Institute of India)'),('covid-vaccination',1,'^ESCT1439300',NULL,'COVID-19 Vaccine Vaxzevria (ChAdOx1 S [recombinant]) 5x10,000,000,000 viral particles/0.5ml dose suspension for injection multidose vials (AstraZeneca UK Ltd)'),('covid-vaccination',1,'^ESCT1439303',NULL,'Generic COVID-19 Vaccine Vaxzevria (ChAdOx1 S [recombinant]) 5x10,000,000,000 viral particles/0.5ml dose suspension for injection multidose vials'),('covid-vaccination',1,'^ESCT1439638',NULL,'COVID-19 Vaccine Sanofi (CoV2 preS dTM monovalent D614 [recombinant]) 5micrograms/0.5ml dose suspension for injection multidose vials (Sanofi Pasteur)'),
('covid-vaccination',1,'^ESCT1439640',NULL,'Generic COVID-19 Vaccine Sanofi (CoV2 preS dTM monovalent D614 [recombinant]) 5micrograms/0.5ml dose suspension for injection multidose vials'),('covid-vaccination',1,'^ESCT1439753',NULL,'COVID-19 Vaccine Moderna (mRNA-1273.529) 50micrograms/0.25ml dose solution for injection multidose vials (Moderna, Inc)'),('covid-vaccination',1,'^ESCT1439755',NULL,'Generic COVID-19 Vaccine Moderna (mRNA-1273.529) 50micrograms/0.25ml dose solution for injection multidose vials'),('covid-vaccination',1,'^ESCT1440075',NULL,'Comirnaty COVID-19 mRNA Vaccine ready to use 30micrograms/0.3ml dose dispersion for injection multidose vials (Pfizer Ltd)'),('covid-vaccination',1,'^ESCT1440078',NULL,'Generic Comirnaty COVID-19 mRNA Vaccine ready to use 30micrograms/0.3ml dose dispersion for injection multidose vials'),('covid-vaccination',1,'^ESCT1441243',NULL,'COVID-19 Vaccine Nuvaxovid (recombinant, adjuvanted) 5micrograms/0.5ml dose dispersion for injection multidose vials (Novavax CZ a.s.)'),('covid-vaccination',1,'^ESCT1441246',NULL,'Generic COVID-19 Vaccine Nuvaxovid (recombinant, adjuvanted) 5micrograms/0.5ml dose dispersion for injection multidose vials'),('covid-vaccination',1,'^ESCTCO397297',NULL,'Coronavirus vaccination'),('covid-vaccination',1,'COCO143126NEMIS',NULL,'Comirnaty Children 6 months - 4 years COVID-19 mRNA Vaccine  Concentrate For Dispersion For Injection  3 micrograms/0.2 ml dose, multidose vial'),('covid-vaccination',1,'COCO144437NEMIS',NULL,'Comirnaty Omicron XBB.1.5 Children 6 months - 4 years Covid-19 mRNA Vaccine  Concentrate For Dispersion For Injection  3 micrograms/0.2 ml dose, multidose vial'),('covid-vaccination',1,'CODI141709NEMIS',NULL,'Comirnaty Covid-19 mRNA Vaccine Ready to Use  Dispersion for injection  30 micrograms/0.3 ml, multidose vial'),('covid-vaccination',1,'CODI142225NEMIS',NULL,'Covid-19 Vaccine Spikevax 0 (Zero)/O (Omicron)  Dispersion for injection  0.1 mg/ml multidose vial'),('covid-vaccination',1,'CODI142339NEMIS',NULL,'Comirnaty Original/Omicron BA.1 Covid-19 mRNA Vaccine  Dispersion for injection  15 microgram + 15 microgram/0.3 ml, multidose vial'),('covid-vaccination',1,'CODI143144NEMIS',NULL,'Comirnaty Original/Omicron BA.4-5 COVID-19 mRNA Vaccine  Dispersion for injection  15 microgram + 15 microgram/0.3 ml, multidose vial'),('covid-vaccination',1,'CODI143381NEMIS',NULL,'Covid-19 Vaccine Spikevax Original/Omicron BA.4/BA.5  Dispersion for injection  0.1 mg/ml multidose vial'),('covid-vaccination',1,'CODI144358NEMIS',NULL,'Comirnaty Omicron XBB.1.5 Covid-19 mRNA Vaccine  Dispersion for injection  30 micrograms/0.3 ml dose, multidose vial'),('covid-vaccination',1,'CODI144435NEMIS',NULL,'Comirnaty Omicron XBB.1.5 Children 5-11 Years Covid-19 mRNA Vaccine  Dispersion for injection  10 micrograms/0.3 ml dose, multidose vial'),('covid-vaccination',1,'COEM139763NEMIS',NULL,'Covid-19 Vaccine Medicago (CoVlp)  Emulsion For Injection  3.75 micrograms/0.5 ml dose, multidose vial'),('covid-vaccination',1,'COEM144188NEMIS',NULL,'Covid-19 Vaccine Bimervax (recombinant, adjuvanted)  Emulsion For Injection  40 micrograms/0.5 ml dose, multidose vial'),('covid-vaccination',1,'COSO141060NEMIS',NULL,'Covid-19 Vaccine Covishield (ChAdOx1 S recombinant)  Solution for injection  5x10 billion viral particles/0.5 ml dose vial'),('covid-vaccination',1,'COSO141063NEMIS',NULL,'Covid-19 Vaccine Sputnik V Component I (recombinant serotype 26 adenoviral particles)  Solution for injection  100 billion viral particles/0.5 ml multidose vial'),('covid-vaccination',1,'COSO141064NEMIS',NULL,'Covid-19 Vaccine Sputnik V Component I (recombinant serotype 26 adenoviral particles)  Solution for injection  100 billion viral particles/0.5 ml dose vial'),('covid-vaccination',1,'COSO141065NEMIS',NULL,'Covid-19 Vaccine Sputnik V Component II (recombinant serotype 5 adenoviral particles)  Solution for injection  100 billion viral particles/0.5 ml multidose vial'),('covid-vaccination',1,'COSO141066NEMIS',NULL,'Covid-19 Vaccine Sputnik V Component II (recombinant serotype 5 adenoviral particles)  Solution for injection  100 billion viral particles/0.5 ml dose vial'),('covid-vaccination',1,'COSO141294NEMIS',NULL,'Covid-19 Vaccine AZD2816 AstraZeneca (ChAdOx1 nCOV-19)  Solution for injection  3.5x10billion viral particles/0.5ml multidose vial'),('covid-vaccination',1,'COSO141705NEMIS',NULL,'Covid-19 Vaccine Moderna (mRNA-1273.529)  Solution for injection  50 micrograms/0.25 ml, multidose vial'),('covid-vaccination',1,'COSO141940NEMIS',NULL,'Covid-19 Vaccine Moderna (mRNA-1273.214)  Dispersion for injection  50 micrograms/0.5 ml dose vial'),('covid-vaccination',1,'COSO142081NEMIS',NULL,'Covid-19 Vaccine Convidecia (Adenovirus Type 5 Vector recombinant)  Solution for injection  40 billion viral particles/0.5 ml dose vial'),('covid-vaccination',1,'COSO144193NEMIS',NULL,'Covid-19 Vaccine Moderna (mRNA-1273.222)  Solution for injection  50 micrograms/0.5 ml dose vial'),('covid-vaccination',1,'COSO144195NEMIS',NULL,'Covid-19 Vaccine Moderna (mRNA-1283.222)  Solution for injection  10 micrograms/0.2 ml dose vial'),('covid-vaccination',1,'COSU141036NEMIS',NULL,'Covid-19 Vaccine Sinopharm BIBP (inactivated adjuvanted)  Suspension For Injection  6.5 units/0.5 ml dose, pre-filled syringe'),('covid-vaccination',1,'COSU141068NEMIS',NULL,'Covid-19 Vaccine Covaxin (NIV-2020-770 inactivated)  Suspension For Injection  6 micrograms/0.5 ml dose, multidose vial'),('covid-vaccination',1,'COSU141069NEMIS',NULL,'Covid-19 Vaccine Covaxin (NIV-2020-770 inactivated)  Suspension For Injection  6 micrograms/0.5 ml dose, vial'),('covid-vaccination',1,'COSU141317NEMIS',NULL,'Covid-19 Vaccine Covovax (adjuvanted)  Suspension For Injection  5 micrograms/0.5 ml dose, multidose vial'),('covid-vaccination',1,'COSU141594NEMIS',NULL,'Covid-19 Vaccine Sanofi (CoV2 preS dTM monovalent D614 recombinant)  Suspension For Injection  5 micrograms/0.5 ml dose, multidose vial'),('covid-vaccination',1,'COVA142363NEMIS',NULL,'Covid-19 Vaccine Sanofi (CoV2 preS dTM bivalent D614+B.1.351 recombinant adjuvanted)  Emulsion For Injection  2.5microgram + 2.5microgram/0.5ml, multidose vial'),('covid-vaccination',1,'COVA142365NEMIS',NULL,'Covid-19 Vaccine VidPrevtyn Beta (CoV2 preS dTM monovalent B.1.351 recombinant adjuv)  Emulsion For Injection  5 micrograms/0.5 ml dose, multidose vial'),('covid-vaccination',1,'SPDI144360NEMIS',NULL,'Spikevax XBB.1.5 Covid-19 mRNA Vaccine  Dispersion for injection  0.1 mg/1 ml, multidose vial')

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

--#endregion

-- >>> Following code sets injected: covid-vaccination v1


IF OBJECT_ID('tempdb..#VacEvents') IS NOT NULL DROP TABLE #VacEvents;
SELECT FK_Patient_Link_ID, CONVERT(DATE, EventDate) AS EventDate into #VacEvents
FROM SharedCare.GP_Events
WHERE SuppliedCode IN (
	SELECT [Code] FROM #AllCodes WHERE [Concept] = 'covid-vaccination' AND [Version] = 1
)
AND EventDate > '2020-12-01'
--AND EventDate < '2022-06-01'; -temp addition for COPI expiration -- not needed now

IF OBJECT_ID('tempdb..#VacMeds') IS NOT NULL DROP TABLE #VacMeds;
SELECT FK_Patient_Link_ID, CONVERT(DATE, MedicationDate) AS EventDate into #VacMeds
FROM SharedCare.GP_Medications
WHERE SuppliedCode IN (
	SELECT [Code] FROM #AllCodes WHERE [Concept] = 'covid-vaccination' AND [Version] = 1
)
AND MedicationDate > '2020-12-01'
--AND MedicationDate < '2022-06-01';--temp addition for COPI expiration -- not needed now

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



DECLARE @EndDate datetime;
SET @EndDate = '2023-12-31'

SELECT PatientId = FK_Patient_Link_ID, 
	VaccineDose1_YearAndMonth = FORMAT(VaccineDose1Date, 'MM-yyyy'), 
	VaccineDose2_YearAndMonth = FORMAT(VaccineDose2Date, 'MM-yyyy'), -- hide the day by setting to first of the month
	VaccineDose3_YearAndMonth = FORMAT(VaccineDose3Date, 'MM-yyyy'), -- hide the day by setting to first of the month
	VaccineDose4_YearAndMonth = FORMAT(VaccineDose4Date, 'MM-yyyy'), -- hide the day by setting to first of the month
	VaccineDose5_YearAndMonth = FORMAT(VaccineDose5Date, 'MM-yyyy'), -- hide the day by setting to first of the month
	VaccineDose6_YearAndMonth = FORMAT(VaccineDose6Date, 'MM-yyyy'), -- hide the day by setting to first of the month
	VaccineDose7_YearAndMonth = FORMAT(VaccineDose7Date, 'MM-yyyy') -- hide the day by setting to first of the month
FROM #COVIDVaccinations
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
	AND (VaccineDose1Date IS NULL OR VaccineDose1Date <= @EndDate)
	AND (VaccineDose2Date IS NULL OR VaccineDose2Date <= @EndDate)
	AND (VaccineDose3Date IS NULL OR VaccineDose3Date <= @EndDate)
	AND (VaccineDose4Date IS NULL OR VaccineDose4Date <= @EndDate)               
	AND (VaccineDose5Date IS NULL OR VaccineDose5Date <= @EndDate)
	AND (VaccineDose6Date IS NULL OR VaccineDose6Date <= @EndDate)
	AND (VaccineDose7Date IS NULL OR VaccineDose7Date <= @EndDate)
