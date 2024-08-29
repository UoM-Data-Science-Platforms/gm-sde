--┌────────────────────────────────────┐
--│ LH001 Patient file                 │
--└────────────────────────────────────┘

--> EXECUTE query-build-lh001-cohort.sql

-- patient demographics table

DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."lh001_1_Patients";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."lh001_1_Patients" AS
SELECT 
	"Snapshot", 
	D."GmPseudo", --- NEEDS PSEUDONYMISING
	D."DateOfBirth",
    c."Cohort",
	dth.DeathDate AS "DeathDate",
	"DiagnosisOriginalMentionCode" AS "CauseOfDeathCode",
	"DiagnosisOriginalMentionDesc" AS "CauseOfDeathDesc",
	"DiagnosisOriginalMentionChapterCode" AS "CauseOfDeathChapterCode",
    "DiagnosisOriginalMentionChapterDesc" AS "CauseOfDeathChapterDesc",
    "DiagnosisOriginalMentionCategory1Code" AS "CauseOfDeathCategoryCode",
    "DiagnosisOriginalMentionCategory1Desc" AS "CauseOfDeathCategoryDesc",
	LSOA11 AS "LSOA11", 
	"IMD_Decile", 
	"Age", 
	"Sex", 
	"EthnicityLatest_Category", 
	"PracticeCode", 
	"Frailty", -- 92% missingness
FROM PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" D
INNER JOIN {{cohort-table}} c ON c."GmPseudo" = D."GmPseudo"
LEFT JOIN Death dth ON dth."GmPseudo" = D."GmPseudo"
QUALIFY row_number() OVER (PARTITION BY D."GmPseudo" ORDER BY "Snapshot" DESC) = 1; -- this brings back the values from the most recent snapshot

---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
