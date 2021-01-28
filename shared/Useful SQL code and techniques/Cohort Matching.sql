-- Cohort matching on static things e.g. age, sex, lsoa on a fixed date

-- This assumes matching on age and sex, but can be extended to other fields

-- Requires two temp tables. The first (#PrimaryCohort) contains the cohort 
-- to be matched. If matching on age and sex the table would have columns: 
-- PatientId, Age, Sex
-- The second table (#PotentialMatches) is the pool of potential matches. It
-- should have the same columns as the first table and will only contain people
-- who don't already appear in the first table

-- First we extend the #PrimaryCohort table to give each age-sex combo a unique number
IF OBJECT_ID('tempdb..#Cases') IS NOT NULL DROP TABLE #Cases;
SELECT PatientId, Age, Sex, Row_Number() OVER(PARTITION BY Age, Sex ORDER BY PatientId) AS CaseRowNumber
INTO #Cases FROM #PrimaryCohort;

-- Then we do the same with the #PotentialMatches
IF OBJECT_ID('tempdb..#Matches') IS NOT NULL DROP TABLE #Matches;
SELECT PatientId, Age, Sex, Row_Number() OVER(PARTITION BY Age, Sex ORDER BY NewID()) AS AssignedPersonNumber
INTO #Matches FROM #PotentialMatches;

-- Find the number of people with each characteristic in the main cohort
IF OBJECT_ID('tempdb..#CharacteristicCount') IS NOT NULL DROP TABLE #CharacteristicCount;
SELECT Age, Sex, COUNT(*) AS [Count] INTO #CharacteristicCount FROM #Cases GROUP BY Age, Sex;

-- Find the number of potential matches for each Age/Sex combination
-- The output of this is useful for seeing how many matches you can get
SELECT A.Age, A.Sex, B.Count / A.Count AS NumberOfPotentialMatches FROM 
(SELECT * FROM #CharacteristicCount) A 
LEFT OUTER JOIN 
(SELECT Age, Sex, COUNT(*) AS [Count] FROM #Matches GROUP BY Age, Sex) B
ON B.Age = A.Age AND B.Sex = A.Sex
ORDER BY NumberOfPotentialMatches,A.Age,A.Sex;

-- Finally we get up to n matches for each person
DECLARE @NumMatches INT;
SET @NumMatches = 5; -- change this to attempt more matches

-- The final table contains a row for each match, so e.g. if patient 1 has 4
-- matches then there will be 4 rows in the table for this.
IF OBJECT_ID('tempdb..#FinalMatching') IS NOT NULL DROP TABLE #FinalMatching;
CREATE TABLE #FinalMatching (PatientId INT, Age INT, Sex nchar(1), MatchingPatientId INT);
DECLARE @Counter INT; 
SET @Counter=1;
-- In this loop we find one match at a time for each patient in the cohort
WHILE ( @Counter <= @NumMatches)
BEGIN
  INSERT INTO #FinalMatching
  SELECT c.PatientId, c.Age, c.Sex, p.PatientId AS MatchedPatientId
  FROM #Cases c
    INNER JOIN #CharacteristicCount cc on cc.Age = c.Age and cc.Sex = c.Sex
    INNER JOIN #Matches p 
      ON p.Sex = c.Sex 
      AND p.Age = c.Age 
      -- This next line is the trick to only matching each person once
      AND p.AssignedPersonNumber = CaseRowNumber + (@counter - 1) * cc.[Count]
  ORDER BY c.PatientId, p.PatientId;

  -- We might not need this, but to be extra sure let's delete any patients who 
  -- we're already using to match people
  DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #FinalMatching);

  SET @Counter  = @Counter  + 1
END
