--┌────────────────────────────────────────────────────┐
--│ Cohort matching on year of birth / sex 					   │
--└────────────────────────────────────────────────────┘

-- OBJECTIVE: To take a primary cohort and find a 1:n matched cohort based on year of birth and sex.

-- INPUT: Takes two parameters
--  - yob-flex: integer - number of years each way that still allow a year of birth match
--  - num-matches: integer - number of matches for each patient in the cohort
-- Requires two temp tables to exist as follows:
-- #MainCohort (FK_Patient_Link_ID, Sex, YearOfBirth)
-- 	- FK_Patient_Link_ID - unique patient id
--	- Sex - M/F
--	- YearOfBirth - Integer
-- #PotentialMatches (FK_Patient_Link_ID, Sex, YearOfBirth)
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

-- First we extend the #PrimaryCohort table to give each age-sex combo a unique number
-- and to avoid polluting the #MainCohort table
IF OBJECT_ID('tempdb..#Cases') IS NOT NULL DROP TABLE #Cases;
SELECT FK_Patient_Link_ID AS PatientId, YearOfBirth, Sex, Row_Number() OVER(PARTITION BY YearOfBirth, Sex ORDER BY FK_Patient_Link_ID) AS CaseRowNumber
INTO #Cases FROM #MainCohort;

-- Then we do the same with the #PotentialMatches
IF OBJECT_ID('tempdb..#Matches') IS NOT NULL DROP TABLE #Matches;
SELECT FK_Patient_Link_ID AS PatientId, YearOfBirth, Sex, Row_Number() OVER(PARTITION BY YearOfBirth, Sex ORDER BY NewID()) AS AssignedPersonNumber
INTO #Matches FROM #PotentialMatches;

-- Find the number of people with each characteristic in the main cohort
IF OBJECT_ID('tempdb..#CharacteristicCount') IS NOT NULL DROP TABLE #CharacteristicCount;
SELECT YearOfBirth, Sex, COUNT(*) AS [Count] INTO #CharacteristicCount FROM #Cases GROUP BY YearOfBirth, Sex;

-- Find the number of potential matches for each Age/Sex combination
-- The output of this is useful for seeing how many matches you can get
-- SELECT A.YearOfBirth, A.Sex, B.Count / A.Count AS NumberOfPotentialMatchesPerCohortPatient FROM (SELECT * FROM #CharacteristicCount) A LEFT OUTER JOIN (SELECT YearOfBirth, Sex, COUNT(*) AS [Count] FROM #Matches GROUP BY YearOfBirth, Sex) B ON B.YearOfBirth = A.YearOfBirth AND B.Sex = A.Sex ORDER BY NumberOfPotentialMatches,A.YearOfBirth,A.Sex;

-- The final table contains a row for each match, so e.g. if patient 1 has 4
-- matches then there will be 4 rows in the table for this.
IF OBJECT_ID('tempdb..#CohortStore') IS NOT NULL DROP TABLE #CohortStore;
CREATE TABLE #CohortStore(
  PatientId BIGINT, 
  YearOfBirth INT, 
  Sex nchar(1), 
  MatchingPatientId BIGINT,
  MatchingYearOfBirth INT
) ON [PRIMARY];

--1. First match try to match people exactly. We do this as follows:
--    - For each YOB/Sex combination we find all potential matches. E.g. all patients
--      in the potential matches with sex='F' and yob=1957
--    - We then try to assign a single match to all cohort members with sex='F' and yob=1957
--    - If there are still matches unused, we then assign a second match to all cohort members
--    - This continues until we either run out of matches, or successfully match everyone with
--      the desired number of matches.
DECLARE @Counter1 INT; 
SET @Counter1=1;
-- In this loop we find one match at a time for each patient in the cohort
WHILE ( @Counter1 <= {param:num-matches})
BEGIN
  INSERT INTO #CohortStore
  SELECT c.PatientId, c.YearOfBirth, c.Sex, p.PatientId AS MatchedPatientId, c.YearOfBirth
  FROM #Cases c
    INNER JOIN #CharacteristicCount cc on cc.YearOfBirth = c.YearOfBirth and cc.Sex = c.Sex
    INNER JOIN #Matches p 
      ON p.Sex = c.Sex 
      AND p.YearOfBirth = c.YearOfBirth 
      -- This next line is the trick to only matching each person once
      AND p.AssignedPersonNumber = CaseRowNumber + (@counter1 - 1) * cc.[Count];

  -- We might not need this, but to be extra sure let's delete any patients who 
  -- we're already using to match people
  DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #CohortStore);

  SET @Counter1  = @Counter1  + 1
END

--2. Now relax the yob restriction to get extra matches for people with no matches
DECLARE @LastRowInsert1 INT;
SET @LastRowInsert1=1;
WHILE ( @LastRowInsert1 > 0)
BEGIN
  INSERT INTO #CohortStore
  SELECT sub.PatientId, sub.YearOfBirth, sub.Sex, MatchedPatientId, MAX(m.YearOfBirth) FROM (
  SELECT c.PatientId, c.YearOfBirth, c.Sex, MAX(p.PatientId) AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(p.PatientId) ORDER BY NewID()) AS AssignedPersonNumber
  FROM #Cases c
  INNER JOIN #Matches p 
    ON p.Sex = c.Sex 
    AND p.YearOfBirth >= c.YearOfBirth - {param:yob-flex}
    AND p.YearOfBirth <= c.YearOfBirth + {param:yob-flex}
  WHERE c.PatientId in (
    -- find patients who aren't currently matched
    select PatientId from #Cases except select PatientId from #CohortStore
  )
  GROUP BY c.PatientId, c.YearOfBirth, c.Sex) sub
  INNER JOIN #Matches m 
    ON m.Sex = sub.Sex 
    AND m.PatientId = sub.MatchedPatientId
    AND m.YearOfBirth >= sub.YearOfBirth - {param:yob-flex}
    AND m.YearOfBirth <= sub.YearOfBirth + {param:yob-flex}
  WHERE sub.AssignedPersonNumber = 1
  GROUP BY sub.PatientId, sub.YearOfBirth, sub.Sex, MatchedPatientId;
  SELECT @LastRowInsert1=@@ROWCOUNT;

  DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #CohortStore);
END

--3. Now relax the yob restriction to get extra matches for people with only 1, 2, 3, ... n-1 matches
DECLARE @Counter2 INT; 
SET @Counter2=1;
WHILE (@Counter2 < 5)
BEGIN
  DECLARE @LastRowInsert INT;
  SET @LastRowInsert=1;
  WHILE ( @LastRowInsert > 0)
  BEGIN

    IF OBJECT_ID('tempdb..#CohortPatientForEachMatchingPatient') IS NOT NULL DROP TABLE #CohortPatientForEachMatchingPatient;
    SELECT p.PatientId AS MatchedPatientId, c.PatientId, Row_Number() OVER(PARTITION BY p.PatientId ORDER BY NewID()) AS MatchedPatientNumber
    INTO #CohortPatientForEachMatchingPatient
    FROM #Matches p
    INNER JOIN #Cases c
      ON p.Sex = c.Sex 
      AND p.YearOfBirth >= c.YearOfBirth - 5
      AND p.YearOfBirth <= c.YearOfBirth + 5
    WHERE c.PatientId IN (
      -- find patients who only have @Counter2 matches
      SELECT PatientId FROM #CohortStore GROUP BY PatientId HAVING count(*) = @Counter2
    );

    IF OBJECT_ID('tempdb..#CohortPatientForEachMatchingPatientWithCohortNumbered') IS NOT NULL DROP TABLE #CohortPatientForEachMatchingPatientWithCohortNumbered;
    SELECT PatientId, MatchedPatientId, Row_Number() OVER(PARTITION BY PatientId ORDER BY NewID()) AS PatientNumber
    INTO #CohortPatientForEachMatchingPatientWithCohortNumbered
    FROM #CohortPatientForEachMatchingPatient
    WHERE MatchedPatientNumber = 1;

    INSERT INTO #CohortStore
    SELECT s.PatientId, c.YearOfBirth, c.Sex, MatchedPatientId, m.YearOfBirth FROM #CohortPatientForEachMatchingPatientWithCohortNumbered s
    LEFT OUTER JOIN #Cases c ON c.PatientId = s.PatientId
    LEFT OUTER JOIN #Matches m ON m.PatientId = MatchedPatientId
    WHERE PatientNumber = 1;

    SELECT @LastRowInsert=@@ROWCOUNT;

    DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #CohortStore);
  END
  
  SET @Counter2  = @Counter2  + 1
END