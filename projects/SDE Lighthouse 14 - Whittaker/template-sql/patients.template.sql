--┌────────────────────────────────────┐
--│ LH004 Patient file                 │
--└────────────────────────────────────┘


---- find the latest snapshot for each spell, to get all virtual ward patients
drop table if exists virtualWards;
create temporary table virtualWards as
select  
	distinct SUBSTRING(vw."Pseudo NHS Number", 2)::INT as "GmPseudo"
from PRESENTATION.LOCAL_FLOWS_VIRTUAL_WARDS.VIRTUAL_WARD_OCCUPANCY vw;

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
WHERE "GmPseudo" IN (SELECT "GmPseudo" FROM virtualWards);


-- patient demographics table

DROP TABLE IF EXISTS Patients;
CREATE TEMPORARY TABLE Patients AS 
SELECT * EXCLUDE (rownum)
FROM (
SELECT 
	"Snapshot", 
	D."GmPseudo" AS GmPseudo,
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
WHERE D."GmPseudo" IN (select "GmPseudo" from virtualwards)
)
WHERE rownum = 1;

---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
