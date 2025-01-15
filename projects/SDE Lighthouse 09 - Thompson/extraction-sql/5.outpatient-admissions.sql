USE SCHEMA SDE_REPOSITORY.SHARED_UTILITIES;

--┌────────────────────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 09 - Thompson - Outpatient hospital encounters │
--└────────────────────────────────────────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK ------------
--------------------------------------------------

set(StudyStartDate) = to_date('2020-01-01');
set(StudyEndDate)   = to_date('2024-10-31');

-- get all inpatient admissions


-- ... processing [[create-output-table::"LH009-5_OutpatientAdmissions"]] ... 
-- ... Need to create an output table called "LH009-5_OutpatientAdmissions" and replace 
-- ... the GmPseudo column with a study-specific random patient id.

-- First we create a table in an area only visible to the RDEs which contains
-- the GmPseudos. THESE CANNOT BE RELEASED TO END USERS.
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH009-5_OutpatientAdmissions_WITH_IDENTIFIER";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH009-5_OutpatientAdmissions_WITH_IDENTIFIER" AS
SELECT 
    ROW_NUMBER() OVER (ORDER BY "Pseudo NHS Number","Appointment Date Time") AS "AppointmentID"	
	, SUBSTRING("Pseudo NHS Number", 2)::INT AS "GmPseudo" 
    , TO_DATE("Appointment Date Time") AS "AppointmentDate"
	, "Priority Type Code"
	, "Priority Type Desc"
	, "Main Specialty Code"
	, "Main Specialty Desc"
	, "Treatment Function Code"
	, "Treatment Function Desc"
	, "Operation Status Code"
	, "Operation Status Desc"
	, "Outcome Of Attendance Code"
	, "Outcome Of Attendance Desc"
FROM PRESENTATION.NATIONAL_FLOWS_OPA."DS709_Outpatients" ap
WHERE "AppointmentDate" BETWEEN $StudyStartDate AND $StudyEndDate
	AND ap."GmPseudo" IN (SELECT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_09_Thompson")
	AND "Attended Or Did Not Attend Code" = 5;

-- Then we check to see if there are any new GmPseudo ids. We do this by making a temp table 
-- of all "new" GmPseudo ids. I.e. any GmPseudo ids that we've already got a unique id for
-- for this study are excluded
DROP TABLE IF EXISTS "AllPseudos_SDE_Lighthouse_09_Thompson";
CREATE TEMPORARY TABLE "AllPseudos_SDE_Lighthouse_09_Thompson" AS
SELECT DISTINCT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."LH009-5_OutpatientAdmissions_WITH_IDENTIFIER"
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
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH009-5_OutpatientAdmissions";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH009-5_OutpatientAdmissions" AS
SELECT SDE_REPOSITORY.SHARED_UTILITIES.gm_pseudo_hash_SDE_Lighthouse_09_Thompson("GmPseudo") AS "PatientID",
	* EXCLUDE "GmPseudo"
FROM SDE_REPOSITORY.SHARED_UTILITIES."LH009-5_OutpatientAdmissions_WITH_IDENTIFIER"; -- attended 

