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


DECLARE @StartDate datetime;
SET @StartDate = '2020-01-01';

--┌───────────────────────────────────────────────────────────┐
--│ Create table of patients who are registered with a GM GP  │
--└───────────────────────────────────────────────────────────┘

-- INPUT REQUIREMENTS: @StartDate

-- Find all patients alive at start date
IF OBJECT_ID('tempdb..#PossiblePatients') IS NOT NULL DROP TABLE #PossiblePatients;
SELECT PK_Patient_Link_ID as FK_Patient_Link_ID, EthnicMainGroup, EthnicGroupDescription, DeathDate INTO #PossiblePatients FROM [SharedCare].Patient_Link
WHERE 
	(DeathDate IS NULL OR (DeathDate >= @StartDate))

-- Find all patients registered with a GP
IF OBJECT_ID('tempdb..#PatientsWithGP') IS NOT NULL DROP TABLE #PatientsWithGP;
SELECT DISTINCT FK_Patient_Link_ID INTO #PatientsWithGP FROM [SharedCare].Patient
where FK_Reference_Tenancy_ID = 2;

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
VALUES ('covid-vaccination',1,'1240491000000103',NULL,'2019-nCoV (novel coronavirus) vaccination'),('covid-vaccination',1,'2807821000000115',NULL,'2019-nCoV (novel coronavirus) vaccination'),('covid-vaccination',1,'840534001',NULL,'Severe acute respiratory syndrome coronavirus 2 vaccination (procedure)'),('covid-vaccination',1,'1324681000000101',NULL,'Administration of first dose of severe acute respiratory syndrome coronavirus 2 vaccine (procedure)'),('covid-vaccination',1,'1324691000000104',NULL,'Administration of second dose of severe acute respiratory syndrome coronavirus 2 vaccine (procedure)'),('covid-vaccination',1,'1363791000000101',NULL,'Administration of fourth dose of severe acute respiratory syndrome coronavirus 2 vaccine (procedure)'),('covid-vaccination',1,'1363831000000108',NULL,'Administration of fifth dose of severe acute respiratory syndrome coronavirus 2 vaccine (procedure)'),('covid-vaccination',1,'1363861000000103',NULL,'Administration of third dose of severe acute respiratory syndrome coronavirus 2 vaccine (procedure)'),('covid-vaccination',1,'196411000000103',NULL,'Transfer-degraded record entry (administrative concept)'),('covid-vaccination',1,'39114911000001105',NULL,'Talent 0.5ml dose solution for injection multidose vials (Secretary of State for Health) (product)'),('covid-vaccination',1,'39115611000001103',NULL,'COVID-19 mRNA Vaccine BNT162b2 30micrograms/0.3ml dose concentrate for suspension for injection multidose vials (Pfizer-BioNTech) (Pfizer Ltd) (product)'),('covid-vaccination',1,'39230211000001104',NULL,'Astute 100,000,000,000 (100 billion) viral particles/0.5ml dose solution for injection multidose vials (Janssen-Cilag Ltd) (product)'),('covid-vaccination',1,'39326911000001101',NULL,'COVID-19 mRNA (nucleoside modified) Vaccine Moderna 0.1mg/0.5mL dose dispersion for injection multidose vials (Moderna, Inc) (product)'),('covid-vaccination',1,'39373511000001104',NULL,'COVID-19 Vaccine Valneva (inactivated adjuvanted whole virus) 40antigen units/0.5mL dose suspension for injection multidose vials (Valneva UK Ltd) (product)'),('covid-vaccination',1,'39473011000001103',NULL,'COVID-19 Vaccine Novavax (adjuvanted) 5micrograms/0.5ml dose suspension for injection multidose vials (Baxter Oncology GmbH) (product)'),('covid-vaccination',1,'40306411000001101',NULL,'CoronaVac COVID-19 Vaccine 600U/0.5ml dose suspension for injection vials (Sinovac Life Sciences) (product)'),('covid-vaccination',1,'40331611000001100',NULL,'COVID-19 Vaccine Sinopharm BIBP (inactivated adjuvanted) 6.5U/0.5ml dose suspension for injection vials (Beijing Institute of Biological Products) (product)'),('covid-vaccination',1,'40348011000001102',NULL,'COVID-19 Vaccine Covishield (ChAdOx1 S [recombinant]) 5x10,000,000,000 viral particles/0.5ml dose solution for injection multidose vials (Serum Institute of India) (product)'),('covid-vaccination',1,'40384611000001108',NULL,'Comirnaty Children 5-11 years COVID-19 mRNA Vaccine 10micrograms/0.2ml dose concentrate for dispersion for injection multidose vials (Pfizer Ltd) (product)')

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
VALUES ('covid-vaccination',1,'^ESCT1348323',NULL,'Administration of first dose of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccine'),('covid-vaccination',1,'^ESCT1348324',NULL,'Administration of first dose of 2019-nCoV (novel coronavirus) vaccine'),('covid-vaccination',1,'COCO138186NEMIS',NULL,'COVID-19 mRNA Vaccine BNT162b2 30micrograms/0.3ml dose concentrate for suspension for injection multidose vials (Pfizer-BioNTech) (Pfizer-BioNTech)'),('covid-vaccination',1,'^ESCT1348325',NULL,'Administration of second dose of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccine'),('covid-vaccination',1,'^ESCT1348326',NULL,'Administration of second dose of 2019-nCoV (novel coronavirus) vaccine'),('covid-vaccination',1,'^ESCT1428354',NULL,'Administration of third dose of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccine'),('covid-vaccination',1,'^ESCT1428342',NULL,'Administration of fourth dose of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccine'),('covid-vaccination',1,'^ESCT1428348',NULL,'Administration of fifth dose of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccine'),('covid-vaccination',1,'^ESCT1348298',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccination'),('covid-vaccination',1,'^ESCT1348301',NULL,'COVID-19 vaccination'),('covid-vaccination',1,'^ESCT1299050',NULL,'2019-nCoV (novel coronavirus) vaccination'),('covid-vaccination',1,'^ESCT1301222',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccination'),('covid-vaccination',1,'CODI138564NEMIS',NULL,'Covid-19 mRna (nucleoside modified) Vaccine Moderna  Dispersion for injection  0.1 mg/0.5 ml dose, multidose vial'),('covid-vaccination',1,'TASO138184NEMIS',NULL,'Covid-19 Vaccine AstraZeneca (ChAdOx1 S recombinant)  Solution for injection  5x10 billion viral particle/0.5 ml multidose vial'),('covid-vaccination',1,'PCSDT18491_1375',NULL,'Administration of first dose of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccine'),('covid-vaccination',1,'PCSDT18491_1376',NULL,'Administration of second dose of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccine'),('covid-vaccination',1,'PCSDT18491_716',NULL,'Administration of second dose of SARS-CoV-2 vacc'),('covid-vaccination',1,'PCSDT18491_903',NULL,'Administration of first dose of SARS-CoV-2 vacccine'),('covid-vaccination',1,'PCSDT3370_2254',NULL,'2019-nCoV (novel coronavirus) vaccination'),('covid-vaccination',1,'PCSDT3919_2185',NULL,'Administration of first dose of SARS-CoV-2 vacccine'),('covid-vaccination',1,'PCSDT3919_662',NULL,'Administration of second dose of SARS-CoV-2 vacc'),('covid-vaccination',1,'PCSDT4803_1723',NULL,'2019-nCoV (novel coronavirus) vaccination'),('covid-vaccination',1,'PCSDT5823_2264',NULL,'Administration of second dose of SARS-CoV-2 vacc'),('covid-vaccination',1,'PCSDT5823_2757',NULL,'Administration of second dose of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccine'),('covid-vaccination',1,'PCSDT5823_2902',NULL,'Administration of first dose of SARS-CoV-2 vacccine'),('covid-vaccination',1,'^ESCT1348300',NULL,'Severe acute respiratory syndrome coronavirus 2 vaccination'),('covid-vaccination',1,'ASSO138368NEMIS',NULL,'COVID-19 Vaccine Janssen (Ad26.COV2-S [recombinant]) 0.5ml dose suspension for injection multidose vials (Janssen-Cilag Ltd)'),('covid-vaccination',1,'COCO141057NEMIS',NULL,'Comirnaty Children 5-11 years COVID-19 mRNA Vaccine 10micrograms/0.2ml dose concentrate for dispersion for injection multidose vials (Pfizer Ltd)'),('covid-vaccination',1,'COSO141059NEMIS',NULL,'COVID-19 Vaccine Covishield (ChAdOx1 S [recombinant]) 5x10,000,000,000 viral particles/0.5ml dose solution for injection multidose vials (Serum Institute of India)'),('covid-vaccination',1,'COSU138776NEMIS',NULL,'COVID-19 Vaccine Valneva (inactivated adjuvanted whole virus) 40antigen units/0.5ml dose suspension for injection multidose vials (Valneva UK Ltd)'),('covid-vaccination',1,'COSU138943NEMIS',NULL,'COVID-19 Vaccine Novavax (adjuvanted) 5micrograms/0.5ml dose suspension for injection multidose vials (Baxter Oncology GmbH)'),('covid-vaccination',1,'COSU141008NEMIS',NULL,'CoronaVac COVID-19 Vaccine (adjuvanted) 600U/0.5ml dose suspension for injection vials (Sinovac Life Sciences)'),('covid-vaccination',1,'COSU141037NEMIS',NULL,'COVID-19 Vaccine Sinopharm BIBP (inactivated adjuvanted) 6.5U/0.5ml dose suspension for injection vials (Beijing Institute of Biological Products)'),('covid-vaccination',1,'^ESCT1299051',NULL,'Wuhan 2019-nCoV (novel coronavirus) vaccination'),('covid-vaccination',1,'^ESCT1299052',NULL,'2019 novel coronavirus vaccination'),('covid-vaccination',1,'^ESCT1348299',NULL,'2019 novel coronavirus vaccination'),('covid-vaccination',1,'^ESCT1348302',NULL,'2019-nCoV (novel coronavirus) vaccination'),('covid-vaccination',1,'^ESCT1402904',NULL,'COVID-19 Vaccine AstraZeneca (ChAdOx1 S [recombinant]) 5x10,000,000,000 viral particles/0.5ml dose solution for injection multidose vials (AstraZeneca UK Ltd)'),('covid-vaccination',1,'^ESCT1402911',NULL,'COVID-19 mRNA Vaccine Pfizer-BioNTech BNT162b2 30micrograms/0.3ml dose concentrate for suspension for injection multidose vials (Pfizer Ltd)'),('covid-vaccination',1,'^ESCT1403901',NULL,'Astute 100,000,000,000 (100 billion) viral particles/0.5ml dose solution for injection multidose vials (Janssen-Cilag Ltd)'),('covid-vaccination',1,'^ESCT1404736',NULL,'COVID-19 mRNA (nucleoside modified) Vaccine Moderna 0.1mg/0.5mL dose dispersion for injection multidose vials (Moderna, Inc)'),('covid-vaccination',1,'^ESCT1405128',NULL,'COVID-19 Vaccine Valneva (inactivated adjuvanted whole virus) 40antigen units/0.5mL dose suspension for injection multidose vials (Valneva UK Ltd)'),('covid-vaccination',1,'^ESCT1418812',NULL,'COVID-19 Vaccine Novavax (adjuvanted) 5micrograms/0.5ml dose suspension for injection multidose vials (Baxter Oncology GmbH)'),('covid-vaccination',1,'^ESCT1421492',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) antigen vaccination'),('covid-vaccination',1,'^ESCT1421493',NULL,'COVID-19 antigen immunisation'),('covid-vaccination',1,'^ESCT1421494',NULL,'2019 novel coronavirus antigen immunisation'),('covid-vaccination',1,'^ESCT1421495',NULL,'2019 novel coronavirus antigen vaccination'),('covid-vaccination',1,'^ESCT1421496',NULL,'COVID-19 antigen vaccination'),('covid-vaccination',1,'^ESCT1421497',NULL,'Severe acute respiratory syndrome coronavirus 2 antigen vaccination'),('covid-vaccination',1,'^ESCT1421498',NULL,'Administration of vaccine product containing only Severe acute respiratory syndrome coronavirus 2 antigen'),('covid-vaccination',1,'^ESCT1421499',NULL,'2019-nCoV (novel coronavirus) antigen vaccination'),('covid-vaccination',1,'^ESCT1423116',NULL,'COVID-19 mRNA (nucleoside modified) Vaccine Moderna 0.1mg/0.5ml dose dispersion for injection multidose vials (Moderna, Inc)'),('covid-vaccination',1,'^ESCT1423124',NULL,'COVID-19 Vaccine Valneva (inactivated adjuvanted whole virus) 40antigen units/0.5ml dose suspension for injection multidose vials (Valneva UK Ltd)'),('covid-vaccination',1,'^ESCT1428110',NULL,'COVID-19 Vaccine Janssen (Ad26.COV2-S [recombinant]) 0.5ml dose solution for injection multidose vials (Janssen-Cilag Ltd)'),('covid-vaccination',1,'^ESCT1428343',NULL,'Administration of fourth dose of 2019-nCoV (novel coronavirus) vaccine'),('covid-vaccination',1,'^ESCT1428349',NULL,'Administration of fifth dose of 2019-nCoV (novel coronavirus) vaccine'),('covid-vaccination',1,'^ESCT1428355',NULL,'Administration of third dose of 2019-nCoV (novel coronavirus) vaccine'),('covid-vaccination',1,'^ESCT1431765',NULL,'COVID-19 Vaccine AstraZeneca (ChAdOx1 S [recombinant]) 5x10,000,000,000 viral particles/0.5ml dose suspension for injection multidose vials (AstraZeneca UK Ltd)'),('covid-vaccination',1,'^ESCT1431769',NULL,'Comirnaty COVID-19 mRNA Vaccine 30micrograms/0.3ml dose concentrate for dispersion for injection multidose vials (Pfizer Ltd)'),('covid-vaccination',1,'^ESCT1431777',NULL,'COVID-19 Vaccine Janssen (Ad26.COV2-S [recombinant]) 0.5ml dose suspension for injection multidose vials (Janssen-Cilag Ltd)'),('covid-vaccination',1,'^ESCT1431787',NULL,'Spikevax COVID-19 mRNA (nucleoside modified) Vaccine 0.1mg/0.5ml dose dispersion for injection multidose vials (Moderna, Inc)'),('covid-vaccination',1,'^ESCT1434508',NULL,'CoronaVac COVID-19 Vaccine (adjuvanted) 600U/0.5ml dose suspension for injection vials (Sinovac Life Sciences)'),('covid-vaccination',1,'^ESCT1434594',NULL,'COVID-19 Vaccine Sinopharm BIBP (inactivated adjuvanted) 6.5U/0.5ml dose suspension for injection vials (Beijing Institute of Biological Products)'),('covid-vaccination',1,'^ESCT1434687',NULL,'COVID-19 Vaccine Covishield (ChAdOx1 S [recombinant]) 5x10,000,000,000 viral particles/0.5ml dose solution for injection multidose vials (Serum Institute of India)'),('covid-vaccination',1,'^ESCT1435624',NULL,'Comirnaty Children 5-11 years COVID-19 mRNA Vaccine 10micrograms/0.2ml dose concentrate for dispersion for injection multidose vials (Pfizer Ltd)'),('covid-vaccination',1,'^ESCT1439300',NULL,'COVID-19 Vaccine Vaxzevria (ChAdOx1 S [recombinant]) 5x10,000,000,000 viral particles/0.5ml dose suspension for injection multidose vials (AstraZeneca UK Ltd)'),('covid-vaccination',1,'^ESCT1441243',NULL,'COVID-19 Vaccine Nuvaxovid (recombinant, adjuvanted) 5micrograms/0.5ml dose dispersion for injection multidose vials (Novavax CZ a.s.)')

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
	VaccineDose1_YearAndMonth = DATEADD(dd, -( DAY( VaccineDose1Date) -1 ), VaccineDose1Date), -- hide the day by setting to first of the month
	VaccineDose2_YearAndMonth = DATEADD(dd, -( DAY( VaccineDose2Date) -1 ), VaccineDose2Date), -- hide the day by setting to first of the month
	VaccineDose3_YearAndMonth = DATEADD(dd, -( DAY( VaccineDose3Date) -1 ), VaccineDose3Date), -- hide the day by setting to first of the month
	VaccineDose4_YearAndMonth = DATEADD(dd, -( DAY( VaccineDose4Date) -1 ), VaccineDose4Date), -- hide the day by setting to first of the month
	VaccineDose5_YearAndMonth = DATEADD(dd, -( DAY( VaccineDose5Date) -1 ), VaccineDose5Date), -- hide the day by setting to first of the month
	VaccineDose6_YearAndMonth = DATEADD(dd, -( DAY( VaccineDose6Date) -1 ), VaccineDose6Date), -- hide the day by setting to first of the month
	VaccineDose7_YearAndMonth = DATEADD(dd, -( DAY( VaccineDose7Date) -1 ), VaccineDose7Date) -- hide the day by setting to first of the month
FROM #COVIDVaccinations
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
	AND (VaccineDose1Date IS NULL OR VaccineDose1Date <= @EndDate)
	AND (VaccineDose2Date IS NULL OR VaccineDose2Date <= @EndDate)
	AND (VaccineDose3Date IS NULL OR VaccineDose3Date <= @EndDate)
	AND (VaccineDose4Date IS NULL OR VaccineDose4Date <= @EndDate)               
	AND (VaccineDose5Date IS NULL OR VaccineDose5Date <= @EndDate)
	AND (VaccineDose6Date IS NULL OR VaccineDose6Date <= @EndDate)
	AND (VaccineDose7Date IS NULL OR VaccineDose7Date <= @EndDate)
