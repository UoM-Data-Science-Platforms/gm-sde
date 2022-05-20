%md
# Obtain matching cohort

**Desciption** To get a matched cohort for the patients with COVID and DM

**Author** Richard Williams

**Github** [https://github.com/rw251/gm-idcr/tree/master/projects/NATIONAL-CCU040-Diabetes](https://github.com/rw251/gm-idcr/tree/master/projects/NATIONAL%20-%20CCU040%20-%20Diabetes)

**Date last updated** /*__date__*/

## Notes

TODO

## Input
Assumes there exist two global temp views: CCU040_MainCohort and CCU040_PotentialMatches

## Output
TODO
**Table name** global_temp.CCU040_LSOA

| Column    | Type   | Description       |
| ----------| ------ | ----------------- |
| PatientId | string | Unique patient id |
| LSOA      | string | The patients LSOA |

-- First let's crystallise the views into actual tables to improve query execution
CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_MainCohort
AS
SELECT * FROM global_temp.CCU040_MainCohort;

DROP TABLE IF EXISTS dars_nic_391419_j3w9t_collab.CCU040_MainCohort_Male;
CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_MainCohort_Male
AS
SELECT PatientId, YearOfBirth, FirstCovidPositiveDate FROM dars_nic_391419_j3w9t_collab.CCU040_MainCohort
WHERE Sex = 1;

DROP TABLE IF EXISTS dars_nic_391419_j3w9t_collab.CCU040_MainCohort_Female;
CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_MainCohort_Female
AS
SELECT PatientId, YearOfBirth, FirstCovidPositiveDate FROM dars_nic_391419_j3w9t_collab.CCU040_MainCohort
WHERE Sex = 2;

CREATE TABLE dars_nic_391419_j3w9t_collab.CCU040_PotentialMatches_Male
AS
SELECT PatientId, YearOfBirth, FirstCovidPositiveDate FROM global_temp.CCU040_PotentialMatches
WHERE Sex = 1;

-- Table to store the matches
CREATE TABLE IF NOT EXISTS dars_nic_391419_j3w9t_collab.CCU040_CohortStore (
  PatientId string, 
  YearOfBirth INT, 
  Sex nchar(1), 
  FirstCovidPositiveDate DATE, 
  MatchingPatientId string,
  MatchingYearOfBirth INT,
  MatchingCovidPositiveDate DATE
);
TRUNCATE TABLE dars_nic_391419_j3w9t_collab.CCU040_CohortStore;

-- 1. If anyone only matches one case then use them. Remove and repeat until everyone matches
--    multiple people or until the CCU040_MainCohort table is empty
DO $$
DECLARE LastRowInsert INTEGER :=1; 
BEGIN  
  WHILE LastRowInsert > 0 LOOP
  -- match them
  INSERT INTO dars_nic_391419_j3w9t_collab.CCU040_CohortStore
  SELECT PatientId, YearOfBirth, Sex, FirstCovidPositiveDate, MatchedPatientId, YearOfBirth, FirstCovidPositiveDate FROM (
	  SELECT c.PatientId, c.YearOfBirth, c.Sex, c.FirstCovidPositiveDate, p.PatientId AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(c.PatientId) ORDER BY gen_random_uuid()) AS AssignedPersonNumber
	  FROM dars_nic_391419_j3w9t_collab.CCU040_MainCohort c
		INNER JOIN dars_nic_391419_j3w9t_collab.CCU040_PotentialMatches p 
		  ON p.Sex = c.Sex 
		  AND p.YearOfBirth = c.YearOfBirth 
		  AND p.FirstCovidPositiveDate = c.FirstCovidPositiveDate
		WHERE p.PatientId in (
		-- find patients in the matches who only match a single case
			select m.PatientId
		  from dars_nic_391419_j3w9t_collab.CCU040_PotentialMatches m 
		  inner join dars_nic_391419_j3w9t_collab.CCU040_MainCohort c ON m.Sex = c.Sex 
			  AND m.YearOfBirth = c.YearOfBirth 
			  AND m.FirstCovidPositiveDate = c.FirstCovidPositiveDate
			group by m.PatientId
			having count(*) = 1
		)
	  GROUP BY c.PatientId, c.YearOfBirth, c.Sex, c.FirstCovidPositiveDate, p.PatientId
	) sub
	WHERE AssignedPersonNumber <= 5
  ORDER BY PatientId;
  GET DIAGNOSTICS LastRowInsert = ROW_COUNT;
  
  -- remove from cases anyone we've already got n for
  delete from dars_nic_391419_j3w9t_collab.CCU040_MainCohort where PatientId in (
  select PatientId FROM dars_nic_391419_j3w9t_collab.CCU040_CohortStore
  group by PatientId
  having count(*) >= 5);

  -- remove from matches anyone already used
  DELETE FROM dars_nic_391419_j3w9t_collab.CCU040_PotentialMatches WHERE PatientId IN (SELECT MatchingPatientId FROM dars_nic_391419_j3w9t_collab.CCU040_CohortStore);
END
