USE SCHEMA SDE_REPOSITORY.SHARED_UTILITIES;

--┌────────────────────────────────┐
--│ LH014 Virtual ward file        │
--└────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK ---------
-- Richard Williams	2024-08-09	Review complete

-- each provider starting providing VW data at different times, so data is incomplete for periods.

set(StudyStartDate) = to_date('2018-01-01');
set(StudyEndDate)   = to_date('2024-06-30');

---- Use the latest snapshot for each spell and get all relevant information


-- ... processing [[create-output-table::"2_VirtualWards"]] ... 
-- ... Need to create an output table called "2_VirtualWards" and replace 
-- ... the GmPseudo column with a study-specific random patient id.

-- First we create a table in an area only visible to the RDEs which contains
-- the GmPseudos. THESE CANNOT BE RELEASED TO END USERS.
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."2_VirtualWards_WITH_PSEUDO_IDS";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."2_VirtualWards_WITH_PSEUDO_IDS" AS
SELECT 
    SUBSTRING(vw."Pseudo NHS Number", 2)::INT AS "GmPseudo", 
    ROW_NUMBER() OVER(PARTITION BY "Pseudo NHS Number" ORDER BY "SnapshotDate") AS "PatientSpellNumber",
    vw."SnapshotDate",
    vw."Admission Source ID",
    adm."Admission Source Description",
    TO_DATE(vw."Admission Date") AS "Admission Date",
    TO_DATE(vw."Discharge Date") AS "Discharge Date",
    vw."Length of stay",
    vw."LoS Group",
    vw."Year Of Birth",
    vw."Month Of Birth",
    vw."Age on Admission",
    vw."Age Group",
    vw."Gender Group" as Sex,
    vw."Ethnicity Group",
    vw."Postcode_LSOA_2011",
    vw."ProviderName",
    vw."Referral Group",
    TO_DATE(vw."Referral Date") AS "Referral Date",
    TO_DATE(vw."Referral Accepted Date") AS "Referral Accepted Date",
    vw."Primary ICD10 Code Group ID",
    vw."Primary ICD10 Code Group",
    vw."Ward ID",
    vw."Ward name",
    vw."WardCapacity",
    vw."Discharge Method",
    vw."Discharge Method Short",
    vw."Discharge Destination",
    vw."Discharge Destination Short",
    vw."Discharge Destination Group",
    vw."Diagnosis Pathway",
    vw."Step up or down",
    vw."Using tech-enabled service"
from PRESENTATION.LOCAL_FLOWS_VIRTUAL_WARDS.VIRTUAL_WARD_OCCUPANCY vw
-- get admission source description
left join (select distinct "Admission Source ID", "Admission Source Description" 
           from PRESENTATION.LOCAL_FLOWS_VIRTUAL_WARDS.DQ_VIRTUAL_WARDS_ADMISSION_SOURCE) adm
    on adm."Admission Source ID" = vw."Admission Source ID"
-- filter to the latest snapshot for each spell (as advised by colleague at NHS GM)
inner join (select  "Unique Spell ID", Max("SnapshotDate") "LatestRecord" 
            from PRESENTATION.LOCAL_FLOWS_VIRTUAL_WARDS.VIRTUAL_WARD_OCCUPANCY
            group by all) a 
    on a."Unique Spell ID" = vw."Unique Spell ID" and vw."SnapshotDate" = a."LatestRecord"
where TO_DATE(vw."Admission Date") BETWEEN $StudyStartDate AND $StudyEndDate
AND SUBSTRING(vw."Pseudo NHS Number", 2)::INT IN (select "GmPseudo" from SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_14_Whittaker");

-- Then we check to see if there are any new GmPseudo ids. We do this by making a temp table 
-- of all "new" GmPseudo ids. I.e. any GmPseudo ids that we've already got a unique id for
-- for this study are excluded
DROP TABLE IF EXISTS "AllPseudos_SDE_Lighthouse_14_Whittaker";
CREATE TEMPORARY TABLE "AllPseudos_SDE_Lighthouse_14_Whittaker" AS
SELECT DISTINCT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."2_VirtualWards_WITH_PSEUDO_IDS"
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
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."2_VirtualWards";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."2_VirtualWards" AS
SELECT SDE_REPOSITORY.SHARED_UTILITIES.gm_pseudo_hash_SDE_Lighthouse_14_Whittaker("GmPseudo") AS "PatientID", * EXCLUDE "GmPseudo"
FROM SDE_REPOSITORY.SHARED_UTILITIES."2_VirtualWards_WITH_PSEUDO_IDS"; -- extra check to ensure consistent cohort

-- 16,107 patients
--24,608 spells
