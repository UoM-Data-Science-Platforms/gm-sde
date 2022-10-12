import pandas as pd

# Pull the cohort data and the potential matches (pool) into pandas dataframes
df_cohort = spark.table('dars_nic_391419_j3w9t_collab.CCU040_Main_Cohort').select("*").toPandas()
df_pool = spark.table('dars_nic_391419_j3w9t_collab.CCU040_Potential_Matches').select("*").toPandas()

############# SPLIT HERE #############

# First let's add a FirstCovidPositiveWeek variable so we can fuzzy match later on
df_cohort['FirstCovidPositiveWeek'] = df_cohort.apply(lambda row: row.FirstCovidPositiveDate.toordinal()//7, axis = 1)
df_pool['FirstCovidPositiveWeek'] = df_pool.apply(lambda row: row.FirstCovidPositiveDate.toordinal()//7, axis = 1)

# Add a cumulative id per Sex/YearOfBirth/FirstCovidPositiveDate combination. This means later
# on we can match people without reusing people from the pool
df_cohort['Group_id'] = df_cohort.groupby(['Sex','YearOfBirth', 'FirstCovidPositiveDate']).cumcount()
df_pool['Group_id'] = df_pool.groupby(['Sex','YearOfBirth', 'FirstCovidPositiveDate']).cumcount()

############# SPLIT HERE #############

# Try to find one exact match for everyone

df_patients_with_matches = pd.merge(df_cohort, df_pool, on=['Sex','YearOfBirth', 'FirstCovidPositiveDate','Group_id'], sort=False)
df_patients_with_matches = df_patients_with_matches.drop(['Group_id'], axis=1)
df_patients_with_matches = df_patients_with_matches.rename(columns={'PatientId_x': 'PatientId', 'PatientId_y': 'MatchingPatientId'})
df_patients_with_matches['MatchingYearOfBirth'] = df_patients_with_matches.YearOfBirth
df_patients_with_matches['MatchingFirstCovidPositiveDate'] = df_patients_with_matches.FirstCovidPositiveDate
print(
  'We now have 1 match for ' + 
  str(df_patients_with_matches.PatientId.drop_duplicates().size) + 
  ' patients (out of ' + 
  str(df_cohort.PatientId.drop_duplicates().size) + ').'
)

############# SPLIT HERE #############

# Get all the people with no matches

df_cohort_unmatched = df_cohort[df_cohort.PatientId.isin(df_patients_with_matches.PatientId.drop_duplicates()) == False]
df_pool_unused = df_pool[df_pool.PatientId.isin(df_patients_with_matches.MatchingPatientId) == False]

print('There are ' + str(df_cohort_unmatched.Sex.size) + ' patients in the cohort as yet unmatched.')
print('There are ' + str(df_pool_unused.Sex.size) + ' unused patients in the matching pool.')

############# SPLIT HERE #############

# Add a cumulative id per Sex/YearOfBirth/FirstCovidPositiveWeek combination.
df_cohort_unmatched['Group_id'] = df_cohort.groupby(['Sex','YearOfBirth', 'FirstCovidPositiveWeek']).cumcount()
df_pool_unused['Group_id'] = df_pool.groupby(['Sex','YearOfBirth', 'FirstCovidPositiveWeek']).cumcount()

############# SPLIT HERE #############

# Try to find fuzzy match for unmatched people

df_temp = pd.merge(df_cohort_unmatched, df_pool_unused, on=['Sex','YearOfBirth', 'FirstCovidPositiveWeek','Group_id'], sort=False)
df_temp = df_temp.drop(['Group_id','FirstCovidPositiveWeek'], axis=1)
df_temp = df_temp.rename(columns={'PatientId_x': 'PatientId', 'PatientId_y': 'MatchingPatientId', 'FirstCovidPositiveDate_x': 'FirstCovidPositiveDate', 'FirstCovidPositiveDate_y': 'MatchingFirstCovidPositiveDate'})
df_temp['MatchingYearOfBirth'] = df_temp.YearOfBirth
df_patients_with_matches = pd.concat([df_patients_with_matches,df_temp])
print(
  'We now have 1 match for ' + 
  str(df_patients_with_matches.PatientId.drop_duplicates().size) + 
  ' patients (out of ' + 
  str(df_cohort.PatientId.drop_duplicates().size) + ').'
)

############# SPLIT HERE #############

# Get all the people with no matches

df_cohort_unmatched = df_cohort[df_cohort.PatientId.isin(df_patients_with_matches.PatientId.drop_duplicates()) == False]
df_pool_unused = df_pool[df_pool.PatientId.isin(df_patients_with_matches.MatchingPatientId) == False]

print('There are ' + str(df_cohort_unmatched.Sex.size) + ' patients in the cohort as yet unmatched.')
print('There are ' + str(df_pool_unused.Sex.size) + ' unused patients in the matching pool.')

############# SPLIT HERE #############

# First let's add a FirstCovidPositive4Week variable so we can fuzzy match later on
df_cohort_unmatched['FirstCovidPositive4Week'] = df_cohort_unmatched.apply(lambda row: row.FirstCovidPositiveDate.toordinal()//28, axis = 1)
df_pool_unused['FirstCovidPositive4Week'] = df_pool_unused.apply(lambda row: row.FirstCovidPositiveDate.toordinal()//28, axis = 1)

# Also add a 5 year buffer
# HARD CODE ALERT - the current yob range in the cohort is 1913-1997 e.g. 85 years inclusive. So to split into "fair"
# 5 year periods we want to group 1913-1917, 1918-1922, ... 1993-1997 which is why our conversion is (X - 3)//5 because that 
# makes years from 1913-1917 = 382, 1918-1922 = 383, ... 1993-1997 = 398
df_cohort_unmatched['YearOfBirth5Year'] = df_cohort_unmatched.apply(lambda row: (row.YearOfBirth-3)//5, axis = 1)
df_pool_unused['YearOfBirth5Year'] = df_pool_unused.apply(lambda row: (row.YearOfBirth-3)//5, axis = 1)

# Add a cumulative id per Sex/YearOfBirth/FirstCovidPositiveWeek combination.
df_cohort_unmatched['Group_id'] = df_cohort_unmatched.groupby(['Sex','YearOfBirth5Year', 'FirstCovidPositive4Week']).cumcount()
df_pool_unused['Group_id'] = df_pool_unused.groupby(['Sex','YearOfBirth5Year', 'FirstCovidPositive4Week']).cumcount()

############# SPLIT HERE #############

# Try to find fuzzy match for unmatched people

df_temp = pd.merge(df_cohort_unmatched, df_pool_unused, on=['Sex','YearOfBirth5Year', 'FirstCovidPositive4Week','Group_id'], sort=False)
df_temp = df_temp.drop(['Group_id','FirstCovidPositiveWeek_x','FirstCovidPositiveWeek_y','YearOfBirth5Year', 'FirstCovidPositive4Week'], axis=1)
df_temp = df_temp.rename(columns={'PatientId_x': 'PatientId', 'PatientId_y': 'MatchingPatientId', 'FirstCovidPositiveDate_x': 'FirstCovidPositiveDate', 'FirstCovidPositiveDate_y': 'MatchingFirstCovidPositiveDate','YearOfBirth_x': 'YearOfBirth', 'YearOfBirth_y': 'MatchingYearOfBirth'})
df_patients_with_matches = pd.concat([df_patients_with_matches,df_temp])
print(
  'We now have 1 match for ' + 
  str(df_patients_with_matches.PatientId.drop_duplicates().size) + 
  ' patients (out of ' + 
  str(df_cohort.PatientId.drop_duplicates().size) + ').'
)

############# SPLIT HERE #############

# Get all the people with no matches

df_cohort_unmatched = df_cohort[df_cohort.PatientId.isin(df_patients_with_matches.PatientId.drop_duplicates()) == False]
df_pool_unused = df_pool[df_pool.PatientId.isin(df_patients_with_matches.MatchingPatientId) == False]

print('There are ' + str(df_cohort_unmatched.Sex.size) + ' patients in the cohort as yet unmatched.')
print('There are ' + str(df_pool_unused.Sex.size) + ' unused patients in the matching pool.')

# Make the covid date a numeric field so we can just find everyong a "nearest" match
df_cohort_unmatched["date"] = pd.to_datetime(df_cohort_unmatched["FirstCovidPositiveDate"])
df_pool_unused["date"] = pd.to_datetime(df_pool_unused["FirstCovidPositiveDate"])

# Must be sorted for the upcoming merge_asof operation
df_cohort_unmatched = df_cohort_unmatched.sort_values(by='date')
df_pool_unused = df_pool_unused.sort_values(by='date')

############# SPLIT HERE #############

# This should ensure at least one match for everyone

df_temp = pd.merge_asof(df_cohort_unmatched, df_pool_unused,by=['Sex','YearOfBirth'],on='date', direction='nearest')
df_temp = df_temp.drop(['date','Group_id_x','Group_id_y','FirstCovidPositiveWeek_x','FirstCovidPositiveWeek_y'], axis=1)
df_temp = df_temp.rename(columns={'PatientId_x': 'PatientId', 'PatientId_y': 'MatchingPatientId', 'FirstCovidPositiveDate_x': 'FirstCovidPositiveDate', 'FirstCovidPositiveDate_y': 'MatchingFirstCovidPositiveDate'})
df_temp['MatchingYearOfBirth'] = df_temp.YearOfBirth

df_patients_with_matches = pd.concat([df_patients_with_matches,df_temp])
print(
  'We now have 1 match for ' + 
  str(df_patients_with_matches.PatientId.drop_duplicates().size) + 
  ' patients (out of ' + 
  str(df_cohort.PatientId.drop_duplicates().size) + ').'
)

############# SPLIT HERE #############

# Reset the pool

df_pool = df_pool[df_pool.PatientId.isin(df_patients_with_matches.MatchingPatientId) == False]
df_pool['Group_id'] = df_pool.groupby(['Sex','YearOfBirth', 'FirstCovidPositiveDate']).cumcount()
print('There are ' + str(df_pool_unused.Sex.size) + ' unused patients in the matching pool.')

############# SPLIT HERE #############

# Try to find a second match for everyone

df_patients_with_matches_2 = pd.merge(df_cohort, df_pool, on=['Sex','YearOfBirth', 'FirstCovidPositiveDate','Group_id'], sort=False)
df_patients_with_matches_2 = df_patients_with_matches_2.drop(['Group_id'], axis=1)
df_patients_with_matches_2 = df_patients_with_matches_2.rename(columns={'PatientId_x': 'PatientId', 'PatientId_y': 'MatchingPatientId'})
df_patients_with_matches_2['MatchingYearOfBirth'] = df_patients_with_matches_2.YearOfBirth
df_patients_with_matches_2['MatchingFirstCovidPositiveDate'] = df_patients_with_matches_2.FirstCovidPositiveDate
print(
  'We now have a second match for ' + 
  str(df_patients_with_matches_2.PatientId.drop_duplicates().size) + 
  ' patients (out of ' + 
  str(df_cohort.PatientId.drop_duplicates().size) + ').'
)


############# SPLIT HERE #############

# Get all the people without a second match

df_cohort_unmatched = df_cohort[df_cohort.PatientId.isin(df_patients_with_matches_2.PatientId.drop_duplicates()) == False]
df_pool_unused = df_pool[df_pool.PatientId.isin(df_patients_with_matches_2.MatchingPatientId) == False]

print('There are ' + str(df_cohort_unmatched.Sex.size) + ' patients in the cohort as yet unmatched.')
print('There are ' + str(df_pool_unused.Sex.size) + ' unused patients in the matching pool.')

############# SPLIT HERE #############

# First let's add a FirstCovidPositive4Week variable so we can fuzzy match later on
df_cohort_unmatched['FirstCovidPositive4Week'] = df_cohort_unmatched.apply(lambda row: row.FirstCovidPositiveDate.toordinal()//28, axis = 1)
df_pool_unused['FirstCovidPositive4Week'] = df_pool_unused.apply(lambda row: row.FirstCovidPositiveDate.toordinal()//28, axis = 1)

# Also add a 5 year buffer
# HARD CODE ALERT - the current yob range in the cohort is 1913-1997 e.g. 85 years inclusive. So to split into "fair"
# 5 year periods we want to group 1913-1917, 1918-1922, ... 1993-1997 which is why our conversion is (X - 3)//5 because that 
# makes years from 1913-1917 = 382, 1918-1922 = 383, ... 1993-1997 = 398
df_cohort_unmatched['YearOfBirth5Year'] = df_cohort_unmatched.apply(lambda row: (row.YearOfBirth-3)//5, axis = 1)
df_pool_unused['YearOfBirth5Year'] = df_pool_unused.apply(lambda row: (row.YearOfBirth-3)//5, axis = 1)

# Add a cumulative id per Sex/YearOfBirth/FirstCovidPositiveWeek combination.
df_cohort_unmatched['Group_id'] = df_cohort_unmatched.groupby(['Sex','YearOfBirth5Year', 'FirstCovidPositive4Week']).cumcount()
df_pool_unused['Group_id'] = df_pool_unused.groupby(['Sex','YearOfBirth5Year', 'FirstCovidPositive4Week']).cumcount()

############# SPLIT HERE #############

# Try to find fuzzy match for unmatched people

df_temp = pd.merge(df_cohort_unmatched, df_pool_unused, on=['Sex','YearOfBirth5Year', 'FirstCovidPositive4Week','Group_id'], sort=False)
df_temp = df_temp.drop(['Group_id','FirstCovidPositiveWeek_x','FirstCovidPositiveWeek_y','YearOfBirth5Year', 'FirstCovidPositive4Week'], axis=1)
df_temp = df_temp.rename(columns={'PatientId_x': 'PatientId', 'PatientId_y': 'MatchingPatientId', 'FirstCovidPositiveDate_x': 'FirstCovidPositiveDate', 'FirstCovidPositiveDate_y': 'MatchingFirstCovidPositiveDate','YearOfBirth_x': 'YearOfBirth', 'YearOfBirth_y': 'MatchingYearOfBirth'})
df_patients_with_matches_2 = pd.concat([df_patients_with_matches_2,df_temp])
print(
  'We now have a second match for ' + 
  str(df_patients_with_matches_2.PatientId.drop_duplicates().size) + 
  ' patients (out of ' + 
  str(df_cohort.PatientId.drop_duplicates().size) + ').'
)

############# SPLIT HERE #############

# Get all the people without a second match

df_cohort_unmatched = df_cohort[df_cohort.PatientId.isin(df_patients_with_matches_2.PatientId.drop_duplicates()) == False]
df_pool_unused = df_pool[df_pool.PatientId.isin(df_patients_with_matches_2.MatchingPatientId) == False]

print('There are ' + str(df_cohort_unmatched.Sex.size) + ' patients in the cohort without a second match.')
print('There are ' + str(df_pool_unused.Sex.size) + ' unused patients in the matching pool.')

# Make the covid date a numeric field so we can just find everyong a "nearest" match
df_cohort_unmatched["date"] = pd.to_datetime(df_cohort_unmatched["FirstCovidPositiveDate"])
df_pool_unused["date"] = pd.to_datetime(df_pool_unused["FirstCovidPositiveDate"])

# Must be sorted for the upcoming merge_asof operation
df_cohort_unmatched = df_cohort_unmatched.sort_values(by='date')
df_pool_unused = df_pool_unused.sort_values(by='date')

############# SPLIT HERE #############

# This should ensure at least one match for everyone

df_temp = pd.merge_asof(df_cohort_unmatched, df_pool_unused,by=['Sex','YearOfBirth'],on='date', direction='nearest')
df_temp = df_temp.drop(['date','Group_id_x','Group_id_y','FirstCovidPositiveWeek_x','FirstCovidPositiveWeek_y'], axis=1)
df_temp = df_temp.rename(columns={'PatientId_x': 'PatientId', 'PatientId_y': 'MatchingPatientId', 'FirstCovidPositiveDate_x': 'FirstCovidPositiveDate', 'FirstCovidPositiveDate_y': 'MatchingFirstCovidPositiveDate'})
df_temp['MatchingYearOfBirth'] = df_temp.YearOfBirth

df_patients_with_matches_2 = pd.concat([df_patients_with_matches_2,df_temp])
print(
  'We now have a second match for ' + 
  str(df_patients_with_matches_2.PatientId.drop_duplicates().size) + 
  ' patients (out of ' + 
  str(df_cohort.PatientId.drop_duplicates().size) + ').'
)

############# SPLIT HERE #############

# Merge matches into single dataframe

df_patients_with_matches = pd.concat([df_patients_with_matches, df_patients_with_matches_2])

############# SPLIT HERE #############

# Reset the pool

df_pool = df_pool[df_pool.PatientId.isin(df_patients_with_matches.MatchingPatientId) == False]
df_pool['Group_id'] = df_pool.groupby(['Sex','YearOfBirth', 'FirstCovidPositiveDate']).cumcount()
print('There are ' + str(df_pool_unused.Sex.size) + ' unused patients in the matching pool.')

############# SPLIT HERE #############

# Try to find a third match for everyone

df_patients_with_matches_2 = pd.merge(df_cohort, df_pool, on=['Sex','YearOfBirth', 'FirstCovidPositiveDate','Group_id'], sort=False)
df_patients_with_matches_2 = df_patients_with_matches_2.drop(['Group_id'], axis=1)
df_patients_with_matches_2 = df_patients_with_matches_2.rename(columns={'PatientId_x': 'PatientId', 'PatientId_y': 'MatchingPatientId'})
df_patients_with_matches_2['MatchingYearOfBirth'] = df_patients_with_matches_2.YearOfBirth
df_patients_with_matches_2['MatchingFirstCovidPositiveDate'] = df_patients_with_matches_2.FirstCovidPositiveDate
print(
  'We now have a third match for ' + 
  str(df_patients_with_matches_2.PatientId.drop_duplicates().size) + 
  ' patients (out of ' + 
  str(df_cohort.PatientId.drop_duplicates().size) + ').'
)

############# SPLIT HERE #############

# Get all the people without a third match

df_cohort_unmatched = df_cohort[df_cohort.PatientId.isin(df_patients_with_matches_2.PatientId.drop_duplicates()) == False]
df_pool_unused = df_pool[df_pool.PatientId.isin(df_patients_with_matches_2.MatchingPatientId) == False]

print('There are ' + str(df_cohort_unmatched.Sex.size) + ' patients in the cohort without a third match.')
print('There are ' + str(df_pool_unused.Sex.size) + ' unused patients in the matching pool.')

############# SPLIT HERE #############

# First let's add a FirstCovidPositive4Week variable so we can fuzzy match later on
df_cohort_unmatched['FirstCovidPositive4Week'] = df_cohort_unmatched.apply(lambda row: row.FirstCovidPositiveDate.toordinal()//28, axis = 1)
df_pool_unused['FirstCovidPositive4Week'] = df_pool_unused.apply(lambda row: row.FirstCovidPositiveDate.toordinal()//28, axis = 1)

# Also add a 5 year buffer
# HARD CODE ALERT - the current yob range in the cohort is 1913-1997 e.g. 85 years inclusive. So to split into "fair"
# 5 year periods we want to group 1913-1917, 1918-1922, ... 1993-1997 which is why our conversion is (X - 3)//5 because that 
# makes years from 1913-1917 = 382, 1918-1922 = 383, ... 1993-1997 = 398
df_cohort_unmatched['YearOfBirth5Year'] = df_cohort_unmatched.apply(lambda row: (row.YearOfBirth-3)//5, axis = 1)
df_pool_unused['YearOfBirth5Year'] = df_pool_unused.apply(lambda row: (row.YearOfBirth-3)//5, axis = 1)

# Add a cumulative id per Sex/YearOfBirth/FirstCovidPositiveWeek combination.
df_cohort_unmatched['Group_id'] = df_cohort_unmatched.groupby(['Sex','YearOfBirth5Year', 'FirstCovidPositive4Week']).cumcount()
df_pool_unused['Group_id'] = df_pool_unused.groupby(['Sex','YearOfBirth5Year', 'FirstCovidPositive4Week']).cumcount()

############# SPLIT HERE #############

# Try to find fuzzy match for unmatched people

df_temp = pd.merge(df_cohort_unmatched, df_pool_unused, on=['Sex','YearOfBirth5Year', 'FirstCovidPositive4Week','Group_id'], sort=False)
df_temp = df_temp.drop(['Group_id','FirstCovidPositiveWeek_x','FirstCovidPositiveWeek_y','YearOfBirth5Year', 'FirstCovidPositive4Week'], axis=1)
df_temp = df_temp.rename(columns={'PatientId_x': 'PatientId', 'PatientId_y': 'MatchingPatientId', 'FirstCovidPositiveDate_x': 'FirstCovidPositiveDate', 'FirstCovidPositiveDate_y': 'MatchingFirstCovidPositiveDate','YearOfBirth_x': 'YearOfBirth', 'YearOfBirth_y': 'MatchingYearOfBirth'})
df_patients_with_matches_2 = pd.concat([df_patients_with_matches_2,df_temp])
print(
  'We now have a third match for ' + 
  str(df_patients_with_matches_2.PatientId.drop_duplicates().size) + 
  ' patients (out of ' + 
  str(df_cohort.PatientId.drop_duplicates().size) + ').'
)

############# SPLIT HERE #############

# Get all the people without a third match

df_cohort_unmatched = df_cohort[df_cohort.PatientId.isin(df_patients_with_matches_2.PatientId.drop_duplicates()) == False]
df_pool_unused = df_pool[df_pool.PatientId.isin(df_patients_with_matches_2.MatchingPatientId) == False]

print('There are ' + str(df_cohort_unmatched.Sex.size) + ' patients in the cohort without a third match.')
print('There are ' + str(df_pool_unused.Sex.size) + ' unused patients in the matching pool.')

# Make the covid date a numeric field so we can just find everyong a "nearest" match
df_cohort_unmatched["date"] = pd.to_datetime(df_cohort_unmatched["FirstCovidPositiveDate"])
df_pool_unused["date"] = pd.to_datetime(df_pool_unused["FirstCovidPositiveDate"])

# Must be sorted for the upcoming merge_asof operation
df_cohort_unmatched = df_cohort_unmatched.sort_values(by='date')
df_pool_unused = df_pool_unused.sort_values(by='date')

############# SPLIT HERE #############

# This should ensure at least one match for everyone

df_temp = pd.merge_asof(df_cohort_unmatched, df_pool_unused,by=['Sex','YearOfBirth'],on='date', direction='nearest')
df_temp = df_temp.drop(['date','Group_id_x','Group_id_y','FirstCovidPositiveWeek_x','FirstCovidPositiveWeek_y'], axis=1)
df_temp = df_temp.rename(columns={'PatientId_x': 'PatientId', 'PatientId_y': 'MatchingPatientId', 'FirstCovidPositiveDate_x': 'FirstCovidPositiveDate', 'FirstCovidPositiveDate_y': 'MatchingFirstCovidPositiveDate'})
df_temp['MatchingYearOfBirth'] = df_temp.YearOfBirth

df_patients_with_matches_2 = pd.concat([df_patients_with_matches_2,df_temp])
print(
  'We now have a third match for ' + 
  str(df_patients_with_matches_2.PatientId.drop_duplicates().size) + 
  ' patients (out of ' + 
  str(df_cohort.PatientId.drop_duplicates().size) + ').'
)



def 