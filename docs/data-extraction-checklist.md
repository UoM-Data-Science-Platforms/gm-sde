# Things to check before extracting data for GMCR projects


## 1. Ensure that ONLY patients who appear in GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" are included in study cohorts
Even when providing data from secondary care (local, national flows etc), we must filter patients to those with a GP record,
so that the opt-out is definitely applied.

## 1. Limit age of patients in patient file (if needed)

## 2. Exclude patients that died prior to study start (if needed)

## 3. Exclude patients that left GM between study start and end date (if needed) 

## 4. Missing SNOMED codes for code sets
Code sets that were developed a while ago may be missing SNOMED codes, as it didn’t matter previously. Before extracting data, code sets used in the project should be checked. SNOMED codes should be added where possible (especially if searching for codes by Code rather than ID). Checking prevalence of each code set is also advised before extraction.

## 5. Unwanted truncation of SNOMED codes
When pasting SNOMED codes into Excel, long ones can be truncated. If many codes end in multiple zeroes, this is likely to have happened. To fix this, format all cells as text before pasting.

## 6. Code descriptions containing delimiters (e.g. commas) – **only relevant if extracting data as CSVs.
If providing a study with descriptions for each clinical code, check that none of them contain a comma, as this will mess up the files when the CSVs are imported into RStudio or any other software. If they do, replace them with another character.

## 7. In previous projects I have excluded repeat medications by mistake
Check this isn’t the case when refreshing files. Column was called something like 'REP_MED'.

## 8. When providing ‘Dosage’ from GP Meds, consider limiting it to values that occur at least 50 times
When unique/rare values are used, mask this by setting to NULL. See GMCR study RQ036 Heald for example of using this code (line 932 in medicaiton file) 

## 9. Include start and end dates for all template files
This avoids incorrect data with a future date, and means we can say to the research team what date range their data covers.


# Snowflake/SDE specific

## 1. Mask death date using DATE_TRUNC to set the day to the first of the month.

## 2. Don’t include identifiers in final table 	
Check that GmPseudo has been successfully pseudonymised, and that FK_Patient_ID is not included.

## 3. Ensure all template scripts contain one of the following:
-	{{no-output-table}}
-	{{create-output-table::table_name}}
-	{{create-output-table-no-gmpseudo-ids::table-name}}
-	{{create-output-table-matched-cohort::table-name}}

## 4. If using cohort matching – ensure correct syntax
In final patient table, there should be the standard “GmPseudo” column, but if you are also providing a matched patient ID field, it should be named “MainCohortMatchedGmPseudo”. See number 3 above for the syntax for pseudonymisation when using a matched cohort.

