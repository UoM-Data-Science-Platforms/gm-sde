USE SCHEMA SDE_REPOSITORY.SHARED_UTILITIES;

--┌──────────────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 14 - Whittaker - A&E Encounters         │
--└──────────────────────────────────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK ---------
-- Richard Williams	2024-08-09	Review complete

-- Date range: 2018 to present

set(StudyStartDate) = to_date('2018-01-01');
set(StudyEndDate)   = to_date('2024-10-31');

-- get all a&e admissions for the virtual ward cohort


-- ... processing [[create-output-table::"LH014-3_AEAdmissions"]] ... 
-- ... Need to create an output table called "LH014-3_AEAdmissions" and replace 
-- ... the GmPseudo column with a study-specific random patient id.

-- First we create a table in an area only visible to the RDEs which contains
-- the GmPseudos. THESE CANNOT BE RELEASED TO END USERS.
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH014-3_AEAdmissions_WITH_PSEUDO_IDS";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH014-3_AEAdmissions_WITH_PSEUDO_IDS" AS
SELECT 
E."GmPseudo", 
TO_DATE(E."ArrivalDate") AS "ArrivalDate",
TO_DATE(E."EcDepartureDate") AS "DepartureDate",
E."EcDuration" AS LOS_Mins,
E."EcChiefComplaintSnomedCtCode" AS ChiefComplaintCode,
E."EcChiefComplaintSnomedCtDesc" AS ChiefComplaintDesc,
E."EmAttendanceCategoryCode",
E."EmAttendanceCategoryDesc", 
E."EmAttendanceDisposalCode",
E."EmAttendanceDisposalDesc"
FROM PRESENTATION.NATIONAL_FLOWS_ECDS."DS707_Ecds" E
WHERE "IsAttendance" = 1 -- advised to use this for A&E attendances
	AND "GmPseudo" IN (select "GmPseudo" from SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_14_Whittaker")
	AND TO_DATE(E."ArrivalDate") BETWEEN $StudyStartDate AND $StudyEndDate;

-- Then we check to see if there are any new GmPseudo ids. We do this by making a temp table 
-- of all "new" GmPseudo ids. I.e. any GmPseudo ids that we've already got a unique id for
-- for this study are excluded
DROP TABLE IF EXISTS "AllPseudos_SDE_Lighthouse_14_Whittaker";
CREATE TEMPORARY TABLE "AllPseudos_SDE_Lighthouse_14_Whittaker" AS
SELECT DISTINCT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."LH014-3_AEAdmissions_WITH_PSEUDO_IDS"
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
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH014-3_AEAdmissions";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH014-3_AEAdmissions" AS
SELECT SDE_REPOSITORY.SHARED_UTILITIES.gm_pseudo_hash_SDE_Lighthouse_14_Whittaker("GmPseudo") AS "PatientID",
	* EXCLUDE "GmPseudo"
FROM SDE_REPOSITORY.SHARED_UTILITIES."LH014-3_AEAdmissions_WITH_PSEUDO_IDS";