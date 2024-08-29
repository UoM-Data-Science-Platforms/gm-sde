--┌────────────────────────────────────────────────────────────────────────────────────────────┐
--│ Define Cohort for LH001: patients that had pharmacogenetic testing, and matched controls   │
--└────────────────────────────────────────────────────────────────────────────────────────────┘

-- OBJECTIVE: To build the cohort of patients needed for LH001. This reduces duplication of code in the template scripts.

-- COHORT: Any patient with a pharmacogenetic test, or a matched control.

set(StudyStartDate) = to_date('2023-06-01');
set(StudyEndDate)   = to_date('2024-06-30');

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
FROM PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" p 
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

-- create main cohort

DROP TABLE IF EXISTS MainCohort;
CREATE TEMPORARY TABLE MainCohort AS
SELECT DISTINCT
	 "FK_Patient_ID",
	 "GmPseudo",
     "Sex" as Sex,
     YEAR("DateOfBirth") AS YearOfBirth
FROM PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" p
WHERE "FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM AlivePatientsAtStart)
 	--AND "FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM PharmacogenticTable)
GROUP BY  "FK_Patient_ID",
	 "GmPseudo",
     "Sex",
     YEAR("DateOfBirth");

-- create table of potential patients to match to the main cohort

DROP TABLE IF EXISTS PotentialMatches;
CREATE TEMPORARY TABLE PotentialMatches AS
SELECT DISTINCT "FK_Patient_ID", 
		"Sex" as Sex,
		YEAR("DateOfBirth") AS YearOfBirth
FROM PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" p
WHERE "FK_Patient_ID" NOT IN (SELECT "FK_Patient_ID" FROM MainCohort);


-- run matching script with parameters filled in

--> EXECUTE query-cohort-matching-yob-sex-alt-SDE.sql yob-flex:2 num-matches:5

-- create permanent cohort table, indicating whether each patient is from the main or the matched cohort

DROP TABLE IF EXISTS {{cohort-table}};
CREATE TABLE {{cohort-table}} AS
SELECT
	"FK_Patient_ID", 
	"GmPseudo", 
	CASE WHEN D."FK_Patient_ID" IN (select PATIENTID from CohortStore) THEN 'Main'
			WHEN D."FK_Patient_ID" IN (select MATCHINGPATIENTID from CohortStore) THEN 'Matched'
			ELSE 'Check' END AS "Cohort",
	"DateOfBirth",
	row_number() over (partition by D."GmPseudo" order by "Snapshot" desc) rownum
FROM PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" D
WHERE D."FK_Patient_ID" IN (select PATIENTID from CohortStore) OR      -- patients in main cohort
		D."FK_Patient_ID" IN (select MATCHINGPATIENTID from CohortStore)
QUALIFY row_number() OVER (PARTITION BY D."GmPseudo" ORDER BY "Snapshot" DESC) = 1; -- this brings back the values from the most recent snapshot


-------------------------------