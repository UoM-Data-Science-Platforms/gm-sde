--┌────────────────────────────────────┐
--│ LH010 Patient file                 │
--└────────────────────────────────────┘

-- Cohort: >50s in 2016

set(StudyStartDate) = to_date('2016-01-01');
set(StudyEndDate)   = to_date('2024-08-01');



-- GET ALL PATIENTS THAT HAD A LUNG HEALTH CHECK - FROM THE LINKED MFT DATA

---------------------------------------------



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

DROP TABLE IF EXISTS LatestSnapshotAdults;
CREATE TEMPORARY TABLE LatestSnapshotAdults AS
SELECT 
    p.*
FROM INTERMEDIATE.GP_RECORD."DemographicsProtectedCharacteristics" p 
INNER JOIN (
    SELECT "GmPseudo", MAX("Snapshot") AS LatestSnapshot
    FROM INTERMEDIATE.GP_RECORD."DemographicsProtectedCharacteristics" p 
    WHERE DATEDIFF(YEAR, TO_DATE("DateOfBirth"), $StudyStartDate) >= 50 -- over 50s only at study start date
    GROUP BY "GmPseudo"
    ) t2
ON t2."GmPseudo" = p."GmPseudo" AND t2.LatestSnapshot = p."Snapshot";

-- FIND ALL ADULT OVER 50s ALIVE AT STUDY START DATE

DROP TABLE IF EXISTS AliveAdultsAtStart;
CREATE TEMPORARY TABLE AliveAdultsAtStart AS 
SELECT  
    dem.*, 
    Death.DeathDate
FROM LatestSnapshotAdults dem
LEFT JOIN Death ON Death."GmPseudo" = dem."GmPseudo"
WHERE 
    (DeathDate IS NULL OR DeathDate > $StudyStartDate); -- alive on study start date


-- GET COHORT OF PATIENTS THAT HAD A LUNG HEALTH CHECK

DROP TABLE IF EXISTS {{cohort-table}};
CREATE TABLE {{cohort-table}} AS 
SELECT "GmPseudo", "FK_Patient_ID" 
FROM LatestSnapshotAdults
LEFT OUTER JOIN **LUNGHEALTHCHECKTABLE**



-- PERSONAL HISTORY OF CANCER - TO JOIN TO LATER
-- THIS CODE INCLUDES ANY PATIENT IF THEY HAVE EVER HAD A SNAPSHOT INDICATING CANCER

DROP TABLE IF EXISTS PersonalHistoryCancer;
CREATE TEMPORARY TABLE PersonalHistoryCancer AS 
SELECT DISTINCT ltc."GmPseudo", "FK_Patient_ID"
FROM LongTermConditionRegister_SecondaryUses ltc
WHERE ("Cancer_QOF" is not null or "Cancer_DiagnosisDate" is not null or "Cancer_DiagnosisAge" is not null or "Cancer_QOF_DiagnosedL5Y" is not null)
	AND "GmPseudo" IN {{cohort-table}}


-- FOR THE ABOVE COHORT, GET ALL REQUIRED DEMOGRAPHICS

{{create-output-table::"1_Patients"}}
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
	 dem."Frailty", -- 92% missingness
	 dem."BMI",
	 dem."BMI_Date",
	 dem."BMI_Description",
	 CASE WHEN phc."GmPseudo" IS NOT NULL THEN 1 ELSE 0 END AS 'PersonalHistoryOfCancer',
	 -- TODO: family history of lung cancer
	 dem."AlcoholStatus",
	 dem."Alcohol_Date",
	 dem."AlcoholConsumption",
	 -- TODO: drug history: COPD meds, statins 
	 dem."SmokingStatus",
	 dem."Smoking_Date",
	 dem."SmokingConsumption"
FROM {{cohort-table}}  co
LEFT OUTER JOIN PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" dem ON dem."GmPseudo" = co."GmPseudo"
LEFT OUTER JOIN Death dth ON dth."GmPseudo" = co."GmPseudo"
LEFT OUTER JOIN PersonalHistoryCancer phc ON phc."GmPseudo" = co."GmPseudo"
QUALIFY row_number() OVER (PARTITION BY dem."GmPseudo" ORDER BY "Snapshot" DESC) = 1;