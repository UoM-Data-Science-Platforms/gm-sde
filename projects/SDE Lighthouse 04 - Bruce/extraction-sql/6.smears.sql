USE SCHEMA SDE_REPOSITORY.SHARED_UTILITIES;

--┌────────────────────────────────────┐
--│ LH004 Infections file              │
--└────────────────────────────────────┘

-- From application:
--	PneumococcalVaccination (ever recorded y/n) [5.vaccinations]
--	PneumoVacDate [5.vaccinations]
--	InfluenzaVaccination (in past 12 months y/n) [5.vaccinations]
--	FluVacDate [5.vaccinations]
--	COVIDVaccination (in past 12 months y/n) [5.vaccinations]
--	COVIDVacDate [5.vaccinations]
--	ShinglesVaccination [5.vaccinations]
--	ShinglesVacDate [5.vaccinations]
--	BCGVaccination [5.vaccinations]
--	BCGVacDate [5.vaccinations]
--	HPVVaccination [5.vaccinations]
--	HPVVacDate [5.vaccinations]
--	Infection (from list below) [4.infections-gp] [4.infections-hospital]
--	InfectionDate (for each recorded infection) [4.infections-gp]
--	HospitalAdmissionForInfection (if available) [4.infections-hospital]
--	HospitalAdmissionDate [4.infections-hospital]
--	PreviousSmear (ever y/n) [6.smears]
--	SmearDates [6.smears]
--	SmearResults (for each smear documented) [6.smears]
-- Infections from : 
-- https://data.bris.ac.uk/datasets/2954m5h0ync672u8yzx16xxj7l/infection_master_published.txt

-- PI agreed to separate files for infections, vaccinations and smear tests

-- Create temp tables of all the vaccine codes for speeding up future queries
DROP TABLE IF EXISTS TEMP_LH004_SMEAR_RECORDS;
CREATE TEMPORARY TABLE TEMP_LH004_SMEAR_RECORDS AS
SELECT "FK_Patient_ID", CAST("EventDate" AS DATE) AS "EventDate", SCTID, "SNOMED_code_description" 
FROM INTERMEDIATE.gp_record."GP_Events_SecondaryUses" gp
LEFT OUTER JOIN intermediate.gp_record.national_clusters_formatted ncf ON ncf."SNOMED_code" = gp.sctid
WHERE "Field_ID" = 'SMEAR_COD'
AND "FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_04_Bruce");


-- ... processing [[create-output-table::"LH004-6_smears"]] ... 
-- ... Need to create an output table called "LH004-6_smears" and replace 
-- ... the GmPseudo column with a study-specific random patient id.

-- First we create a table in an area only visible to the RDEs which contains
-- the GmPseudos. THESE CANNOT BE RELEASED TO END USERS.
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH004-6_smears_WITH_PSEUDO_IDS";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH004-6_smears_WITH_PSEUDO_IDS" AS
SELECT DISTINCT "GmPseudo", "EventDate","SNOMED_code_description" AS "SmearDescription"
FROM TEMP_LH004_SMEAR_RECORDS smear
INNER JOIN SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_04_Bruce" c ON c."FK_Patient_ID" = smear."FK_Patient_ID"
ORDER BY "GmPseudo", "EventDate";

-- Then we check to see if there are any new GmPseudo ids. We do this by making a temp table 
-- of all "new" GmPseudo ids. I.e. any GmPseudo ids that we've already got a unique id for
-- for this study are excluded
DROP TABLE IF EXISTS "AllPseudos_SDE_Lighthouse_04_Bruce";
CREATE TEMPORARY TABLE "AllPseudos_SDE_Lighthouse_04_Bruce" AS
SELECT DISTINCT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."LH004-6_smears_WITH_PSEUDO_IDS"
EXCEPT
SELECT "GmPseudo" FROM "Patient_ID_Mapping_SDE_Lighthouse_04_Bruce";

-- Find the highest currently assigned id. Ids are given incrementally, so now ones
-- need to start at +1 of the current highest
SET highestPatientId = (
    SELECT IFNULL(MAX("StudyPatientPseudoId"),0) FROM "Patient_ID_Mapping_SDE_Lighthouse_04_Bruce"
);

-- Make a study specific hash for each new GmPseudo and insert it
-- into the patient lookup table
INSERT INTO "Patient_ID_Mapping_SDE_Lighthouse_04_Bruce"
SELECT
    "GmPseudo", -- the GM SDE patient ids for patients in this cohort
    SHA2(CONCAT('SDE_Lighthouse_04_Bruce', "GmPseudo")) AS "Hash", -- used to provide a random (study-specific) ordering for the patient ids we provide
    $highestPatientId + ROW_NUMBER() OVER (ORDER BY "Hash") -- the patient id that we provide to the analysts
FROM "AllPseudos_SDE_Lighthouse_04_Bruce";

-- Finally, we select from the output table which includes the GmPseudos, in order
-- to populate the table for the end users where the GmPseudo fields are redacted via a function
-- created in the 0.code-sets.sql file
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH004-6_smears";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH004-6_smears" AS
SELECT SDE_REPOSITORY.SHARED_UTILITIES.gm_pseudo_hash_SDE_Lighthouse_04_Bruce("GmPseudo") AS "PatientID", * EXCLUDE "GmPseudo"
FROM SDE_REPOSITORY.SHARED_UTILITIES."LH004-6_smears_WITH_PSEUDO_IDS";