--
--┌────────────────────┐
--│ Clinical code sets │
--└────────────────────┘

--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
--!!! DO NOT EDIT THIS FILE MANUALLY !!!
--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

-- Instructions for use

-- 1. Create a folder under the "Worksheets" tab within Snowflake named SDE-Lighthouse-06-Chen (unless it already exists)
-- 2. For each sql file in the extraction-sql directory, create a worksheet with the same name within the SDE-Lighthouse-06-Chen folder
-- 3. Copy/paste the contents of each sql file into the matching worksheet
-- 4. Run this worksheet first (to create an empty code set table for this project)
-- 5. Before running the other worksheets you must load the code sets for this project into the code set table:
--    a. From the "Database" menu on the far left hand side, select "Add Data"
--    b. Select "Load data into a Table"
--    c. Browse to select the 0.code-sets.csv file in this directory
--    d. Select the "SDE_REPOSITORY.SHARED_UTILITIES" schema
--    e. Select the table: "Code_Sets_SDE_Lighthouse_06_Chen" and click "Next"
--    f. Select the file format "Delimited files (CSV/TSV)"
--    g. Double check that the preview looks ok and then click "Load"
-- 6. You can now return to the worksheet folder SDE-Lighthouse-06-Chen and execute the remaining sql files.

USE SDE_REPOSITORY.SHARED_UTILITIES;

-- Creates the code set table for this project.
DROP TABLE IF EXISTS "Code_Sets_SDE_Lighthouse_06_Chen";
CREATE TABLE "Code_Sets_SDE_Lighthouse_06_Chen" (
	CONCEPT VARCHAR(255),
	VERSION NUMBER(38,0),
	TERMINOLOGY VARCHAR(20),
	CODE VARCHAR(20),
	DESCRIPTION VARCHAR(255)
);

-----------------------------------------------------------------------------------------------
-- START: GmPseudo obfuscator                                                                --
-----------------------------------------------------------------------------------------------

-- Can't provide GmPseudo. Need to obfuscate it. Requirements
--  - Consistent, so two different SQL files for the same study would produce the same output
--  - Study-specific. GmPseudo=xxx would come out as different ids in different studies
--  - Repeatable. GmPseudo=xxx would always produce the same id
--  - Secure. Can't inadvertently reveal gmpseudo, or allow guessing.

-- Current solution.
-- Create a study specific hash for each GmPseudo. But, only use this to sort
-- the patients in study specific random way. We then assign number (1,2,3...) according to
-- this ordering. On subsequent runs, we only do this to GmPseudo ids that haven't already
-- been done for this study. The table is stored in a location only visible to the data
-- engineers, but the original mapping from GmPseudo to study specific pseudo is maintained in
-- case of query.

-- First create the output table unless it already exists
CREATE TABLE IF NOT EXISTS "Patient_ID_Mapping_SDE_Lighthouse_06_Chen" (
    "GmPseudo" NUMBER(38,0),
    "Hash" VARCHAR(255),
    "StudyPatientPseudoId" NUMBER(38,0)
);


-- Define the function to return the study specific id
-- NB we need one function per study because UDFs don't allow
-- dynamic table names to be set from the arguments
DROP FUNCTION IF EXISTS gm_pseudo_hash_SDE_Lighthouse_06_Chen(NUMBER(38,0));
CREATE FUNCTION gm_pseudo_hash_SDE_Lighthouse_06_Chen("GmPseudo" NUMBER(38,0))
  RETURNS NUMBER(38,0)
  AS
  $$
    SELECT MAX("StudyPatientPseudoId")
    FROM SDE_REPOSITORY.SHARED_UTILITIES."Patient_ID_Mapping_SDE_Lighthouse_06_Chen"
    WHERE "GmPseudo" = GmPseudo
  $$
  ;

-----------------------------------------------------------------------------------------------
-- END: GmPseudo obfuscator                                                                  --
-----------------------------------------------------------------------------------------------

