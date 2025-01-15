--┌────────────────────────────────────────────────────┐
--│ Cohort matching on year of birth / sex / diagnosis │
--└────────────────────────────────────────────────────┘

-- OBJECTIVE: To take a primary cohort and find a 1:n matched cohort based on year of birth, sex and diagnosis.

-- NOTE: this script is unique to LH015, becasue there are patients in the main cohort
-- with an unknown diagnosis, that we need to match to potential matches with a given diagnosis (we assign them randomly).

-- INPUT: Takes two parameters
--  - yob-flex: integer - number of years each way that still allow a year of birth match
--  - num-matches: integer - number of matches for each patient in the cohort

-- Requires two temp tables to exist as follows:
-- MainCohort (FK_Patient_Link_ID, Sex, YearOfBirth)
-- 	- FK_Patient_Link_ID - unique patient id
--	- Sex - M/F
--	- YearOfBirth - Integer
--  - Diagnosis - varchar
-- PotentialMatches (FK_Patient_Link_ID, Sex, YearOfBirth)
-- 	- FK_Patient_Link_ID - unique patient id
--	- Sex - M/F
--	- YearOfBirth - Integer
--  - Diagnosis - varchar 

-- OUTPUT: A temp table as follows:
-- #CohortStore (FK_Patient_Link_ID, YearOfBirth, Sex, MatchingPatientId, MatchingYearOfBirth)
--  - FK_Patient_Link_ID - unique patient id for primary cohort patient
--  - YearOfBirth - of the primary cohort patient
--  - Sex - of the primary cohort patient
--  - Diagnosis - diagnosis of patient
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
SELECT "GmPseudo" AS PatientId, 
	YearOfBirth, 
	Sex, 
	Diagnosis,
		Row_Number() OVER(PARTITION BY YearOfBirth, Sex, Diagnosis ORDER BY "GmPseudo") AS CaseRowNumber
FROM MainCohort;


-- Then we do the same with the PotentialMatches table
DROP TABLE IF EXISTS Matches;
CREATE TEMPORARY TABLE Matches AS
SELECT "GmPseudo" AS PatientId, 
	YearOfBirth, 
	Sex, 
	Diagnosis,
	Row_Number() OVER(PARTITION BY YearOfBirth, Sex, Diagnosis ORDER BY "GmPseudo") AS AssignedPersonNumber
FROM PotentialMatches;

-- Find the number of people with each characteristic in the main cohort
DROP TABLE IF EXISTS CharacteristicCount;
CREATE TEMPORARY TABLE CharacteristicCount AS
SELECT YearOfBirth, Sex, Diagnosis, COUNT(*) AS "Count" 
FROM Cases 
GROUP BY YearOfBirth, Sex, Diagnosis;


-- The final table contains a row for each match, so e.g. if patient 1 has 4
-- matches then there will be 4 rows in the table for this.
DROP TABLE IF EXISTS CohortStore;
CREATE TEMPORARY TABLE CohortStore ( 
  PatientId BIGINT, 
  YearOfBirth INT, 
  Sex nchar(1), 
  Diagnosis varchar(50),
  MatchingPatientId BIGINT,
  MatchingYearOfBirth INT
);

--1. First match try to match people exactly. We do this as follows:
--    - For each YOB/Sex/Diagnosis combination we find all potential matches. E.g. all patients
--    - in the potential matches with sex='F' and yob=1957 and Diagnosis = 'White British'
--    - We then try to assign a single match to all cohort members with sex='F' and yob=1957 and
--    - Diagnosis = 'White British'. If there are still matches unused, we then assign
--    - a second match to all cohort members. This continues until we either run out of matches,
--    - or successfully match everyone with the desired number of matches.

DECLARE 
    counter INT;

BEGIN 
    counter := 1; 
    
    WHILE (counter <= {param:num-matches}) DO 
    
        INSERT INTO CohortStore
          SELECT c.PatientId, c.YearOfBirth, c.Sex, c.Diagnosis, p.PatientId AS MatchedPatientId, c.YearOfBirth
          FROM Cases c
            INNER JOIN CharacteristicCount cc on cc.YearOfBirth = c.YearOfBirth and cc.Sex = c.Sex and cc.Diagnosis = c.Diagnosis
            INNER JOIN Matches p 
              ON p.Sex = c.Sex 
              AND p.YearOfBirth = c.YearOfBirth 
			  AND p.Diagnosis = c.Diagnosis
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
		SELECT sub.PatientId, sub.YearOfBirth, sub.Sex, sub.Diagnosis, MatchedPatientId, MAX(m.YearOfBirth) FROM (
		SELECT c.PatientId, c.YearOfBirth, c.Sex, c.Diagnosis, MAX(p.PatientId) AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(p.PatientId) ORDER BY p.PatientId) AS AssignedPersonNumber
		FROM Cases c
		INNER JOIN Matches p 
			ON p.Sex = c.Sex 
			AND p.Diagnosis = c.Diagnosis 
			AND p.YearOfBirth >= c.YearOfBirth - {param:yob-flex}
			AND p.YearOfBirth <= c.YearOfBirth + {param:yob-flex}
		WHERE c.PatientId in (
			-- find patients who aren't currently matched
			select PatientId from Cases except select PatientId from CohortStore
		)
		GROUP BY c.PatientId, c.YearOfBirth, c.Sex, c.Diagnosis, p.PatientId) sub
		INNER JOIN Matches m 
			ON m.Sex = sub.Sex 
			AND m.Diagnosis = sub.Diagnosis 
			AND m.PatientId = sub.MatchedPatientId
			AND m.YearOfBirth >= sub.YearOfBirth - {param:yob-flex}
			AND m.YearOfBirth <= sub.YearOfBirth + {param:yob-flex}
		WHERE sub.AssignedPersonNumber = 1
		GROUP BY sub.PatientId, sub.YearOfBirth, sub.Sex, sub.Diagnosis, MatchedPatientId;

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

    WHILE (Counter2 < {param:num-matches}) DO
            LastRowInsert:= 1;
            
            WHILE (LastRowInsert > 0) DO
            CohortStoreRowsAtStart := (SELECT COUNT(*) FROM CohortStore);

                DROP TABLE IF EXISTS CohortPatientForEachMatchingPatient;
                CREATE TEMPORARY TABLE CohortPatientForEachMatchingPatient AS
                SELECT p.PatientId AS MatchedPatientId, c.PatientId, Row_Number() OVER(PARTITION BY p.PatientId ORDER BY p.PatientId) AS MatchedPatientNumber
                FROM Matches p
                INNER JOIN Cases c
                  ON p.Sex = c.Sex 
				  AND p.Diagnosis = c.Diagnosis 
                  AND p.YearOfBirth >= c.YearOfBirth - {param:yob-flex}
                  AND p.YearOfBirth <= c.YearOfBirth + {param:yob-flex}
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
                SELECT s.PatientId, c.YearOfBirth, c.Sex, c.Diagnosis, MatchedPatientId, m.YearOfBirth FROM CohortPatientForEachMatchingPatientWithCohortNumbered s
                LEFT OUTER JOIN Cases c ON c.PatientId = s.PatientId
                LEFT OUTER JOIN Matches m ON m.PatientId = MatchedPatientId
                WHERE PatientNumber = 1;
            
                lastrowinsert := CohortStoreRowsAtStart - (SELECT COUNT(*) FROM CohortStore);
            
                DELETE FROM Matches WHERE PatientId IN (SELECT MatchingPatientId FROM CohortStore);
                
            END WHILE;
  
    Counter2 := Counter2  + 1;
    END WHILE;
END;

-- 4. Now attempt to match any patients in the main cohort with 'unknown' diagnosis
       -- NOTE: no patients in the potentialMatches table have 'unknown' diagnosis so we match to a random diagnosis
	   -- (either hodgkin or diffuse large b cell lymphoma)

	-- need to create a new matching table that ignores diagnosis, 
	-- to ensure we only get desired number of matches for each patient

DROP TABLE IF EXISTS Matches2;
CREATE TEMPORARY TABLE Matches2 AS
SELECT PatientId, 
    YearOfBirth, 
    Sex, 
    Row_Number() OVER(PARTITION BY YearOfBirth, Sex ORDER BY PatientId) AS AssignedPersonNumber
FROM Matches;

DECLARE 
    counter3 INT;

BEGIN 
    counter3 := 1; 
    
    WHILE (counter3 <= {param:num-matches}) DO 
    
        INSERT INTO CohortStore
          SELECT c.PatientId, c.YearOfBirth, c.Sex, c.Diagnosis, p.PatientId AS MatchedPatientId, c.YearOfBirth
          FROM Cases c
            INNER JOIN Matches2 p 
              ON p.Sex = c.Sex 
                AND p.YearOfBirth >= c.YearOfBirth - {param:yob-flex}
                AND p.YearOfBirth <= c.YearOfBirth + {param:yob-flex}
              -- This next line is the trick to only matching each person once
              AND p.AssignedPersonNumber = CaseRowNumber + (:counter3 - 1)
            WHERE c.Diagnosis = 'unknown';
              
           -- We might not need this, but to be extra sure let's delete any patients who 
           -- we're already using to match people
           DELETE FROM Matches2 WHERE PatientId IN (SELECT MatchingPatientId FROM CohortStore);
        
        counter3 := counter3 + 1; 
        
    END WHILE; 

END;
