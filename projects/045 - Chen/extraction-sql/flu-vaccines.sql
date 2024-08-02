
--┌────────────────────┐
--│ Flu vaccinations   │
--└────────────────────┘

-- OBJECTIVE: To obtain a table with all flu vaccinations for each patient.

-- OUTPUT: 
-- 	- FK_Patient_Link_ID - unique patient id
--	- FluVaccineYearAndMonth - date of vaccine administration (YYYY-MM)

-- Set the start date
DECLARE @EndDate datetime;
SET @EndDate = '2023-12-31';


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
VALUES ('flu-vaccine',1,'n47..',NULL,'INFLUENZA VACCINES'),('flu-vaccine',1,'n47..00',NULL,'INFLUENZA VACCINES'),('flu-vaccine',1,'n471.',NULL,'FLUVIRIN prefilled syringe 0.5mL'),('flu-vaccine',1,'n471.00',NULL,'FLUVIRIN prefilled syringe 0.5mL'),('flu-vaccine',1,'n472.',NULL,'INFLUVAC SUB-UNIT prefilled syringe 0.5mL'),('flu-vaccine',1,'n472.00',NULL,'INFLUVAC SUB-UNIT prefilled syringe 0.5mL'),('flu-vaccine',1,'n473.',NULL,'INFLUVAC SUB-UNIT prefilled syringe 0.5mL'),('flu-vaccine',1,'n473.00',NULL,'INFLUVAC SUB-UNIT prefilled syringe 0.5mL'),('flu-vaccine',1,'n474.',NULL,'*INFLUVAC SUB-UNIT vials 5mL'),('flu-vaccine',1,'n474.00',NULL,'*INFLUVAC SUB-UNIT vials 5mL'),('flu-vaccine',1,'n475.',NULL,'*INFLUVAC SUB-UNIT vials 25mL'),('flu-vaccine',1,'n475.00',NULL,'*INFLUVAC SUB-UNIT vials 25mL'),('flu-vaccine',1,'n476.',NULL,'MFV-JECT prefilled syringe 0.5mL'),('flu-vaccine',1,'n476.00',NULL,'MFV-JECT prefilled syringe 0.5mL'),('flu-vaccine',1,'n477.',NULL,'INACTIVATED INFLUENZA VACCINE injection 0.5mL'),('flu-vaccine',1,'n477.00',NULL,'INACTIVATED INFLUENZA VACCINE injection 0.5mL'),('flu-vaccine',1,'n478.',NULL,'INACTIVATED INFLUENZA VACCINE prefilled syringe 0.5mL'),('flu-vaccine',1,'n478.00',NULL,'INACTIVATED INFLUENZA VACCINE prefilled syringe 0.5mL'),('flu-vaccine',1,'n479.',NULL,'*INFLUENZA VACCINE vials 5mL'),('flu-vaccine',1,'n479.00',NULL,'*INFLUENZA VACCINE vials 5mL'),('flu-vaccine',1,'n47A.',NULL,'PANDEMRIX INFLUENZA A VACCINE (H1N1v) 2009 injection'),('flu-vaccine',1,'n47A.00',NULL,'PANDEMRIX INFLUENZA A VACCINE (H1N1v) 2009 injection'),('flu-vaccine',1,'n47B.',NULL,'CELVAPAN INFLUENZA A VACCINE (H1N1v) 2009 injection'),('flu-vaccine',1,'n47B.00',NULL,'CELVAPAN INFLUENZA A VACCINE (H1N1v) 2009 injection'),('flu-vaccine',1,'n47C.',NULL,'PREFLUCEL suspension for injection prefilled syringe 0.5mL'),('flu-vaccine',1,'n47C.00',NULL,'PREFLUCEL suspension for injection prefilled syringe 0.5mL'),('flu-vaccine',1,'n47D.',NULL,'*FLUENZ nasal suspension 0.2mL'),('flu-vaccine',1,'n47D.00',NULL,'*FLUENZ nasal suspension 0.2mL'),('flu-vaccine',1,'n47E.',NULL,'INFLUENZA VACCINE (LIVE ATTENUATED) nasal suspension 0.2mL'),('flu-vaccine',1,'n47E.00',NULL,'INFLUENZA VACCINE (LIVE ATTENUATED) nasal suspension 0.2mL'),('flu-vaccine',1,'n47F.',NULL,'OPTAFLU suspension for injection prefilled syringe 0.5mL'),('flu-vaccine',1,'n47F.00',NULL,'OPTAFLU suspension for injection prefilled syringe 0.5mL'),('flu-vaccine',1,'n47G.',NULL,'INFLUVAC DESU suspension for injection prefill syringe 0.5mL'),('flu-vaccine',1,'n47G.00',NULL,'INFLUVAC DESU suspension for injection prefill syringe 0.5mL'),('flu-vaccine',1,'n47H.',NULL,'FLUARIX TETRA suspension for injection prefill syringe 0.5mL'),('flu-vaccine',1,'n47H.00',NULL,'FLUARIX TETRA suspension for injection prefill syringe 0.5mL'),('flu-vaccine',1,'n47I.',NULL,'FLUENZ TETRA nasal spray suspension 0.2mL'),('flu-vaccine',1,'n47I.00',NULL,'FLUENZ TETRA nasal spray suspension 0.2mL'),('flu-vaccine',1,'n47a.',NULL,'*INFLUENZA VACCINE vials 25mL'),('flu-vaccine',1,'n47a.00',NULL,'*INFLUENZA VACCINE vials 25mL'),('flu-vaccine',1,'n47b.',NULL,'FLUZONE prefilled syringe 0.5mL'),('flu-vaccine',1,'n47b.00',NULL,'FLUZONE prefilled syringe 0.5mL'),('flu-vaccine',1,'n47c.',NULL,'*FLUZONE vials 5mL'),('flu-vaccine',1,'n47c.00',NULL,'*FLUZONE vials 5mL'),('flu-vaccine',1,'n47d.',NULL,'FLUARIX VACCINE prefilled syringe'),('flu-vaccine',1,'n47d.00',NULL,'FLUARIX VACCINE prefilled syringe'),('flu-vaccine',1,'n47e.',NULL,'BEGRIVAC VACCINE prefilled syringe 0.5mL'),('flu-vaccine',1,'n47e.00',NULL,'BEGRIVAC VACCINE prefilled syringe 0.5mL'),('flu-vaccine',1,'n47f.',NULL,'AGRIPPAL VACCINE prefilled syringe 0.5mL'),('flu-vaccine',1,'n47f.00',NULL,'AGRIPPAL VACCINE prefilled syringe 0.5mL'),('flu-vaccine',1,'n47g.',NULL,'INACTIVATED INFLUENZA VACCINE (SPLIT VIRION) prefilled syringe 0.5mL'),('flu-vaccine',1,'n47g.00',NULL,'INACTIVATED INFLUENZA VACCINE (SPLIT VIRION) prefilled syringe 0.5mL'),('flu-vaccine',1,'n47h.',NULL,'INACTIVATED INFLUENZA VACCINE (SURFACE ANTIGEN SUB-UNIT) prefilled syringe 0.5mL'),('flu-vaccine',1,'n47h.00',NULL,'INACTIVATED INFLUENZA VACCINE (SURFACE ANTIGEN SUB-UNIT) prefilled syringe 0.5mL'),('flu-vaccine',1,'n47i.',NULL,'INFLEXAL BERNA V prefilled syringe 0.5mL'),('flu-vaccine',1,'n47i.00',NULL,'INFLEXAL BERNA V prefilled syringe 0.5mL'),('flu-vaccine',1,'n47j.',NULL,'MASTAFLU prefilled syringe 0.5mL'),('flu-vaccine',1,'n47j.00',NULL,'MASTAFLU prefilled syringe 0.5mL'),('flu-vaccine',1,'n47k.',NULL,'INFLEXAL V prefilled syringe 0.5mL'),('flu-vaccine',1,'n47k.00',NULL,'INFLEXAL V prefilled syringe 0.5mL'),('flu-vaccine',1,'n47l.',NULL,'INVIVAC prefilled syringe 0.5mL'),('flu-vaccine',1,'n47l.00',NULL,'INVIVAC prefilled syringe 0.5mL'),('flu-vaccine',1,'n47m.',NULL,'ENZIRA prefilled syringe 0.5mL'),('flu-vaccine',1,'n47m.00',NULL,'ENZIRA prefilled syringe 0.5mL'),('flu-vaccine',1,'n47n.',NULL,'VIROFLU prefilled syringe 0.5mL'),('flu-vaccine',1,'n47n.00',NULL,'VIROFLU prefilled syringe 0.5mL'),('flu-vaccine',1,'n47o.',NULL,'IMUVAC prefilled syringe 0.5mL'),('flu-vaccine',1,'n47o.00',NULL,'IMUVAC prefilled syringe 0.5mL'),('flu-vaccine',1,'n47p.',NULL,'INTANZA 15micrograms/strain susp for inj pfs 0.1mL'),('flu-vaccine',1,'n47p.00',NULL,'INTANZA 15micrograms/strain susp for inj pfs 0.1mL'),('flu-vaccine',1,'n47q.',NULL,'INACT INFLUENZA VACC (SPLIT VIRION) 15mcg/strain pfs 0.1mL'),('flu-vaccine',1,'n47q.00',NULL,'INACT INFLUENZA VACC (SPLIT VIRION) 15mcg/strain pfs 0.1mL'),('flu-vaccine',1,'n47r.',NULL,'CELVAPAN (H1N1) suspension for injection vials 5mL'),('flu-vaccine',1,'n47r.00',NULL,'CELVAPAN (H1N1) suspension for injection vials 5mL'),('flu-vaccine',1,'n47s.',NULL,'CELVAPAN (H5N1) suspension for injection vials 5mL'),('flu-vaccine',1,'n47s.00',NULL,'CELVAPAN (H5N1) suspension for injection vials 5mL'),('flu-vaccine',1,'n47t.',NULL,'PANDEMRIX (H5N1) injection vials'),('flu-vaccine',1,'n47t.00',NULL,'PANDEMRIX (H5N1) injection vials'),('flu-vaccine',1,'n47u.',NULL,'INTANZA 9micrograms/strain susp for inj pfs 0.1mL'),('flu-vaccine',1,'n47u.00',NULL,'INTANZA 9micrograms/strain susp for inj pfs 0.1mL'),('flu-vaccine',1,'n47v.',NULL,'INACT INFLUENZA VACC (SPLIT VIRION) 9mcg/strain pfs 0.1mL'),('flu-vaccine',1,'n47v.00',NULL,'INACT INFLUENZA VACC (SPLIT VIRION) 9mcg/strain pfs 0.1mL'),('flu-vaccine',1,'n47y.',NULL,'INACTIVATED INFLUENZA VACCINE (SPLIT VIRION) prefilled syringe 0.25mL'),('flu-vaccine',1,'n47y.00',NULL,'INACTIVATED INFLUENZA VACCINE (SPLIT VIRION) prefilled syringe 0.25mL'),('flu-vaccine',1,'n47z.',NULL,'INACTIVATED INFLUENZA VACCINE (SURFACE ANTIGEN VIROSOME) prefilled syringe 0.5mL'),('flu-vaccine',1,'n47z.00',NULL,'INACTIVATED INFLUENZA VACCINE (SURFACE ANTIGEN VIROSOME) prefilled syringe 0.5mL');
INSERT INTO #codesreadv2
VALUES ('flu-vaccination',1,'65E..',NULL,'Influenza vaccination'),('flu-vaccination',1,'65E..00',NULL,'Influenza vaccination'),('flu-vaccination',1,'65E0.',NULL,'First pandemic influenza vaccination'),('flu-vaccination',1,'65E0.00',NULL,'First pandemic influenza vaccination'),('flu-vaccination',1,'65E00',NULL,'Administration of first intranasal pandemic influenza vaccination'),('flu-vaccination',1,'65E0000',NULL,'Administration of first intranasal pandemic influenza vaccination'),('flu-vaccination',1,'65E1.',NULL,'Second pandemic influenza vaccination'),('flu-vaccination',1,'65E1.00',NULL,'Second pandemic influenza vaccination'),('flu-vaccination',1,'65E10',NULL,'Administration of second intranasal pandemic influenza vaccination'),('flu-vaccination',1,'65E1000',NULL,'Administration of second intranasal pandemic influenza vaccination'),('flu-vaccination',1,'65E2.',NULL,'Influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'65E2.00',NULL,'Influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'65E20',NULL,'Seasonal influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'65E2000',NULL,'Seasonal influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'65E21',NULL,'First intranasal seasonal influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'65E2100',NULL,'First intranasal seasonal influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'65E22',NULL,'Second intranasal seasonal influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'65E2200',NULL,'Second intranasal seasonal influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'65E23',NULL,'Second intramuscular seasonal influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'65E2300',NULL,'Second intramuscular seasonal influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'65E24',NULL,'First intramuscular seasonal influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'65E2400',NULL,'First intramuscular seasonal influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'65E3.',NULL,'First pandemic influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'65E3.00',NULL,'First pandemic influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'65E30',NULL,'First intranasal pandemic influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'65E3000',NULL,'First intranasal pandemic influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'65E4.',NULL,'Second pandemic influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'65E4.00',NULL,'Second pandemic influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'65E40',NULL,'Second intranasal pandemic influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'65E4000',NULL,'Second intranasal pandemic influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'65E5.',NULL,'CELVAPAN - first influenza A (H1N1v) 2009 vaccination given'),('flu-vaccination',1,'65E5.00',NULL,'CELVAPAN - first influenza A (H1N1v) 2009 vaccination given'),('flu-vaccination',1,'65E6.',NULL,'CELVAPAN - second influenza A (H1N1v) 2009 vaccination given'),('flu-vaccination',1,'65E6.00',NULL,'CELVAPAN - second influenza A (H1N1v) 2009 vaccination given'),('flu-vaccination',1,'65E7.',NULL,'CELVAPAN - first influenza A (H1N1v) 2009 vaccination given by other healthcare provider'),('flu-vaccination',1,'65E7.00',NULL,'CELVAPAN - first influenza A (H1N1v) 2009 vaccination given by other healthcare provider'),('flu-vaccination',1,'65E8.',NULL,'CELVAPAN - second influenza A (H1N1v) 2009 vaccination given by other healthcare provider'),('flu-vaccination',1,'65E8.00',NULL,'CELVAPAN - second influenza A (H1N1v) 2009 vaccination given by other healthcare provider'),('flu-vaccination',1,'65E9.',NULL,'PANDEMRIX - first influenza A (H1N1v) 2009 vaccination given'),('flu-vaccination',1,'65E9.00',NULL,'PANDEMRIX - first influenza A (H1N1v) 2009 vaccination given'),('flu-vaccination',1,'65EA.',NULL,'PANDEMRIX - second influenza A (H1N1v) 2009 vaccination given'),('flu-vaccination',1,'65EA.00',NULL,'PANDEMRIX - second influenza A (H1N1v) 2009 vaccination given'),('flu-vaccination',1,'65EB.',NULL,'PANDEMRIX - first influenza A (H1N1v) 2009 vaccination given by other healthcare provider'),('flu-vaccination',1,'65EB.00',NULL,'PANDEMRIX - first influenza A (H1N1v) 2009 vaccination given by other healthcare provider'),('flu-vaccination',1,'65EC.',NULL,'PANDEMRIX - second influenza A (H1N1v) 2009 vaccination given by other healthcare provider'),('flu-vaccination',1,'65EC.00',NULL,'PANDEMRIX - second influenza A (H1N1v) 2009 vaccination given by other healthcare provider'),('flu-vaccination',1,'65ED.',NULL,'Seasonal influenza vaccination'),('flu-vaccination',1,'65ED.00',NULL,'Seasonal influenza vaccination'),('flu-vaccination',1,'65ED0',NULL,'Seasonal influenza vaccination given by pharmacist'),('flu-vaccination',1,'65ED000',NULL,'Seasonal influenza vaccination given by pharmacist'),('flu-vaccination',1,'65ED1',NULL,'Administration of first intranasal seasonal influenza vaccination'),('flu-vaccination',1,'65ED100',NULL,'Administration of first intranasal seasonal influenza vaccination'),('flu-vaccination',1,'65ED2',NULL,'Seasonal influenza vaccination given while hospital inpatient'),('flu-vaccination',1,'65ED200',NULL,'Seasonal influenza vaccination given while hospital inpatient'),('flu-vaccination',1,'65ED3',NULL,'Administration of second intranasal seasonal influenza vaccination'),('flu-vaccination',1,'65ED300',NULL,'Administration of second intranasal seasonal influenza vaccination'),('flu-vaccination',1,'65ED4',NULL,'Administration of first inactivated seasonal influenza vaccination'),('flu-vaccination',1,'65ED400',NULL,'Administration of first inactivated seasonal influenza vaccination'),('flu-vaccination',1,'65ED5',NULL,'Administration of second inactivated seasonal influenza vaccination'),('flu-vaccination',1,'65ED500',NULL,'Administration of second inactivated seasonal influenza vaccination'),('flu-vaccination',1,'65ED6',NULL,'First intranasal seasonal influenza vaccination given by pharmacist'),('flu-vaccination',1,'65ED600',NULL,'First intranasal seasonal influenza vaccination given by pharmacist'),('flu-vaccination',1,'65ED7',NULL,'Second intranasal seasonal influenza vaccination given by pharmacist'),('flu-vaccination',1,'65ED700',NULL,'Second intranasal seasonal influenza vaccination given by pharmacist'),('flu-vaccination',1,'65ED8',NULL,'First inactivated seasonal influenza vaccination given by pharmacist'),('flu-vaccination',1,'65ED800',NULL,'First inactivated seasonal influenza vaccination given by pharmacist'),('flu-vaccination',1,'65ED9',NULL,'Second inactivated seasonal influenza vaccination given by pharmacist'),('flu-vaccination',1,'65ED900',NULL,'Second inactivated seasonal influenza vaccination given by pharmacist'),('flu-vaccination',1,'65EE.',NULL,'Administration of intranasal influenza vaccination'),('flu-vaccination',1,'65EE.00',NULL,'Administration of intranasal influenza vaccination'),('flu-vaccination',1,'65EE0',NULL,'Administration of first intranasal influenza vaccination'),('flu-vaccination',1,'65EE000',NULL,'Administration of first intranasal influenza vaccination'),('flu-vaccination',1,'65EE1',NULL,'Administration of second intranasal influenza vaccination'),('flu-vaccination',1,'65EE100',NULL,'Administration of second intranasal influenza vaccination'),('flu-vaccination',1,'ZV048',NULL,'[V]Influenza vaccination'),('flu-vaccination',1,'ZV04800',NULL,'[V]Influenza vaccination')

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
VALUES ('flu-vaccine',1,'n47..',NULL,'FLU - Influenza vaccine'),('flu-vaccine',1,'n471.',NULL,'Fluvirin prefilled syringe 0.5mL'),('flu-vaccine',1,'n473.',NULL,'Influvac sub-unit prefilled syringe 0.5mL'),('flu-vaccine',1,'n474.',NULL,'Influvac sub-unit Vials 5mL'),('flu-vaccine',1,'n475.',NULL,'Influvac sub-unit Vials 25mL'),('flu-vaccine',1,'n476.',NULL,'MFV-Ject prefilled syringe 0.5mL'),('flu-vaccine',1,'n477.',NULL,'Inactivated Influenza vaccine injection 0.5mL'),('flu-vaccine',1,'n478.',NULL,'Inactivated Influenza vaccine prefilled syringe 0.5mL'),('flu-vaccine',1,'n479.',NULL,'Influenza vaccine Vials 5mL'),('flu-vaccine',1,'n47a.',NULL,'Influenza vaccine Vials 25mL'),('flu-vaccine',1,'n47A.',NULL,'PANDEMRIX INFLUENZA A VACCINE (H1N1v) 2009 injection'),('flu-vaccine',1,'n47B.',NULL,'CELVAPAN INFLUENZA A VACCINE (H1N1v) 2009 injection'),('flu-vaccine',1,'n47b.',NULL,'Fluzone prefilled syringe 0.5mL'),('flu-vaccine',1,'n47c.',NULL,'Fluzone Vials 5mL'),('flu-vaccine',1,'n47C.',NULL,'PREFLUCEL suspension for injection prefilled syringe 0.5mL'),('flu-vaccine',1,'n47d.',NULL,'Fluarix vaccine prefilled syringe'),('flu-vaccine',1,'n47D.',NULL,'FLUENZ nasal suspension 0.2mL'),('flu-vaccine',1,'n47e.',NULL,'Begrivac vaccine pre-filled syringe 0.5mL'),('flu-vaccine',1,'n47E.',NULL,'INFLUENZA VACCINE (LIVE ATTENUATED) nasal suspension 0.2mL'),('flu-vaccine',1,'n47f.',NULL,'Agrippal vaccine prefilled syringe 0.5mL'),('flu-vaccine',1,'n47F.',NULL,'OPTAFLU suspension for injection prefilled syringe 0.5mL'),('flu-vaccine',1,'n47g.',NULL,'Inactivated Influenza vaccine (split virion) prefilled syringe 0.5mL'),('flu-vaccine',1,'n47G.',NULL,'INFLUVAC DESU suspension for injection prefill syringe 0.5mL'),('flu-vaccine',1,'n47H.',NULL,'FLUARIX TETRA suspension for injection prefill syringe 0.5mL'),('flu-vaccine',1,'n47h.',NULL,'Inactivated Influenza vaccine (surface antigen) prefilled syringe 0.5mL'),('flu-vaccine',1,'n47I.',NULL,'FLUENZ TETRA nasal spray suspension 0.2mL'),('flu-vaccine',1,'n47i.',NULL,'Inflexal Berna V prefilled syringe 0.5mL'),('flu-vaccine',1,'n47j.',NULL,'MASTAFLU prefilled syringe 0.5mL'),('flu-vaccine',1,'n47k.',NULL,'Inflexal V prefilled syringe 0.5mL'),('flu-vaccine',1,'n47l.',NULL,'Invivac prefilled syringe 0.5mL'),('flu-vaccine',1,'n47m.',NULL,'Enzira prefilled syringe 0.5mL'),('flu-vaccine',1,'n47n.',NULL,'Viroflu prefilled syringe 0.5mL'),('flu-vaccine',1,'n47o.',NULL,'IMUVAC prefilled syringe 0.5mL'),('flu-vaccine',1,'n47p.',NULL,'INTANZA 15micrograms/strain susp for inj pfs 0.1mL'),('flu-vaccine',1,'n47q.',NULL,'INACT INFLUENZA VACC (SPLIT VIRION) 15mcg/strain pfs 0.1mL'),('flu-vaccine',1,'n47r.',NULL,'CELVAPAN (H1N1) suspension for injection vials 5mL'),('flu-vaccine',1,'n47s.',NULL,'CELVAPAN (H5N1) suspension for injection vials 5mL'),('flu-vaccine',1,'n47t.',NULL,'PANDEMRIX (H5N1) injection vials'),('flu-vaccine',1,'n47u.',NULL,'INTANZA 9micrograms/strain susp for inj pfs 0.1mL'),('flu-vaccine',1,'n47v.',NULL,'INACT INFLUENZA VACC (SPLIT VIRION) 9mcg/strain pfs 0.1mL'),('flu-vaccine',1,'n47y.',NULL,'Inactivated Influenza vaccine (split virion) prefilled syringe 0.25mL'),('flu-vaccine',1,'n47z.',NULL,'Inactivated Influenza vaccine (surface antigen virosome) prefilled syringe 0.5mL'),('flu-vaccine',1,'x006a',NULL,'Inactivated Influenza surface antigen sub-unit vaccine'),('flu-vaccine',1,'x006Z',NULL,'Inactivated Influenza split virion vaccine'),('flu-vaccine',1,'x00Yd',NULL,'Fluvirin vaccine prefilled syringe'),('flu-vaccine',1,'x00Ye',NULL,'Fluzone vaccine prefilled syringe'),('flu-vaccine',1,'x00Yi',NULL,'Inactivated Influenza (split virion) vaccine prefilled syringe'),('flu-vaccine',1,'x00Yj',NULL,'Inactivated Influenza (surface antigen sub-unit ) vaccine prefilled syringe'),('flu-vaccine',1,'x00Yk',NULL,'Influvac Sub-unit vaccine prefilled syringe'),('flu-vaccine',1,'x00Yp',NULL,'MFV-Ject vaccine prefilled syringe'),('flu-vaccine',1,'x01LF',NULL,'Influvac Sub-unit injection'),('flu-vaccine',1,'x01LG',NULL,'Fluzone injection vial'),('flu-vaccine',1,'x02d0',NULL,'Fluarix'),('flu-vaccine',1,'x03qt',NULL,'Begrivac vaccine prefilled syringe'),('flu-vaccine',1,'x03qu',NULL,'Begrivac'),('flu-vaccine',1,'x03zt',NULL,'Fluvirin'),('flu-vaccine',1,'x03zu',NULL,'Fluzone'),('flu-vaccine',1,'x0453',NULL,'Influvac Sub-unit'),('flu-vaccine',1,'x05cg',NULL,'Inflexal Berna V prefilled syringe'),('flu-vaccine',1,'x05cj',NULL,'Inflexal Berna V'),('flu-vaccine',1,'x05oa',NULL,'MASTAFLU prefilled syringe'),('flu-vaccine',1,'x05ob',NULL,'MASTAFLU'),('flu-vaccine',1,'x05pi',NULL,'Inflexal V'),('flu-vaccine',1,'x05pY',NULL,'Inflexal V prefilled syringe'),('flu-vaccine',1,'x05vU',NULL,'Invivac vaccine prefilled syringe'),('flu-vaccine',1,'x05vV',NULL,'Invivac'),('flu-vaccine',1,'x05Y1',NULL,'Agrippal vaccine prefilled syringe'),('flu-vaccine',1,'x05yK',NULL,'Enzira vaccine prefilled syringe'),('flu-vaccine',1,'x05yL',NULL,'Enzira'),('flu-vaccine',1,'x05yO',NULL,'Inactivated Influenza surface antigen virosome vaccine prefilled syringe'),('flu-vaccine',1,'x05yP',NULL,'Inactivated Influenza surface antigen virosome vaccine'),('flu-vaccine',1,'x05zC',NULL,'Viroflu prefilled syringe'),('flu-vaccine',1,'x05zD',NULL,'Viroflu');
INSERT INTO #codesctv3
VALUES ('flu-vaccination',1,'65E..',NULL,'Influenza vaccination'),('flu-vaccination',1,'Xaa9G',NULL,'Administration of intranasal influenza vaccination'),('flu-vaccination',1,'Xaac1',NULL,'Administration of first intranasal pandemic influenza vaccination'),('flu-vaccination',1,'Xaac2',NULL,'Administration of second intranasal pandemic influenza vaccination'),('flu-vaccination',1,'Xaac3',NULL,'Administration of first intranasal seasonal influenza vaccination'),('flu-vaccination',1,'Xaac4',NULL,'Administration of second intranasal seasonal influenza vaccination'),('flu-vaccination',1,'Xaac5',NULL,'First intranasal pandemic influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'Xaac6',NULL,'Second intranasal pandemic influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'Xaac7',NULL,'First intranasal seasonal influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'Xaac8',NULL,'Second intranasal seasonal influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'XaaED',NULL,'Administration of first intranasal influenza vaccination'),('flu-vaccination',1,'XaaEF',NULL,'Administration of second intranasal influenza vaccination'),('flu-vaccination',1,'XaaZp',NULL,'Seasonal influenza vaccination given while hospital inpatient'),('flu-vaccination',1,'XabvT',NULL,'Second intramuscular seasonal influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'Xac5J',NULL,'First intramuscular seasonal influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'Xad9j',NULL,'Administration of first inactivated seasonal influenza vaccination'),('flu-vaccination',1,'Xad9k',NULL,'Administration of second inactivated seasonal influenza vaccination'),('flu-vaccination',1,'Xaeet',NULL,'First intranasal seasonal influenza vaccination given by pharmacist'),('flu-vaccination',1,'Xaeeu',NULL,'Second intranasal seasonal influenza vaccination given by pharmacist'),('flu-vaccination',1,'Xaeev',NULL,'First inactivated seasonal influenza vaccination given by pharmacist'),('flu-vaccination',1,'Xaeew',NULL,'Second inactivated seasonal influenza vaccination given by pharmacist'),('flu-vaccination',1,'XafhP',NULL,'Seasonal influenza vaccination given by midwife'),('flu-vaccination',1,'XafhQ',NULL,'First inactivated seasonal influenza vaccination given by midwife'),('flu-vaccination',1,'XafhR',NULL,'Second inactivated seasonal influenza vaccination given by midwife'),('flu-vaccination',1,'XaLK4',NULL,'Booster influenza vaccination'),('flu-vaccination',1,'XaLNG',NULL,'First pandemic influenza vaccination'),('flu-vaccination',1,'XaLNH',NULL,'Second pandemic influenza vaccination'),('flu-vaccination',1,'XaPwi',NULL,'First pandemic influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'XaPwj',NULL,'Second pandemic influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'XaPyT',NULL,'Influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'XaQhk',NULL,'CELVAPAN - first influenza A (H1N1v) 2009 vaccination given'),('flu-vaccination',1,'XaQhl',NULL,'CELVAPAN - second influenza A (H1N1v) 2009 vaccination given'),('flu-vaccination',1,'XaQhm',NULL,'PANDEMRIX - first influenza A (H1N1v) 2009 vaccination given'),('flu-vaccination',1,'XaQhn',NULL,'PANDEMRIX - second influenza A (H1N1v) 2009 vaccination given'),('flu-vaccination',1,'XaQho',NULL,'CELVAPAN - first influenza A (H1N1v) 2009 vaccination given by other healthcare provider'),('flu-vaccination',1,'XaQhp',NULL,'CELVAPAN - second influenza A (H1N1v) 2009 vaccination given by other healthcare provider'),('flu-vaccination',1,'XaQhq',NULL,'PANDEMRIX - first influenza A (H1N1v) 2009 vaccination given by other healthcare provider'),('flu-vaccination',1,'XaQhr',NULL,'PANDEMRIX - second influenza A (H1N1v) 2009 vaccination given by other healthcare provider'),('flu-vaccination',1,'XaZ0d',NULL,'Seasonal influenza vaccination'),('flu-vaccination',1,'XaZ0e',NULL,'Seasonal influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'XaZfY',NULL,'Seasonal influenza vaccination given by pharmacist'),('flu-vaccination',1,'ZV048',NULL,'[V]Flu - influenza vaccination'),('flu-vaccination',1,'Y0c3f',NULL,'First influenza A (H1N1v) 2009 vaccination given'),('flu-vaccination',1,'Y0c40',NULL,'Second influenza A (H1N1v) 2009 vaccination given')

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
VALUES ('flu-vaccine',1,'10306411000001104',NULL,'Invivac suspension for injection 0.5ml pre-filled syringes (Solvay Healthcare Ltd) (product)'),('flu-vaccine',1,'10309511000001105',NULL,'Influenza vaccine (surface antigen, inactivated, virosome) suspension for injection 0.5ml pre-filled syringes (product)'),('flu-vaccine',1,'10455811000001107',NULL,'Viroflu vaccine suspension for injection 0.5ml pre-filled syringes (sanofi pasteur MSD Ltd) (product)'),('flu-vaccine',1,'10859911000001105',NULL,'Imuvac vaccine suspension for injection 0.5ml pre-filled syringes (Viatris UK Healthcare Ltd) (product)'),('flu-vaccine',1,'11278411000001109',NULL,'Influenza vaccine (split virion, inactivated) suspension for injection 0.5ml pre-filled syringes (Wyeth Pharmaceuticals) (product)'),('flu-vaccine',1,'15382311000001101',NULL,'Optaflu vaccine suspension for injection 0.5ml pre-filled syringes (Seqirus UK Ltd) (product)'),('flu-vaccine',1,'15454511000001101',NULL,'Intanza 9microgram strain vaccine suspension for injection 0.1ml pre-filled syringes (sanofi pasteur MSD Ltd) (product)'),('flu-vaccine',1,'15506511000001107',NULL,'Intanza 15microgram strain vaccine suspension for injection 0.1ml pre-filled syringes (sanofi pasteur MSD Ltd) (product)'),('flu-vaccine',1,'15507511000001109',NULL,'Influenza vaccine (split virion, inactivated) 15microgram strain suspension for injection 0.1ml pre-filled syringes (product)'),('flu-vaccine',1,'15650611000001107',NULL,'Celvapan (H1N1) vaccine (whole virion, Vero cell derived, inactivated) suspension for injection (Baxter Healthcare Ltd) (product)'),('flu-vaccine',1,'19820511000001106',NULL,'Fluenz vaccine nasal spray (AstraZeneca UK Ltd) (product)'),('flu-vaccine',1,'19821411000001103',NULL,'Influenza vaccine (live attenuated) nasal spray (product)'),('flu-vaccine',1,'20292211000001109',NULL,'Preflucel vaccine suspension for injection 0.5ml pre-filled syringes (Baxter Healthcare Ltd) (product)'),('flu-vaccine',1,'22628411000001107',NULL,'Influvac Desu vaccine suspension for injection 0.5ml pre-filled syringes (Abbott Healthcare Products Ltd) (product)'),('flu-vaccine',1,'22704311000001109',NULL,'Fluarix Tetra vaccine suspension for injection 0.5ml pre-filled syringes (GlaxoSmithKline UK Ltd) (product)'),('flu-vaccine',1,'27114211000001105',NULL,'Fluenz Tetra vaccine nasal suspension 0.2ml unit dose (AstraZeneca UK Ltd) (product)'),('flu-vaccine',1,'30935711000001104',NULL,'FluMist Quadrivalent vaccine nasal suspension 0.2ml unit dose (AstraZeneca UK Ltd) (product)'),('flu-vaccine',1,'3244411000001106',NULL,'Influenza (split virion, inactivated) vaccine suspension for injection 0.5ml pre-filled syringes (Aventis Pasteur MSD Ltd) (product)'),('flu-vaccine',1,'3245911000001104',NULL,'Fluarix suspension for injection 0.5ml pre-filled syringes (GlaxoSmithKline) (product)'),('flu-vaccine',1,'3247011000001105',NULL,'Begrivac suspension for injection 0.5ml pre-filled syringes (Wyeth Laboratories) (product)'),('flu-vaccine',1,'3249511000001109',NULL,'Fluvirin suspension for injection 0.5ml pre-filled syringes (Chiron Vaccines Evans) (product)'),('flu-vaccine',1,'3255011000001100',NULL,'Influvac Sub-unit vaccine suspension for injection 0.5ml pre-filled syringes (Viatris UK Healthcare Ltd) (product)'),('flu-vaccine',1,'3255311000001102',NULL,'Agrippal vaccine suspension for injection 0.5ml pre-filled syringes (Seqirus UK Ltd) (product)'),('flu-vaccine',1,'34680411000001107',NULL,'Quadrivalent influenza vaccine (split virion, inactivated) suspension for injection 0.5ml pre-filled syringes (Sanofi) (product)'),('flu-vaccine',1,'34783811000001108',NULL,'Fluad vaccine suspension for injection 0.5ml pre-filled syringes (Seqirus Vaccines) (product)'),('flu-vaccine',1,'35726811000001104',NULL,'Influenza Tetra MYL vaccine suspension for injection 0.5ml pre-filled syringes (Viatris UK Healthcare Ltd) (product)'),('flu-vaccine',1,'35727111000001109',NULL,'Influvac sub-unit Tetra vaccine suspension for injection 0.5ml pre-filled syringes (Viatris UK Healthcare Ltd) (product)'),('flu-vaccine',1,'35727211000001103',NULL,'Influvac sub-unit Tetra vaccine suspension for injection 0.5ml pre-filled syringes (Viatris UK Healthcare Ltd) 1 pre-filled disposable injection (product)'),('flu-vaccine',1,'36509011000001106',NULL,'Flucelvax Tetra vaccine suspension for injection 0.5ml pre-filled syringes (Seqirus UK Ltd) (product)'),('flu-vaccine',1,'36754111000001101',NULL,'Trivalent vaccine (split virion, inactivated) High Dose solution for injection pre-filled syringes (Sanofi Pasteur) (product)'),('flu-vaccine',1,'37514711000001105',NULL,'Fluad vaccine suspension for injection 0.5ml pre-filled syringes (Seqirus UK Ltd) (product)'),('flu-vaccine',1,'37547211000001103',NULL,'Adjuvanted trivalent influenza vaccine (surface antigen, inactivated) suspension for injection 0.5ml pre-filled syringes (Seqirus UK Ltd) (product)'),('flu-vaccine',1,'38973211000001108',NULL,'Fluad Tetra vaccine suspension for injection 0.5ml pre-filled syringes (Seqirus UK Ltd) (product)'),('flu-vaccine',1,'39716611000001104',NULL,'Influenza vaccine (surface antigen, inactivated) suspension for injection 0.5ml pre-filled syringes (product)'),('flu-vaccine',1,'39716811000001100',NULL,'Influenza vaccine (split virion, inactivated) suspension for injection 0.5ml pre-filled syringes (product)'),('flu-vaccine',1,'4365711000001104',NULL,'Mastaflu suspension for injection 0.5ml pre-filled syringes (Masta Ltd) (product)'),('flu-vaccine',1,'9511411000001107',NULL,'Enzira suspension for injection 0.5ml pre-filled syringes (Chiron Vaccines Evans) (product)');
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
VALUES ('flu-vaccine',1,'^ESCT1173898',NULL,'Fluad vaccine suspension for injection 0.5ml pre-filled syringes (Seqirus Vaccines Ltd)'),('flu-vaccine',1,'FLVA127091NEMIS',NULL,'Fluad vaccine suspension for injection 0.5ml pre-filled syringes (Seqirus Vaccines Ltd)'),('flu-vaccine',1,'FLVA137918NEMIS',NULL,'Fluad Tetra vaccine suspension for injection 0.5ml pre-filled syringes (Seqirus Vaccines Ltd)'),('flu-vaccine',1,'^ESCT1188861',NULL,'Influvac Sub-unit vaccine suspension for injection 0.5ml pre-filled syringes (Mylan)'),('flu-vaccine',1,'^ESCT1199425',NULL,'Influvac sub-unit Tetra vaccine suspension for injection 0.5ml pre-filled syringes (Mylan) 1 pre-filled disposable injection'),('flu-vaccine',1,'ININ1468',NULL,'Influvac Sub-unit vaccine suspension for injection 0.5ml pre-filled syringes (Mylan)'),('flu-vaccine',1,'INSU82033NEMIS',NULL,'Influvac Desu  Suspension For Injection  0.5 ml pre-filled syringe'),('flu-vaccine',1,'INSU82033NEMIS',NULL,'Influvac Desu vaccine suspension for injection 0.5ml pre-filled syringes (Abbott Healthcare Products Ltd)'),('flu-vaccine',1,'INVA127171NEMIS',NULL,'Influvac sub-unit Tetra vaccine suspension for injection 0.5ml pre-filled syringes (Mylan)'),('flu-vaccine',1,'AVVA5297NEMIS',NULL,'Influenza vaccine (split virion, inactivated) suspension for injection 0.5ml pre-filled syringes (sanofi pasteur MSD Ltd)'),('flu-vaccine',1,'AVVA5297NEMIS',NULL,'Influenza vaccine (split virion, inactivated) suspension for injection 0.5ml pre-filled syringes (Sanofi Pasteur)'),('flu-vaccine',1,'ININ27868EMIS',NULL,'Inactivated Influenza Vaccine, Surface Antigen  Injection  0.5 ml pre-filled syringe'),('flu-vaccine',1,'ININ27868EMIS',NULL,'Influenza vaccine (surface antigen, inactivated) suspension for injection 0.5ml pre-filled syringes'),('flu-vaccine',1,'INNA52407NEMIS',NULL,'Influenza vaccine (live attenuated) nasal suspension 0.2ml unit dose'),('flu-vaccine',1,'INSU127173NEMIS',NULL,'Influenza Vaccine Tetra Myl Suspension For Injection 0.5 ml pre-filled syringe'),('flu-vaccine',1,'INSU23004NEMIS',NULL,'Inactivated Influenza Vaccine, Surface Antigen, Virosome  Suspension For Injection  0.5 ml pre-filled syringe'),('flu-vaccine',1,'INSU23004NEMIS',NULL,'Influenza vaccine (surface antigen, inactivated, virosome) suspension for injection 0.5ml pre-filled syringes'),('flu-vaccine',1,'INVA30366EMIS',NULL,'Influenza vaccine (split virion, inactivated) suspension for injection 0.5ml pre-filled syringes'),('flu-vaccine',1,'INVA36706NEMIS',NULL,'Influenza vaccine (split virion, inactivated) 15microgram strain suspension for injection 0.1ml pre-filled syringes'),('flu-vaccine',1,'PAVA19010EMIS',NULL,'Pasteur Merieux Inactivated Influenza Vaccine 0.5 ml'),('flu-vaccine',1,'PFVA95151NEMIS',NULL,'Influenza vaccine (split virion, inactivated) suspension for injection 0.5ml pre-filled syringes (Pfizer Ltd)'),('flu-vaccine',1,'QUVA124210NEMIS',NULL,'Quadrivalent influenza vaccine (split virion, inactivated) suspension for injection 0.5ml pre-filled syringes (Sanofi Pasteur)'),('flu-vaccine',1,'SAVA131918NEMIS',NULL,'Trivalent influenza vaccine (split virion, inactivated) High Dose suspension for injection 0.5ml pre-filled syringes (Sanofi Pasteur)'),('flu-vaccine',1,'SEVA133336NEMIS',NULL,'Adjuvanted trivalent influenza vaccine (surface antigen, inactivated) suspension for injection 0.5ml pre-filled syringes (Seqirus Vaccines Ltd)'),('flu-vaccine',1,'FLIN9810BRIDL',NULL,'Fluvirin vaccine suspension for injection 0.5ml pre-filled syringes (Novartis Vaccines and Diagnostics Ltd)'),('flu-vaccine',1,'FLNA52410NEMIS',NULL,'Fluenz  Vaccine Nasal Suspension  0.2 ml unit dose'),('flu-vaccine',1,'FLNA52410NEMIS',NULL,'Fluenz vaccine nasal suspension 0.2ml unit dose (AstraZeneca UK Ltd)'),('flu-vaccine',1,'FLVA90951NEMIS',NULL,'Fluenz Tetra vaccine nasal suspension 0.2ml unit dose (AstraZeneca UK Ltd)'),('flu-vaccine',1,'FLVA105396NEMIS',NULL,'FluMist Quadrivalent vaccine nasal suspension 0.2ml unit dose (AstraZeneca UK Ltd)'),('flu-vaccine',1,'FLVA130397NEMIS',NULL,'Flucelvax Tetra vaccine suspension for injection 0.5ml pre-filled syringes (Seqirus Vaccines Ltd)'),('flu-vaccine',1,'FLVA19006EMIS',NULL,'Fluzone Vaccine 0.5 ml'),('flu-vaccine',1,'FLVA24698EMIS',NULL,'Fluarix vaccine suspension for injection 0.5ml pre-filled syringes (GlaxoSmithKline UK Ltd)'),('flu-vaccine',1,'FLVA82448NEMIS',NULL,'Fluarix Tetra vaccine suspension for injection 0.5ml pre-filled syringes (GlaxoSmithKline UK Ltd)'),('flu-vaccine',1,'INSU127173NEMIS',NULL,'Influenza Tetra MYL vaccine suspension for injection 0.5ml pre-filled syringes (Mylan)'),('flu-vaccine',1,'MASU15057NEMIS',NULL,'Mastaflu vaccine suspension for injection 0.5ml pre-filled syringes (Masta Ltd)'),('flu-vaccine',1,'OPSU76843NEMIS',NULL,'Optaflu vaccine suspension for injection 0.5ml pre-filled syringes (Novartis Vaccines and Diagnostics Ltd)'),('flu-vaccine',1,'OPSU76843NEMIS',NULL,'Optaflu vaccine suspension for injection 0.5ml pre-filled syringes (Seqirus Vaccines Ltd)'),('flu-vaccine',1,'PRSU51924NEMIS',NULL,'Preflucel vaccine suspension for injection 0.5ml pre-filled syringes (Baxter Healthcare Ltd)'),('flu-vaccine',1,'VISU23002NEMIS',NULL,'Viroflu vaccine suspension for injection 0.5ml pre-filled syringes (Janssen-Cilag Ltd)'),('flu-vaccine',1,'ENSU20871NEMIS',NULL,'Enzira  Suspension For Injection  0.5 ml pre-filled syringe'),('flu-vaccine',1,'IMSU22976NEMIS',NULL,'Imuvac  Suspension For Injection  0.5 ml pre-filled syringe'),('flu-vaccine',1,'INVA36708NEMIS',NULL,'Intanza  Vaccine  15 microgram strain, 0.1 ml pre-filled syringe'),('flu-vaccine',1,'INVA40484NEMIS',NULL,'Intanza  Vaccine  9 microgram strain, 0.1 ml pre-filled syringe'),('flu-vaccine',1,'AGIN11649NEMIS',NULL,'Agrippal  Injection'),('flu-vaccine',1,'BEVA30364EMIS',NULL,'Begrivac  Vaccine'),('flu-vaccine',1,'AGIN11649NEMIS',NULL,'Agrippal  Injection'),('flu-vaccine',1,'BEVA30364EMIS',NULL,'Begrivac  Vaccine'),('flu-vaccine',1,'CESU38013NEMIS',NULL,'Celvapan (H1N1) Vaccine  Suspension For Injection'),('flu-vaccine',1,'ININ12704NEMIS',NULL,'Inflexal Berna V  Injection  0.5 ml pre-filled syringe'),('flu-vaccine',1,'ININ18889NEMIS',NULL,'Invivac  Injection  0.5 ml pre-filled syringe'),('flu-vaccine',1,'^ESCT1188860',NULL,'Influenza vaccine (split virion, inactivated) suspension for injection 0.5ml pre-filled syringes (Sanofi Pasteur)'),('flu-vaccine',1,'^ESCT1189570',NULL,'Imuvac vaccine suspension for injection 0.5ml pre-filled syringes (Mylan)'),('flu-vaccine',1,'^ESCT1190211',NULL,'Quadrivalent vaccine (split virion, inactivated) suspension for injection 0.5ml pre-filled syringes (Sanofi Pasteur)'),('flu-vaccine',1,'^ESCT1199421',NULL,'Influenza Tetra MYL vaccine suspension for injection 0.5ml pre-filled syringes (Mylan)'),('flu-vaccine',1,'^ESCT1199424',NULL,'Influvac sub-unit Tetra vaccine suspension for injection 0.5ml pre-filled syringes (Mylan)'),('flu-vaccine',1,'^ESCT1254465',NULL,'Flucelvax Tetra vaccine suspension for injection 0.5ml pre-filled syringes (Seqirus Vaccines Ltd)'),('flu-vaccine',1,'^ESCT1257726',NULL,'Trivalent influenza vaccine (split virion, inactivated) High Dose solution for injection 0.5ml pre-filled syringes (Sanofi Pasteur)'),('flu-vaccine',1,'^ESCT1260613',NULL,'Quadrivalent influenza vaccine (split virion, inactivated) suspension for injection 0.5ml pre-filled syringes (Sanofi Pasteur)'),('flu-vaccine',1,'^ESCT1260719',NULL,'Trivalent influenza vaccine (split virion, inactivated) High Dose suspension for injection 0.5ml pre-filled syringes (Sanofi Pasteur)'),('flu-vaccine',1,'^ESCT1267880',NULL,'Fluad vaccine suspension for injection 0.5ml pre-filled syringes (Seqirus Vaccines Ltd)'),('flu-vaccine',1,'^ESCT1270958',NULL,'Adjuvanted trivalent influenza vaccine (surface antigen, inactivated) suspension for injection 0.5ml pre-filled syringes (Seqirus Vaccines Ltd)'),('flu-vaccine',1,'^ESCT1376173',NULL,'Fluad Tetra vaccine suspension for injection 0.5ml pre-filled syringes (Seqirus Vaccines Ltd)'),('flu-vaccine',1,'^ESCT1410117',NULL,'Agrippal vaccine suspension for injection 0.5ml pre-filled syringes (Seqirus UK Ltd)'),('flu-vaccine',1,'^ESCT1410987',NULL,'Optaflu vaccine suspension for injection 0.5ml pre-filled syringes (Seqirus UK Ltd)'),('flu-vaccine',1,'^ESCT1412573',NULL,'Flucelvax Tetra vaccine suspension for injection 0.5ml pre-filled syringes (Seqirus UK Ltd)'),('flu-vaccine',1,'^ESCT1412663',NULL,'Fluad vaccine suspension for injection 0.5ml pre-filled syringes (Seqirus UK Ltd)'),('flu-vaccine',1,'^ESCT1412666',NULL,'Adjuvanted trivalent influenza vaccine (surface antigen, inactivated) suspension for injection 0.5ml pre-filled syringes (Seqirus UK Ltd)'),('flu-vaccine',1,'^ESCT1412729',NULL,'Fluad Tetra vaccine suspension for injection 0.5ml pre-filled syringes (Seqirus UK Ltd)'),('flu-vaccine',1,'^ESCT1425009',NULL,'Influenza vaccine (surface antigen, inactivated) suspension for injection 0.5ml pre-filled syringes'),('flu-vaccine',1,'^ESCT1425011',NULL,'Influenza vaccine (split virion, inactivated) suspension for injection 0.5ml pre-filled syringes'),('flu-vaccine',1,'^ESCT1437567',NULL,'Influvac Sub-unit vaccine suspension for injection 0.5ml pre-filled syringes (Viatris UK Healthcare Ltd)'),('flu-vaccine',1,'^ESCT1438045',NULL,'Imuvac vaccine suspension for injection 0.5ml pre-filled syringes (Viatris UK Healthcare Ltd)'),('flu-vaccine',1,'^ESCT1439014',NULL,'Influenza Tetra MYL vaccine suspension for injection 0.5ml pre-filled syringes (Viatris UK Healthcare Ltd)'),('flu-vaccine',1,'^ESCT1439017',NULL,'Influvac sub-unit Tetra vaccine suspension for injection 0.5ml pre-filled syringes (Viatris UK Healthcare Ltd)'),('flu-vaccine',1,'^ESCT1439018',NULL,'Influvac sub-unit Tetra vaccine suspension for injection 0.5ml pre-filled syringes (Viatris UK Healthcare Ltd) 1 pre-filled disposable injection'),('flu-vaccine',1,'^ESCTAG860467',NULL,'Agrippal vaccine suspension for injection 0.5ml pre-filled syringes (Seqirus Vaccines Ltd)'),
('flu-vaccine',1,'^ESCTBE860405',NULL,'Begrivac vaccine suspension for injection 0.5ml pre-filled syringes (Novartis Vaccines and Diagnostics Ltd)'),('flu-vaccine',1,'^ESCTCE983716',NULL,'Celvapan (H1N1) vaccine (whole virion, Vero cell derived, inactivated) suspension for injection (Baxter Healthcare Ltd)'),('flu-vaccine',1,'^ESCTEN919233',NULL,'Enzira vaccine suspension for injection 0.5ml pre-filled syringes (Pfizer Ltd)'),('flu-vaccine',1,'^ESCTFL1023449',NULL,'Fluenz vaccine nasal suspension 0.2ml unit dose (AstraZeneca UK Ltd)'),('flu-vaccine',1,'^ESCTFL1049909',NULL,'Fluarix Tetra vaccine suspension for injection 0.5ml pre-filled syringes (GlaxoSmithKline UK Ltd)'),('flu-vaccine',1,'^ESCTFL1091900',NULL,'Fluenz Tetra vaccine nasal suspension 0.2ml unit dose (AstraZeneca UK Ltd)'),('flu-vaccine',1,'^ESCTFL1127766',NULL,'FluMist Quadrivalent vaccine nasal suspension 0.2ml unit dose (AstraZeneca UK Ltd)'),('flu-vaccine',1,'^ESCTFL860395',NULL,'Fluarix vaccine suspension for injection 0.5ml pre-filled syringes (GlaxoSmithKline UK Ltd)'),('flu-vaccine',1,'^ESCTFL860422',NULL,'Fluvirin vaccine suspension for injection 0.5ml pre-filled syringes (Novartis Vaccines and Diagnostics Ltd)'),('flu-vaccine',1,'^ESCTIM933665',NULL,'Imuvac vaccine suspension for injection 0.5ml pre-filled syringes (Mylan Ltd)'),('flu-vaccine',1,'^ESCTIN1023457',NULL,'Influenza vaccine (live attenuated) nasal suspension 0.2ml unit dose'),('flu-vaccine',1,'^ESCTIN1049247',NULL,'Influvac Desu vaccine suspension for injection 0.5ml pre-filled syringes (Abbott Healthcare Products Ltd)'),('flu-vaccine',1,'^ESCTIN860383',NULL,'Influenza vaccine (split virion, inactivated) suspension for injection 0.5ml pre-filled syringes (sanofi pasteur MSD Ltd)'),('flu-vaccine',1,'^ESCTIN860464',NULL,'Influvac Sub-unit vaccine suspension for injection 0.5ml pre-filled syringes (Mylan Ltd)'),('flu-vaccine',1,'^ESCTIN927955',NULL,'Invivac vaccine suspension for injection 0.5ml pre-filled syringes (Abbott Healthcare Products Ltd)'),('flu-vaccine',1,'^ESCTIN927986',NULL,'Influenza vaccine (surface antigen, inactivated, virosome) suspension for injection 0.5ml pre-filled syringes'),('flu-vaccine',1,'^ESCTIN938007',NULL,'Influenza vaccine (split virion, inactivated) suspension for injection 0.5ml pre-filled syringes (Pfizer Ltd)'),('flu-vaccine',1,'^ESCTIN981787',NULL,'Intanza 9microgram strain vaccine suspension for injection 0.1ml pre-filled syringes (sanofi pasteur MSD Ltd)'),('flu-vaccine',1,'^ESCTIN982247',NULL,'Intanza 15microgram strain vaccine suspension for injection 0.1ml pre-filled syringes (sanofi pasteur MSD Ltd)'),('flu-vaccine',1,'^ESCTIN982257',NULL,'Influenza vaccine (split virion, inactivated) 15microgram strain suspension for injection 0.1ml pre-filled syringes'),('flu-vaccine',1,'^ESCTMA869372',NULL,'Mastaflu vaccine suspension for injection 0.5ml pre-filled syringes (Masta Ltd)'),('flu-vaccine',1,'^ESCTOP981118',NULL,'Optaflu vaccine suspension for injection 0.5ml pre-filled syringes (Seqirus Vaccines Ltd)'),('flu-vaccine',1,'^ESCTPR1027628',NULL,'Preflucel vaccine suspension for injection 0.5ml pre-filled syringes (Baxter Healthcare Ltd)'),('flu-vaccine',1,'^ESCTQU1162893',NULL,'Quadrivalent vaccine (split virion, inactivated) suspension for injection 0.5ml pre-filled syringes (sanofi pasteur MSD Ltd)'),('flu-vaccine',1,'^ESCTVI929454',NULL,'Viroflu vaccine suspension for injection 0.5ml pre-filled syringes (Janssen-Cilag Ltd)');
INSERT INTO #codesemis
VALUES ('flu-vaccination',1,'^ESCT1300221',NULL,'Seasonal influenza vaccination given in school'),('flu-vaccination',1,'^ESCTFI843902',NULL,'First inactivated seasonal influenza vaccination given by midwife'),('flu-vaccination',1,'^ESCTIN802297',NULL,'Influenza vaccination given'),('flu-vaccination',1,'^ESCTSE843901',NULL,'Seasonal influenza vaccination given by midwife'),('flu-vaccination',1,'EMISNQAD138',NULL,'Administration of first quadrivalent (QIV) inactivated seasonal influenza vaccination'),('flu-vaccination',1,'EMISNQAD139',NULL,'Administration of first non adjuvanted trivalent (TIV) inactivated seasonal influenza vaccination'),('flu-vaccination',1,'EMISNQAD142',NULL,'Administration of adjuvanted trivalent (aTIV) inactivated seasonal influenza vaccination'),('flu-vaccination',1,'EMISNQAD144',NULL,'Administration of first quadrivalent (QIV) inactivated seasonal influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'EMISNQAD145',NULL,'Administration of first non adjuvanted trivalent (TIV) inactivated seasonal influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'EMISNQAD147',NULL,'Administration of adjuvanted trivalent (aTIV) inactivated seasonal influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'EMISNQAD148',NULL,'Administration of second quadrivalent (QIV) inactivated seasonal influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'EMISNQAD149',NULL,'Adjuvanted trivalent (aTIV) inactivated seasonal influenza vaccination given by pharmacist'),('flu-vaccination',1,'EMISNQAD150',NULL,'Administration of second non adjuvanted trivalent (TIV) inactivated seasonal influenza vaccination given by other healthcare provider'),('flu-vaccination',1,'EMISNQAD151',NULL,'Administration of second quadrivalent (QIV) inactivated seasonal influenza vaccination'),('flu-vaccination',1,'EMISNQFI45',NULL,'First quadrivalent (QIV) inactivated seasonal influenza vaccination given by pharmacist'),('flu-vaccination',1,'EMISNQFI46',NULL,'First non adjuvanted trivalent (TIV) inactivated seasonal influenza vaccination given by pharmacist'),('flu-vaccination',1,'EMISNQIN160',NULL,'Intranasal influenza vaccination'),('flu-vaccination',1,'EMISNQSE164',NULL,'Second quadrivalent (QIV) inactivated seasonal influenza vaccination given by pharmacist'),('flu-vaccination',1,'PCSDT18434_779',NULL,'First intranasal seasonal influenza vacc given by pharmacist'),('flu-vaccination',1,'PCSDT18439_1184',NULL,'First intranasal seasonal influenza vacc given by pharmacist'),('flu-vaccination',1,'PCSDT18439_711',NULL,'Second intranasal seasonal influenza vacc givn by pharmacist'),('flu-vaccination',1,'PCSDT28849_483',NULL,'First intranasal seasonal influenza vacc given by pharmacist'),('flu-vaccination',1,'PCSDT7022_652',NULL,'First intranasal seasonal influenza vacc given by pharmacist'),('flu-vaccination',1,'^ESCTSE843903',NULL,'Second inactivated seasonal influenza vaccination given by midwife')

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

-- >>> Following code sets injected: flu-vaccination v1
-- First get all patients from the GP_Events table who have a flu vaccination (procedure) code
IF OBJECT_ID('tempdb..#PatientsWithFluVacConcept1') IS NOT NULL DROP TABLE #PatientsWithFluVacConcept1;
SELECT FK_Patient_Link_ID, CAST(EventDate AS DATE) AS FluVaccineDate
INTO #PatientsWithFluVacConcept1
FROM SharedCare.GP_Events
WHERE (
	FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'flu-vaccination' AND [Version] = 1) OR
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'flu-vaccination' AND [Version] = 1)
)
AND EventDate >= '1900-01-01'
AND EventDate <= '2023-12-31';

-- >>> Following code sets injected: flu-vaccine v1
-- Then get all patients from the GP_Medications table who have a flu vaccine (medication) code
INSERT INTO #PatientsWithFluVacConcept1
SELECT FK_Patient_Link_ID, CAST(MedicationDate AS DATE) FROM SharedCare.GP_Medications
WHERE (
	FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'flu-vaccine' AND [Version] = 1) OR
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'flu-vaccine' AND [Version] = 1)
)
and MedicationDate >= '1900-01-01'
and MedicationDate <= '2023-12-31';

-- Bring all together in final table
IF OBJECT_ID('tempdb..#PatientHadFluVaccine1') IS NOT NULL DROP TABLE #PatientHadFluVaccine1;
SELECT 
	FK_Patient_Link_ID,
	MIN(FluVaccineDate) AS FluVaccineDate
INTO #PatientHadFluVaccine1 FROM #PatientsWithFluVacConcept1
GROUP BY FK_Patient_Link_ID;


-- final table of flu vaccinations

SELECT 
	PatientId = FK_Patient_Link_ID, 
	FluVaccineYearAndMonth = FORMAT(FluVaccineDate, 'MM-yyyy')
FROM #PatientsWithFluVacConcept1
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
