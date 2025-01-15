USE SCHEMA SDE_REPOSITORY.SHARED_UTILITIES;

--┌────────────────────────────────────┐
--│ LH004 Patient file                 │
--└────────────────────────────────────┘

-- From application:
--	Data File 1: Patient Demographics
--	- PatientId
--	- Sex
--	- YearOfBirth
--	- Ethnicity
--	- IMDQuartile
--	- SmokerEver
--	- SmokerCurrent
--	- BMI
--	- AlcoholIntake
--	- DateOfSLEdiagnosis
--	- DateOfLupusNephritisDiagnosis
--	- CKDStage
--	- EgfrResult
--	- EgfrDate
--	- CreatinineResult
--	- CreatinineDate
--	- LDLCholesterol
--	- LDLCholesterolDate
--	- HDLCholesterol
--	- HDLCholesterolDate
--	- Triglycerides
--	- TrigylceridesDate 
-- 
--	All values need most recent value

-- smoking, alcohol are based on most recent codes available

-- Data file 7 - mortality - include here
-- From application:
--  DeathDate
--  CauseOfDeath

set(StudyStartDate) = to_date('2024-12-31');
set(StudyEndDate)   = to_date('2024-12-31');


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
	WHERE DATEDIFF(YEAR, TO_DATE("DateOfBirth"), $StudyStartDate) >= 0 -- adults only
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
    case when DeathDate is null and "max" < (select max("max") from PatientSummary) then "max" else null end as "leftGMDate"
from PatientSummary;

-- FIND ALL ADULT PATIENTS ALIVE AT STUDY START DATE

DROP TABLE IF EXISTS AlivePatientsAtStart;
CREATE TEMPORARY TABLE AlivePatientsAtStart AS 
SELECT  
    dem.*, 
    Death."DEATHDATE" AS "DeathDate",
	l."leftGMDate"
FROM LatestSnapshot dem
LEFT JOIN Death ON Death."GmPseudo" = dem."GmPseudo"
LEFT JOIN leftGMDate l ON l."GmPseudo" = dem."GmPseudo"
WHERE 
    (Death."DEATHDATE" IS NULL OR Death."DEATHDATE" > $StudyStartDate) -- alive on study start date
	AND 
	(l."leftGMDate" IS NULL OR l."leftGMDate" > $StudyEndDate); -- if patient left GM (therefore we stop receiving their data), ensure it is after study end date
 

-- Find all patients with SLE
-- >>> Codesets required... Inserting the code set code
-- >>> Codesets extracted into 0.code-sets.sql
-- >>> Following code sets injected: sle v1
DROP TABLE IF EXISTS LH004_SLE_Dx;
CREATE TEMPORARY TABLE LH004_SLE_Dx AS
SELECT "FK_Patient_ID", MIN(CAST("EventDate" AS DATE)) AS "FirstSLEDiagnosis"
FROM INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses"
WHERE "SuppliedCode" IN (SELECT code FROM SDE_REPOSITORY.SHARED_UTILITIES."Code_Sets_SDE_Lighthouse_04_Bruce" WHERE concept = 'sle')
	  AND "FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM AlivePatientsAtStart)
GROUP BY "FK_Patient_ID";

-- Create a temporary cohort table to link gmpseudo with fk_patient_id
-- but also get the other columns required from the demographic table
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_04_Bruce";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_04_Bruce" AS
SELECT
	"GmPseudo",
	lh."FK_Patient_ID",
	"FirstSLEDiagnosis",
	"Sex",
	YEAR("DateOfBirth") AS "YearOfBirth",
	"EthnicityLatest" AS "Ethnicity",
	"EthnicityLatest_Category" AS "EthnicityCategory",
	"IMD_Decile" AS "IMD2019Decile1IsMostDeprived10IsLeastDeprived",
	"SmokingStatus",
	"SmokingConsumption",
	"BMI",
	"BMI_Date" AS "BMIDate",
	"AlcoholStatus",
	"AlcoholConsumption",
FROM PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" demo
INNER JOIN LH004_SLE_Dx lh ON lh."FK_Patient_ID" = demo."FK_Patient_ID"
QUALIFY row_number() OVER (PARTITION BY demo."GmPseudo" ORDER BY "Snapshot" DESC) = 1;


-- Get eGFRs
DROP TABLE IF EXISTS LH004_eGFR;
CREATE TEMPORARY TABLE LH004_eGFR AS
SELECT DISTINCT "GmPseudo", 
    last_value("eGFR") OVER (PARTITION BY "GmPseudo" ORDER BY "EventDate") AS "eGFRValue", 
    last_value(CAST("EventDate" AS DATE)) OVER (PARTITION BY "GmPseudo" ORDER BY "EventDate") AS "eGFRDate"
FROM INTERMEDIATE.GP_RECORD."Readings_eGFR_SecondaryUses"
WHERE "GmPseudo" IN (SELECT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_04_Bruce");

-- Get creatinine
DROP TABLE IF EXISTS LH004_creatinine;
CREATE TEMPORARY TABLE LH004_creatinine AS
SELECT DISTINCT "GmPseudo", 
    last_value("SerumCreatinine") OVER (PARTITION BY "GmPseudo" ORDER BY "EventDate") AS "SerumCreatinineValue", 
    last_value(CAST("EventDate" AS DATE)) OVER (PARTITION BY "GmPseudo" ORDER BY "EventDate") AS "SerumCreatinineDate"
FROM INTERMEDIATE.GP_RECORD."Readings_SerumCreatinine_SecondaryUses"
WHERE "GmPseudo" IN (SELECT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_04_Bruce");

-- Get hdl cholesterol
DROP TABLE IF EXISTS LH004_hdl;
CREATE TEMPORARY TABLE LH004_hdl AS
SELECT DISTINCT "GmPseudo", 
    last_value("HDL") OVER (PARTITION BY "GmPseudo" ORDER BY "EventDate") AS "HDLValue", 
    last_value(CAST("EventDate" AS DATE)) OVER (PARTITION BY "GmPseudo" ORDER BY "EventDate") AS "HDLDate"
FROM INTERMEDIATE.GP_RECORD."Readings_Cholesterol_SecondaryUses"
WHERE "GmPseudo" IN (SELECT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_04_Bruce")
AND "HDL" IS NOT NULL;

-- Get ldl cholesterol
DROP TABLE IF EXISTS LH004_ldl;
CREATE TEMPORARY TABLE LH004_ldl AS
SELECT DISTINCT "GmPseudo", 
    last_value("LDL") OVER (PARTITION BY "GmPseudo" ORDER BY "EventDate") AS "LDLValue", 
    last_value(CAST("EventDate" AS DATE)) OVER (PARTITION BY "GmPseudo" ORDER BY "EventDate") AS "LDLDate"
FROM INTERMEDIATE.GP_RECORD."Readings_Cholesterol_SecondaryUses"
WHERE "GmPseudo" IN (SELECT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_04_Bruce")
AND "LDL" IS NOT NULL;

-- Get triglycerides
DROP TABLE IF EXISTS LH004_triglycerides;
CREATE TEMPORARY TABLE LH004_triglycerides AS
SELECT DISTINCT "GmPseudo", 
    last_value("Triglycerides") OVER (PARTITION BY "GmPseudo" ORDER BY "EventDate") AS "TriglyceridesValue", 
    last_value(CAST("EventDate" AS DATE)) OVER (PARTITION BY "GmPseudo" ORDER BY "EventDate") AS "TriglyceridesDate"
FROM INTERMEDIATE.GP_RECORD."Readings_Cholesterol_SecondaryUses"
WHERE "GmPseudo" IN (SELECT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_04_Bruce")
AND "Triglycerides" IS NOT NULL;

-- Create a temp table of all SuppliedCodes required to get
-- the next several queries in order to make them a lot faster.
DROP TABLE IF EXISTS LH004_cohort_codes;
CREATE TEMPORARY TABLE LH004_cohort_codes AS
SELECT "FK_Patient_ID", "SuppliedCode", CAST("EventDate" AS DATE) AS "EventDate"
FROM INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses"
WHERE "SuppliedCode" IN (SELECT code FROM SDE_REPOSITORY.SHARED_UTILITIES."Code_Sets_SDE_Lighthouse_04_Bruce" WHERE concept in ('lupus-nephritis','ckd-stage-1','ckd-stage-2','ckd-stage-3','ckd-stage-4','ckd-stage-5'))
AND "FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_04_Bruce");

-- Get Lupus neprhitis
-- >>> Following code sets injected: lupus-nephritis v1
DROP TABLE IF EXISTS LH004_lupus_nephritis;
CREATE TEMPORARY TABLE LH004_lupus_nephritis AS
SELECT "FK_Patient_ID", MIN("EventDate") AS "FirstLupusNephritisDiagnosis"
FROM LH004_cohort_codes
WHERE "SuppliedCode" IN (SELECT code FROM SDE_REPOSITORY.SHARED_UTILITIES."Code_Sets_SDE_Lighthouse_04_Bruce" WHERE concept = 'lupus-nephritis')
GROUP BY "FK_Patient_ID";

-- >>> Following code sets injected: ckd-stage-1 v1
DROP TABLE IF EXISTS LH004_ckd_1;
CREATE TEMPORARY TABLE LH004_ckd_1 AS
SELECT "FK_Patient_ID", MIN("EventDate") AS "FirstCKD1Diagnosis"
FROM LH004_cohort_codes
WHERE "SuppliedCode" IN (SELECT code FROM SDE_REPOSITORY.SHARED_UTILITIES."Code_Sets_SDE_Lighthouse_04_Bruce" WHERE concept = 'ckd-stage-1')
GROUP BY "FK_Patient_ID";

-- >>> Following code sets injected: ckd-stage-2 v1
DROP TABLE IF EXISTS LH004_ckd_2;
CREATE TEMPORARY TABLE LH004_ckd_2 AS
SELECT "FK_Patient_ID", MIN("EventDate") AS "FirstCKD2Diagnosis"
FROM LH004_cohort_codes
WHERE "SuppliedCode" IN (SELECT code FROM SDE_REPOSITORY.SHARED_UTILITIES."Code_Sets_SDE_Lighthouse_04_Bruce" WHERE concept = 'ckd-stage-2')
GROUP BY "FK_Patient_ID";

-- >>> Following code sets injected: ckd-stage-3 v1
DROP TABLE IF EXISTS LH004_ckd_3;
CREATE TEMPORARY TABLE LH004_ckd_3 AS
SELECT "FK_Patient_ID", MIN("EventDate") AS "FirstCKD3Diagnosis"
FROM LH004_cohort_codes
WHERE "SuppliedCode" IN (SELECT code FROM SDE_REPOSITORY.SHARED_UTILITIES."Code_Sets_SDE_Lighthouse_04_Bruce" WHERE concept = 'ckd-stage-3')
GROUP BY "FK_Patient_ID";

-- >>> Following code sets injected: ckd-stage-4 v1
DROP TABLE IF EXISTS LH004_ckd_4;
CREATE TEMPORARY TABLE LH004_ckd_4 AS
SELECT "FK_Patient_ID", MIN("EventDate") AS "FirstCKD4Diagnosis"
FROM LH004_cohort_codes
WHERE "SuppliedCode" IN (SELECT code FROM SDE_REPOSITORY.SHARED_UTILITIES."Code_Sets_SDE_Lighthouse_04_Bruce" WHERE concept = 'ckd-stage-4')
GROUP BY "FK_Patient_ID";

-- >>> Following code sets injected: ckd-stage-5 v1
DROP TABLE IF EXISTS LH004_ckd_5;
CREATE TEMPORARY TABLE LH004_ckd_5 AS
SELECT "FK_Patient_ID", MIN("EventDate") AS "FirstCKD5Diagnosis"
FROM LH004_cohort_codes
WHERE "SuppliedCode" IN (SELECT code FROM SDE_REPOSITORY.SHARED_UTILITIES."Code_Sets_SDE_Lighthouse_04_Bruce" WHERE concept = 'ckd-stage-5')
GROUP BY "FK_Patient_ID";


-- ... processing [[create-output-table::"LH004-1_Patients"]] ... 
-- ... Need to create an output table called "LH004-1_Patients" and replace 
-- ... the GmPseudo column with a study-specific random patient id.

-- First we create a table in an area only visible to the RDEs which contains
-- the GmPseudos. THESE CANNOT BE RELEASED TO END USERS.
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH004-1_Patients_WITH_IDENTIFIER";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH004-1_Patients_WITH_IDENTIFIER" AS
SELECT
	sle."GmPseudo",
	sle."Sex",
	sle."YearOfBirth",
	sle."Ethnicity",
	sle."EthnicityCategory",
	sle."IMD2019Decile1IsMostDeprived10IsLeastDeprived",
	sle."SmokingStatus",
	sle."SmokingConsumption",
	sle."BMI",
	sle."BMIDate",
	sle."AlcoholStatus",
	sle."AlcoholConsumption",
	"FirstSLEDiagnosis",
	"FirstLupusNephritisDiagnosis",
	"FirstCKD1Diagnosis",
	"FirstCKD2Diagnosis",
	"FirstCKD3Diagnosis",
	"FirstCKD4Diagnosis",
	"FirstCKD5Diagnosis",
	"eGFRValue", 
	"eGFRDate",
	"SerumCreatinineValue", 
	"SerumCreatinineDate",
	"HDLValue", 
	"HDLDate",
	"LDLValue", 
	"LDLDate",
	"TriglyceridesValue", 
	"TriglyceridesDate",
	mortality."RegisteredDateOfDeath",
  mortality."DiagnosisUnderlyingCode" AS "DiagnosisUnderlyingICD10Code",
  mortality."DiagnosisUnderlyingDesc"
FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_04_Bruce" sle
    LEFT OUTER JOIN LH004_eGFR egfr ON egfr."GmPseudo" = sle."GmPseudo"
    LEFT OUTER JOIN LH004_creatinine creat ON creat."GmPseudo" = sle."GmPseudo"
    LEFT OUTER JOIN LH004_hdl hdl ON hdl."GmPseudo" = sle."GmPseudo"
    LEFT OUTER JOIN LH004_ldl ldl ON ldl."GmPseudo" = sle."GmPseudo"
    LEFT OUTER JOIN LH004_triglycerides triglycerides ON triglycerides."GmPseudo" = sle."GmPseudo"
    LEFT OUTER JOIN LH004_lupus_nephritis nephritis ON nephritis."FK_Patient_ID" = sle."FK_Patient_ID"
    LEFT OUTER JOIN LH004_ckd_1 ckd1 ON ckd1."FK_Patient_ID" = sle."FK_Patient_ID"
    LEFT OUTER JOIN LH004_ckd_2 ckd2 ON ckd2."FK_Patient_ID" = sle."FK_Patient_ID"
    LEFT OUTER JOIN LH004_ckd_3 ckd3 ON ckd3."FK_Patient_ID" = sle."FK_Patient_ID"
    LEFT OUTER JOIN LH004_ckd_4 ckd4 ON ckd4."FK_Patient_ID" = sle."FK_Patient_ID"
    LEFT OUTER JOIN LH004_ckd_5 ckd5 ON ckd5."FK_Patient_ID" = sle."FK_Patient_ID"
    LEFT OUTER JOIN PRESENTATION.NATIONAL_FLOWS_PCMD."DS1804_Pcmd" mortality ON mortality."GmPseudo" = sle."GmPseudo";

-- Then we check to see if there are any new GmPseudo ids. We do this by making a temp table 
-- of all "new" GmPseudo ids. I.e. any GmPseudo ids that we've already got a unique id for
-- for this study are excluded
DROP TABLE IF EXISTS "AllPseudos_SDE_Lighthouse_04_Bruce";
CREATE TEMPORARY TABLE "AllPseudos_SDE_Lighthouse_04_Bruce" AS
SELECT DISTINCT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."LH004-1_Patients_WITH_IDENTIFIER"
EXCEPT
SELECT "GmPseudo" FROM "Patient_ID_Mapping_SDE_Lighthouse_04_Bruce";

-- Find the highest currently assigned id. Ids are given incrementally, so now ones
-- need to start at +1 of the current highest
SET highestPatientId = (
    SELECT IFNULL(MAX("StudyPatientPseudoId"),0) FROM "Patient_ID_Mapping_SDE_Lighthouse_04_Bruce"
);

-- Make a study specific hash for each new GmPseudo and insert it
-- into the patient lookup table
INSERT INTO "Patient_ID_Mapping_SDE_Lighthouse_04_Bruce"
SELECT
    "GmPseudo", -- the GM SDE patient ids for patients in this cohort
    SHA2(CONCAT('SDE_Lighthouse_04_Bruce', "GmPseudo")) AS "Hash", -- used to provide a random (study-specific) ordering for the patient ids we provide
    $highestPatientId + ROW_NUMBER() OVER (ORDER BY "Hash") -- the patient id that we provide to the analysts
FROM "AllPseudos_SDE_Lighthouse_04_Bruce";

-- Finally, we select from the output table which includes the GmPseudos, in order
-- to populate the table for the end users where the GmPseudo fields are redacted via a function
-- created in the 0.code-sets.sql file
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH004-1_Patients";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH004-1_Patients" AS
SELECT SDE_REPOSITORY.SHARED_UTILITIES.gm_pseudo_hash_SDE_Lighthouse_04_Bruce("GmPseudo") AS "PatientID",
	* EXCLUDE "GmPseudo"
FROM SDE_REPOSITORY.SHARED_UTILITIES."LH004-1_Patients_WITH_IDENTIFIER";