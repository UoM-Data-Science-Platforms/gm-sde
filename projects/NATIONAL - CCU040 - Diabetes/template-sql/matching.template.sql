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

-- SPLIT HERE --

-- Create copies of the main cohort and potential matches tables in order to avoid pollution
CREATE TABLE IF NOT EXISTS dars_nic_391419_j3w9t_collab.CCU040_01_Cases (
  PatientId string,
  Sex char(1),
  YearOfBirth INT,
  FirstCovidPositiveDate DATE
);

TRUNCATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Cases;

INSERT INTO dars_nic_391419_j3w9t_collab.CCU040_01_Cases
SELECT * FROM dars_nic_391419_j3w9t_collab.CCU040_Main_Cohort;

CREATE TABLE IF NOT EXISTS dars_nic_391419_j3w9t_collab.CCU040_01_Matches (
  PatientId string,
  Sex char(1),
  YearOfBirth INT,
  FirstCovidPositiveDate DATE
);

TRUNCATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Matches;

INSERT INTO dars_nic_391419_j3w9t_collab.CCU040_01_Matches
SELECT * FROM dars_nic_391419_j3w9t_collab.CCU040_Potential_Matches;

-- SPLIT HERE --

-- Display how many people in cohort have 0, 1, 2 etc matches
SELECT Num, COUNT(*) FROM (
  SELECT PatientId, COUNT(*) As Num
  FROM dars_nic_391419_j3w9t_collab.CCU040_Cohort_Store
  GROUP BY PatientId
)
GROUP BY Num
UNION
SELECT 0, x FROM (
  SELECT COUNT(*) AS x FROM (
    SELECT PatientId FROM dars_nic_391419_j3w9t_collab.CCU040_01_Cases
    EXCEPT
    SELECT PatientId FROM dars_nic_391419_j3w9t_collab.CCU040_Cohort_Store
  )
)
ORDER BY Num;

-- SPLIT HERE --

%python

# 1. If anyone only matches one case then use them. Remove and repeat until everyone matches
#    multiple people or until the CCU040_01_Cases table is empty

updated = 1

while updated > 0:
  before = spark.sql(f'''SELECT COUNT(*) FROM dars_nic_391419_j3w9t_collab.CCU040_Cohort_Store''').head()[0]
  print('Records in store initially: ' + str(before))
  print('Finding patients in the potential matches who only match a single case...')

  spark.sql(f'''INSERT INTO dars_nic_391419_j3w9t_collab.CCU040_Cohort_Store
    SELECT PatientId, YearOfBirth, Sex, FirstCovidPositiveDate, MatchedPatientId, YearOfBirth, FirstCovidPositiveDate FROM (
      SELECT c.PatientId, c.YearOfBirth, c.Sex, c.FirstCovidPositiveDate, p.PatientId AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(c.PatientId) ORDER BY random()) AS AssignedPersonNumber
      FROM dars_nic_391419_j3w9t_collab.CCU040_01_Cases c
      INNER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Matches p 
        ON p.YearOfBirth = c.YearOfBirth
        AND p.Sex = c.Sex
        AND p.FirstCovidPositiveDate = c.FirstCovidPositiveDate
      WHERE p.PatientId in (
      -- find patients in the matches who only match a single case
        select m.PatientId
        from dars_nic_391419_j3w9t_collab.CCU040_01_Matches m 
        inner join dars_nic_391419_j3w9t_collab.CCU040_01_Cases c 
          ON m.YearOfBirth = c.YearOfBirth 
          AND m.FirstCovidPositiveDate = c.FirstCovidPositiveDate
        group by m.PatientId
        having count(*) = 1
      )
      GROUP BY c.PatientId, c.YearOfBirth, c.Sex, c.FirstCovidPositiveDate, p.PatientId
    ) sub
    WHERE AssignedPersonNumber <= 5
    ORDER BY PatientId''')

  print("Removing from the main cohort anyone we've already got the required number of matches for...")

  spark.sql(f'''TRUNCATE TABLE dars_nic_391419_j3w9t_collab.CCU040_Cohort_Store_Temp''')
  spark.sql(f'''INSERT INTO dars_nic_391419_j3w9t_collab.CCU040_Cohort_Store_Temp
    SELECT * FROM dars_nic_391419_j3w9t_collab.CCU040_01_Cases
    where PatientId in (
    select PatientId FROM dars_nic_391419_j3w9t_collab.CCU040_01_Cases
    EXCEPT (
      select PatientId FROM dars_nic_391419_j3w9t_collab.CCU040_Cohort_Store
      group by PatientId
      having count(*) >= 5)
    );''')
  spark.sql(f'''TRUNCATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Cases''')
  spark.sql(f'''INSERT INTO dars_nic_391419_j3w9t_collab.CCU040_01_Cases
    SELECT * FROM dars_nic_391419_j3w9t_collab.CCU040_Cohort_Store_Temp''')

  print("Removing from the potential matches anyone we've already used...")

  spark.sql(f'''TRUNCATE TABLE dars_nic_391419_j3w9t_collab.CCU040_Cohort_Store_Temp''')
  spark.sql(f'''INSERT INTO dars_nic_391419_j3w9t_collab.CCU040_Cohort_Store_Temp
    SELECT * FROM dars_nic_391419_j3w9t_collab.CCU040_01_Matches
    where PatientId in (
      select PatientId FROM dars_nic_391419_j3w9t_collab.CCU040_01_Matches
      EXCEPT
      select MatchingPatientId FROM dars_nic_391419_j3w9t_collab.CCU040_Cohort_Store
    );''')
  spark.sql(f'''TRUNCATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Matches''')
  spark.sql(f'''INSERT INTO dars_nic_391419_j3w9t_collab.CCU040_01_Matches
    SELECT * FROM dars_nic_391419_j3w9t_collab.CCU040_Cohort_Store_Temp''')

  after = spark.sql(f'''SELECT COUNT(*) FROM dars_nic_391419_j3w9t_collab.CCU040_Cohort_Store''').head()[0]
  print('Records in store after inserts: ' + str(after))

  updated = after - before
  print('Records updated: ' + str(updated))

  if updated > 0:
    print('Records inserted, so lets try it all again.')

print('done')


-- SPLIT HERE --

%python

# 2. Now we focus on people without any matches and try and give everyone a match

updated = 1

while updated > 0:
  before = spark.sql(f'''SELECT COUNT(*) FROM dars_nic_391419_j3w9t_collab.CCU040_Cohort_Store''').head()[0]
  print('Records in store initially: ' + str(before))
  print('Finding a match for patients who are not currently matched...')

  spark.sql(f'''INSERT INTO dars_nic_391419_j3w9t_collab.CCU040_Cohort_Store
    SELECT PatientId, YearOfBirth, Sex, FirstCovidPositiveDate, MatchedPatientId, YearOfBirth, FirstCovidPositiveDate FROM (
      SELECT c.PatientId, c.YearOfBirth, c.Sex, c.FirstCovidPositiveDate, MAX(p.PatientId) AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(p.PatientId) ORDER BY random()) AS AssignedPersonNumber
      FROM dars_nic_391419_j3w9t_collab.CCU040_01_Cases c
      INNER JOIN dars_nic_391419_j3w9t_collab.CCU040_01_Matches p 
        ON p.YearOfBirth = c.YearOfBirth
        AND p.Sex = c.Sex
        AND p.FirstCovidPositiveDate = c.FirstCovidPositiveDate
      WHERE c.PatientId in (
      -- find patients who are not currently matched
        select PatientId from dars_nic_391419_j3w9t_collab.CCU040_01_Cases 
        except
        select PatientId from dars_nic_391419_j3w9t_collab.CCU040_Cohort_Store
      )
      GROUP BY c.PatientId, c.YearOfBirth, c.Sex, c.FirstCovidPositiveDate
    )
    WHERE AssignedPersonNumber = 1;''')

  print("Removing from the potential matches anyone we've already used...")

  spark.sql(f'''TRUNCATE TABLE dars_nic_391419_j3w9t_collab.CCU040_Cohort_Store_Temp''')
  spark.sql(f'''INSERT INTO dars_nic_391419_j3w9t_collab.CCU040_Cohort_Store_Temp
    SELECT * FROM dars_nic_391419_j3w9t_collab.CCU040_01_Matches
    where PatientId in (
      select PatientId FROM dars_nic_391419_j3w9t_collab.CCU040_01_Matches
      EXCEPT
      select MatchingPatientId FROM dars_nic_391419_j3w9t_collab.CCU040_Cohort_Store
    );''')
  spark.sql(f'''TRUNCATE TABLE dars_nic_391419_j3w9t_collab.CCU040_01_Matches''')
  spark.sql(f'''INSERT INTO dars_nic_391419_j3w9t_collab.CCU040_01_Matches
    SELECT * FROM dars_nic_391419_j3w9t_collab.CCU040_Cohort_Store_Temp''')

  after = spark.sql(f'''SELECT COUNT(*) FROM dars_nic_391419_j3w9t_collab.CCU040_Cohort_Store''').head()[0]
  print('Records in store after inserts: ' + str(after))

  updated = after - before
  print('Records updated: ' + str(updated))

  if updated > 0:
    print('Records inserted, so lets try it all again.')

print('done')


-- SOME TEST CODE TO SEE IF WE CAN DO THIS IN PYTHON IN MEMORY
%python

# Pull the cohort data and the potential matches (pool) into pandas dataframes
df_cohort = spark.table('dars_nic_391419_j3w9t_collab.CCU040_Main_Cohort').select("*").toPandas();
df_pool = spark.table('dars_nic_391419_j3w9t_collab.CCU040_Potential_Matches').select("*").toPandas();

-- SPLIT HERE --

%python
import pandas as pd;

# Get the frequency of each sex/year of birth/covid date combination

df_cohort_combos = df_cohort.groupby(['Sex','YearOfBirth', 'FirstCovidPositiveDate']).size().reset_index(name='Freq')
df_pool_combos = df_pool.groupby(['Sex','YearOfBirth', 'FirstCovidPositiveDate']).size().reset_index(name='Freq')

print('There are ' + str(df_cohort.Sex.size) + ' patients in the cohort and ' + str(df_cohort_combos.Sex.size) + ' unique combinations of Sex/YearOfBirth/CovidDate.')
print('There are ' + str(df_pool.Sex.size) + ' patients in the matching pool and ' + str(df_pool_combos.Sex.size) + ' unique combinations of Sex/YearOfBirth/CovidDate.')

-- SPLIT HERE --

%python
import pandas as pd;

# Merge the two dataframes to find any combination of categories where the pool has >=3x the number of the cohort.
# These are all people where there are enough matches already without flexing the year of birth or covid date

df_cohort_pool_merged = pd.merge(df_cohort_combos, df_pool_combos, on=['Sex','YearOfBirth', 'FirstCovidPositiveDate'])
df_combos_with_enough_matches = df_cohort_pool_merged[(df_cohort_pool_merged.Freq_x*3 <= df_cohort_pool_merged.Freq_y)]

print('There are ' + str(df_combos_with_enough_matches.Sex.size) + ' combinations (out of ' + str(df_cohort_combos.Sex.size) + ') with sufficient matches. This represents ' + str(df_combos_with_enough_matches.Freq_x.sum()) + ' patients (out of ' + str(df_cohort.Sex.size) + ').')

-- SPLIT HERE --

%python
import pandas as pd;

# Add ids to patients so that the matching does not reuse people from the pool more than once

df_cohort['Group_id'] = df_cohort.groupby(['Sex','YearOfBirth', 'FirstCovidPositiveDate']).cumcount()
df_pool['Group_id'] = df_pool.groupby(['Sex','YearOfBirth', 'FirstCovidPositiveDate']).cumcount()

# We want a 3:1 matching, so flatten the matching pool ids so the 3 have 0, 3 have 1, 3 have 2 etc.
df_pool['Group_id_flattened'] = df_pool.apply(lambda row: row.Group_id //3, axis = 1) # //3 divides without remainder

-- SPLIT HERE --

%python
import pandas as pd;

# Populate a dataframe with cohort patients and their 3 matches from the pool

df_patients_with_matches = pd.merge(df_cohort, pd.merge(df_combos_with_enough_matches, df_pool, on=['Sex','YearOfBirth', 'FirstCovidPositiveDate'], sort=False),left_on=['Sex','YearOfBirth', 'FirstCovidPositiveDate', 'Group_id'],right_on=['Sex','YearOfBirth', 'FirstCovidPositiveDate', 'Group_id_flattened'],sort=False).sort_values(by=['Sex','YearOfBirth', 'FirstCovidPositiveDate'])
df_patients_with_matches = df_patients_with_matches.drop(['Group_id_x','Freq_x','Freq_y','Group_id_y','Group_id_flattened'], axis=1)
df_patients_with_matches = df_patients_with_matches.rename(columns={'PatientId_x': 'PatientId', 'PatientId_y': 'MatchingPatientId'})
df_patients_with_matches['MatchingYearOfBirth'] = df_patients_with_matches.YearOfBirth
df_patients_with_matches['MatchingFirstCovidPositiveDate'] = df_patients_with_matches.FirstCovidPositiveDate
print('We just found matches for ' + str(df_patients_with_matches.PatientId.drop_duplicates().size) + ' patients.')

-- SPLIT HERE --

%python
import pandas as pd;

# We now create a dataframe with all the as yet unmatched cohort patients, and a
# dataframe for the unused patients in the matching pool

df_cohort_unmatched = df_cohort[df_cohort.PatientId.isin(df_patients_with_matches.PatientId.drop_duplicates()) == False]
df_pool_unused = df_pool[df_pool.PatientId.isin(df_patients_with_matches.MatchingPatientId) == False]

print('There are ' + str(df_cohort_unmatched.Sex.size) + ' patients in the cohort as yet unmatched.')
print('There are ' + str(df_pool_unused.Sex.size) + ' unused patients in the matching pool.')

-- SPLIT HERE --

%python
import pandas as pd;

# Add a week number to each patient to flex the matching on date

df_cohort_unmatched['week'] = df_cohort_unmatched.apply(lambda row: row.FirstCovidPositiveDate.toordinal()//7, axis = 1)
df_pool_unused['week'] = df_pool_unused.apply(lambda row: row.FirstCovidPositiveDate.toordinal()//7, axis = 1)

# Get the frequency of each sex/year of birth/covid week combination

df_cohort_combos_week = df_cohort_unmatched.groupby(['Sex','YearOfBirth', 'week']).size().reset_index(name='Freq')
df_pool_combos_week = df_pool_unused.groupby(['Sex','YearOfBirth', 'week']).size().reset_index(name='Freq')

print('There are ' + str(df_cohort_unmatched.Sex.size) + ' unmatched patients in the cohort and ' + str(df_cohort_combos_week.Sex.size) + ' unique combinations of Sex/YearOfBirth/CovidWeek.')
print('There are ' + str(df_pool_unused.Sex.size) + ' unused patients in the matching pool and ' + str(df_pool_combos_week.Sex.size) + ' unique combinations of Sex/YearOfBirth/CovidWeek.')

-- SPLIT HERE --
%python
import pandas as pd;

# Merge the two dataframes to find any combination of categories where the pool has >=3x the number of the cohort.
# These are all people where there are enough matches by flexing the covid date, but not the year of birth.

df_cohort_pool_week_merged = pd.merge(df_cohort_combos_week, df_pool_combos_week, on=['Sex','YearOfBirth', 'week'])
df_combos_with_enough_matches_week = df_cohort_pool_week_merged[(df_cohort_pool_week_merged.Freq_x*3 <= df_cohort_pool_week_merged.Freq_y)]

print('There are ' + str(df_combos_with_enough_matches_week.Sex.size) + ' combinations (out of ' + str(df_cohort_combos_week.Sex.size) + ') with sufficient matches. This represents ' + str(df_combos_with_enough_matches_week.Freq_x.sum()) + ' patients (out of ' + str(df_cohort_unmatched.Sex.size) + ').')

-- SPLIT HERE --

%python
import pandas as pd;

# Update the ids

df_cohort_unmatched['Group_id'] = df_cohort_unmatched.groupby(['Sex','YearOfBirth', 'week']).cumcount()
df_pool_unused['Group_id'] = df_pool_unused.groupby(['Sex','YearOfBirth', 'week']).cumcount()

# We want a 3:1 matching, so flatten the matching pool ids so the 3 have 0, 3 have 1, 3 have 2 etc.
df_pool_unused['Group_id_flattened'] = df_pool_unused.apply(lambda row: row.Group_id //3, axis = 1) # //3 divides without remainder

-- SPLIT HERE --

%python
import pandas as pd;

# Populate a dataframe with cohort patients and their 3 matches from the pool

df_patients_with_matches_week = pd.merge(
  df_cohort_unmatched,
  pd.merge(
    df_combos_with_enough_matches_week,
    df_pool_unused,
    on=['Sex','YearOfBirth', 'week'],
    sort=False
  ),
  left_on=['Sex','YearOfBirth', 'week', 'Group_id'],
  right_on=['Sex','YearOfBirth', 'week', 'Group_id_flattened'],
  sort=False
).sort_values(by=['Sex','YearOfBirth', 'week']
).drop(['Group_id_x','week','Freq_x','Freq_y','Group_id_y','Group_id_flattened'], axis=1
).rename(
  columns={'PatientId_x': 'PatientId', 'PatientId_y': 'MatchingPatientId', 'FirstCovidPositiveDate_x': 'FirstCovidPositiveDate', 'FirstCovidPositiveDate_y': 'MatchingFirstCovidPositiveDate'}
)

df_patients_with_matches_week['MatchingYearOfBirth'] = df_patients_with_matches_week.YearOfBirth

print('We just found matches for ' + str(df_patients_with_matches_week.PatientId.drop_duplicates().size) + ' patients.')

-- SPLIT HERE --

%python
import pandas as pd;

# Add the new matches to the collection
df_patients_with_matches = pd.concat([df_patients_with_matches,df_patients_with_matches_week])

print('We now have matches for ' + str(df_patients_with_matches.PatientId.drop_duplicates().size) + ' patients.')





























-- SPLIT HERE --

%python
import pandas as pd;

# Update the dataframes with all the as yet unmatched cohort patients, and a
# dataframe for the unused patients in the matching pool

df_cohort_unmatched = df_cohort_unmatched[df_cohort_unmatched.PatientId.isin(df_patients_with_matches.PatientId.drop_duplicates()) == False]
df_pool_unused = df_pool_unused[df_pool_unused.PatientId.isin(df_patients_with_matches.MatchingPatientId) == False]

print('There are ' + str(df_cohort_unmatched.Sex.size) + ' patients in the cohort as yet unmatched.')
print('There are ' + str(df_pool_unused.Sex.size) + ' unused patients in the matching pool.')

-- SPLIT HERE --

%python
import pandas as pd;

# Add a week number to each patient to flex the matching on date

df_cohort_unmatched['week'] = df_cohort_unmatched.apply(lambda row: row.FirstCovidPositiveDate.toordinal()//7, axis = 1)
df_pool_unused['week'] = df_pool_unused.apply(lambda row: row.FirstCovidPositiveDate.toordinal()//7, axis = 1)

# Add a 5 year age buffer

df_cohort_unmatched['yob_range'] = df_cohort_unmatched.apply(lambda row: 5*(row.YearOfBirth//5), axis = 1)
df_pool_unused['yob_range'] = df_pool_unused.apply(lambda row: 5*(row.YearOfBirth//5), axis = 1)

# Get the frequency of each sex/year of birth range/covid week combination

df_cohort_combos_week_yob = df_cohort_unmatched.groupby(['Sex','yob_range', 'week']).size().reset_index(name='Freq')
df_pool_combos_week_yob = df_pool_unused.groupby(['Sex','yob_range', 'week']).size().reset_index(name='Freq')

print('There are ' + str(df_cohort_unmatched.Sex.size) + ' unmatched patients in the cohort and ' + str(df_cohort_combos_week_yob.Sex.size) + ' unique combinations of Sex/YearOfBirthRange/CovidWeek.')
print('There are ' + str(df_pool_unused.Sex.size) + ' unused patients in the matching pool and ' + str(df_pool_combos_week_yob.Sex.size) + ' unique combinations of Sex/YearOfBirthRange/CovidWeek.')

-- SPLIT HERE --
%python
import pandas as pd;

# Merge the two dataframes to find any combination of categories where the pool has >=3x the number of the cohort.
# These are all people where there are enough matches by flexing the covid date, but not the year of birth.

df_cohort_pool_week_yob_merged = pd.merge(df_cohort_combos_week_yob, df_pool_combos_week_yob, on=['Sex','yob_range', 'week'])
df_combos_with_enough_matches_week_yob = df_cohort_pool_week_yob_merged[(df_cohort_pool_week_yob_merged.Freq_x*3 <= df_cohort_pool_week_yob_merged.Freq_y)]

print('There are ' + str(df_combos_with_enough_matches_week_yob.Sex.size) + ' combinations (out of ' + str(df_cohort_combos_week_yob.Sex.size) + ') with sufficient matches. This represents ' + str(df_combos_with_enough_matches_week_yob.Freq_x.sum()) + ' patients (out of ' + str(df_cohort_unmatched.Sex.size) + ').')

-- SPLIT HERE --

%python
import pandas as pd;

# Update the ids

df_cohort_unmatched['Group_id'] = df_cohort_unmatched.groupby(['Sex','yob_range', 'week']).cumcount()
df_pool_unused['Group_id'] = df_pool_unused.groupby(['Sex','yob_range', 'week']).cumcount()

# We want a 3:1 matching, so flatten the matching pool ids so the 3 have 0, 3 have 1, 3 have 2 etc.
df_pool_unused['Group_id_flattened'] = df_pool_unused.apply(lambda row: row.Group_id //3, axis = 1) # //3 divides without remainder

-- SPLIT HERE --

%python
import pandas as pd;

# Populate a dataframe with cohort patients and their 3 matches from the pool

df_patients_with_matches_week_yob = pd.merge(
  df_cohort_unmatched,
  pd.merge(
    df_combos_with_enough_matches_week_yob,
    df_pool_unused,
    on=['Sex','yob_range', 'week'],
    sort=False
  ),
  left_on=['Sex','yob_range', 'week', 'Group_id'],
  right_on=['Sex','yob_range', 'week', 'Group_id_flattened'],
  sort=False
).sort_values(by=['Sex','yob_range', 'week']
).drop(['Group_id_x','week','Freq_x','Freq_y','Group_id_y','Group_id_flattened','yob_range'], axis=1
).rename(
  columns={'PatientId_x': 'PatientId', 'PatientId_y': 'MatchingPatientId', 'YearOfBirth_x':'YearOfBirth','YearOfBirth_y':'MatchingYearOfBirth', 'FirstCovidPositiveDate_x': 'FirstCovidPositiveDate', 'FirstCovidPositiveDate_y': 'MatchingFirstCovidPositiveDate'}
)

print('We just found matches for ' + str(df_patients_with_matches_week_yob.PatientId.drop_duplicates().size) + ' patients.')

-- SPLIT HERE --

%python
import pandas as pd;

# Add the new matches to the collection
df_patients_with_matches = pd.concat([df_patients_with_matches,df_patients_with_matches_week_yob])

print('We now have matches for ' + str(df_patients_with_matches.PatientId.drop_duplicates().size) + ' patients.')


















-- SPLIT HERE --

%python
import pandas as pd;

# Update the dataframes with all the as yet unmatched cohort patients, and a
# dataframe for the unused patients in the matching pool

df_cohort_unmatched = df_cohort_unmatched[df_cohort_unmatched.PatientId.isin(df_patients_with_matches.PatientId.drop_duplicates()) == False]
df_pool_unused = df_pool_unused[df_pool_unused.PatientId.isin(df_patients_with_matches.MatchingPatientId) == False]

print('There are ' + str(df_cohort_unmatched.Sex.size) + ' patients in the cohort as yet unmatched.')
print('There are ' + str(df_pool_unused.Sex.size) + ' unused patients in the matching pool.')

# Add a 4-week number to each patient to flex the matching on date

df_cohort_unmatched['week'] = df_cohort_unmatched.apply(lambda row: row.FirstCovidPositiveDate.toordinal()//28, axis = 1)
df_pool_unused['week'] = df_pool_unused.apply(lambda row: row.FirstCovidPositiveDate.toordinal()//28, axis = 1)

# Add a 10 year age buffer

df_cohort_unmatched['yob_range'] = df_cohort_unmatched.apply(lambda row: 10*(row.YearOfBirth//10), axis = 1)
df_pool_unused['yob_range'] = df_pool_unused.apply(lambda row: 10*(row.YearOfBirth//10), axis = 1)

# Get the frequency of each sex/year of birth range/covid week combination

df_cohort_combos_week_yob = df_cohort_unmatched.groupby(['Sex','yob_range', 'week']).size().reset_index(name='Freq')
df_pool_combos_week_yob = df_pool_unused.groupby(['Sex','yob_range', 'week']).size().reset_index(name='Freq')

print('There are ' + str(df_cohort_unmatched.Sex.size) + ' unmatched patients in the cohort and ' + str(df_cohort_combos_week_yob.Sex.size) + ' unique combinations of Sex/YearOfBirthRange/CovidWeek.')
print('There are ' + str(df_pool_unused.Sex.size) + ' unused patients in the matching pool and ' + str(df_pool_combos_week_yob.Sex.size) + ' unique combinations of Sex/YearOfBirthRange/CovidWeek.')

# Merge the two dataframes to find any combination of categories where the pool has >=3x the number of the cohort.
# These are all people where there are enough matches by flexing the covid date, but not the year of birth.

df_cohort_pool_week_yob_merged = pd.merge(df_cohort_combos_week_yob, df_pool_combos_week_yob, on=['Sex','yob_range', 'week'])
df_combos_with_enough_matches_week_yob = df_cohort_pool_week_yob_merged[(df_cohort_pool_week_yob_merged.Freq_x*3 <= df_cohort_pool_week_yob_merged.Freq_y)]

print('There are ' + str(df_combos_with_enough_matches_week_yob.Sex.size) + ' combinations (out of ' + str(df_cohort_combos_week_yob.Sex.size) + ') with sufficient matches. This represents ' + str(df_combos_with_enough_matches_week_yob.Freq_x.sum()) + ' patients (out of ' + str(df_cohort_unmatched.Sex.size) + ').')

# Update the ids

df_cohort_unmatched['Group_id'] = df_cohort_unmatched.groupby(['Sex','yob_range', 'week']).cumcount()
df_pool_unused['Group_id'] = df_pool_unused.groupby(['Sex','yob_range', 'week']).cumcount()

# We want a 3:1 matching, so flatten the matching pool ids so the 3 have 0, 3 have 1, 3 have 2 etc.
df_pool_unused['Group_id_flattened'] = df_pool_unused.apply(lambda row: row.Group_id //3, axis = 1) # //3 divides without remainder

-- SPLIT HERE --

%python
import pandas as pd;

# Populate a dataframe with cohort patients and their 3 matches from the pool

df_patients_with_matches_week_yob = pd.merge(
  df_cohort_unmatched,
  pd.merge(
    df_combos_with_enough_matches_week_yob,
    df_pool_unused,
    on=['Sex','yob_range', 'week'],
    sort=False
  ),
  left_on=['Sex','yob_range', 'week', 'Group_id'],
  right_on=['Sex','yob_range', 'week', 'Group_id_flattened'],
  sort=False
).sort_values(by=['Sex','yob_range', 'week']
).drop(['Group_id_x','week','Freq_x','Freq_y','Group_id_y','Group_id_flattened','yob_range'], axis=1
).rename(
  columns={'PatientId_x': 'PatientId', 'PatientId_y': 'MatchingPatientId', 'YearOfBirth_x':'YearOfBirth','YearOfBirth_y':'MatchingYearOfBirth', 'FirstCovidPositiveDate_x': 'FirstCovidPositiveDate', 'FirstCovidPositiveDate_y': 'MatchingFirstCovidPositiveDate'}
)

print('We just found matches for ' + str(df_patients_with_matches_week_yob.PatientId.drop_duplicates().size) + ' patients.')

-- SPLIT HERE --

%python
import pandas as pd;

# Add the new matches to the collection
df_patients_with_matches = pd.concat([df_patients_with_matches,df_patients_with_matches_week_yob])

print('We now have matches for ' + str(df_patients_with_matches.PatientId.drop_duplicates().size) + ' patients.')

