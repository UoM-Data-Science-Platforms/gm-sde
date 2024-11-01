USE SCHEMA SDE_REPOSITORY.SHARED_UTILITIES;

--┌──────────────────────────────────────────────┐
--│ SDE Lighthouse study 06 - Patients           │
--└──────────────────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK ------------
-- Richard Williams	2024-08-30	Review complete --
--------------------------------------------------

--┌───────────────────────────────────────────────────────────────────────────┐
--│ Define Cohort for LH006: patients that had multiple opioid prescriptions  │
--└───────────────────────────────────────────────────────────────────────────┘

-- OBJECTIVE: To build the cohort of patients needed for LH006. This reduces duplication of code in the template scripts.

-- COHORT: Any adult patient with non-chronic cancer pain, who received more than two oral or transdermal opioid prescriptions
--          for 14 days within 90 days, between 2017 and 2023.
--          Excluding patients with a cancer diagnosis within 12 months from index date
--			Opioids should exclude the main addiction substitutes

-- INPUT: none
-- OUTPUT: Temp tables as follows:
-- Cohort

set(StudyStartDate) = to_date('2017-01-01');
set(StudyEndDate)   = to_date('2024-10-31');

-- >>> Codesets required... Inserting the code set code
-- >>> Codesets extracted into 0.code-sets.sql
-- >>> Following code sets injected: chronic-pain v1/cancer v1


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

-- find patients with chronic pain

DROP TABLE IF EXISTS chronic_pain;
CREATE TEMPORARY TABLE chronic_pain AS
SELECT "FK_Patient_ID", to_date("Date") AS "EventDate"
FROM  INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" e
WHERE "SuppliedCode" IN (SELECT code FROM SDE_REPOSITORY.SHARED_UTILITIES."Code_Sets_SDE_Lighthouse_06_Chen" WHERE concept = 'chronic-pain' AND Version = 1) 
AND "Date" BETWEEN $StudyStartDate and $StudyEndDate
AND "FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM AliveAdultsAtStart); -- only include alive patients at study start

-- find first chronic pain code in the study period 
DROP TABLE IF EXISTS FirstPain;
CREATE TEMPORARY TABLE FirstPain AS
SELECT 
	"FK_Patient_ID", 
	MIN(TO_DATE("EventDate")) AS FirstPainCodeDate
FROM chronic_pain
GROUP BY "FK_Patient_ID";

-- find patients with a cancer code within 12 months either side of first chronic pain code
-- to exclude in next step

DROP TABLE IF EXISTS cancer;
CREATE TEMPORARY TABLE cancer AS
SELECT e."FK_Patient_ID", to_date("Date") AS "EventDate"
FROM  INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" e
INNER JOIN FirstPain fp ON fp."FK_Patient_ID" = e."FK_Patient_ID" 
				AND e."Date" BETWEEN DATEADD(year, 1, FirstPainCodeDate) AND DATEADD(year, -1, FirstPainCodeDate)
WHERE "SuppliedCode" IN (SELECT code FROM SDE_REPOSITORY.SHARED_UTILITIES."Code_Sets_SDE_Lighthouse_06_Chen" WHERE concept = 'cancer' AND Version = 1)
AND e."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM chronic_pain) --only look in patients with chronic pain
AND e."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM AliveAdultsAtStart); -- only include alive patients at study start 


-- find patients in the chronic pain cohort who received more than 2 opioids
-- for 14 days, within a 90 day period, after their first chronic pain code
-- excluding those with cancer code close to first pain code 

-- first get all opioid prescriptions for the cohort

DROP TABLE IF EXISTS OpioidPrescriptions;
CREATE TEMPORARY TABLE OpioidPrescriptions AS
SELECT 
    ec."FK_Patient_ID"
    , TO_DATE(ec."Date") AS "MedicationDate"
    , ec."SCTID" AS "SnomedCode"
    , ec."Units"
    , ec."Dosage"
    , ec."Dosage_GP_Medications"
    , ec."MedicationDescription" AS "Description"
	, fp.FirstPainCodeDate
	, TO_DATE(Lag(ec."Date", 1) OVER 
		(PARTITION BY ec."FK_Patient_ID" ORDER BY "Date" ASC)) AS "PreviousOpioidDate"
FROM INTERMEDIATE.GP_RECORD."Combined_EventsMedications_Clusters_SecondaryUses" ec
INNER JOIN FirstPain fp ON fp."FK_Patient_ID" = ec."FK_Patient_ID" 
WHERE 
	"Cluster_ID" in ('OPIOIDDRUG_COD') 									-- opioids only (excluding heroin substitutes)
	AND TO_DATE(ec."Date") > fp.FirstPainCodeDate				-- only prescriptions after the patients first pain code
	AND ec."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM chronic_pain) -- chronic pain patients only 
	AND ec."FK_Patient_ID" NOT IN (SELECT "FK_Patient_ID" FROM cancer)  -- exclude cancer patients
	AND TO_DATE(ec."Date") BETWEEN $StudyStartDate and $StudyEndDate;    -- only looking at opioid prescriptions in the study period;

-- find all patients that have had two prescriptions within 90 days, and calculate the index date as
-- the first prescription that meets the criteria

DROP TABLE IF EXISTS IndexDates;
CREATE TEMPORARY TABLE IndexDates AS
SELECT "FK_Patient_ID", 
	MIN(TO_DATE("PreviousOpioidDate")) AS IndexDate 
FROM OpioidPrescriptions
WHERE DATEDIFF(dd, "PreviousOpioidDate", "MedicationDate") <= 90
GROUP BY "FK_Patient_ID";

-- create cohort of patients, join to demographics table to get GmPseudo

DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_06_Chen";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_06_Chen" AS
SELECT DISTINCT
	 i."FK_Patient_ID",
     dem."GmPseudo",
	 i.IndexDate
FROM IndexDates i
LEFT JOIN -- join to demographics table to get GmPseudo
    (SELECT DISTINCT "FK_Patient_ID", "GmPseudo"
     FROM PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses"
    ) dem ON dem."FK_Patient_ID" = i."FK_Patient_ID";

-- create cohort of patients
-- join to demographic table to get ethnicity and date of birth


-- ... processing [[create-output-table::"LH006-1_Patients"]] ... 
-- ... Need to create an output table called "LH006-1_Patients" and replace 
-- ... the GmPseudo column with a study-specific random patient id.

-- First we create a table in an area only visible to the RDEs which contains
-- the GmPseudos. THESE CANNOT BE RELEASED TO END USERS.
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH006-1_Patients_WITH_PSEUDO_IDS";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH006-1_Patients_WITH_PSEUDO_IDS" AS
SELECT
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
	 co.IndexDate
FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_06_Chen"  co
LEFT OUTER JOIN PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" dem ON dem."GmPseudo" = co."GmPseudo"
LEFT OUTER JOIN Death dth ON dth."GmPseudo" = co."GmPseudo"
QUALIFY row_number() OVER (PARTITION BY dem."GmPseudo" ORDER BY "Snapshot" DESC) = 1;

-- Then we check to see if there are any new GmPseudo ids. We do this by making a temp table 
-- of all "new" GmPseudo ids. I.e. any GmPseudo ids that we've already got a unique id for
-- for this study are excluded
DROP TABLE IF EXISTS "AllPseudos_SDE_Lighthouse_06_Chen";
CREATE TEMPORARY TABLE "AllPseudos_SDE_Lighthouse_06_Chen" AS
SELECT DISTINCT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."LH006-1_Patients_WITH_PSEUDO_IDS"
EXCEPT
SELECT "GmPseudo" FROM "Patient_ID_Mapping_SDE_Lighthouse_06_Chen";

-- Find the highest currently assigned id. Ids are given incrementally, so now ones
-- need to start at +1 of the current highest
SET highestPatientId = (
    SELECT IFNULL(MAX("StudyPatientPseudoId"),0) FROM "Patient_ID_Mapping_SDE_Lighthouse_06_Chen"
);

-- Make a study specific hash for each new GmPseudo and insert it
-- into the patient lookup table
INSERT INTO "Patient_ID_Mapping_SDE_Lighthouse_06_Chen"
SELECT
    "GmPseudo", -- the GM SDE patient ids for patients in this cohort
    SHA2(CONCAT('SDE_Lighthouse_06_Chen', "GmPseudo")) AS "Hash", -- used to provide a random (study-specific) ordering for the patient ids we provide
    $highestPatientId + ROW_NUMBER() OVER (ORDER BY "Hash") -- the patient id that we provide to the analysts
FROM "AllPseudos_SDE_Lighthouse_06_Chen";

-- Finally, we select from the output table which includes the GmPseudos, in order
-- to populate the table for the end users where the GmPseudo fields are redacted via a function
-- created in the 0.code-sets.sql file
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH006-1_Patients";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH006-1_Patients" AS
SELECT SDE_REPOSITORY.SHARED_UTILITIES.gm_pseudo_hash_SDE_Lighthouse_06_Chen("GmPseudo") AS "PatientID",
	* EXCLUDE "GmPseudo"
FROM SDE_REPOSITORY.SHARED_UTILITIES."LH006-1_Patients_WITH_PSEUDO_IDS";