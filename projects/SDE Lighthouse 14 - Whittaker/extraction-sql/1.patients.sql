USE SCHEMA SDE_REPOSITORY.SHARED_UTILITIES;

--┌────────────────────────────────────┐
--│ LH014 Patient file                 │
--└────────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK ---------
-- Richard Williams	2024-08-09	Review complete

-- around 2.5k patients don't have a record in the demographics table, and therefore aren't included in the data provided, because we don't know their opt-out status.
-- potential reasons for patients not appearing in the demographics table:

-- 1. opted out of sharing GP record info
-- 2. Their GP practice has not signed up to sharing info
-- 3. Discrepancies between snapshot dates in the VW dataset and the GP data when patients move practices


 -- need to load a codeset for the pipeline to work so loading an example one

-- CODESET allergy-ace:1      


set(StudyStartDate) = to_date('2018-01-01');
set(StudyEndDate)   = to_date('2024-10-31');

---- find the latest snapshot for each spell, to get all virtual ward patients

DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_14_Whittaker";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_14_Whittaker" AS
SELECT  
	DISTINCT SUBSTRING(vw."Pseudo NHS Number", 2)::INT AS "GmPseudo"
FROM PRESENTATION.LOCAL_FLOWS_VIRTUAL_WARDS.VIRTUAL_WARD_OCCUPANCY vw
WHERE SUBSTRING(vw."Pseudo NHS Number", 2)::INT IN (SELECT "GmPseudo" FROM  PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses") -- limit to GM GP registered patients (which applies opt out)
AND TO_DATE(vw."Admission Date") BETWEEN $StudyStartDate AND $StudyEndDate;


-- deaths table

DROP TABLE IF EXISTS Death;
CREATE TEMPORARY TABLE Death AS
SELECT 
    DEATH."GmPseudo",
    TO_DATE(DEATH."RegisteredDateOfDeath") AS DeathDate,
    OM."DiagnosisOriginalMentionCode",
    OM."DiagnosisOriginalMentionDesc",
    OM."DiagnosisOriginalMentionChapterCode",
    OM."DiagnosisOriginalMentionChapterDesc",
    OM."DiagnosisOriginalMentionCategory1Code",
    OM."DiagnosisOriginalMentionCategory1Desc"
FROM PRESENTATION.NATIONAL_FLOWS_PCMD."DS1804_Pcmd" DEATH
LEFT JOIN PRESENTATION.NATIONAL_FLOWS_PCMD."DS1804_PcmdDiagnosisOriginalMentions" OM 
        ON OM."XSeqNo" = DEATH."XSeqNo" AND OM."DiagnosisOriginalMentionNumber" = 1
WHERE "GmPseudo" IN (SELECT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_14_Whittaker");
--2,195

-- patient demographics table


-- ... processing [[create-output-table::"LH014-1_Patients"]] ... 
-- ... Need to create an output table called "LH014-1_Patients" and replace 
-- ... the GmPseudo column with a study-specific random patient id.

-- First we create a table in an area only visible to the RDEs which contains
-- the GmPseudos. THESE CANNOT BE RELEASED TO END USERS.
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH014-1_Patients_WITH_IDENTIFIER";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH014-1_Patients_WITH_IDENTIFIER" AS
SELECT *
FROM (
SELECT 
	"Snapshot", 
	D."GmPseudo", 
	"YearAndMonthOfBirth",
	DATE_TRUNC(month, dth.DeathDate) AS "YearAndMonthOfDeath",
	"DiagnosisOriginalMentionCode" AS "CauseOfDeathCode",
	"DiagnosisOriginalMentionDesc" AS "CauseOfDeathDesc",
	"DiagnosisOriginalMentionChapterCode" AS "CauseOfDeathChapterCode",
    "DiagnosisOriginalMentionChapterDesc" AS "CauseOfDeathChapterDesc",
    "DiagnosisOriginalMentionCategory1Code" AS "CauseOfDeathCategoryCode",
    "DiagnosisOriginalMentionCategory1Desc" AS "CauseOfDeathCategoryDesc",
	LSOA11, 
	"IMD_Decile", 
	"Age", 
	"Sex", 
	"EthnicityLatest_Category", 
	"MarriageCivilPartership"
FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_14_Whittaker" co
LEFT JOIN PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" D ON co."GmPseudo" = D."GmPseudo"
LEFT JOIN Death dth ON dth."GmPseudo" = D."GmPseudo"
QUALIFY row_number() OVER (PARTITION BY D."GmPseudo" ORDER BY "Snapshot" DESC) = 1 -- this brings back the values from the most recent snapshot
);

-- Then we check to see if there are any new GmPseudo ids. We do this by making a temp table 
-- of all "new" GmPseudo ids. I.e. any GmPseudo ids that we've already got a unique id for
-- for this study are excluded
DROP TABLE IF EXISTS "AllPseudos_SDE_Lighthouse_14_Whittaker";
CREATE TEMPORARY TABLE "AllPseudos_SDE_Lighthouse_14_Whittaker" AS
SELECT DISTINCT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."LH014-1_Patients_WITH_IDENTIFIER"
EXCEPT
SELECT "GmPseudo" FROM "Patient_ID_Mapping_SDE_Lighthouse_14_Whittaker";

-- Find the highest currently assigned id. Ids are given incrementally, so now ones
-- need to start at +1 of the current highest
SET highestPatientId = (
    SELECT IFNULL(MAX("StudyPatientPseudoId"),0) FROM "Patient_ID_Mapping_SDE_Lighthouse_14_Whittaker"
);

-- Make a study specific hash for each new GmPseudo and insert it
-- into the patient lookup table
INSERT INTO "Patient_ID_Mapping_SDE_Lighthouse_14_Whittaker"
SELECT
    "GmPseudo", -- the GM SDE patient ids for patients in this cohort
    SHA2(CONCAT('SDE_Lighthouse_14_Whittaker', "GmPseudo")) AS "Hash", -- used to provide a random (study-specific) ordering for the patient ids we provide
    $highestPatientId + ROW_NUMBER() OVER (ORDER BY "Hash") -- the patient id that we provide to the analysts
FROM "AllPseudos_SDE_Lighthouse_14_Whittaker";

-- Finally, we select from the output table which includes the GmPseudos, in order
-- to populate the table for the end users where the GmPseudo fields are redacted via a function
-- created in the 0.code-sets.sql file
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH014-1_Patients";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH014-1_Patients" AS
SELECT SDE_REPOSITORY.SHARED_UTILITIES.gm_pseudo_hash_SDE_Lighthouse_14_Whittaker("GmPseudo") AS "PatientID",
	* EXCLUDE "GmPseudo"
FROM SDE_REPOSITORY.SHARED_UTILITIES."LH014-1_Patients_WITH_IDENTIFIER";

---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
--13.5k rows
