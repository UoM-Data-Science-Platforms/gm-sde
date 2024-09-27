USE SCHEMA SDE_REPOSITORY.SHARED_UTILITIES;

--┌──────────────────────────────┐
--│ Medications for LH006 cohort │
--└──────────────────────────────┘

-- meds: benzodiazepines, gabapentinoids, nsaids, opioids, antidepressants

-------- RESEARCH DATA ENGINEER CHECK ------------
-- Richard Williams	2024-08-30	Review complete --
--------------------------------------------------

set(StudyStartDate) = to_date('2017-01-01');
set(StudyEndDate)   = to_date('2023-12-31');

DROP TABLE IF EXISTS prescriptions;
CREATE TEMPORARY TABLE prescriptions AS
SELECT 
    co."GmPseudo"
    , TO_DATE(ec."MedicationDate") AS "MedicationDate"
    , ec."SCTID" AS "SnomedCode"
	, ec."Quantity"
    , ec."Dosage_GP_Medications" AS "Dosage"
    , CASE WHEN ec."Cluster_ID" = 'BENZODRUG_COD' THEN 'benzodiazepine' -- benzodiazepines
           WHEN ec."Cluster_ID" = 'GABADRUG_COD' THEN 'gabapentinoid' -- gabapentinoids
           WHEN ec."Cluster_ID" = 'ORALNSAIDDRUG_COD' THEN 'nsaid' -- oral nsaids
		   WHEN ec."Cluster_ID" = 'OPIOIDDRUG_COD' THEN 'opioid' -- opioids except heroin addiction substitutes
	       WHEN ec."Cluster_ID" = 'ANTIDEPDRUG_COD' THEN 'antidepressant' -- antidepressants
           ELSE 'other' END AS "CodeSet"
    , ec."MedicationDescription" AS "Description"
FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_06_Chen" co
LEFT JOIN INTERMEDIATE.GP_RECORD."MedicationsClusters" ec ON co."FK_Patient_ID" = ec."FK_Patient_ID"
WHERE "Cluster_ID" in ('BENZODRUG_COD', 'GABADRUG_COD', 'ORALNSAIDDRUG_COD', 'OPIOIDDRUG_COD', 'ANTIDEPDRUG_COD')
    AND TO_DATE(ec."MedicationDate") BETWEEN $StudyStartDate and $StudyEndDate;

-- ONLY KEEP DOSAGE INFO IF IT HAS APPEARED > 50 TIMES

DROP TABLE IF EXISTS SafeDosages;
CREATE TEMPORARY TABLE SafeDosages AS
SELECT "Dosage" 
FROM prescriptions
GROUP BY "Dosage"
HAVING count(*) >= 50;

-- table with redacted dosage info

DROP TABLE IF EXISTS prescriptions1;
CREATE TEMPORARY TABLE prescriptions1 AS
SELECT 
    p."GmPseudo",
    p."MedicationDate",
    p."SnomedCode",
    p."Quantity",
    p."CodeSet",
    p."Description",
	CASE WHEN "CodeSet" = 'benzodiazepine' THEN 1 ELSE 0 END AS "Benzodiazepine",
	CASE WHEN "CodeSet" = 'gabapentinoid' THEN 1 ELSE 0 END AS "Gabapentinoid",
	CASE WHEN "CodeSet" = 'nsaid' THEN 1 ELSE 0 END AS "Nsaid",
	CASE WHEN "CodeSet" = 'opioid' THEN 1 ELSE 0 END AS "Opioid",
	CASE WHEN "CodeSet" = 'antidepressant' THEN 1 ELSE 0 END AS "Antidepressant",
    IFNULL(sd."Dosage", 'REDACTED') as "Dosage"
FROM prescriptions p
LEFT JOIN SafeDosages sd ON sd."Dosage" = p."Dosage";

-- transform into wide format to reduce the number of rows in final table


-- ... processing [[create-output-table::"2_Medications"]] ... 
-- ... Need to create an output table called "2_Medications" and replace 
-- ... the GmPseudo column with a study-specific random patient id.

-- First we create a table in an area only visible to the RDEs which contains
-- the GmPseudos. THESE CANNOT BE RELEASED TO END USERS.
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."2_Medications_WITH_PSEUDO_IDS";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."2_Medications_WITH_PSEUDO_IDS" AS
SELECT "GmPseudo",
	YEAR("MedicationDate") AS "Year",
    MONTH("MedicationDate") AS "Month",
	SUM("Benzodiazepine") AS "Benzodiazepines",
	SUM("Gabapentinoid") AS "Gabapentinoids",
	SUM("Nsaid") AS "Nsaids",
	SUM("Opioid") AS "Opioids",
	SUM("Antidepressant") AS "Antidepressants"
FROM prescriptions1
GROUP BY "GmPseudo",
	YEAR("MedicationDate"),
    MONTH("MedicationDate")
ORDER BY 
	YEAR("MedicationDate"),
    MONTH("MedicationDate");

-- Then we check to see if there are any new GmPseudo ids. We do this by making a temp table 
-- of all "new" GmPseudo ids. I.e. any GmPseudo ids that we've already got a unique id for
-- for this study are excluded
DROP TABLE IF EXISTS "AllPseudos_SDE_Lighthouse_06_Chen";
CREATE TEMPORARY TABLE "AllPseudos_SDE_Lighthouse_06_Chen" AS
SELECT DISTINCT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."2_Medications_WITH_PSEUDO_IDS"
EXCEPT
SELECT "GmPseudo" FROM "Patient_ID_Mapping_SDE_Lighthouse_06_Chen";

-- Find the highest currently assigned id. Ids are given incrementally, so now ones
-- need to start at +1 of the current highest
SET highestPatientId = (
    SELECT IFNULL(MAX("StudyPatientPseudoId"),0) FROM "Patient_ID_Mapping_SDE_Lighthouse_06_Chen"
);

-- Make a study specific hash for each new GmPseudo and insert it
-- into the patient lookup table
INSERT INTO "Patient_ID_Mapping_SDE_Lighthouse_06_Chen"
SELECT
    "GmPseudo", -- the GM SDE patient ids for patients in this cohort
    SHA2(CONCAT('SDE_Lighthouse_06_Chen', "GmPseudo")) AS "Hash", -- used to provide a random (study-specific) ordering for the patient ids we provide
    $highestPatientId + ROW_NUMBER() OVER (ORDER BY "Hash") -- the patient id that we provide to the analysts
FROM "AllPseudos_SDE_Lighthouse_06_Chen";

-- Finally, we select from the output table which includes the GmPseudos, in order
-- to populate the table for the end users where the GmPseudo fields are redacted via a function
-- created in the 0.code-sets.sql file
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."2_Medications";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."2_Medications" AS
SELECT SDE_REPOSITORY.SHARED_UTILITIES.gm_pseudo_hash_SDE_Lighthouse_06_Chen("GmPseudo") AS "PatientID",
	* EXCLUDE "GmPseudo"
FROM SDE_REPOSITORY.SHARED_UTILITIES."2_Medications_WITH_PSEUDO_IDS";