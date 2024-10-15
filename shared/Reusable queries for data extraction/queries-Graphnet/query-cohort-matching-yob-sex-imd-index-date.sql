--┌──────────────────────────────────────────────────────────────────┐
--│ Cohort matching on year of birth / sex / imd / and an index date │
--└──────────────────────────────────────────────────────────────────┘

-- OBJECTIVE: To take a primary cohort and find a 1:n matched cohort based on year of birth,
--            sex, imd, and an index date of an event.

-- INPUT: Takes two parameters
--  - yob-flex: integer - number of years each way that still allow a year of birth match
--  - index-date-flex: integer - number of days either side of the index date that we allow matching
--  - num-matches: integer - number of matches for each patient in the cohort
-- Requires two temp tables to exist as follows:
-- #MainCohort (FK_Patient_Link_ID, IndexDate, Sex, YearOfBirth,IMD2019Quintile1IsMostDeprived5IsLeastDeprived)
-- 	- FK_Patient_Link_ID - unique patient id
--	- IndexDate - date of event of interest (YYYY-MM-DD)
--	- Sex - M/F
--	- YearOfBirth - Integer
--  - IMD2019Quintile1IsMostDeprived5IsLeastDeprived - Integer 1-5
-- #PotentialMatches (FK_Patient_Link_ID, IndexDate, Sex, YearOfBirth, IMD2019Quintile1IsMostDeprived5IsLeastDeprived)
-- 	- FK_Patient_Link_ID - unique patient id
--	- IndexDate - date of event of interest (YYYY-MM-DD)
--	- Sex - M/F
--	- YearOfBirth - Integer
--  - IMD2019Quintile1IsMostDeprived5IsLeastDeprived - Integer 1-5

-- OUTPUT: A temp table as follows:
-- #CohortStore (FK_Patient_Link_ID, YearOfBirth, Sex, IMD2019Quintile1IsMostDeprived5IsLeastDeprived, IndexDate, MatchingPatientId, MatchingYearOfBirth, MatchingIndexDate)
--  - FK_Patient_Link_ID - unique patient id for primary cohort patient
--  - YearOfBirth - of the primary cohort patient
--  - Sex - of the primary cohort patient
--  - IMD2019Quintile1IsMostDeprived5IsLeastDeprived - of the primary cohort patient
--  - IndexDate - date of event of interest (YYYY-MM-DD)
--  - MatchingPatientId - id of the matched patient
--  - MatchingYearOfBirth - year of birth of the matched patient
--  - MatchingIndexDate - index date for the matched patient

-- First we extend the #PrimaryCohort table to give each age-sex-imdQuintile-indexDate combo a unique number
-- and to avoid polluting the #MainCohort table
IF OBJECT_ID('tempdb..#Cases') IS NOT NULL DROP TABLE #Cases;
SELECT FK_Patient_Link_ID AS PatientId, YearOfBirth, Sex, IMD2019Quintile1IsMostDeprived5IsLeastDeprived, IndexDate, Row_Number() OVER(PARTITION BY YearOfBirth, Sex, IMD2019Quintile1IsMostDeprived5IsLeastDeprived, IndexDate ORDER BY FK_Patient_Link_ID) AS CaseRowNumber
INTO #Cases FROM #MainCohort;

-- Then we do the same with the #PotentialMatches
IF OBJECT_ID('tempdb..#Matches') IS NOT NULL DROP TABLE #Matches;
SELECT FK_Patient_Link_ID AS PatientId, YearOfBirth, Sex, IMD2019Quintile1IsMostDeprived5IsLeastDeprived, IndexDate, Row_Number() OVER(PARTITION BY YearOfBirth, Sex, IMD2019Quintile1IsMostDeprived5IsLeastDeprived, IndexDate ORDER BY FK_Patient_Link_ID) AS AssignedPersonNumber
INTO #Matches FROM #PotentialMatches;

-- Find the number of people with each characteristic in the main cohort
IF OBJECT_ID('tempdb..#CharacteristicCount') IS NOT NULL DROP TABLE #CharacteristicCount;
SELECT YearOfBirth, Sex, IMD2019Quintile1IsMostDeprived5IsLeastDeprived, IndexDate, COUNT(*) AS [Count] INTO #CharacteristicCount FROM #Cases GROUP BY YearOfBirth, Sex, IMD2019Quintile1IsMostDeprived5IsLeastDeprived, IndexDate;

-- Find the number of potential matches for each combination
-- The output of this is useful for seeing how many matches you can get
-- SELECT A.YearOfBirth, A.Sex, A.IMD2019Quintile1IsMostDeprived5IsLeastDeprived, A.IndexDate,  B.Count / A.Count AS NumberOfPotentialMatchesPerCohortPatient FROM (SELECT * FROM #CharacteristicCount) A LEFT OUTER JOIN (	SELECT YearOfBirth, Sex, IMD2019Quintile1IsMostDeprived5IsLeastDeprived, IndexDate,  COUNT(*) AS [Count] FROM #Matches GROUP BY YearOfBirth, Sex, IMD2019Quintile1IsMostDeprived5IsLeastDeprived, IndexDate) B ON B.YearOfBirth = A.YearOfBirth AND B.Sex = A.Sex AND B.IndexDate = A.IndexDate AND B.IMD2019Quintile1IsMostDeprived5IsLeastDeprived = A.IMD2019Quintile1IsMostDeprived5IsLeastDeprived ORDER BY NumberOfPotentialMatchesPerCohortPatient,A.YearOfBirth,A.Sex,A.IMD2019Quintile1IsMostDeprived5IsLeastDeprived, A.IndexDate;

-- The final table contains a row for each match, so e.g. if patient 1 has 4
-- matches then there will be 4 rows in the table for this.
IF OBJECT_ID('tempdb..#CohortStore') IS NOT NULL DROP TABLE #CohortStore;
CREATE TABLE #CohortStore(
  PatientId BIGINT, 
  YearOfBirth INT, 
  Sex nchar(1), 
  IMD2019Quintile1IsMostDeprived5IsLeastDeprived INT,
  IndexDate DATE, 
  MatchingPatientId BIGINT,
  MatchingYearOfBirth INT,
  MatchingIndexDate DATE
) ON [PRIMARY];

--1. First match try to match people exactly. We do this as follows:
--    - For each YOB/Sex/IMD/IndexDate combination we find all potential matches. E.g. all patients
--      in the potential matches with sex='F', yob=1957, IMDQuintile=4 and IndexDate=2021-04-03
--    - We then try to assign a single match to all cohort members with these characteristics
--    - If there are still matches unused, we then assign a second match to all cohort members
--    - This continues until we either run out of matches, or successfully match everyone with
--      the desired number of matches.
DECLARE @Counter1 INT; 
SET @Counter1=1;
-- In this loop we find one match at a time for each patient in the cohort
WHILE ( @Counter1 <= {param:num-matches})
BEGIN
  INSERT INTO #CohortStore
  SELECT c.PatientId, c.YearOfBirth, c.Sex, c.IMD2019Quintile1IsMostDeprived5IsLeastDeprived, c.IndexDate, p.PatientId AS MatchedPatientId, c.YearOfBirth, c.IndexDate
  FROM #Cases c
    INNER JOIN #CharacteristicCount cc on cc.YearOfBirth = c.YearOfBirth and cc.Sex = c.Sex and cc.IMD2019Quintile1IsMostDeprived5IsLeastDeprived = c.IMD2019Quintile1IsMostDeprived5IsLeastDeprived and cc.IndexDate = c.IndexDate
    INNER JOIN #Matches p 
      ON p.Sex = c.Sex 
      AND p.YearOfBirth = c.YearOfBirth 
      AND p.IMD2019Quintile1IsMostDeprived5IsLeastDeprived = c.IMD2019Quintile1IsMostDeprived5IsLeastDeprived 
      AND p.IndexDate = c.IndexDate 
      -- This next line is the trick to only matching each person once
      AND p.AssignedPersonNumber = CaseRowNumber + (@counter1 - 1) * cc.[Count];

  -- We might not need this, but to be extra sure let's delete any patients who 
  -- we're already using to match people
  DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #CohortStore);

  SET @Counter1  = @Counter1  + 1
END

--2. Now relax the yob and index date restriction to get extra matches for people. Loop round starting with
--   those with 0 matches, then 1 match, then 2 matches etc.
DECLARE @Counter2 INT; 
SET @Counter2=0;
WHILE (@Counter2 <= {param:num-matches})
BEGIN
	DECLARE @LastRowInsert1 INT;
	SET @LastRowInsert1=1;
	WHILE ( @LastRowInsert1 > 0)
	BEGIN
	  INSERT INTO #CohortStore
	  SELECT PatientId, YearOfBirth, Sex, IMD2019Quintile1IsMostDeprived5IsLeastDeprived, IndexDate, MatchedPatientId, MatchedYOB, MatchedIndexDate FROM (
	  SELECT sub.PatientId, sub.YearOfBirth, sub.Sex, sub.IMD2019Quintile1IsMostDeprived5IsLeastDeprived, sub.IndexDate, MatchedPatientId, MAX(m.YearOfBirth) AS MatchedYOB, MAX(m.IndexDate) AS MatchedIndexDate, Row_Number() OVER(PARTITION BY sub.PatientId ORDER BY sub.PatientId) AS NthMatch FROM (
	  SELECT c.PatientId, c.YearOfBirth, c.Sex, c.IMD2019Quintile1IsMostDeprived5IsLeastDeprived, c.IndexDate, MAX(p.PatientId) AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(p.PatientId) ORDER BY p.PatientId) AS AssignedPersonNumber
	  FROM #Cases c
	  INNER JOIN #Matches p 
		ON p.Sex = c.Sex 
		AND p.IMD2019Quintile1IsMostDeprived5IsLeastDeprived = c.IMD2019Quintile1IsMostDeprived5IsLeastDeprived 
		AND p.YearOfBirth >= c.YearOfBirth - {param:yob-flex}
		AND p.YearOfBirth <= c.YearOfBirth + {param:yob-flex}
		AND p.IndexDate between DATEADD(day,-{param:index-date-flex},c.IndexDate) and DATEADD(day,{param:index-date-flex},c.IndexDate)
	  WHERE c.PatientId in (
		-- find patients who aren't currently matched
		select PatientId from #Cases except (select PatientId from #CohortStore group by PatientId having count(*) >= @Counter2)
	  )
	  GROUP BY c.PatientId, c.YearOfBirth, c.Sex, c.IMD2019Quintile1IsMostDeprived5IsLeastDeprived, c.IndexDate, p.PatientId) sub
	  INNER JOIN #Matches m 
		ON m.Sex = sub.Sex 
		AND m.IMD2019Quintile1IsMostDeprived5IsLeastDeprived = sub.IMD2019Quintile1IsMostDeprived5IsLeastDeprived 
		AND m.PatientId = sub.MatchedPatientId
		AND m.YearOfBirth >= sub.YearOfBirth - {param:yob-flex}
		AND m.YearOfBirth <= sub.YearOfBirth + {param:yob-flex}
		AND m.IndexDate between DATEADD(day,-{param:index-date-flex},sub.IndexDate) and DATEADD(day,{param:index-date-flex},sub.IndexDate)
	  WHERE sub.AssignedPersonNumber = 1
	  GROUP BY sub.PatientId, sub.YearOfBirth, sub.Sex, sub.IMD2019Quintile1IsMostDeprived5IsLeastDeprived, sub.IndexDate, MatchedPatientId) sub2
	  WHERE NthMatch = 1
	  ORDER BY PatientId;
	  SELECT @LastRowInsert1=@@ROWCOUNT;

	  DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #CohortStore);
	END
	SET @Counter2  = @Counter2  + 1
END

--Useful checks:
-- These first two queries should give the same number
--select count(*) from #CohortStore;
--select count(distinct MatchingPatientId) from #CohortStore;
-- This query shows how many people have how many matches
--SELECT Num, COUNT(*) FROM ( SELECT PatientId, COUNT(*) AS Num FROM #CohortStore GROUP BY PatientId) sub GROUP BY Num UNION SELECT 0, x FROM (SELECT COUNT(*) AS x FROM (SELECT PatientId FROM #Cases EXCEPT SELECT PatientId FROM #CohortStore) sub1) sub ORDER BY Num;
