--┌────────────────────────────────────┐
--│ LH014 Patient file                 │
--└────────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK ---------
-- Richard Williams	2024-08-09	Review complete

-- around 2.5k patients don't have a record in the demographics table, and therefore aren't included in the data provided, because we don't know their opt-out status.
-- potential reasons for patients not appearing in the demographics table:

-- 1. opted out of sharing GP record info
-- 2. Their GP practice has not signed up to sharing info
-- 3. Discrepancies between snapshot dates in the VW dataset and the GP data when patients move practices


 -- need to load a codeset for the pipeline to work so loading an example one

-- CODESET allergy-ace:1      


set(StudyStartDate) = to_date('2018-01-01');
set(StudyEndDate)   = to_date('2024-11-31');

---- find the latest snapshot for each spell, to get all virtual ward patients

DROP TABLE IF EXISTS {{cohort-table}};
CREATE TABLE {{cohort-table}} AS
SELECT  
	DISTINCT SUBSTRING(vw."Pseudo NHS Number", 2)::INT AS "GmPseudo"
FROM PRESENTATION.LOCAL_FLOWS_VIRTUAL_WARDS.VIRTUAL_WARD_OCCUPANCY vw
WHERE SUBSTRING(vw."Pseudo NHS Number", 2)::INT IN (SELECT "GmPseudo" FROM  PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses") -- limit to GM GP registered patients (which applies opt out)
AND TO_DATE(vw."Admission Date") BETWEEN $StudyStartDate AND $StudyEndDate;


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

{{create-output-table::"LH014-1_Patients"}}
SELECT *
FROM (
SELECT 
	"Snapshot", 
	D."GmPseudo", 
	"DateOfBirth" AS "YearAndMonthOfBirth",
	DATE_TRUNC(month, dth.DeathDate) AS "YearAndMonthOfDeath",
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
--20.3k rows
