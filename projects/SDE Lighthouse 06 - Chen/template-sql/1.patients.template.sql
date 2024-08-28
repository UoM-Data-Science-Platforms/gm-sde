--┌──────────────────────────────────────────────┐
--│ SDE Lighthouse study 06 - Patients           │
--└──────────────────────────────────────────────┘

--> EXECUTE query-build-lh006-cohort.sql
	
--- death table to join to later

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

-- create cohort of patients
-- join to demographic table to get ethnicity and date of birth

DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."1_Patients";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."1_Patients" AS
SELECT
	 co."FK_Patient_ID",
	 dem."GmPseudo",
	 dem."Sex",
	 dem."Age",
	 dem."IMD_Decile",
	 dem."EthnicityLatest_Category",
	 dem."PracticeCode", 
	 dth.DeathDate,
	 dem."DateOfBirth", 
	 co.IndexDate
FROM {{cohort-table}}  co
LEFT OUTER JOIN        -- use row_number to filter demographics table to most recent snapshot
	(
	SELECT 
		*, 
		ROW_NUMBER() OVER (PARTITION BY "FK_Patient_ID" ORDER BY "Snapshot" DESC) AS ROWNUM
	FROM PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" p 
	) dem	ON dem."FK_Patient_ID" = co."FK_Patient_ID"
LEFT OUTER JOIN Death dth ON dth."GmPseudo" = dem."GmPseudo"
WHERE dem.ROWNUM = 1