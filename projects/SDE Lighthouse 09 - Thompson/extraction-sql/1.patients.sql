USE SCHEMA SDE_REPOSITORY.SHARED_UTILITIES;

--┌──────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 09 - Thompson - Patients file   │
--└──────────────────────────────────────────────────────┘

-- Cohort: 30-70 year old women, alive in 2020

set(StudyStartDate) = to_date('2020-01-01');
set(StudyEndDate)   = to_date('2024-09-30');


--┌─────────────────────────────────────────────────────────────────┐
--│ Create table of patients who were alive at the study start date │
--└─────────────────────────────────────────────────────────────────┘

-- ** any patients opted out of sharing GP data would not appear in the final table

-- this script requires an input of StudyStartDate

-- takes one parameter: 
-- minimum-age : integer - The minimum age of the group of patients. Typically this would be 0 (all patients) or 18 (all adults)

--ALL DEATHS 

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
        ON OM."XSeqNo" = DEATH."XSeqNo" AND OM."DiagnosisOriginalMentionNumber" = 1;

-- GET LATEST SNAPSHOT OF DEMOGRAPHICS TABLE

DROP TABLE IF EXISTS LatestSnapshot;
CREATE TEMPORARY TABLE LatestSnapshot AS
SELECT 
    p.*
FROM PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" p 
INNER JOIN (
    SELECT "GmPseudo", MAX("Snapshot") AS LatestSnapshot
    FROM PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" p 
	WHERE DATEDIFF(YEAR, TO_DATE("DateOfBirth"), $StudyStartDate) >= 18 -- adults only
    GROUP BY "GmPseudo"
    ) t2
ON t2."GmPseudo" = p."GmPseudo" AND t2.LatestSnapshot = p."Snapshot";

-- CREATE A PATIENT SUMMARY TABLE TO WORK OUT WHICH PATIENTS HAVE LEFT GM 
-- AND THEREFORE THEIR DATA FEED STOPPED 

drop table if exists PatientSummary;
create temporary table PatientSummary as
select dem."GmPseudo", 
        min("Snapshot") as "min", 
        max("Snapshot") as "max", 
        max(DeathDate) as DeathDate
from PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" dem
LEFT JOIN Death ON Death."GmPseudo" = dem."GmPseudo"
group by dem."GmPseudo";

-- FIND THE DATE THAT PATIENT LEFT GM

drop table if exists leftGMDate;
create temporary table leftGMDate as 
select *,
    case when DeathDate is null and "max" < (select max("max") from PatientSummary) then "max" else null end as leftGMDate
from PatientSummary;

-- FIND ALL ADULT PATIENTS ALIVE AT STUDY START DATE

DROP TABLE IF EXISTS AlivePatientsAtStart;
CREATE TEMPORARY TABLE AlivePatientsAtStart AS 
SELECT  
    dem.*, 
    Death.DeathDate,
	l.leftGMDate
FROM LatestSnapshot dem
LEFT JOIN Death ON Death."GmPseudo" = dem."GmPseudo"
LEFT JOIN leftGMDate l ON l."GmPseudo" = dem."GmPseudo"
WHERE 
    (Death.DeathDate IS NULL OR Death.DeathDate > $StudyStartDate) -- alive on study start date
	AND 
	(leftGMDate IS NULL OR leftGMDate > $StudyEndDate); -- if patient left GM (therefore we stop receiving their data), ensure it is after study end date

-- GET COHORT OF WOMEN 30 - 70 YEARS OLD

DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_09_Thompson";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_09_Thompson" AS 
SELECT DISTINCT "GmPseudo", "FK_Patient_ID" 
FROM AlivePatientsAtStart ap
WHERE DATEDIFF(YEAR, "DateOfBirth",$StudyStartDate) BETWEEN 30 AND 70  -- over 50 in 2016
	AND "Sex" = 'F'
LIMIT 1000; --THIS IS TEMPORARY


-- FOR THE ABOVE COHORT, GET ALL REQUIRED DEMOGRAPHICS


-- ... processing [[create-output-table::"LH009-1_Patients"]] ... 
-- ... Need to create an output table called "LH009-1_Patients" and replace 
-- ... the GmPseudo column with a study-specific random patient id.

-- First we create a table in an area only visible to the RDEs which contains
-- the GmPseudos. THESE CANNOT BE RELEASED TO END USERS.
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH009-1_Patients_WITH_PSEUDO_IDS";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH009-1_Patients_WITH_PSEUDO_IDS" AS
SELECT
	 dem."Snapshot",
	 dem."GmPseudo", 
	 dem."Sex",
	 dem."DateOfBirth" AS "MonthOfBirth", 
	 dem."Age",
	 dem."IMD_Decile",
	 dem."EthnicityLatest_Category",
	 dem."PracticeCode", 
	 dth.DeathDate,
     dth."DiagnosisOriginalMentionCode" AS "ReasonForDeathCode",
     dth."DiagnosisOriginalMentionDesc" AS "ReasonForDeathDesc",
	 dem."BMI",
	 dem."BMI_Date",
	 dem."BMI_Description",
	 dem."AlcoholStatus",
	 dem."Alcohol_Date",
	 dem."AlcoholConsumption",
	 dem."SmokingStatus",
	 dem."Smoking_Date",
	 dem."SmokingConsumption"
FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_09_Thompson"  co
LEFT OUTER JOIN AlivePatientsAtStart dem ON dem."GmPseudo" = co."GmPseudo"
LEFT OUTER JOIN Death dth ON dth."GmPseudo" = co."GmPseudo"
QUALIFY row_number() OVER (PARTITION BY dem."GmPseudo" ORDER BY "Snapshot" DESC) = 1;

-- Then we check to see if there are any new GmPseudo ids. We do this by making a temp table 
-- of all "new" GmPseudo ids. I.e. any GmPseudo ids that we've already got a unique id for
-- for this study are excluded
DROP TABLE IF EXISTS "AllPseudos_SDE_Lighthouse_09_Thompson";
CREATE TEMPORARY TABLE "AllPseudos_SDE_Lighthouse_09_Thompson" AS
SELECT DISTINCT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."LH009-1_Patients_WITH_PSEUDO_IDS"
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
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH009-1_Patients";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH009-1_Patients" AS
SELECT SDE_REPOSITORY.SHARED_UTILITIES.gm_pseudo_hash_SDE_Lighthouse_09_Thompson("GmPseudo") AS "PatientID",
	* EXCLUDE "GmPseudo"
FROM SDE_REPOSITORY.SHARED_UTILITIES."LH009-1_Patients_WITH_PSEUDO_IDS";