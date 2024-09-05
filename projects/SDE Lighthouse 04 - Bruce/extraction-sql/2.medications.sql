USE SCHEMA SDE_REPOSITORY.SHARED_UTILITIES;

--┌─────────────┐
--│ Medications │
--└─────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------
-- 
------------------------------------------------------

-- In the request this is in 3 files, but the PI has confirmed that a single long file
-- with columns PatientID, Date, MedicationCategory, Medication, Dose, Units is fine.
-- Medications to includes are : Prednisolone, MycophenolateMofetil, Azathioprine, 
-- Tacrolimus, Methotrexate, Ciclosporin, HydroxychloroquineOrChloroquine, Belimumab, 
-- ACEInhibitorOrARB*, SGLT2Inhibitor*, AntiplateletDrug*, Statin*, Anticoagulant*,
-- Cyclophosphamide and Rituximab

-- Medication categories such as "antiplatelet" should give the actual drug within that
-- category

-- >>> Codesets required... Inserting the code set code
-- >>> Codesets extracted into 0.code-sets.sql
-- >>> Following code sets injected: belimumab v1/hydroxychloroquine v1/chloroquine v1
DROP TABLE IF EXISTS LH004_med_codes;
CREATE TEMPORARY TABLE LH004_med_codes AS
SELECT
    "GmPseudo",
    CAST("MedicationDate" AS DATE) AS "MedicationDate",
    "SuppliedCode",
    "Dosage",
    "Quantity",
    "Units"
FROM INTERMEDIATE.GP_RECORD."GP_Medications_SecondaryUses" gp
INNER JOIN SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_04_Bruce" c ON gp."FK_Patient_ID" = c."FK_Patient_ID"
WHERE "SuppliedCode" IN (SELECT code FROM SDE_REPOSITORY.SHARED_UTILITIES."Code_Sets_SDE_Lighthouse_04_Bruce" WHERE concept in ('belimumab','hydroxychloroquine','chloroquine'));


-- First we create a table in an area only visible to the RDEs which contains
-- the GmPseudos. These cannot be released to end users.
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH004-2_medications_WITH_PSEUDO_IDS";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH004-2_medications_WITH_PSEUDO_IDS" AS
SELECT "GmPseudo", "MedicationDate",
    CASE 
        WHEN "Field_ID" IN ('SAL_COD','NONASPANTIPLTDRUG_COD') THEN 'Antiplatelet'
        WHEN "Field_ID" IN ('Immunosuppression_Drugs') THEN 'Immunosuppression'
        WHEN "Field_ID" IN ('ACEInhibitor','ARB') THEN 'ACEInhibitorOrARB'
        WHEN "Field_ID" IN ('SGLT2') THEN 'SGLT2Inhibitor'
        WHEN "Field_ID" IN ('DOAC','Warfarin','ORANTICOAGDRUG_COD') THEN 'Anticoagulant'
        ELSE "Field_ID"
    END AS MedicationCategory, 
    SPLIT_PART(LOWER("MedicationDescription"), ' ',0) AS Medication, "Dosage_GP_Medications", "Quantity", "Units"
FROM INTERMEDIATE.GP_RECORD."MedicationsClusters" mc
INNER JOIN SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_04_Bruce" c ON mc."FK_Patient_ID" = c."FK_Patient_ID"
WHERE "Field_ID" IN ('Immunosuppression_Drugs', 'Prednisolone', 'ACEInhibitor','SGLT2','SAL_COD','NONASPANTIPLTDRUG_COD','Statin','DOAC','Warfarin','ORANTICOAGDRUG_COD','ARB')
UNION
SELECT 
    "GmPseudo", 
    "MedicationDate",
    CASE
        WHEN "SuppliedCode" IN (SELECT code FROM SDE_REPOSITORY.SHARED_UTILITIES."Code_Sets_SDE_Lighthouse_04_Bruce" WHERE concept = 'chloroquine') THEN     'HydroxychloroquineOrChloroquine'
        WHEN "SuppliedCode" IN (SELECT code FROM SDE_REPOSITORY.SHARED_UTILITIES."Code_Sets_SDE_Lighthouse_04_Bruce" WHERE concept = 'hydroxychloroquine') THEN     'HydroxychloroquineOrChloroquine'
        WHEN "SuppliedCode" IN (SELECT code FROM SDE_REPOSITORY.SHARED_UTILITIES."Code_Sets_SDE_Lighthouse_04_Bruce" WHERE concept = 'belimumab') THEN     'Belimumab'
    END AS MedicationCategory, 
    CASE
        WHEN "SuppliedCode" IN (SELECT code FROM SDE_REPOSITORY.SHARED_UTILITIES."Code_Sets_SDE_Lighthouse_04_Bruce" WHERE concept = 'chloroquine') THEN     'chloroquine'
        WHEN "SuppliedCode" IN (SELECT code FROM SDE_REPOSITORY.SHARED_UTILITIES."Code_Sets_SDE_Lighthouse_04_Bruce" WHERE concept = 'hydroxychloroquine') THEN     'hydroxychloroquine'
        WHEN "SuppliedCode" IN (SELECT code FROM SDE_REPOSITORY.SHARED_UTILITIES."Code_Sets_SDE_Lighthouse_04_Bruce" WHERE concept = 'belimumab') THEN     'belimumab'
    END AS Medication,
    "Dosage",
    "Quantity",
    "Units"
FROM LH004_med_codes;

-- Then we check to see if there are any new GmPseudo ids. We do this by making a temp table 
-- of all "new" GmPseudo ids. I.e. any GmPseudo ids that we've already got a unique id for
-- for this study are excluded
DROP TABLE IF EXISTS "AllPseudos_SDE_Lighthouse_04_Bruce";
CREATE TEMPORARY TABLE "AllPseudos_SDE_Lighthouse_04_Bruce" AS
SELECT DISTINCT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."LH004-2_medications_WITH_PSEUDO_IDS"
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
    "GmPseudo",
    SHA2(CONCAT('SDE_Lighthouse_04_Bruce', "GmPseudo")) AS "Hash",
    $highestPatientId + ROW_NUMBER() OVER (ORDER BY "Hash")
FROM "AllPseudos_SDE_Lighthouse_04_Bruce";

-- Finally, we select from the output table which includes the GmPseudos, in order
-- to populate the table for the end users where the GmPseudo fields are redacted via a function
-- created in the 0.code-sets.sql file
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH004-2_medications";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH004-2_medications" AS
SELECT SDE_REPOSITORY.SHARED_UTILITIES.gm_pseudo_hash_SDE_Lighthouse_04_Bruce("GmPseudo") AS "PatientID", * EXCLUDE "GmPseudo"
FROM SDE_REPOSITORY.SHARED_UTILITIES."LH004-2_medications_WITH_PSEUDO_IDS";