USE SCHEMA SDE_REPOSITORY.SHARED_UTILITIES;

--┌──────────────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 14 - Whittaker - Trust level admissions │
--└──────────────────────────────────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK ---------
-- Richard Williams	2024-08-09	Review complete

-- Date range: 2018 to present

set(StudyStartDate) = to_date('2018-04-01');
set(StudyEndDate)   = to_date('2024-06-30');

-- CREATE A TABLE OF ADMISSIONS FROM GM TRUSTS
DROP TABLE IF EXISTS ManchesterTrusts;
CREATE TEMPORARY TABLE ManchesterTrusts AS 
SELECT *
FROM PRESENTATION.NATIONAL_FLOWS_APC."DS708_Apcs"
WHERE "ProviderDesc" IN    -- limit to trusts that have virtual ward data 
    ('Manchester University NHS Foundation Trust',
     --'Pennine Acute Hospitals NHS Trust',
     'Northern Care Alliance NHS Foundation Trust',
     'Wrightington, Wigan And Leigh NHS Foundation Trust',
     'Stockport NHS Foundation Trust',
     'Bolton NHS Foundation Trust',
     'Tameside And Glossop Integrated Care NHS Foundation Trust')
where TO_DATE("AdmissionDttm") between $StudyStartDate and $StudyEndDate
and "HospitalSpellDuration" != '*'; -- < 10 records have missing discharge date and spell duration, so exclude
  -- FILTER OUT ELECTIVE ??   
  
-- MONTHLY ADMISSION COUNTS AND AVG LENGTH OF STAY BY TRUST

    -- GROUP BY TRUST ONLY

-- ... processing [[create-output-table::"6a_TrustLevelAdmissions"]] ... 
-- ... Need to create an output table called "6a_TrustLevelAdmissions" and replace 
-- ... the GmPseudo column with a study-specific random patient id.

-- First we create a table in an area only visible to the RDEs which contains
-- the GmPseudos. THESE CANNOT BE RELEASED TO END USERS.
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."6a_TrustLevelAdmissions_WITH_PSEUDO_IDS";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."6a_TrustLevelAdmissions_WITH_PSEUDO_IDS" AS
select 
      YEAR("AdmissionDttm") AS "Year"
    , MONTH("AdmissionDttm") AS "Month"
    ,"ProviderDesc"
    , count(*) as Admissions  
    , AVG("HospitalSpellDuration") as "Avg_LengthOfStay" 
from ManchesterTrusts
group by YEAR("AdmissionDttm"), MONTH("AdmissionDttm"), "ProviderDesc"
order by YEAR("AdmissionDttm"), MONTH("AdmissionDttm"), "ProviderDesc";

-- Then we check to see if there are any new GmPseudo ids. We do this by making a temp table 
-- of all "new" GmPseudo ids. I.e. any GmPseudo ids that we've already got a unique id for
-- for this study are excluded
DROP TABLE IF EXISTS "AllPseudos_SDE_Lighthouse_14_Whittaker";
CREATE TEMPORARY TABLE "AllPseudos_SDE_Lighthouse_14_Whittaker" AS
SELECT DISTINCT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."6a_TrustLevelAdmissions_WITH_PSEUDO_IDS"
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
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."6a_TrustLevelAdmissions";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."6a_TrustLevelAdmissions" AS
SELECT SDE_REPOSITORY.SHARED_UTILITIES.gm_pseudo_hash_SDE_Lighthouse_14_Whittaker("GmPseudo") AS "PatientID", * EXCLUDE "GmPseudo"
FROM SDE_REPOSITORY.SHARED_UTILITIES."6a_TrustLevelAdmissions_WITH_PSEUDO_IDS";

    -- READMISSIONS ONLY

-- ... processing [[create-output-table::"6b_TrustLevelReadmissions"]] ... 
-- ... Need to create an output table called "6b_TrustLevelReadmissions" and replace 
-- ... the GmPseudo column with a study-specific random patient id.

-- First we create a table in an area only visible to the RDEs which contains
-- the GmPseudos. THESE CANNOT BE RELEASED TO END USERS.
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."6b_TrustLevelReadmissions_WITH_PSEUDO_IDS";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."6b_TrustLevelReadmissions_WITH_PSEUDO_IDS" AS
select 
      YEAR("AdmissionDttm") AS "Year"
    , MONTH("AdmissionDttm") AS "Month"
    ,"ProviderDesc"
    , count(*) as Readmissions  
    , AVG("HospitalSpellDuration") as "Avg_LengthOfStay" 
FROM ManchesterTrusts
and "IsReadmission" = 'TRUE'
group by YEAR("AdmissionDttm"), MONTH("AdmissionDttm"), "ProviderDesc"
order by YEAR("AdmissionDttm"), MONTH("AdmissionDttm"), "ProviderDesc";

-- Then we check to see if there are any new GmPseudo ids. We do this by making a temp table 
-- of all "new" GmPseudo ids. I.e. any GmPseudo ids that we've already got a unique id for
-- for this study are excluded
DROP TABLE IF EXISTS "AllPseudos_SDE_Lighthouse_14_Whittaker";
CREATE TEMPORARY TABLE "AllPseudos_SDE_Lighthouse_14_Whittaker" AS
SELECT DISTINCT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."6b_TrustLevelReadmissions_WITH_PSEUDO_IDS"
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
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."6b_TrustLevelReadmissions";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."6b_TrustLevelReadmissions" AS
SELECT SDE_REPOSITORY.SHARED_UTILITIES.gm_pseudo_hash_SDE_Lighthouse_14_Whittaker("GmPseudo") AS "PatientID", * EXCLUDE "GmPseudo"
FROM SDE_REPOSITORY.SHARED_UTILITIES."6b_TrustLevelReadmissions_WITH_PSEUDO_IDS";

    -- GROUP BY TRUST AND ICD CATEGORY 


-- ... processing [[create-output-table::"6c_TrustLevelAdmissions_icd"]] ... 
-- ... Need to create an output table called "6c_TrustLevelAdmissions_icd" and replace 
-- ... the GmPseudo column with a study-specific random patient id.

-- First we create a table in an area only visible to the RDEs which contains
-- the GmPseudos. THESE CANNOT BE RELEASED TO END USERS.
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."6c_TrustLevelAdmissions_icd_WITH_PSEUDO_IDS";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."6c_TrustLevelAdmissions_icd_WITH_PSEUDO_IDS" AS
select 
      YEAR("AdmissionDttm") AS "Year"
    , MONTH("AdmissionDttm") AS "Month"
    , "ProviderDesc" 
    , "DerPrimaryDiagnosisChapterCodeReportingEpisode" as PrimaryICDCategoryCode
    , "DerPrimaryDiagnosisChapterDescReportingEpisode" as PrimaryICDCategoryDesc
    , count(*) as Admissions  
    , AVG("HospitalSpellDuration") as "Avg_LengthOfStay" 
FROM ManchesterTrusts
group by   
      YEAR("AdmissionDttm") 
    , MONTH("AdmissionDttm") 
    , "ProviderDesc"
    , "DerPrimaryDiagnosisChapterCodeReportingEpisode" 
    , "DerPrimaryDiagnosisChapterDescReportingEpisode"
order by 
      YEAR("AdmissionDttm") 
    , MONTH("AdmissionDttm") 
    , "ProviderDesc"
    , "DerPrimaryDiagnosisChapterCodeReportingEpisode" 
    , "DerPrimaryDiagnosisChapterDescReportingEpisode";

-- Then we check to see if there are any new GmPseudo ids. We do this by making a temp table 
-- of all "new" GmPseudo ids. I.e. any GmPseudo ids that we've already got a unique id for
-- for this study are excluded
DROP TABLE IF EXISTS "AllPseudos_SDE_Lighthouse_14_Whittaker";
CREATE TEMPORARY TABLE "AllPseudos_SDE_Lighthouse_14_Whittaker" AS
SELECT DISTINCT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."6c_TrustLevelAdmissions_icd_WITH_PSEUDO_IDS"
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
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."6c_TrustLevelAdmissions_icd";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."6c_TrustLevelAdmissions_icd" AS
SELECT SDE_REPOSITORY.SHARED_UTILITIES.gm_pseudo_hash_SDE_Lighthouse_14_Whittaker("GmPseudo") AS "PatientID", * EXCLUDE "GmPseudo"
FROM SDE_REPOSITORY.SHARED_UTILITIES."6c_TrustLevelAdmissions_icd_WITH_PSEUDO_IDS";

    -- GROUP BY TRUST AND AGE BAND

-- ... processing [[create-output-table::"6d_TrustLevelAdmissions_age"]] ... 
-- ... Need to create an output table called "6d_TrustLevelAdmissions_age" and replace 
-- ... the GmPseudo column with a study-specific random patient id.

-- First we create a table in an area only visible to the RDEs which contains
-- the GmPseudos. THESE CANNOT BE RELEASED TO END USERS.
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."6d_TrustLevelAdmissions_age_WITH_PSEUDO_IDS";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."6d_TrustLevelAdmissions_age_WITH_PSEUDO_IDS" AS
select 
      YEAR("AdmissionDttm") AS "Year"
    , MONTH("AdmissionDttm") AS "Month"
    , "ProviderDesc" 
    , case when "AgeAtStartOfSpellSus" < 18 then '1. <18' 
         when "AgeAtStartOfSpellSus" between 18 and 30  then '2. 18-30'
         when "AgeAtStartOfSpellSus" between 31 and 50  then '3. 31-50' 
         when "AgeAtStartOfSpellSus" between 51 and 70  then '4. 51-70'
         when "AgeAtStartOfSpellSus" between 71 and 90  then '5. 71-90'
         when "AgeAtStartOfSpellSus" > 90  then '6. >90'
            else NULL end as AgeBand
    , count(*) as Admissions  
    , AVG("HospitalSpellDuration") as "Avg_LengthOfStay" 
from ManchesterTrusts
and "AgeAtStartOfSpellSus" between 0 and 120 -- REMOVE UNREALISTIC VALUES
group by 
      YEAR("AdmissionDttm")
    , MONTH("AdmissionDttm")
    , "ProviderDesc"  
    , case when "AgeAtStartOfSpellSus" < 18 then '1. <18' 
         when "AgeAtStartOfSpellSus" between 18 and 30  then '2. 18-30'
         when "AgeAtStartOfSpellSus" between 31 and 50  then '3. 31-50' 
         when "AgeAtStartOfSpellSus" between 51 and 70  then '4. 51-70'
         when "AgeAtStartOfSpellSus" between 71 and 90  then '5. 71-90'
         when "AgeAtStartOfSpellSus" > 90  then '6. >90'
            else end NULL
order by 
      YEAR("AdmissionDttm")
    , MONTH("AdmissionDttm")
    , "ProviderDesc"
    , case when "AgeAtStartOfSpellSus" < 18 then '1. <18' 
         when "AgeAtStartOfSpellSus" between 18 and 30  then '2. 18-30'
         when "AgeAtStartOfSpellSus" between 31 and 50  then '3. 31-50' 
         when "AgeAtStartOfSpellSus" between 51 and 70  then '4. 51-70'
         when "AgeAtStartOfSpellSus" between 71 and 90  then '5. 71-90'
         when "AgeAtStartOfSpellSus" > 90  then '6. >90'
            else end NULL;

-- Then we check to see if there are any new GmPseudo ids. We do this by making a temp table 
-- of all "new" GmPseudo ids. I.e. any GmPseudo ids that we've already got a unique id for
-- for this study are excluded
DROP TABLE IF EXISTS "AllPseudos_SDE_Lighthouse_14_Whittaker";
CREATE TEMPORARY TABLE "AllPseudos_SDE_Lighthouse_14_Whittaker" AS
SELECT DISTINCT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."6d_TrustLevelAdmissions_age_WITH_PSEUDO_IDS"
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
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."6d_TrustLevelAdmissions_age";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."6d_TrustLevelAdmissions_age" AS
SELECT SDE_REPOSITORY.SHARED_UTILITIES.gm_pseudo_hash_SDE_Lighthouse_14_Whittaker("GmPseudo") AS "PatientID", * EXCLUDE "GmPseudo"
FROM SDE_REPOSITORY.SHARED_UTILITIES."6d_TrustLevelAdmissions_age_WITH_PSEUDO_IDS";

-- Emergency department attendances: 
	-- Total
	-- by ICD   -- providing this is likely to have too many small numbers, as we could only do it using 'chief complaint snomed code'
	-- by ageband 

DROP TABLE IF EXISTS ManchesterTrustsAE;
CREATE TEMPORARY TABLE ManchesterTrustsAE AS 
SELECT *
FROM PRESENTATION.NATIONAL_FLOWS_ECDS."DS707_Ecds" E
WHERE "ProviderDesc" IN 
    ('Manchester University NHS Foundation Trust',
     'Pennine Acute Hospitals NHS Trust',
     'Northern Care Alliance NHS Foundation Trust',
     'Wrightington, Wigan And Leigh NHS Foundation Trust',
     'Stockport NHS Foundation Trust',
     'Bolton NHS Foundation Trust',
     'Tameside And Glossop Integrated Care NHS Foundation Trust')
AND  TO_DATE("ArrivalDate") between $StudyStartDate and $StudyEndDate

    
-- total

-- ... processing [[create-output-table::"6e_TrustLevelAEAdmissions"]] ... 
-- ... Need to create an output table called "6e_TrustLevelAEAdmissions" and replace 
-- ... the GmPseudo column with a study-specific random patient id.

-- First we create a table in an area only visible to the RDEs which contains
-- the GmPseudos. THESE CANNOT BE RELEASED TO END USERS.
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."6e_TrustLevelAEAdmissions_WITH_PSEUDO_IDS";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."6e_TrustLevelAEAdmissions_WITH_PSEUDO_IDS" AS
SELECT
	  YEAR("ArrivalDate") AS "Year"
    , MONTH("ArrivalDate") AS "Month"
	, "ProviderDesc"
    , count(*) as count 
FROM ManchesterTrustsAE
WHERE "IsAttendance" = 1 -- been advised to apply this filter to get A&E admissions
GROUP BY 
	  YEAR("ArrivalDate")
    , MONTH("ArrivalDate")
	, "ProviderDesc"
ORDER BY 
	  YEAR("ArrivalDate")
    , MONTH("ArrivalDate")
	, "ProviderDesc"

-- by Age band

-- ... processing [[create-output-table::"6f_TrustLevelAEAdmissions_age"]] ... 
-- ... Need to create an output table called "6f_TrustLevelAEAdmissions_age" and replace 
-- ... the GmPseudo column with a study-specific random patient id.

-- First we create a table in an area only visible to the RDEs which contains
-- the GmPseudos. THESE CANNOT BE RELEASED TO END USERS.
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."6f_TrustLevelAEAdmissions_age_WITH_PSEUDO_IDS";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."6f_TrustLevelAEAdmissions_age_WITH_PSEUDO_IDS" AS
SELECT
	  YEAR("ArrivalDate") AS "Year"
    , MONTH("ArrivalDate") AS "Month"
	, "ProviderDesc"
    , case when "AgeAtArrival" < 18 then '1. <18' 
         when "AgeAtArrival" between 18 and 30  then '2. 18-30'
         when "AgeAtArrival" between 31 and 50  then '3. 31-50' 
         when "AgeAtArrival" between 51 and 70  then '4. 51-70'
         when "AgeAtArrival" between 71 and 90  then '5. 71-90'
         when "AgeAtArrival" > 90  then '6. >90'
            else NULL end AS AgeBand
    , count(*) as count 
FROM ManchesterTrustsAE
GROUP BY 
	  YEAR("ArrivalDate")
    , MONTH("ArrivalDate")
	, "ProviderDesc"
    , case when "AgeAtArrival" < 18 then '1. <18' 
         when "AgeAtArrival" between 18 and 30  then '2. 18-30'
         when "AgeAtArrival" between 31 and 50  then '3. 31-50' 
         when "AgeAtArrival" between 51 and 70  then '4. 51-70'
         when "AgeAtArrival" between 71 and 90  then '5. 71-90'
         when "AgeAtArrival" > 90  then '6. >90'
            else NULL end
ORDER BY YEAR("ArrivalDate")
    , MONTH("ArrivalDate")
	, "ProviderDesc"
    , case when "AgeAtArrival" < 18 then '1. <18' 
         when "AgeAtArrival" between 18 and 30  then '2. 18-30'
         when "AgeAtArrival" between 31 and 50  then '3. 31-50' 
         when "AgeAtArrival" between 51 and 70  then '4. 51-70'
         when "AgeAtArrival" between 71 and 90  then '5. 71-90'
         when "AgeAtArrival" > 90  then '6. >90'
            else NULL end;

-- Then we check to see if there are any new GmPseudo ids. We do this by making a temp table 
-- of all "new" GmPseudo ids. I.e. any GmPseudo ids that we've already got a unique id for
-- for this study are excluded
DROP TABLE IF EXISTS "AllPseudos_SDE_Lighthouse_14_Whittaker";
CREATE TEMPORARY TABLE "AllPseudos_SDE_Lighthouse_14_Whittaker" AS
SELECT DISTINCT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."6f_TrustLevelAEAdmissions_age_WITH_PSEUDO_IDS"
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
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."6f_TrustLevelAEAdmissions_age";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."6f_TrustLevelAEAdmissions_age" AS
SELECT SDE_REPOSITORY.SHARED_UTILITIES.gm_pseudo_hash_SDE_Lighthouse_14_Whittaker("GmPseudo") AS "PatientID", * EXCLUDE "GmPseudo"
FROM SDE_REPOSITORY.SHARED_UTILITIES."6f_TrustLevelAEAdmissions_age_WITH_PSEUDO_IDS";

-- Then we check to see if there are any new GmPseudo ids. We do this by making a temp table 
-- of all "new" GmPseudo ids. I.e. any GmPseudo ids that we've already got a unique id for
-- for this study are excluded
DROP TABLE IF EXISTS "AllPseudos_SDE_Lighthouse_14_Whittaker";
CREATE TEMPORARY TABLE "AllPseudos_SDE_Lighthouse_14_Whittaker" AS
SELECT DISTINCT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."6e_TrustLevelAEAdmissions_WITH_PSEUDO_IDS"
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
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."6e_TrustLevelAEAdmissions";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."6e_TrustLevelAEAdmissions" AS
SELECT SDE_REPOSITORY.SHARED_UTILITIES.gm_pseudo_hash_SDE_Lighthouse_14_Whittaker("GmPseudo") AS "PatientID", * EXCLUDE "GmPseudo"
FROM SDE_REPOSITORY.SHARED_UTILITIES."6e_TrustLevelAEAdmissions_WITH_PSEUDO_IDS";