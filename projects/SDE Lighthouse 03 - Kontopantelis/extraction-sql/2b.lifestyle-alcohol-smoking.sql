USE SCHEMA SDE_REPOSITORY.SHARED_UTILITIES;

--┌──────────────────────────────────────────┐
--│ SDE Lighthouse study 03 - Kontopantelis  │
--└──────────────────────────────────────────┘

-- From application:
--	Table 2: Lifestyle factors (from 2006 to present)
--		- PatientID
--		- TestName ( Alcohol, Smoking)
--		- TestDate
--		- Description
--		- TestResult
--		- TestUnits
--		- Status
--		- Consumption

-- NB1 - I'm only restricting BMI values to 2006 to present.
-- NB2 - The PI confirmed that instead of raw values of when statuses were
--			 recorded, they are happy with the information as currently used
--			 within the tables below.


set(StudyStartDate) = to_date('2006-01-01');
set(StudyEndDate)   = to_date('2024-06-30');



-- ... processing [[create-output-table::"LH003-2b_Lifestyle_Alcohol_Smoking"]] ... 
-- ... Need to create an output table called "LH003-2b_Lifestyle_Alcohol_Smoking" and replace 
-- ... the GmPseudo column with a study-specific random patient id.

-- First we create a table in an area only visible to the RDEs which contains
-- the GmPseudos. THESE CANNOT BE RELEASED TO END USERS.
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH003-2b_Lifestyle_Alcohol_Smoking_WITH_PSEUDO_IDS";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH003-2b_Lifestyle_Alcohol_Smoking_WITH_PSEUDO_IDS" AS
SELECT
	"GmPseudo",
	'Alcohol' AS "TestName",
	"EventDate" AS "TestDate",
	"Term" AS "Description",
	"Value" AS "TestResult",
	"Units" AS "TestUnits",
	"AlcoholStatus" AS "Status",
	"AlcoholConsumption" AS "Consumption"
FROM INTERMEDIATE.GP_RECORD."Readings_Alcohol_SecondaryUses"
WHERE "GmPseudo" IN (SELECT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_03_Kontopantelis") AND "EventDate" BETWEEN $StudyStartDate AND $StudyEndDate
UNION
SELECT
	"GmPseudo",
	'Smoking',	-- "TestName",
	"SmokingStatus_Date",	-- "TestDate",
	NULL, -- "Description",
	NULL, -- "TestResult",
	NULL, -- "TestUnits",
	"SmokingStatus", 	-- "Status",
	CASE
		WHEN "SmokingConsumption_Date" = "SmokingStatus_Date" THEN "SmokingConsumption"
		ELSE NULL
	END -- "Consumption"
FROM INTERMEDIATE.GP_RECORD."Readings_Smoking_SecondaryUses"
WHERE "GmPseudo" IN (SELECT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_03_Kontopantelis") AND "SmokingStatus_Date" BETWEEN $StudyStartDate AND $StudyEndDate;

-- Then we check to see if there are any new GmPseudo ids. We do this by making a temp table 
-- of all "new" GmPseudo ids. I.e. any GmPseudo ids that we've already got a unique id for
-- for this study are excluded
DROP TABLE IF EXISTS "AllPseudos_SDE_Lighthouse_03_Kontopantelis";
CREATE TEMPORARY TABLE "AllPseudos_SDE_Lighthouse_03_Kontopantelis" AS
SELECT DISTINCT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."LH003-2b_Lifestyle_Alcohol_Smoking_WITH_PSEUDO_IDS"
EXCEPT
SELECT "GmPseudo" FROM "Patient_ID_Mapping_SDE_Lighthouse_03_Kontopantelis";

-- Find the highest currently assigned id. Ids are given incrementally, so now ones
-- need to start at +1 of the current highest
SET highestPatientId = (
    SELECT IFNULL(MAX("StudyPatientPseudoId"),0) FROM "Patient_ID_Mapping_SDE_Lighthouse_03_Kontopantelis"
);

-- Make a study specific hash for each new GmPseudo and insert it
-- into the patient lookup table
INSERT INTO "Patient_ID_Mapping_SDE_Lighthouse_03_Kontopantelis"
SELECT
    "GmPseudo", -- the GM SDE patient ids for patients in this cohort
    SHA2(CONCAT('SDE_Lighthouse_03_Kontopantelis', "GmPseudo")) AS "Hash", -- used to provide a random (study-specific) ordering for the patient ids we provide
    $highestPatientId + ROW_NUMBER() OVER (ORDER BY "Hash") -- the patient id that we provide to the analysts
FROM "AllPseudos_SDE_Lighthouse_03_Kontopantelis";

-- Finally, we select from the output table which includes the GmPseudos, in order
-- to populate the table for the end users where the GmPseudo fields are redacted via a function
-- created in the 0.code-sets.sql file
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH003-2b_Lifestyle_Alcohol_Smoking";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH003-2b_Lifestyle_Alcohol_Smoking" AS
SELECT SDE_REPOSITORY.SHARED_UTILITIES.gm_pseudo_hash_SDE_Lighthouse_03_Kontopantelis("GmPseudo") AS "PatientID",
	* EXCLUDE "GmPseudo"
FROM SDE_REPOSITORY.SHARED_UTILITIES."LH003-2b_Lifestyle_Alcohol_Smoking_WITH_PSEUDO_IDS";