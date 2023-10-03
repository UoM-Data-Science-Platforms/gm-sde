%md
# Obtain matching cohort

**Desciption** To get a matched cohort for the patients with COVID and DM

**Author** Richard Williams

**Github** [https://github.com/rw251/gm-idcr/tree/master/projects/NATIONAL-CCU040-Diabetes](https://github.com/rw251/gm-idcr/tree/master/projects/NATIONAL%20-%20CCU040%20-%20Diabetes)

**Date last updated** /*__date__*/

## Notes

For each patient in our main cohort (DM + COVID diagnosis), we attempt to find a matched 3:1
cohort, matching on age, sex and date of COVID diagnosis.

This now uses SGSS data in addition to GDPPR to get all covid positive tests.

## Input
Assumes there exists the following tables:

### CCU040_01_SGSS_Main_Cohort and CCU040_01_SGSS_Potential_Matches
The table of the main cohort and the potential matches

| Column                 | Type    | Description            |
| ---------------------- | ------- | ---------------------- |
| PatientId              | string  |      Unique patient id |
| Sex                    | char(1) |                    M/F |
| YearOfBirth            | int     |          Year of birth |
| FirstCovidPositiveDate | date    | Date of first +ve text |

### CCU040_01_Patients_With_Matches
The table that this script will populate

## Output
The CCU040_01_Patients_With_Matches will be popluated

############# SPLIT HERE #############

import pandas as pd
import numpy as np

# Pull the cohort data and the potential matches (pool) into pandas dataframes
df_cohort = spark.table('dars_nic_391419_j3w9t_collab.CCU040_01_SGSS_Main_Cohort').select("*").toPandas()
df_pool = spark.table('dars_nic_391419_j3w9t_collab.CCU040_01_SGSS_Potential_Matches').select("*").toPandas()

############# SPLIT HERE #############

# Now let's add useful columns for fuzzy matching later on

# Aggregate the COVID date to a COVID week
df_cohort['FirstCovidPositiveWeek'] = df_cohort.apply(lambda row: row.FirstCovidPositiveDate.toordinal()//7, axis = 1)
df_pool['FirstCovidPositiveWeek'] = df_pool.apply(lambda row: row.FirstCovidPositiveDate.toordinal()//7, axis = 1)

# Aggregate the COVID date to a COVID 4 week period
df_cohort['FirstCovidPositive4Week'] = df_cohort.apply(lambda row: row.FirstCovidPositiveDate.toordinal()//28, axis = 1)
df_pool['FirstCovidPositive4Week'] = df_pool.apply(lambda row: row.FirstCovidPositiveDate.toordinal()//28, axis = 1)

# Aggregate the COVID date to a COVID 12 week period
df_cohort['FirstCovidPositive12Week'] = df_cohort.apply(lambda row: row.FirstCovidPositiveDate.toordinal()//84, axis = 1)
df_pool['FirstCovidPositive12Week'] = df_pool.apply(lambda row: row.FirstCovidPositiveDate.toordinal()//84, axis = 1)

# Also add a 5 year buffer
# HARD CODE ALERT - the current yob range in the cohort is 1910-2022 e.g. 113 years inclusive. So to split into "fair"
# 5 year periods we want to group 1910-1914, 1915-1919, ... 2015-2019
df_cohort['YearOfBirth5Year'] = df_cohort.apply(lambda row: (row.YearOfBirth)//5, axis = 1)
df_pool['YearOfBirth5Year'] = df_pool.apply(lambda row: (row.YearOfBirth)//5, axis = 1)

# And finally make the covid date a numeric field so we can just find everyong a "nearest" match
df_cohort["FirstCovidPositiveDate"] = pd.to_datetime(df_cohort["FirstCovidPositiveDate"])
df_pool["FirstCovidPositiveDate"] = pd.to_datetime(df_pool["FirstCovidPositiveDate"])

# And add a column for when the date column disappears in the merge_asof operation
df_pool['MatchingDate'] = df_pool['FirstCovidPositiveDate']

# Must be sorted for the upcoming merge_asof operation
df_cohort = df_cohort.sort_values(by='FirstCovidPositiveDate')
df_pool = df_pool.sort_values(by='FirstCovidPositiveDate')

############# SPLIT HERE #############

# Declare a function that takes a cohort, a pool of matches
# and a list of things to match on. Returns a single match
# for each person in the cohort
# isNearest is a boolean flag to say whether we want exact matches
# or to match precisely on some fields, but then just pick the nearest
# Covid date
def getMatches(groupByFields, cohort, pool, degree, isNearest = False):
  # Add a cumulative id per groupByFields combination. This means later
  # on we can match people without reusing people from the pool
  if not isNearest:
    pd.options.mode.chained_assignment = None  # to prevent error message which doesn't apply in this situation
    cohort['Group_id'] = cohort.groupby(groupByFields).cumcount()
    pool['Group_id'] = pool.groupby(groupByFields).cumcount()
    pd.options.mode.chained_assignment = 'warn'  # put it back to default value

    groupByFields.append('Group_id')

  df_matches = pd.merge_asof(cohort, pool,by=groupByFields,on='FirstCovidPositiveDate', direction='nearest',suffixes=(None, 'OfMatchingPatient')) if isNearest else pd.merge(cohort, pool, on=groupByFields, sort=False, suffixes=(None, 'OfMatchingPatient'))
  df_matches = df_matches.drop(['Group_id', 'FirstCovidPositiveWeek','FirstCovidPositiveWeekOfMatchingPatient','FirstCovidPositive4Week','FirstCovidPositive4WeekOfMatchingPatient','FirstCovidPositive12Week','FirstCovidPositive12WeekOfMatchingPatient','YearOfBirth5Year','YearOfBirth5YearOfMatchingPatient'], axis=1, errors='ignore')
  if isNearest:
    df_matches = df_matches.rename(columns={'MatchingDate':'FirstCovidPositiveDateOfMatchingPatient'})
  print(
    '...we have a ' + degree + ' match for ' + 
    str(df_matches.PatientId.drop_duplicates().size) + 
    ' patients (out of ' + 
    str(cohort.PatientId.drop_duplicates().size) + ').'
  )
  return df_matches

# Find all the patients in the cohort
def getUnmatchedPatients(df_patients_with_matches, usedPoolPatients):
  df_unmatched = df_cohort[df_cohort.PatientId.isin(df_patients_with_matches.PatientId.drop_duplicates()) == False]
  df_unused = df_pool[df_pool.PatientId.isin(usedPoolPatients) == False]

  print('......there are ' + str(df_unmatched.Sex.size) + ' patients in the cohort as yet unmatched.')
  print('......there are ' + str(df_unused.Sex.size) + ' unused patients in the matching pool.')

  return df_unmatched, df_unused

def readableN(n):
  if n == 1:
    return 'first'
  if n == 2:
    return 'second'
  if n == 3:
    return 'third'

def getOneMatchForEveryone(n, c, p, usedPoolPatients = []):
  
  ## Match precisely
  print('First we try and get a match by matching exactly on sex, yearofbirth, and covid date...')
  df_matches = getMatches(['Sex','YearOfBirth', 'FirstCovidPositiveDate'], c, p, readableN(n))
  df_matches['YearOfBirthOfMatchingPatient'] = df_matches.YearOfBirth
  df_matches['FirstCovidPositiveDateOfMatchingPatient'] = df_matches.FirstCovidPositiveDate

  ## Get unmatched patients
  usedPoolPatients = usedPoolPatients + df_matches.PatientIdOfMatchingPatient.tolist()
  df_cohort_unmatched, df_pool_unused = getUnmatchedPatients(df_matches, usedPoolPatients)

  ## Attempt match on covid week rather than date and add to matches
  print('Now we relax the matching on covid date to covid week...')
  df_temp = getMatches(['Sex','YearOfBirth', 'FirstCovidPositiveWeek'], df_cohort_unmatched, df_pool_unused, readableN(n))
  df_temp['YearOfBirthOfMatchingPatient'] = df_temp.YearOfBirth
  df_matches = pd.concat([df_matches,df_temp])
  print(
    'In total, we now have a ' + readableN(n) + ' match for ' + 
    str(df_matches.PatientId.drop_duplicates().size) + 
    ' patients (out of ' + 
    str(df_cohort.PatientId.drop_duplicates().size) + ').'
  )

  ## Get unmatched patients
  usedPoolPatients = usedPoolPatients + df_temp.PatientIdOfMatchingPatient.tolist()
  df_cohort_unmatched, df_pool_unused = getUnmatchedPatients(df_matches, usedPoolPatients)

  ## Fairly fuzzy match now
  print('Now we relax to covid 4 week period and age 5 year either side...')
  df_temp = getMatches(['Sex','YearOfBirth5Year', 'FirstCovidPositive4Week'], df_cohort_unmatched, df_pool_unused, readableN(n))
  df_matches = pd.concat([df_matches,df_temp])
  print(
    'In total, we now have a ' + readableN(n) + ' match for ' + 
    str(df_matches.PatientId.drop_duplicates().size) + 
    ' patients (out of ' + 
    str(df_cohort.PatientId.drop_duplicates().size) + ').'
  )

  ## Get unmatched patients
  usedPoolPatients = usedPoolPatients + df_temp.PatientIdOfMatchingPatient.tolist()
  df_cohort_unmatched, df_pool_unused = getUnmatchedPatients(df_matches, usedPoolPatients)

  ## Nuclear option, just pick the closest for each person
  # print('Now we exact match on sex and yearofbirth, and pick the patient with the nearest covid date...')
  # df_temp = getMatches(['Sex','YearOfBirth'], df_cohort_unmatched, df_pool_unused, readableN(n), True)
  # df_temp['YearOfBirthOfMatchingPatient'] = df_temp.YearOfBirth
  # df_matches = pd.concat([df_matches,df_temp])
  # print(
  #   'We now have 1 match for ' + 
  #   str(df_matches.PatientId.drop_duplicates().size) + 
  #   ' patients (out of ' + 
  #   str(df_cohort.PatientId.drop_duplicates().size) + ').'
  # )

  ## Really fuzzy match now
  print('Now we relax to covid 12 week period and age 5 year either side...')
  df_temp = getMatches(['Sex','YearOfBirth5Year', 'FirstCovidPositive12Week'], df_cohort_unmatched, df_pool_unused, readableN(n))
  df_matches = pd.concat([df_matches,df_temp])
  print(
    'In total, we now have a ' + readableN(n) + ' match for ' + 
    str(df_matches.PatientId.drop_duplicates().size) + 
    ' patients (out of ' + 
    str(df_cohort.PatientId.drop_duplicates().size) + ').'
  )

  return df_matches

def getNMatches(n, cohort, pool):
  df_patients_with_matches = getOneMatchForEveryone(1, cohort, pool)
  for i in range(1, n):

    # Reset the pool
    pool = pool[pool.PatientId.isin(df_patients_with_matches.PatientIdOfMatchingPatient) == False]
    df_temp = getOneMatchForEveryone(i + 1, cohort, pool, df_patients_with_matches.PatientIdOfMatchingPatient.tolist())
    df_patients_with_matches = pd.concat([df_patients_with_matches,df_temp])
  
  return df_patients_with_matches

############# SPLIT HERE #############

# Try for 3 matches per person
df_patients_with_matches = getNMatches(3, df_cohort, df_pool)

############# SPLIT HERE #############

# Final tidy up of the data and conversion to spark dataframe to subsequently allow
# writing back to the database

# This line recommended by the tutorial
spark.conf.set("spark.sql.legacy.allowCreatingManagedTableUsingNonemptyLocation", "true")

df_patients_with_matches = df_patients_with_matches.drop(['MatchingDate'], axis=1, errors='ignore')
df_patients_with_matches = df_patients_with_matches[(df_patients_with_matches["YearOfBirth"].notnull())]
df_patients_with_matches["YearOfBirth"] = df_patients_with_matches["YearOfBirth"].astype("Int32")
df_patients_with_matches["YearOfBirthOfMatchingPatient"] = df_patients_with_matches["YearOfBirthOfMatchingPatient"].astype("Int32")

from pyspark.sql.types import *
schema = StructType([
  StructField("PatientId", StringType(), True),
  StructField("Sex", StringType(), True),
  StructField("YearOfBirth", IntegerType(), True),
  StructField("FirstCovidPositiveDate", DateType(), True),
  StructField("PatientIdOfMatchingPatient", StringType(), True),
  StructField("YearOfBirthOfMatchingPatient", IntegerType(), True),
  StructField("FirstCovidPositiveDateOfMatchingPatient", DateType(), True),
])
spark_df_patients_with_matches = spark.createDataFrame(df_patients_with_matches, schema)
spark_df_patients_with_matches.show()

############# SPLIT HERE #############

# Finally write the data back to the database
db_name = 'dars_nic_391419_j3w9t_collab'
table_name = 'ccu040_01_sgss_patients_with_matches'
spark_df_patients_with_matches.createOrReplaceTempView(table_name) 
spark.sql("INSERT INTO " + db_name + "." + table_name + " SELECT * FROM " + table_name)

