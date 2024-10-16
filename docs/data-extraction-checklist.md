## Things to check before extracting data for GMCR projects

1.	Missing SNOMED codes for code sets
Code sets that were developed a while ago may be missing SNOMED codes, as it didn’t matter previously. Before extracting data, code sets used in the project should be checked. SNOMED codes should be added where possible (especially if searching for codes by Code rather than ID). Checking prevalence of each code set is also advised before extraction.

2.	Unwanted truncation of SNOMED codes
When pasting SNOMED codes into Excel, long ones can be truncated. If many codes end in multiple zeroes, this is likely to have happened. To fix this, format all cells as text before pasting. 

3.	Code descriptions containing delimiters (e.g. commas) – not as relevant in SDE as we don't extract data as CSVs.
If providing a study with descriptions for each clinical code, check that none of them contain a comma, as this will mess up the files when the CSVs are imported into RStudio or any other software. If they do, replace them with another character.

4.	In previous projects I have excluded repeat medications by mistake
Check this isn’t the case when refreshing files

5.	When providing ‘Dosage’ from GP Meds, limit it to values that occur at least 50 times
When unique/rare values are used, mask this by setting to NULL


## Snowflake/SDE specific

1.	Limit cohort to patients in DemographicsProtectedCharacteristics_SecondaryUses 
This means we don’t include any opted out patients

2.	Don’t include identifiers in final table 	
Check that GmPseudo has been successfully pseudonymised, and that FK_Patient_ID is not included.

3.	Ensure all template scripts contain one of the following:
-	{{no-output-table}}
-	{{create-output-table::table_name}}
-	{{create-output-table-no-gmpseudo-ids::table-name}}
-	{{create-output-table-matched-cohort::table-name}}

4.	If using cohort matching – ensure correct syntax
In final patient table, there should be the standard “GmPseudo” column, but if you are also providing a matched patient ID field, it should be named “MainCohortMatchedGmPseudo”. See number 3 above for the syntax for pseudonymisation when using a matched cohort.

