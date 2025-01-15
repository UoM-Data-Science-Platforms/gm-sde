USE SCHEMA SDE_REPOSITORY.SHARED_UTILITIES;

--┌──────────────────────────────────────────────┐
--│ Medications and treatments for LH009 cohort  │
--└──────────────────────────────────────────────┘

-- meds: HRT, birth control, steroids, NSAIDS, DMARDS, biologics, coil fittings 

-------- RESEARCH DATA ENGINEER CHECK ------------

--------------------------------------------------

set(StudyStartDate) = to_date('2020-01-01');
set(StudyEndDate)   = to_date('2024-10-31');

-- >>> Codesets required... Inserting the code set code
-- >>> Codesets extracted into 0.code-sets.sql
-- >>> Following code sets injected: corticosteroid v1/anabolic-steroids v1/biologic-immune-modulators v1/disease-modifying-med v1
-- >>> Following code sets injected: male-sex-hormones v1/female-sex-hormones v1
-- >>> Following code sets injected: contraceptives-emergency-pills v1/contraceptives-tablet v1/contraceptives-iud v1/contraceptives-injection v1/contraceptives-implant v1

DROP TABLE IF EXISTS LH009_med_codes;
CREATE TEMPORARY TABLE LH009_med_codes AS
SELECT DISTINCT
    c. "GmPseudo",
    CAST("MedicationDate" AS DATE) AS "Date",
    "SuppliedCode",
	SCTID AS "SnomedCode",
	co.concept as "CodeSet",
	"MedicationDescription" AS "Description"
FROM INTERMEDIATE.GP_RECORD."GP_Medications_SecondaryUses" gp
INNER JOIN SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_09_Thompson" c ON gp."FK_Patient_ID" = c."FK_Patient_ID"
INNER JOIN SDE_REPOSITORY.SHARED_UTILITIES."Code_Sets_SDE_Lighthouse_09_Thompson" co ON co.code = gp."SuppliedCode"
WHERE co.concept in ('corticosteroid', 'anabolic-steroids', 'biologic-immune-modulators','disease-modifying-med',
				'male-sex-hormones', 'female-sex-hormones', 
				'contraceptives-emergency-pill',
				'contraceptives-tablet', 'contraceptives-iud', 'contraceptives-injection', 'contraceptives-implant');


-- meds from cluster tables: nsaids,

DROP TABLE IF EXISTS prescriptions;
CREATE TEMPORARY TABLE prescriptions AS
SELECT 
    co."GmPseudo",
    TO_DATE(ec."Date") AS "Date",
    ec."SCTID" AS "SnomedCode",
	ec."SuppliedCode",
    CASE WHEN ec."Cluster_ID" = 'ORALNSAIDDRUG_COD' THEN 'nsaid' -- oral nsaids
			ELSE 'other' END AS "CodeSet",
    ec."Term" AS "Description",
FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_09_Thompson" co
LEFT JOIN INTERMEDIATE.GP_RECORD."Combined_EventsMedications_Clusters_SecondaryUses" ec ON co."FK_Patient_ID" = ec."FK_Patient_ID"
WHERE "Cluster_ID" in ('ORALNSAIDDRUG_COD')
    AND TO_DATE(ec."Date") BETWEEN $StudyStartDate and $StudyEndDate;


-- join cluster and gmcr code set tables


-- ... processing [[create-output-table::"LH009-4_Medications"]] ... 
-- ... Need to create an output table called "LH009-4_Medications" and replace 
-- ... the GmPseudo column with a study-specific random patient id.

-- First we create a table in an area only visible to the RDEs which contains
-- the GmPseudos. THESE CANNOT BE RELEASED TO END USERS.
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH009-4_Medications_WITH_IDENTIFIER";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH009-4_Medications_WITH_IDENTIFIER" AS
SELECT 
	"GmPseudo"
	, "Date"
	, "SnomedCode"
	--, "SuppliedCode"
	, "CodeSet"
	, "Description"
FROM LH009_med_codes
UNION
SELECT 
	"GmPseudo"
	, "Date"
	, "SnomedCode"
	--, "SuppliedCode"
	, "CodeSet"
	, "Description"
FROM prescriptions;

-- Then we check to see if there are any new GmPseudo ids. We do this by making a temp table 
-- of all "new" GmPseudo ids. I.e. any GmPseudo ids that we've already got a unique id for
-- for this study are excluded
DROP TABLE IF EXISTS "AllPseudos_SDE_Lighthouse_09_Thompson";
CREATE TEMPORARY TABLE "AllPseudos_SDE_Lighthouse_09_Thompson" AS
SELECT DISTINCT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."LH009-4_Medications_WITH_IDENTIFIER"
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
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH009-4_Medications";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH009-4_Medications" AS
SELECT SDE_REPOSITORY.SHARED_UTILITIES.gm_pseudo_hash_SDE_Lighthouse_09_Thompson("GmPseudo") AS "PatientID",
	* EXCLUDE "GmPseudo"
FROM SDE_REPOSITORY.SHARED_UTILITIES."LH009-4_Medications_WITH_IDENTIFIER";