--┌────────────────────────────────────┐
--│ LH014 Patient file                 │
--└────────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK ---------
-- Richard Williams	2024-08-09	Review complete

-- *** this file gets extra patient demographics from the GP record for about 85% of the patients in the VW data.
-- Some patients are missing for a couple of reasons:
-- 1. opted out of sharing GP record info
-- 2. Their GP practice has not signed up to sharing info
-- 3. Different inclusion criterias between the VW dataset and the GP data

-- For patients that don't appear in demographics table, basic demographics can be taken from VW table.
-- Information in this file will be based on the latest snapshot available, so may be conflicting with information 
-- from the VW table which was based on time of activity.

set(StudyStartDate) = to_date('2018-01-01');
set(StudyEndDate)   = to_date('2024-06-30');

---- find the latest snapshot for each spell, to get all virtual ward patients

DROP TABLE IF EXISTS {{cohort-table}};
CREATE TABLE {{cohort-table}} AS
SELECT  
	DISTINCT SUBSTRING(vw."Pseudo NHS Number", 2)::INT AS "GmPseudo"
FROM PRESENTATION.LOCAL_FLOWS_VIRTUAL_WARDS.VIRTUAL_WARD_OCCUPANCY vw
WHERE TO_DATE(vw."Admission Date") BETWEEN $StudyStartDate AND $StudyEndDate;


-- deaths table

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
        ON OM."XSeqNo" = DEATH."XSeqNo" AND OM."DiagnosisOriginalMentionNumber" = 1
WHERE "GmPseudo" IN (SELECT "GmPseudo" FROM {{cohort-table}});
--2,195

-- patient demographics table

DROP TABLE IF EXISTS {{project-schema}}."1_Patients";
CREATE TABLE {{project-schema}}."1_Patients" AS
SELECT *
FROM (
SELECT 
	"Snapshot", 
	D."GmPseudo", -- NEEDS PSEUDONYMISING
	"DateOfBirth",
	DATE_TRUNC(month, dth.DeathDate) AS "DeathDate",
	"DiagnosisOriginalMentionCode" AS "CauseOfDeathCode",
	"DiagnosisOriginalMentionDesc" AS "CauseOfDeathDesc",
	"DiagnosisOriginalMentionChapterCode" AS "CauseOfDeathChapterCode",
    "DiagnosisOriginalMentionChapterDesc" AS "CauseOfDeathChapterDesc",
    "DiagnosisOriginalMentionCategory1Code" AS "CauseOfDeathCategoryCode",
    "DiagnosisOriginalMentionCategory1Desc" AS "CauseOfDeathCategoryDesc",
	LSOA11, 
	"IMD_Decile", 
	"Age", 
	"Sex", 
	"EthnicityLatest_Category", 
	"MarriageCivilPartership"
FROM {{cohort-table}} co
LEFT JOIN PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" D ON co."GmPseudo" = D."GmPseudo"
LEFT JOIN Death dth ON dth."GmPseudo" = D."GmPseudo"
QUALIFY row_number() OVER (PARTITION BY D."GmPseudo" ORDER BY "Snapshot" DESC) = 1 -- this brings back the values from the most recent snapshot
);

---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
--13.5k rows