USE SCHEMA SDE_REPOSITORY.SHARED_UTILITIES;

--┌─────────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 09 - Thompson - referrals          │
--└─────────────────────────────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK ------------
--------------------------------------------------

set(StudyStartDate) = to_date('2020-01-01');
set(StudyEndDate)   = to_date('2024-10-31');


-- ... processing [[create-output-table::"LH009-8_Referrals"]] ... 
-- ... Need to create an output table called "LH009-8_Referrals" and replace 
-- ... the GmPseudo column with a study-specific random patient id.

-- First we create a table in an area only visible to the RDEs which contains
-- the GmPseudos. THESE CANNOT BE RELEASED TO END USERS.
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH009-8_Referrals_WITH_PSEUDO_IDS";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH009-8_Referrals_WITH_PSEUDO_IDS" AS
SELECT 
    co."GmPseudo"
    , TO_DATE(ec."Date") AS "Date"
    , ec."SCTID" AS "SnomedCode"
    , ec."Term" AS "Description"
FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_09_Thompson" co
LEFT JOIN INTERMEDIATE.GP_RECORD."Combined_EventsMedications_Clusters_SecondaryUses" ec ON co."FK_Patient_ID" = ec."FK_Patient_ID"
WHERE "Cluster_ID" = 'REFERRAL_COD'
	AND (SCTID IN 
		-- gynaecology referral
		('183549000', '183886008', '249011000000106', '306133003',
		'905011000006110', '718550001', '900941000000107', 
		'904991000006117', '785781000000101', '700125004',
		-- sexual healh and contraception service referral
		'892041000000100')
		-- cancer referrals
		OR UPPER(ec."Term") like '%CANCER%'
		)
    AND TO_DATE(ec."Date") BETWEEN $StudyStartDate and $StudyEndDate;

-- Then we check to see if there are any new GmPseudo ids. We do this by making a temp table 
-- of all "new" GmPseudo ids. I.e. any GmPseudo ids that we've already got a unique id for
-- for this study are excluded
DROP TABLE IF EXISTS "AllPseudos_SDE_Lighthouse_09_Thompson";
CREATE TEMPORARY TABLE "AllPseudos_SDE_Lighthouse_09_Thompson" AS
SELECT DISTINCT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."LH009-8_Referrals_WITH_PSEUDO_IDS"
EXCEPT
SELECT "GmPseudo" FROM "Patient_ID_Mapping_SDE_Lighthouse_09_Thompson";

-- Find the highest currently assigned id. Ids are given incrementally, so now ones
-- need to start at +1 of the current highest
SET highestPatientId = (
    SELECT IFNULL(MAX("StudyPatientPseudoId"),0) FROM "Patient_ID_Mapping_SDE_Lighthouse_09_Thompson"
);

-- Make a study specific hash for each new GmPseudo and insert it
-- into the patient lookup table
INSERT INTO "Patient_ID_Mapping_SDE_Lighthouse_09_Thompson"
SELECT
    "GmPseudo", -- the GM SDE patient ids for patients in this cohort
    SHA2(CONCAT('SDE_Lighthouse_09_Thompson', "GmPseudo")) AS "Hash", -- used to provide a random (study-specific) ordering for the patient ids we provide
    $highestPatientId + ROW_NUMBER() OVER (ORDER BY "Hash") -- the patient id that we provide to the analysts
FROM "AllPseudos_SDE_Lighthouse_09_Thompson";

-- Finally, we select from the output table which includes the GmPseudos, in order
-- to populate the table for the end users where the GmPseudo fields are redacted via a function
-- created in the 0.code-sets.sql file
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH009-8_Referrals";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH009-8_Referrals" AS
SELECT SDE_REPOSITORY.SHARED_UTILITIES.gm_pseudo_hash_SDE_Lighthouse_09_Thompson("GmPseudo") AS "PatientID",
	* EXCLUDE "GmPseudo"
FROM SDE_REPOSITORY.SHARED_UTILITIES."LH009-8_Referrals_WITH_PSEUDO_IDS";
