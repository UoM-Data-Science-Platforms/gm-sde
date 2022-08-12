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

-- Table to store the matches
CREATE TABLE IF NOT EXISTS dars_nic_391419_j3w9t_collab.CCU040_Cohort_Store (
  PatientId string, 
  YearOfBirth INT, 
  Sex char(1), 
  FirstCovidPositiveDate DATE, 
  MatchingPatientId string,
  MatchingYearOfBirth INT,
  MatchingCovidPositiveDate DATE
);
TRUNCATE TABLE dars_nic_391419_j3w9t_collab.CCU040_Cohort_Store;

CREATE TABLE IF NOT EXISTS dars_nic_391419_j3w9t_collab.CCU040_Cohort_Store_Temp (
  PatientId string, 
  Sex char(1), 
  YearOfBirth INT, 
  FirstCovidPositiveDate DATE
);
TRUNCATE TABLE dars_nic_391419_j3w9t_collab.CCU040_Cohort_Store_Temp;



-- Now the python bit...
%python

updated = 1

while updated > 0:
  before = spark.sql(f'''SELECT COUNT(*) FROM dars_nic_391419_j3w9t_collab.CCU040_Cohort_Store''').head()[0]
  print('Records in store initially: ' + str(before))
  print('Finding patients in the potential matches who only match a single case...')

  spark.sql(f'''INSERT INTO dars_nic_391419_j3w9t_collab.CCU040_Cohort_Store
    SELECT PatientId, YearOfBirth, Sex, FirstCovidPositiveDate, MatchedPatientId, YearOfBirth, FirstCovidPositiveDate FROM (
      SELECT c.PatientId, c.YearOfBirth, c.Sex, c.FirstCovidPositiveDate, p.PatientId AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(c.PatientId) ORDER BY random()) AS AssignedPersonNumber
      FROM dars_nic_391419_j3w9t_collab.CCU040_Main_Cohort c
      INNER JOIN dars_nic_391419_j3w9t_collab.CCU040_Potential_Matches p 
        ON p.YearOfBirth = c.YearOfBirth
        AND p.FirstCovidPositiveDate = c.FirstCovidPositiveDate
      WHERE p.PatientId in (
      -- find patients in the matches who only match a single case
        select m.PatientId
        from dars_nic_391419_j3w9t_collab.CCU040_Potential_Matches m 
        inner join dars_nic_391419_j3w9t_collab.CCU040_Main_Cohort c 
          ON m.YearOfBirth = c.YearOfBirth 
          AND m.FirstCovidPositiveDate = c.FirstCovidPositiveDate
        group by m.PatientId
        having count(*) = 1
      )
      GROUP BY c.PatientId, c.YearOfBirth, c.Sex, c.FirstCovidPositiveDate, p.PatientId
    ) sub
    WHERE AssignedPersonNumber <= 5
    ORDER BY PatientId''')

  print("Removing from cases anyone we've already got n for...")

  spark.sql(f'''TRUNCATE TABLE dars_nic_391419_j3w9t_collab.CCU040_Cohort_Store_Temp''')

  spark.sql(f'''INSERT INTO dars_nic_391419_j3w9t_collab.CCU040_Cohort_Store_Temp
    SELECT * FROM dars_nic_391419_j3w9t_collab.CCU040_Main_Cohort
    where PatientId in (
    select PatientId FROM dars_nic_391419_j3w9t_collab.CCU040_Main_Cohort
    EXCEPT (
      select PatientId FROM dars_nic_391419_j3w9t_collab.CCU040_Cohort_Store
      group by PatientId
      having count(*) >= 5)
    );''')

  spark.sql(f'''TRUNCATE TABLE dars_nic_391419_j3w9t_collab.CCU040_Main_Cohort''')

  spark.sql(f'''INSERT INTO dars_nic_391419_j3w9t_collab.CCU040_Main_Cohort
    SELECT * FROM dars_nic_391419_j3w9t_collab.CCU040_Cohort_Store_Temp''')

  print("Removing from matches anyone we've already used...")

  spark.sql(f'''TRUNCATE TABLE dars_nic_391419_j3w9t_collab.CCU040_Cohort_Store_Temp''')

  spark.sql(f'''INSERT INTO dars_nic_391419_j3w9t_collab.CCU040_Cohort_Store_Temp
    SELECT * FROM dars_nic_391419_j3w9t_collab.CCU040_Potential_Matches
    where PatientId in (
      select PatientId FROM dars_nic_391419_j3w9t_collab.CCU040_Potential_Matches
      EXCEPT
      select MatchingPatientId FROM dars_nic_391419_j3w9t_collab.CCU040_Cohort_Store
    );''')

  spark.sql(f'''TRUNCATE TABLE dars_nic_391419_j3w9t_collab.CCU040_Potential_Matches''')

  spark.sql(f'''INSERT INTO dars_nic_391419_j3w9t_collab.CCU040_Potential_Matches
    SELECT * FROM dars_nic_391419_j3w9t_collab.CCU040_Cohort_Store_Temp''')

  after = spark.sql(f'''SELECT COUNT(*) FROM dars_nic_391419_j3w9t_collab.CCU040_Cohort_Store''').head()[0]
  print('Records in store after inserts: ' + str(after))

  updated = after - before
  print('Records updated: ' + str(updated))

print('done')
