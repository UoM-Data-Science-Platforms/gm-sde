--┌────────────────────────────────────┐
--│ LH004 Patient file                 │
--└────────────────────────────────────┘


-- create cohort of patients who have been on a virtual ward
DROP TABLE IF EXISTS VIRTUAL_WARDS
CREATE TEMPORARY TABLE VIRTUAL_WARDS AS
SELECT DISTINCT "Pseudo NHS Number"
FROM VIRTUAL_WARD_OCCUPANCY;


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
-- WHERE PATIENT IN VIRTUAL_WARDS TBL


-- patient demographics table

DROP TABLE IF EXISTS Patients;
CREATE TEMPORARY TABLE Patients AS 
SELECT * EXCLUDE (rownum)
FROM (
SELECT 
	"Snapshot", 
	D."GmPseudo",
	"FK_Patient_ID", 
	"DateOfBirth",
	DATE_TRUNC(month, dth.DeathDate) AS DeathDate,
	"DiagnosisOriginalMentionCode" AS CauseOfDeathCode,
	"DiagnosisOriginalMentionDesc" AS CauseOfDeathDesc,
	"DiagnosisOriginalMentionChapterCode" AS CauseOfDeathChapterCode,
    "DiagnosisOriginalMentionChapterDesc" AS CauseOfDeathChapterDesc,
    "DiagnosisOriginalMentionCategory1Code" AS CauseOfDeathCategoryCode,
    "DiagnosisOriginalMentionCategory1Desc" AS CauseOfDeathCategoryDesc,
	LSOA11, 
	tow.quintile AS "TownsendQuintile", 
	"Age", 
	"Sex", 
	"EthnicityLatest_Category", 
	"MarriageCivilPartership",
	row_number() over (partition by D."GmPseudo" order by "Snapshot" desc) rownum
FROM INTERMEDIATE.GP_RECORD."DemographicsProtectedCharacteristics" D
LEFT JOIN INTERMEDIATE.GP_RECORD.TOWNSENDSCORE_LSOA_2011 tow on tow.geo_code = D.LSOA11
LEFT JOIN Death dth ON dth."GmPseudo" = D."GmPseudo"
)
WHERE rownum = 1;
-- AND PATIENT IN VIRTUAL_WARDS


---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
