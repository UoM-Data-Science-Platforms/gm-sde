USE SCHEMA SDE_REPOSITORY.SHARED_UTILITIES;

--┌──────────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 06 - Chen - adverse events          │
--└──────────────────────────────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK ------------
-- Richard Williams	2024-08-30	Review complete --
--------------------------------------------------

-- NOTE: the SDE does have self harm and fracture code sets (eFI2_SelfHarm and eFI2_Fracture)
-- but our GMCR code sets seem more comprehensive

set(StudyStartDate) = to_date('2017-01-01');
set(StudyEndDate)   = to_date('2023-12-31');

-- >>> Codesets required... Inserting the code set code
-- >>> Codesets extracted into 0.code-sets.sql
-- >>> Following code sets injected: selfharm-episodes v1/fracture v1


-- First we create a table in an area only visible to the RDEs which contains
-- the GmPseudo or FK_Patient_IDs. These cannot be released to end users.
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."3_AdverseEvents_WITH_PSEUDO_IDS";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."3_AdverseEvents_WITH_PSEUDO_IDS" AS
SELECT DISTINCT
	cohort."GmPseudo",  -- NEEDS PSEUDONYMISING
	to_date("EventDate") as "EventDate",
	cs.concept AS "Concept",
	"SuppliedCode", 
	"Term" AS "Description"
FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_06_Chen" cohort
LEFT OUTER JOIN INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" events ON events."FK_Patient_ID" = cohort."FK_Patient_ID"
LEFT OUTER JOIN SDE_REPOSITORY.SHARED_UTILITIES."Code_Sets_SDE_Lighthouse_06_Chen" cs ON cs.code = events."SuppliedCode" 
WHERE cs.concept IN ('selfharm-episodes', 'fracture')
	AND TO_DATE(events."EventDate") BETWEEN $StudyStartDate AND $StudyEndDate;

-- Then we select from that table, to populate the table for the end users
-- where the GmPseudo or FK_Patient_ID fields are redacted via a function
-- created in the 0.code-sets.sql
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."3_AdverseEvents";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."3_AdverseEvents" AS
SELECT SDE_REPOSITORY.SHARED_UTILITIES.gm_pseudo_hash_SDE_Lighthouse_06_Chen("GmPseudo") AS "PatientID", * EXCLUDE "GmPseudo"
FROM SDE_REPOSITORY.SHARED_UTILITIES."3_AdverseEvents_WITH_PSEUDO_IDS";
