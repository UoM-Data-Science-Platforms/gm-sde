USE SCHEMA SDE_REPOSITORY.SHARED_UTILITIES;

--┌────────────────────────────────────┐
--│ LH001 Patient file                 │
--└────────────────────────────────────┘

--┌────────────────────────────────────────────────────────────────────────────────────────────┐
--│ Define Cohort for LH001: patients that had pharmacogenetic testing, and matched controls   │
--└────────────────────────────────────────────────────────────────────────────────────────────┘

-- OBJECTIVE: To build the cohort of patients needed for LH001. This reduces duplication of code in the template scripts.

-- COHORT: Any patient with a pharmacogenetic test, or a matched control.

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

--┌────────────────────────────────────────────────────┐
--│ Cohort matching on year of birth / sex 					   │
--└────────────────────────────────────────────────────┘

-- OBJECTIVE: To take a primary cohort and find a 1:n matched cohort based on year of birth and sex.

-- INPUT: Takes two parameters
--  - yob-flex: integer - number of years each way that still allow a year of birth match
--  - num-matches: integer - number of matches for each patient in the cohort
-- Requires two temp tables to exist as follows:
-- MainCohort (FK_Patient_Link_ID, Sex, YearOfBirth)
-- 	- FK_Patient_Link_ID - unique patient id
--	- Sex - M/F
--	- YearOfBirth - Integer
-- PotentialMatches (FK_Patient_Link_ID, Sex, YearOfBirth)
-- 	- FK_Patient_Link_ID - unique patient id
--	- Sex - M/F
--	- YearOfBirth - Integer

-- OUTPUT: A temp table as follows:
-- #CohortStore (FK_Patient_Link_ID, YearOfBirth, Sex, MatchingPatientId, MatchingYearOfBirth)
--  - FK_Patient_Link_ID - unique patient id for primary cohort patient
--  - YearOfBirth - of the primary cohort patient
--  - Sex - of the primary cohort patient
--  - MatchingPatientId - id of the matched patient
--  - MatchingYearOfBirth - year of birth of the matched patient

-- TODO 
-- A few things to consider when doing matching:
--  - Consider removing "ghost patients" e.g. people without a primary care record
--  - Consider matching on practice. Patients in different locations might have different outcomes. Also
--    for primary care based diagnosing, practices might have different thoughts on severity, timing etc.
--  - For instances where lots of cases have no matches, consider allowing matching to occur with replacement.
--    I.e. a patient can match more than one person in the main cohort.

-- First we extend the PrimaryCohort table to give each age-sex combo a unique number
-- and to avoid polluting the MainCohort table

DROP TABLE IF EXISTS Cases;
CREATE TEMPORARY TABLE Cases AS
SELECT "FK_Patient_ID" AS PatientId, 
	YearOfBirth, 
	Sex, 
	Row_Number() OVER(PARTITION BY YearOfBirth, Sex ORDER BY "FK_Patient_ID") AS CaseRowNumber
FROM MainCohort;

-- Then we do the same with the PotentialMatches table
DROP TABLE IF EXISTS Matches;
CREATE TEMPORARY TABLE Matches AS
SELECT "FK_Patient_ID" AS PatientId, 
	YearOfBirth, 
	Sex, 
	Row_Number() OVER(PARTITION BY YearOfBirth, Sex ORDER BY "FK_Patient_ID") AS AssignedPersonNumber
FROM PotentialMatches;

-- Find the number of people with each characteristic in the main cohort
DROP TABLE IF EXISTS CharacteristicCount;
CREATE TEMPORARY TABLE CharacteristicCount AS
SELECT YearOfBirth, Sex, COUNT(*) AS "Count" 
FROM Cases 
GROUP BY YearOfBirth, Sex;

-- Find the number of potential matches for each Age/Sex combination
-- The output of this is useful for seeing how many matches you can get
-- SELECT A.YearOfBirth, A.Sex, B.Count / A.Count AS NumberOfPotentialMatchesPerCohortPatient FROM (SELECT * FROM #CharacteristicCount) A LEFT OUTER JOIN (SELECT YearOfBirth, Sex, COUNT(*) AS [Count] FROM #Matches GROUP BY YearOfBirth, Sex) B ON B.YearOfBirth = A.YearOfBirth AND B.Sex = A.Sex ORDER BY NumberOfPotentialMatches,A.YearOfBirth,A.Sex;

-- The final table contains a row for each match, so e.g. if patient 1 has 4
-- matches then there will be 4 rows in the table for this.
DROP TABLE IF EXISTS CohortStore;
CREATE TEMPORARY TABLE CohortStore ( 
  PatientId BIGINT, 
  YearOfBirth INT, 
  Sex nchar(1), 
  MatchingPatientId BIGINT,
  MatchingYearOfBirth INT
);

--1. First match try to match people exactly. We do this as follows:
--    - For each YOB/Sex combination we find all potential matches. E.g. all patients
--      in the potential matches with sex='F' and yob=1957
--    - We then try to assign a single match to all cohort members with sex='F' and yob=1957
--    - If there are still matches unused, we then assign a second match to all cohort members
--    - This continues until we either run out of matches, or successfully match everyone with
--      the desired number of matches.

DECLARE 
    counter INT;

BEGIN 
    counter := 1; 
    
    WHILE (counter <= 5) DO 
    
        INSERT INTO CohortStore
          SELECT c.PatientId, c.YearOfBirth, c.Sex, p.PatientId AS MatchedPatientId, c.YearOfBirth
          FROM Cases c
            INNER JOIN CharacteristicCount cc on cc.YearOfBirth = c.YearOfBirth and cc.Sex = c.Sex
            INNER JOIN Matches p 
              ON p.Sex = c.Sex 
              AND p.YearOfBirth = c.YearOfBirth 
              -- This next line is the trick to only matching each person once
              AND p.AssignedPersonNumber = CaseRowNumber + (:counter - 1) * cc."Count";
              
           -- We might not need this, but to be extra sure let's delete any patients who 
           -- we're already using to match people
           DELETE FROM Matches WHERE PatientId IN (SELECT MatchingPatientId FROM CohortStore);
        
        counter := counter + 1; 
        
    END WHILE; 

END; 

--2. Now relax the yob restriction to get extra matches for people with no matches

DECLARE 
    lastrowinsert1 INT;
    CohortStoreRowsAtStart1 INT;

BEGIN 
    lastrowinsert1 := 1; 
    
    WHILE (lastrowinsert1 > 0) DO 
    CohortStoreRowsAtStart1 := (SELECT COUNT(*) FROM CohortStore);
    
		INSERT INTO CohortStore
		SELECT sub.PatientId, sub.YearOfBirth, sub.Sex, MatchedPatientId, MAX(m.YearOfBirth) FROM (
		SELECT c.PatientId, c.YearOfBirth, c.Sex, MAX(p.PatientId) AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(p.PatientId) ORDER BY p.PatientId) AS AssignedPersonNumber
		FROM Cases c
		INNER JOIN Matches p 
			ON p.Sex = c.Sex 
			AND p.YearOfBirth >= c.YearOfBirth - 2
			AND p.YearOfBirth <= c.YearOfBirth + 2
		WHERE c.PatientId in (
			-- find patients who aren't currently matched
			select PatientId from Cases except select PatientId from CohortStore
		)
		GROUP BY c.PatientId, c.YearOfBirth, c.Sex, p.PatientId) sub
		INNER JOIN Matches m 
			ON m.Sex = sub.Sex 
			AND m.PatientId = sub.MatchedPatientId
			AND m.YearOfBirth >= sub.YearOfBirth - 2
			AND m.YearOfBirth <= sub.YearOfBirth + 2
		WHERE sub.AssignedPersonNumber = 1
		GROUP BY sub.PatientId, sub.YearOfBirth, sub.Sex, MatchedPatientId;

        lastrowinsert1 := CohortStoreRowsAtStart1 - (SELECT COUNT(*) FROM CohortStore);

		DELETE FROM Matches WHERE PatientId IN (SELECT MatchingPatientId FROM CohortStore);

	END WHILE;

END;

--3. Now relax the yob restriction to get extra matches for people with only 1, 2, 3, ... n-1 matches

DECLARE
    Counter2 INT;
    CohortStoreRowsAtStart INT;
    LastRowInsert INT;

BEGIN
    Counter2 := 1;

    WHILE (Counter2 < 5) DO
            LastRowInsert:= 1;
            
            WHILE (LastRowInsert > 0) DO
            CohortStoreRowsAtStart := (SELECT COUNT(*) FROM CohortStore);

                DROP TABLE IF EXISTS CohortPatientForEachMatchingPatient;
                CREATE TEMPORARY TABLE CohortPatientForEachMatchingPatient AS
                SELECT p.PatientId AS MatchedPatientId, c.PatientId, Row_Number() OVER(PARTITION BY p.PatientId ORDER BY p.PatientId) AS MatchedPatientNumber
                FROM Matches p
                INNER JOIN Cases c
                  ON p.Sex = c.Sex 
                  AND p.YearOfBirth >= c.YearOfBirth - 2
                  AND p.YearOfBirth <= c.YearOfBirth + 2
                WHERE c.PatientId IN (
                  -- find patients who only have @Counter2 matches
                  SELECT PatientId FROM CohortStore GROUP BY PatientId HAVING count(*) = :Counter2
                );
            
                DROP TABLE IF EXISTS CohortPatientForEachMatchingPatientWithCohortNumbered;
                CREATE TEMPORARY TABLE CohortPatientForEachMatchingPatientWithCohortNumbered AS
                SELECT PatientId, MatchedPatientId, Row_Number() OVER(PARTITION BY PatientId ORDER BY MatchedPatientId) AS PatientNumber
                FROM CohortPatientForEachMatchingPatient
                WHERE MatchedPatientNumber = 1;
                
                INSERT INTO CohortStore
                SELECT s.PatientId, c.YearOfBirth, c.Sex, MatchedPatientId, m.YearOfBirth FROM CohortPatientForEachMatchingPatientWithCohortNumbered s
                LEFT OUTER JOIN Cases c ON c.PatientId = s.PatientId
                LEFT OUTER JOIN Matches m ON m.PatientId = MatchedPatientId
                WHERE PatientNumber = 1;
            
                lastrowinsert := CohortStoreRowsAtStart - (SELECT COUNT(*) FROM CohortStore);
            
                DELETE FROM Matches WHERE PatientId IN (SELECT MatchingPatientId FROM CohortStore);
                
            END WHILE;
  
    Counter2 := Counter2  + 1;
    END WHILE;
END;


-- create permanent cohort table, indicating whether each patient is from the main or the matched cohort

DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_01_Newman";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_01_Newman" AS
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
INNER JOIN SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_01_Newman" c ON c."GmPseudo" = D."GmPseudo"
LEFT JOIN Death dth ON dth."GmPseudo" = D."GmPseudo"
QUALIFY row_number() OVER (PARTITION BY D."GmPseudo" ORDER BY "Snapshot" DESC) = 1; -- this brings back the values from the most recent snapshot

---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
