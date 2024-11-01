USE SCHEMA SDE_REPOSITORY.SHARED_UTILITIES;

--┌────────────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 14 - Whittaker - Inpatient admissions │
--└────────────────────────────────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK ---------
-- Richard Williams	2024-08-09	Review complete

-- Date range: 2018 to present

set(StudyStartDate) = to_date('2018-01-01');
set(StudyEndDate)   = to_date('2024-10-31');

-- get all inpatient admissions

-- ... processing [[create-output-table::"LH014-5_InpatientAdmissions"]] ... 
-- ... Need to create an output table called "LH014-5_InpatientAdmissions" and replace 
-- ... the GmPseudo column with a study-specific random patient id.

-- First we create a table in an area only visible to the RDEs which contains
-- the GmPseudos. THESE CANNOT BE RELEASED TO END USERS.
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH014-5_InpatientAdmissions_WITH_PSEUDO_IDS";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH014-5_InpatientAdmissions_WITH_PSEUDO_IDS" AS
SELECT 
    "GmPseudo" -- NEEDS PSEUDONYMISING
    , TO_DATE("AdmissionDttm") AS "AdmissionDate"
    , TO_DATE("DischargeDttm") AS "DischargeDate"
	, "AdmissionMethodCode"
	, "AdmissionMethodDesc"
    , "HospitalSpellDuration" AS "LOS_days"
    , "DerPrimaryDiagnosisChapterDescReportingEpisode" AS PrimaryDiagnosisChapter
	, "DerPrimaryDiagnosisCodeReportingEpisode" AS PrimaryDiagnosisCode 
    , "DerPrimaryDiagnosisDescReportingEpisode" AS PrimaryDiagnosisDesc
FROM PRESENTATION.NATIONAL_FLOWS_APC."DS708_Apcs"
WHERE TO_DATE("AdmissionDttm") BETWEEN $StudyStartDate AND $StudyEndDate
	AND "GmPseudo" IN (select "GmPseudo" from SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_14_Whittaker");

-- Then we check to see if there are any new GmPseudo ids. We do this by making a temp table 
-- of all "new" GmPseudo ids. I.e. any GmPseudo ids that we've already got a unique id for
-- for this study are excluded
DROP TABLE IF EXISTS "AllPseudos_SDE_Lighthouse_14_Whittaker";
CREATE TEMPORARY TABLE "AllPseudos_SDE_Lighthouse_14_Whittaker" AS
SELECT DISTINCT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."LH014-5_InpatientAdmissions_WITH_PSEUDO_IDS"
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
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH014-5_InpatientAdmissions";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH014-5_InpatientAdmissions" AS
SELECT SDE_REPOSITORY.SHARED_UTILITIES.gm_pseudo_hash_SDE_Lighthouse_14_Whittaker("GmPseudo") AS "PatientID",
	* EXCLUDE "GmPseudo"
FROM SDE_REPOSITORY.SHARED_UTILITIES."LH014-5_InpatientAdmissions_WITH_PSEUDO_IDS";

