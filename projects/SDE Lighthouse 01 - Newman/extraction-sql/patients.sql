--┌────────────────────────────────────┐
--│ LH001 Patient file                 │
--└────────────────────────────────────┘

--┌────────────────────────────────────────────────────────────────────────────────────────────┐
--│ Define Cohort for LH001: patients that had pharmacogenetic testing, and matched controls   │
--└────────────────────────────────────────────────────────────────────────────────────────────┘

-- OBJECTIVE: To build the cohort of patients needed for LH001. This reduces duplication of code in the template scripts.

-- COHORT: Any patient with a pharmacogenetic test, or a matched control.

-- OUTPUT: Temp tables as follows:
-- Cohort


USE INTERMEDIATE.GP_RECORD;

set(StudyStartDate) = to_date('2023-06-01');
set(StudyEndDate)   = to_date('2024-06-30');

--ALL DEATHS 

DROP TABLE IF EXISTS Death;
CREATE TEMPORARY TABLE Death AS
SELECT 
    DEATH."GmPseudo",
    TO_DATE(DEATH."RegisteredDateOfDeath") AS DeathDate
FROM PRESENTATION.NATIONAL_FLOWS_PCMD."DS1804_Pcmd" DEATH;

-- GET LATEST SNAPSHOT OF DEMOGRAPHICS TABLE

DROP TABLE IF EXISTS LatestSnapshotAdults;
CREATE TEMPORARY TABLE LatestSnapshotAdults AS
SELECT 
    p.*
FROM INTERMEDIATE.GP_RECORD."DemographicsProtectedCharacteristics" p 
INNER JOIN (
    SELECT "GmPseudo", MAX("Snapshot") AS LatestSnapshot
    FROM INTERMEDIATE.GP_RECORD."DemographicsProtectedCharacteristics" p 
    WHERE DATEDIFF(YEAR, TO_DATE("DateOfBirth"), $StudyStartDate) >= 18 -- adults only
    GROUP BY "GmPseudo"
    ) t2
ON t2."GmPseudo" = p."GmPseudo" AND t2.LatestSnapshot = p."Snapshot";

-- FIND ALL ADULT PATIENTS ALIVE AT STUDY START DATE

DROP TABLE IF EXISTS AlivePatientsAtStart;
CREATE TEMPORARY TABLE AlivePatientsAtStart AS 
SELECT  
    dem.*, 
    Death.DeathDate
FROM LatestSnapshotAdults dem
LEFT JOIN Death ON Death."GmPseudo" = dem."GmPseudo"
WHERE 
    (DeathDate IS NULL OR DeathDate > $StudyStartDate); -- alive on study start date



-- table of pharmacogenetic test patients

------


DROP TABLE IF EXISTS Cohort;
CREATE TEMPORARY TABLE AS
SELECT DISTINCT 
	 "FK_Patient_ID",
	 "GmPseudo"
INTO Cohort
FROM Pharmacogenetic p



---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------


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
WHERE "GmPseudo" IN (SELECT "GmPseudo" FROM Cohort);

-- patient demographics table

--DROP TABLE IF EXISTS Patients;
--CREATE TEMPORARY TABLE Patients AS 
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
	"IMD_Decile", 
	"Age", 
	"Sex", 
	"EthnicityLatest_Category", 
	"PracticeCode", -- need to anonymise
	"Frailty" -- 92% missingness
	row_number() over (partition by D."GmPseudo" order by "Snapshot" desc) rownum
FROM PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" D
LEFT JOIN Death dth ON dth."GmPseudo" = D."GmPseudo"
WHERE D."GmPseudo" IN (select "GmPseudo" from Cohort) -- patients in pharmacogenetic cohort
)
WHERE rownum = 1; -- get latest demographic snapshot only

---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
-- 