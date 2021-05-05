--┌────────────────────────────────────────────────────────────┐
--│ Cohort matching on year of birth / sex / and an index date │
--└────────────────────────────────────────────────────────────┘

-- OBJECTIVE: To take a primary cohort and find a 1:5 matched cohort based on year of birth,
--            sex, and an index date of an event.

-- INPUT: Takes two parameters
--  - yob-flex: integer - number of years each way that still allow a year of birth match
--  - index-date-flex: integer - number of days either side of the index date that we allow matching
-- Requires two temp tables to exist as follows:
-- #MainCohort (FK_Patient_Link_ID, IndexDate, Sex, YearOfBirth)
-- 	- FK_Patient_Link_ID - unique patient id
--	- IndexDate - date of event of interest (YYYY-MM-DD)
--	- Sex - M/F
--	- YearOfBirth - Integer
-- #PotentialMatches (FK_Patient_Link_ID, IndexDate, Sex, YearOfBirth)
-- 	- FK_Patient_Link_ID - unique patient id
--	- IndexDate - date of event of interest (YYYY-MM-DD)
--	- Sex - M/F
--	- YearOfBirth - Integer

-- OUTPUT: A temp table as follows:
-- #CohortStore (FK_Patient_Link_ID, YearOfBirth, Sex, IndexDate, MatchingPatientId, MatchingYearOfBirth, MatchingIndexDate)
--  - FK_Patient_Link_ID - unique patient id for primary cohort patient
--  - YearOfBirth - of the primary cohort patient
--  - Sex - of the primary cohort patient
--  - IndexDate - date of event of interest (YYYY-MM-DD)
--  - MatchingPatientId - id of the matched patient
--  - MatchingYearOfBirth - year of birth of the matched patient
--  - MatchingIndexDate - index date for the matched patient

-- First we copy the #PrimaryCohort table to avoid pollution
IF OBJECT_ID('tempdb..#Cases') IS NOT NULL DROP TABLE #Cases;
SELECT FK_Patient_Link_ID AS PatientId, YearOfBirth, Sex, IndexDate as IndexDate
INTO #Cases FROM #MainCohort;

-- Then we do the same with the #PotentialMatches but with a bit of flexibility on the age and date
IF OBJECT_ID('tempdb..#Matches') IS NOT NULL DROP TABLE #Matches;
SELECT FK_Patient_Link_ID AS PatientId, YearOfBirth, Sex, IndexDate as IndexDate
INTO #Matches FROM (select p.FK_Patient_Link_ID, p.YearOfBirth, p.Sex, p.IndexDate from #Cases c inner join (
	SELECT FK_Patient_Link_ID, YearOfBirth, Sex, IndexDate FROM #PotentialMatches
) p on c.Sex = p.Sex and c.YearOfBirth >= p.YearOfBirth - {param:yob-flex} and c.YearOfBirth <= p.YearOfBirth + {param:yob-flex} and c.IndexDate between DATEADD(day,-{param:index-date-flex},p.IndexDate) and DATEADD(day,{param:index-date-flex},p.IndexDate)
group by p.FK_Patient_Link_ID, p.YearOfBirth, p.Sex, p.IndexDate) sub;

-- Table to store the matches
IF OBJECT_ID('tempdb..#CohortStore') IS NOT NULL DROP TABLE #CohortStore;
CREATE TABLE #CohortStore(
  PatientId BIGINT, 
  YearOfBirth INT, 
  Sex nchar(1), 
  IndexDate DATE, 
  MatchingPatientId BIGINT,
  MatchingYearOfBirth INT,
  MatchingCovidPositiveDate DATE
) ON [PRIMARY];

-- 1. If anyone only matches one case then use them. Remove and repeat until everyone matches
--    multiple people TODO or until the #Cases table is empty
DECLARE @LastRowInsert INT; 
SET @LastRowInsert=1;
WHILE ( @LastRowInsert > 0)
BEGIN  
  -- match them
  INSERT INTO #CohortStore
  SELECT PatientId, YearOfBirth, Sex, IndexDate, MatchedPatientId, YearOfBirth, IndexDate FROM (
	  SELECT c.PatientId, c.YearOfBirth, c.Sex, c.IndexDate, p.PatientId AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(c.PatientId) ORDER BY NewID()) AS AssignedPersonNumber
	  FROM #Cases c
		INNER JOIN #Matches p 
		  ON p.Sex = c.Sex 
		  AND p.YearOfBirth = c.YearOfBirth 
		  AND p.IndexDate = c.IndexDate
		WHERE p.PatientId in (
		-- find patients in the matches who only match a single case
			select m.PatientId
		  from #Matches m 
		  inner join #Cases c ON m.Sex = c.Sex 
			  AND m.YearOfBirth = c.YearOfBirth 
			  AND m.IndexDate = c.IndexDate
			group by m.PatientId
			having count(*) = 1
		)
	  GROUP BY c.PatientId, c.YearOfBirth, c.Sex, c.IndexDate, p.PatientId
	) sub
	WHERE AssignedPersonNumber <= 5
  ORDER BY PatientId;
  SELECT @LastRowInsert=@@ROWCOUNT;

  -- remove from cases anyone we've already got n for
  delete from #Cases where PatientId in (
  select PatientId FROM #CohortStore
  group by PatientId
  having count(*) >= 5);

  -- remove from matches anyone already used
  DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #CohortStore);
END

--select distinct MatchingPatientId from #CohortStore
--select count(*) from #CohortStore
--This next query shows how many people with no match, 1 match, 2 match etc.
--SELECT Num, COUNT(*) FROM ( SELECT PatientId, COUNT(*) AS Num FROM #CohortStore GROUP BY PatientId) sub GROUP BY Num UNION SELECT 0, x FROM (SELECT COUNT(*) AS x FROM (SELECT PatientId FROM #Cases EXCEPT SELECT PatientId FROM #CohortStore) sub1) sub ORDER BY Num;


-- 2. Now we focus on people without any matches and try and give everyone a match
DECLARE @LastRowInsert2 INT;
SET @LastRowInsert2=1;
WHILE ( @LastRowInsert2 > 0)
BEGIN
  INSERT INTO #CohortStore
  SELECT PatientId, YearOfBirth, Sex, IndexDate, MatchedPatientId, YearOfBirth, IndexDate FROM (
  SELECT c.PatientId, c.YearOfBirth, c.Sex, c.IndexDate, MAX(p.PatientId) AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(p.PatientId) ORDER BY NewID()) AS AssignedPersonNumber
  FROM #Cases c
  INNER JOIN #Matches p 
    ON p.Sex = c.Sex 
    AND p.YearOfBirth = c.YearOfBirth 
    AND p.IndexDate = c.IndexDate
  WHERE c.PatientId in (
    -- find patients who aren't currently matched
select PatientId from #Cases except select PatientId from #CohortStore
  )
  GROUP BY c.PatientId, c.YearOfBirth, c.Sex, c.IndexDate) sub
  WHERE sub.AssignedPersonNumber = 1;
  SELECT @LastRowInsert2=@@ROWCOUNT;

  DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #CohortStore);
END

-- 3. There are some people who we can't find a match for.. try relaxing the date requirement
DECLARE @LastRowInsert3 INT;
SET @LastRowInsert3=1;
WHILE ( @LastRowInsert3 > 0)
BEGIN
  INSERT INTO #CohortStore
  SELECT sub.PatientId, sub.YearOfBirth, sub.Sex, sub.IndexDate, MatchedPatientId, m.YearOfBirth, MAX(m.IndexDate) FROM (
  SELECT c.PatientId, c.YearOfBirth, c.Sex, c.IndexDate, MAX(p.PatientId) AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(p.PatientId) ORDER BY NewID()) AS AssignedPersonNumber
  FROM #Cases c
  INNER JOIN #Matches p 
    ON p.Sex = c.Sex 
    AND p.YearOfBirth = c.YearOfBirth
    AND p.IndexDate between DATEADD(day,-{param:index-date-flex},c.IndexDate) and DATEADD(day,{param:index-date-flex},c.IndexDate)
  WHERE c.PatientId in (
    -- find patients who aren't currently matched
select PatientId from #Cases except select PatientId from #CohortStore
  )
  GROUP BY c.PatientId, c.YearOfBirth, c.Sex, c.IndexDate) sub
  INNER JOIN #Matches m 
    ON m.Sex = sub.Sex 
    AND m.PatientId = sub.MatchedPatientId
    AND m.YearOfBirth = sub.YearOfBirth
    AND m.IndexDate between DATEADD(day,-{param:index-date-flex},sub.IndexDate) and DATEADD(day,{param:index-date-flex},sub.IndexDate)
  WHERE sub.AssignedPersonNumber = 1
  GROUP BY sub.PatientId, sub.YearOfBirth, sub.Sex, sub.IndexDate, MatchedPatientId, m.YearOfBirth;
  SELECT @LastRowInsert3=@@ROWCOUNT;

  DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #CohortStore);
END


-- 4. There are some people who we still can't find a match for.. try relaxing the age and date requirement
DECLARE @LastRowInsert4 INT;
SET @LastRowInsert4=1;
WHILE ( @LastRowInsert4 > 0)
BEGIN
  INSERT INTO #CohortStore
  SELECT sub.PatientId, sub.YearOfBirth, sub.Sex, sub.IndexDate, MatchedPatientId, MAX(m.YearOfBirth), MAX(m.IndexDate) FROM (
  SELECT c.PatientId, c.YearOfBirth, c.Sex, c.IndexDate, MAX(p.PatientId) AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(p.PatientId) ORDER BY NewID()) AS AssignedPersonNumber
  FROM #Cases c
  INNER JOIN #Matches p 
    ON p.Sex = c.Sex 
    AND p.YearOfBirth >= c.YearOfBirth - {param:yob-flex}
    AND p.YearOfBirth <= c.YearOfBirth + {param:yob-flex}
    AND p.IndexDate between DATEADD(day,-{param:index-date-flex},c.IndexDate) and DATEADD(day,{param:index-date-flex},c.IndexDate)
  WHERE c.PatientId in (
    -- find patients who aren't currently matched
select PatientId from #Cases except select PatientId from #CohortStore
  )
  GROUP BY c.PatientId, c.YearOfBirth, c.Sex, c.IndexDate) sub
  INNER JOIN #Matches m 
    ON m.Sex = sub.Sex 
    AND m.PatientId = sub.MatchedPatientId
    AND m.YearOfBirth >= sub.YearOfBirth - {param:yob-flex}
    AND m.YearOfBirth <= sub.YearOfBirth + {param:yob-flex}
    AND m.IndexDate between DATEADD(day,-{param:index-date-flex},sub.IndexDate) and DATEADD(day,{param:index-date-flex},sub.IndexDate)
  WHERE sub.AssignedPersonNumber = 1
  GROUP BY sub.PatientId, sub.YearOfBirth, sub.Sex, sub.IndexDate, MatchedPatientId;
  SELECT @LastRowInsert4=@@ROWCOUNT;

  DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #CohortStore);
END

--This next query shows how many people with no match, 1 match, 2 match etc.
--SELECT Num, COUNT(*) FROM ( SELECT PatientId, COUNT(*) AS Num FROM #CohortStore GROUP BY PatientId) sub GROUP BY Num UNION SELECT 0, x FROM (SELECT COUNT(*) AS x FROM (SELECT PatientId FROM #Cases EXCEPT SELECT PatientId FROM #CohortStore) sub1) sub ORDER BY Num;

-- 5. Now we focus on people with only 1 match(es) and attempt to give them another
DECLARE @LastRowInsert5 INT;
SET @LastRowInsert5=1;
WHILE ( @LastRowInsert5 > 0)
BEGIN
  INSERT INTO #CohortStore
  SELECT PatientId, YearOfBirth, Sex, IndexDate, MatchedPatientId, YearOfBirth, IndexDate FROM (
  SELECT c.PatientId, c.YearOfBirth, c.Sex, c.IndexDate, MAX(p.PatientId) AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(p.PatientId) ORDER BY NewID()) AS AssignedPersonNumber
  FROM #Cases c
  INNER JOIN #Matches p 
    ON p.Sex = c.Sex 
    AND p.YearOfBirth = c.YearOfBirth 
    AND p.IndexDate = c.IndexDate
  WHERE c.PatientId in (
    -- find patients who currently only have 1 match(es)
select PatientId from #CohortStore group by PatientId having count(*) = 1
  )
  GROUP BY c.PatientId, c.YearOfBirth, c.Sex, c.IndexDate) sub
  WHERE sub.AssignedPersonNumber = 1;
  SELECT @LastRowInsert5=@@ROWCOUNT;

  DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #CohortStore);
END

-- 6. There are some people who we can't find a 2nd match.. try relaxing the date requirement
DECLARE @LastRowInsert6 INT;
SET @LastRowInsert6=1;
WHILE ( @LastRowInsert6 > 0)
BEGIN
  INSERT INTO #CohortStore
  SELECT sub.PatientId, sub.YearOfBirth, sub.Sex, sub.IndexDate, MatchedPatientId, m.YearOfBirth, MAX(m.IndexDate) FROM (
  SELECT c.PatientId, c.YearOfBirth, c.Sex, c.IndexDate, MAX(p.PatientId) AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(p.PatientId) ORDER BY NewID()) AS AssignedPersonNumber
  FROM #Cases c
  INNER JOIN #Matches p 
    ON p.Sex = c.Sex 
    AND p.YearOfBirth = c.YearOfBirth
    AND p.IndexDate between DATEADD(day,-{param:index-date-flex},c.IndexDate) and DATEADD(day,{param:index-date-flex},c.IndexDate)
  WHERE c.PatientId in (
    -- find patients who currently only have 1 match(es)
select PatientId from #CohortStore group by PatientId having count(*) = 1
  )
  GROUP BY c.PatientId, c.YearOfBirth, c.Sex, c.IndexDate) sub
  INNER JOIN #Matches m 
    ON m.Sex = sub.Sex 
    AND m.PatientId = sub.MatchedPatientId
    AND m.YearOfBirth = sub.YearOfBirth
    AND m.IndexDate between DATEADD(day,-{param:index-date-flex},sub.IndexDate) and DATEADD(day,{param:index-date-flex},sub.IndexDate)
  WHERE sub.AssignedPersonNumber = 1
  GROUP BY sub.PatientId, sub.YearOfBirth, sub.Sex, sub.IndexDate, MatchedPatientId, m.YearOfBirth;
  SELECT @LastRowInsert6=@@ROWCOUNT;

  DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #CohortStore);
END

-- 7. There are some people who we still can't find a 2nd match.. try relaxing the age and date requirement
DECLARE @LastRowInsert7 INT;
SET @LastRowInsert7=1;
WHILE ( @LastRowInsert7 > 0)
BEGIN
  INSERT INTO #CohortStore
  SELECT sub.PatientId, sub.YearOfBirth, sub.Sex, sub.IndexDate, MatchedPatientId, MAX(m.YearOfBirth), MAX(m.IndexDate) FROM (
  SELECT c.PatientId, c.YearOfBirth, c.Sex, c.IndexDate, MAX(p.PatientId) AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(p.PatientId) ORDER BY NewID()) AS AssignedPersonNumber
  FROM #Cases c
  INNER JOIN #Matches p 
    ON p.Sex = c.Sex 
    AND p.YearOfBirth >= c.YearOfBirth - {param:yob-flex}
    AND p.YearOfBirth <= c.YearOfBirth + {param:yob-flex}
    AND p.IndexDate between DATEADD(day,-{param:index-date-flex},c.IndexDate) and DATEADD(day,{param:index-date-flex},c.IndexDate)
  WHERE c.PatientId in (
    -- find patients who currently only have 1 match(es)
select PatientId from #CohortStore group by PatientId having count(*) = 1
  )
  GROUP BY c.PatientId, c.YearOfBirth, c.Sex, c.IndexDate) sub
  INNER JOIN #Matches m 
    ON m.Sex = sub.Sex 
    AND m.PatientId = sub.MatchedPatientId
    AND m.YearOfBirth >= sub.YearOfBirth - {param:yob-flex}
    AND m.YearOfBirth <= sub.YearOfBirth + {param:yob-flex}
    AND m.IndexDate between DATEADD(day,-{param:index-date-flex},sub.IndexDate) and DATEADD(day,{param:index-date-flex},sub.IndexDate)
  WHERE sub.AssignedPersonNumber = 1
  GROUP BY sub.PatientId, sub.YearOfBirth, sub.Sex, sub.IndexDate, MatchedPatientId;
  SELECT @LastRowInsert7=@@ROWCOUNT;

  DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #CohortStore);
END

--This next query shows how many people with no match, 1 match, 2 match etc.
--SELECT Num, COUNT(*) FROM ( SELECT PatientId, COUNT(*) AS Num FROM #CohortStore GROUP BY PatientId) sub GROUP BY Num UNION SELECT 0, x FROM (SELECT COUNT(*) AS x FROM (SELECT PatientId FROM #Cases EXCEPT SELECT PatientId FROM #CohortStore) sub1) sub ORDER BY Num;

-- 8. Now we focus on people with only 2 match(es) and attempt to give them another
DECLARE @LastRowInsert8 INT;
SET @LastRowInsert8=1;
WHILE ( @LastRowInsert8 > 0)
BEGIN
  INSERT INTO #CohortStore
  SELECT PatientId, YearOfBirth, Sex, IndexDate, MatchedPatientId, YearOfBirth, IndexDate FROM (
  SELECT c.PatientId, c.YearOfBirth, c.Sex, c.IndexDate, MAX(p.PatientId) AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(p.PatientId) ORDER BY NewID()) AS AssignedPersonNumber
  FROM #Cases c
  INNER JOIN #Matches p 
    ON p.Sex = c.Sex 
    AND p.YearOfBirth = c.YearOfBirth 
    AND p.IndexDate = c.IndexDate
  WHERE c.PatientId in (
    -- find patients who currently only have 2 match(es)
select PatientId from #CohortStore group by PatientId having count(*) = 2
  )
  GROUP BY c.PatientId, c.YearOfBirth, c.Sex, c.IndexDate) sub
  WHERE sub.AssignedPersonNumber = 1;
  SELECT @LastRowInsert8=@@ROWCOUNT;

  DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #CohortStore);
END

-- 9. There are some people who we can't find a 3rd match.. try relaxing the date requirement
DECLARE @LastRowInsert9 INT;
SET @LastRowInsert9=1;
WHILE ( @LastRowInsert9 > 0)
BEGIN
  INSERT INTO #CohortStore
  SELECT sub.PatientId, sub.YearOfBirth, sub.Sex, sub.IndexDate, MatchedPatientId, m.YearOfBirth, MAX(m.IndexDate) FROM (
  SELECT c.PatientId, c.YearOfBirth, c.Sex, c.IndexDate, MAX(p.PatientId) AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(p.PatientId) ORDER BY NewID()) AS AssignedPersonNumber
  FROM #Cases c
  INNER JOIN #Matches p 
    ON p.Sex = c.Sex 
    AND p.YearOfBirth = c.YearOfBirth
    AND p.IndexDate between DATEADD(day,-{param:index-date-flex},c.IndexDate) and DATEADD(day,{param:index-date-flex},c.IndexDate)
  WHERE c.PatientId in (
    -- find patients who currently only have 2 match(es)
select PatientId from #CohortStore group by PatientId having count(*) = 2
  )
  GROUP BY c.PatientId, c.YearOfBirth, c.Sex, c.IndexDate) sub
  INNER JOIN #Matches m 
    ON m.Sex = sub.Sex 
    AND m.PatientId = sub.MatchedPatientId
    AND m.YearOfBirth = sub.YearOfBirth
    AND m.IndexDate between DATEADD(day,-{param:index-date-flex},sub.IndexDate) and DATEADD(day,{param:index-date-flex},sub.IndexDate)
  WHERE sub.AssignedPersonNumber = 1
  GROUP BY sub.PatientId, sub.YearOfBirth, sub.Sex, sub.IndexDate, MatchedPatientId, m.YearOfBirth;
  SELECT @LastRowInsert9=@@ROWCOUNT;

  DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #CohortStore);
END

-- 10. There are some people who we still can't find a 3rd match.. try relaxing the age and date requirement
DECLARE @LastRowInsert10 INT;
SET @LastRowInsert10=1;
WHILE ( @LastRowInsert10 > 0)
BEGIN
  INSERT INTO #CohortStore
  SELECT sub.PatientId, sub.YearOfBirth, sub.Sex, sub.IndexDate, MatchedPatientId, MAX(m.YearOfBirth), MAX(m.IndexDate) FROM (
  SELECT c.PatientId, c.YearOfBirth, c.Sex, c.IndexDate, MAX(p.PatientId) AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(p.PatientId) ORDER BY NewID()) AS AssignedPersonNumber
  FROM #Cases c
  INNER JOIN #Matches p 
    ON p.Sex = c.Sex 
    AND p.YearOfBirth >= c.YearOfBirth - {param:yob-flex}
    AND p.YearOfBirth <= c.YearOfBirth + {param:yob-flex}
    AND p.IndexDate between DATEADD(day,-{param:index-date-flex},c.IndexDate) and DATEADD(day,{param:index-date-flex},c.IndexDate)
  WHERE c.PatientId in (
    -- find patients who currently only have 2 match(es)
select PatientId from #CohortStore group by PatientId having count(*) = 2
  )
  GROUP BY c.PatientId, c.YearOfBirth, c.Sex, c.IndexDate) sub
  INNER JOIN #Matches m 
    ON m.Sex = sub.Sex 
    AND m.PatientId = sub.MatchedPatientId
    AND m.YearOfBirth >= sub.YearOfBirth - {param:yob-flex}
    AND m.YearOfBirth <= sub.YearOfBirth + {param:yob-flex}
    AND m.IndexDate between DATEADD(day,-{param:index-date-flex},sub.IndexDate) and DATEADD(day,{param:index-date-flex},sub.IndexDate)
  WHERE sub.AssignedPersonNumber = 1
  GROUP BY sub.PatientId, sub.YearOfBirth, sub.Sex, sub.IndexDate, MatchedPatientId;
  SELECT @LastRowInsert10=@@ROWCOUNT;

  DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #CohortStore);
END

--This next query shows how many people with no match, 1 match, 2 match etc.
--SELECT Num, COUNT(*) FROM ( SELECT PatientId, COUNT(*) AS Num FROM #CohortStore GROUP BY PatientId) sub GROUP BY Num UNION SELECT 0, x FROM (SELECT COUNT(*) AS x FROM (SELECT PatientId FROM #Cases EXCEPT SELECT PatientId FROM #CohortStore) sub1) sub ORDER BY Num;

-- 11. Now we focus on people with only 3 match(es) and attempt to give them another
DECLARE @LastRowInsert11 INT;
SET @LastRowInsert11=1;
WHILE ( @LastRowInsert11 > 0)
BEGIN
  INSERT INTO #CohortStore
  SELECT PatientId, YearOfBirth, Sex, IndexDate, MatchedPatientId, YearOfBirth, IndexDate FROM (
  SELECT c.PatientId, c.YearOfBirth, c.Sex, c.IndexDate, MAX(p.PatientId) AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(p.PatientId) ORDER BY NewID()) AS AssignedPersonNumber
  FROM #Cases c
  INNER JOIN #Matches p 
    ON p.Sex = c.Sex 
    AND p.YearOfBirth = c.YearOfBirth 
    AND p.IndexDate = c.IndexDate
  WHERE c.PatientId in (
    -- find patients who currently only have 3 match(es)
select PatientId from #CohortStore group by PatientId having count(*) = 3
  )
  GROUP BY c.PatientId, c.YearOfBirth, c.Sex, c.IndexDate) sub
  WHERE sub.AssignedPersonNumber = 1;
  SELECT @LastRowInsert11=@@ROWCOUNT;

  DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #CohortStore);
END

-- 12. There are some people who we can't find a 4th match.. try relaxing the date requirement
DECLARE @LastRowInsert12 INT;
SET @LastRowInsert12=1;
WHILE ( @LastRowInsert12 > 0)
BEGIN
  INSERT INTO #CohortStore
  SELECT sub.PatientId, sub.YearOfBirth, sub.Sex, sub.IndexDate, MatchedPatientId, m.YearOfBirth, MAX(m.IndexDate) FROM (
  SELECT c.PatientId, c.YearOfBirth, c.Sex, c.IndexDate, MAX(p.PatientId) AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(p.PatientId) ORDER BY NewID()) AS AssignedPersonNumber
  FROM #Cases c
  INNER JOIN #Matches p 
    ON p.Sex = c.Sex 
    AND p.YearOfBirth = c.YearOfBirth
    AND p.IndexDate between DATEADD(day,-{param:index-date-flex},c.IndexDate) and DATEADD(day,{param:index-date-flex},c.IndexDate)
  WHERE c.PatientId in (
    -- find patients who currently only have 3 match(es)
select PatientId from #CohortStore group by PatientId having count(*) = 3
  )
  GROUP BY c.PatientId, c.YearOfBirth, c.Sex, c.IndexDate) sub
  INNER JOIN #Matches m 
    ON m.Sex = sub.Sex 
    AND m.PatientId = sub.MatchedPatientId
    AND m.YearOfBirth = sub.YearOfBirth
    AND m.IndexDate between DATEADD(day,-{param:index-date-flex},sub.IndexDate) and DATEADD(day,{param:index-date-flex},sub.IndexDate)
  WHERE sub.AssignedPersonNumber = 1
  GROUP BY sub.PatientId, sub.YearOfBirth, sub.Sex, sub.IndexDate, MatchedPatientId, m.YearOfBirth;
  SELECT @LastRowInsert12=@@ROWCOUNT;

  DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #CohortStore);
END

-- 13. There are some people who we still can't find a 4th match.. try relaxing the age and date requirement
DECLARE @LastRowInsert13 INT;
SET @LastRowInsert13=1;
WHILE ( @LastRowInsert13 > 0)
BEGIN
  INSERT INTO #CohortStore
  SELECT sub.PatientId, sub.YearOfBirth, sub.Sex, sub.IndexDate, MatchedPatientId, MAX(m.YearOfBirth), MAX(m.IndexDate) FROM (
  SELECT c.PatientId, c.YearOfBirth, c.Sex, c.IndexDate, MAX(p.PatientId) AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(p.PatientId) ORDER BY NewID()) AS AssignedPersonNumber
  FROM #Cases c
  INNER JOIN #Matches p 
    ON p.Sex = c.Sex 
    AND p.YearOfBirth >= c.YearOfBirth - {param:yob-flex}
    AND p.YearOfBirth <= c.YearOfBirth + {param:yob-flex}
    AND p.IndexDate between DATEADD(day,-{param:index-date-flex},c.IndexDate) and DATEADD(day,{param:index-date-flex},c.IndexDate)
  WHERE c.PatientId in (
    -- find patients who currently only have 3 match(es)
select PatientId from #CohortStore group by PatientId having count(*) = 3
  )
  GROUP BY c.PatientId, c.YearOfBirth, c.Sex, c.IndexDate) sub
  INNER JOIN #Matches m 
    ON m.Sex = sub.Sex 
    AND m.PatientId = sub.MatchedPatientId
    AND m.YearOfBirth >= sub.YearOfBirth - {param:yob-flex}
    AND m.YearOfBirth <= sub.YearOfBirth + {param:yob-flex}
    AND m.IndexDate between DATEADD(day,-{param:index-date-flex},sub.IndexDate) and DATEADD(day,{param:index-date-flex},sub.IndexDate)
  WHERE sub.AssignedPersonNumber = 1
  GROUP BY sub.PatientId, sub.YearOfBirth, sub.Sex, sub.IndexDate, MatchedPatientId;
  SELECT @LastRowInsert13=@@ROWCOUNT;

  DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #CohortStore);
END

--This next query shows how many people with no match, 1 match, 2 match etc.
--SELECT Num, COUNT(*) FROM ( SELECT PatientId, COUNT(*) AS Num FROM #CohortStore GROUP BY PatientId) sub GROUP BY Num UNION SELECT 0, x FROM (SELECT COUNT(*) AS x FROM (SELECT PatientId FROM #Cases EXCEPT SELECT PatientId FROM #CohortStore) sub1) sub ORDER BY Num;

-- 14. Now we focus on people with only 4 match(es) and attempt to give them another
DECLARE @LastRowInsert14 INT;
SET @LastRowInsert14=1;
WHILE ( @LastRowInsert14 > 0)
BEGIN
  INSERT INTO #CohortStore
  SELECT PatientId, YearOfBirth, Sex, IndexDate, MatchedPatientId, YearOfBirth, IndexDate FROM (
  SELECT c.PatientId, c.YearOfBirth, c.Sex, c.IndexDate, MAX(p.PatientId) AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(p.PatientId) ORDER BY NewID()) AS AssignedPersonNumber
  FROM #Cases c
  INNER JOIN #Matches p 
    ON p.Sex = c.Sex 
    AND p.YearOfBirth = c.YearOfBirth 
    AND p.IndexDate = c.IndexDate
  WHERE c.PatientId in (
    -- find patients who currently only have 4 match(es)
select PatientId from #CohortStore group by PatientId having count(*) = 4
  )
  GROUP BY c.PatientId, c.YearOfBirth, c.Sex, c.IndexDate) sub
  WHERE sub.AssignedPersonNumber = 1;
  SELECT @LastRowInsert14=@@ROWCOUNT;

  DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #CohortStore);
END

-- 15. There are some people who we can't find a 5th match.. try relaxing the date requirement
DECLARE @LastRowInsert15 INT;
SET @LastRowInsert15=1;
WHILE ( @LastRowInsert15 > 0)
BEGIN
  INSERT INTO #CohortStore
  SELECT sub.PatientId, sub.YearOfBirth, sub.Sex, sub.IndexDate, MatchedPatientId, m.YearOfBirth, MAX(m.IndexDate) FROM (
  SELECT c.PatientId, c.YearOfBirth, c.Sex, c.IndexDate, MAX(p.PatientId) AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(p.PatientId) ORDER BY NewID()) AS AssignedPersonNumber
  FROM #Cases c
  INNER JOIN #Matches p 
    ON p.Sex = c.Sex 
    AND p.YearOfBirth = c.YearOfBirth
    AND p.IndexDate between DATEADD(day,-{param:index-date-flex},c.IndexDate) and DATEADD(day,{param:index-date-flex},c.IndexDate)
  WHERE c.PatientId in (
    -- find patients who currently only have 4 match(es)
select PatientId from #CohortStore group by PatientId having count(*) = 4
  )
  GROUP BY c.PatientId, c.YearOfBirth, c.Sex, c.IndexDate) sub
  INNER JOIN #Matches m 
    ON m.Sex = sub.Sex 
    AND m.PatientId = sub.MatchedPatientId
    AND m.YearOfBirth = sub.YearOfBirth
    AND m.IndexDate between DATEADD(day,-{param:index-date-flex},sub.IndexDate) and DATEADD(day,{param:index-date-flex},sub.IndexDate)
  WHERE sub.AssignedPersonNumber = 1
  GROUP BY sub.PatientId, sub.YearOfBirth, sub.Sex, sub.IndexDate, MatchedPatientId, m.YearOfBirth;
  SELECT @LastRowInsert15=@@ROWCOUNT;

  DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #CohortStore);
END

-- 16. There are some people who we still can't find a 5th match.. try relaxing the age and date requirement
DECLARE @LastRowInsert16 INT;
SET @LastRowInsert16=1;
WHILE ( @LastRowInsert16 > 0)
BEGIN
  INSERT INTO #CohortStore
  SELECT sub.PatientId, sub.YearOfBirth, sub.Sex, sub.IndexDate, MatchedPatientId, MAX(m.YearOfBirth), MAX(m.IndexDate) FROM (
  SELECT c.PatientId, c.YearOfBirth, c.Sex, c.IndexDate, MAX(p.PatientId) AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(p.PatientId) ORDER BY NewID()) AS AssignedPersonNumber
  FROM #Cases c
  INNER JOIN #Matches p 
    ON p.Sex = c.Sex 
    AND p.YearOfBirth >= c.YearOfBirth - {param:yob-flex}
    AND p.YearOfBirth <= c.YearOfBirth + {param:yob-flex}
    AND p.IndexDate between DATEADD(day,-{param:index-date-flex},c.IndexDate) and DATEADD(day,{param:index-date-flex},c.IndexDate)
  WHERE c.PatientId in (
    -- find patients who currently only have 4 match(es)
select PatientId from #CohortStore group by PatientId having count(*) = 4
  )
  GROUP BY c.PatientId, c.YearOfBirth, c.Sex, c.IndexDate) sub
  INNER JOIN #Matches m 
    ON m.Sex = sub.Sex 
    AND m.PatientId = sub.MatchedPatientId
    AND m.YearOfBirth >= sub.YearOfBirth - {param:yob-flex}
    AND m.YearOfBirth <= sub.YearOfBirth + {param:yob-flex}
    AND m.IndexDate between DATEADD(day,-{param:index-date-flex},sub.IndexDate) and DATEADD(day,{param:index-date-flex},sub.IndexDate)
  WHERE sub.AssignedPersonNumber = 1
  GROUP BY sub.PatientId, sub.YearOfBirth, sub.Sex, sub.IndexDate, MatchedPatientId;
  SELECT @LastRowInsert16=@@ROWCOUNT;

  DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #CohortStore);
END
