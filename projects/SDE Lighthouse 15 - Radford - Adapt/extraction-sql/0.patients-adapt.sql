USE SCHEMA SDE_REPOSITORY.SHARED_UTILITIES;


--┌───────────────────────────────────────────────────────────────────────────┐
--│ LH015: provide IDs of all ADAPT patients (even those without a GP record) │
--└───────────────────────────────────────────────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK ------------

--------------------------------------------------

-- table of ADAPT patients

-- ... processing [[create-output-table::"LH015-0_AdaptPatients"]] ... 
-- ... Need to create an output table called "LH015-0_AdaptPatients" and replace 
-- ... the GmPseudo column with a study-specific random patient id.

-- First we create a table in an area only visible to the RDEs which contains
-- the GmPseudos. THESE CANNOT BE RELEASED TO END USERS.
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH015-0_AdaptPatients_WITH_IDENTIFIER";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH015-0_AdaptPatients_WITH_IDENTIFIER" AS
SELECT DISTINCT "GmPseudo", "AdaptDate"
FROM INTERMEDIATE.LOCAL_FLOWS_GM_ADAPT."Adapt";

-- Then we check to see if there are any new GmPseudo ids. We do this by making a temp table 
-- of all "new" GmPseudo ids. I.e. any GmPseudo ids that we've already got a unique id for
-- for this study are excluded
DROP TABLE IF EXISTS "AllPseudos_SDE_Lighthouse_15_Radford_Adapt";
CREATE TEMPORARY TABLE "AllPseudos_SDE_Lighthouse_15_Radford_Adapt" AS
SELECT DISTINCT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."LH015-0_AdaptPatients_WITH_IDENTIFIER"
EXCEPT
SELECT "GmPseudo" FROM "Patient_ID_Mapping_SDE_Lighthouse_15_Radford_Adapt";

-- Find the highest currently assigned id. Ids are given incrementally, so now ones
-- need to start at +1 of the current highest
SET highestPatientId = (
    SELECT IFNULL(MAX("StudyPatientPseudoId"),0) FROM "Patient_ID_Mapping_SDE_Lighthouse_15_Radford_Adapt"
);

-- Make a study specific hash for each new GmPseudo and insert it
-- into the patient lookup table
INSERT INTO "Patient_ID_Mapping_SDE_Lighthouse_15_Radford_Adapt"
SELECT
    "GmPseudo", -- the GM SDE patient ids for patients in this cohort
    SHA2(CONCAT('SDE_Lighthouse_15_Radford_Adapt', "GmPseudo")) AS "Hash", -- used to provide a random (study-specific) ordering for the patient ids we provide
    $highestPatientId + ROW_NUMBER() OVER (ORDER BY "Hash") -- the patient id that we provide to the analysts
FROM "AllPseudos_SDE_Lighthouse_15_Radford_Adapt";

-- Finally, we select from the output table which includes the GmPseudos, in order
-- to populate the table for the end users where the GmPseudo fields are redacted via a function
-- created in the 0.code-sets.sql file
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH015-0_AdaptPatients";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH015-0_AdaptPatients" AS
SELECT SDE_REPOSITORY.SHARED_UTILITIES.gm_pseudo_hash_SDE_Lighthouse_15_Radford_Adapt("GmPseudo") AS "PatientID",
	* EXCLUDE "GmPseudo"
FROM SDE_REPOSITORY.SHARED_UTILITIES."LH015-0_AdaptPatients_WITH_IDENTIFIER";
--
