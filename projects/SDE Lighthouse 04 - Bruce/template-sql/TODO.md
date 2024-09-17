## TODO

- Awaiting final SLE code set from study team
- Q. Do we want to also find people with SLE from the hospital data? This is probably a more general question going forward. Previously, cohorts were identified based on diagnosis codes in the GP record - because that is all we had. But we now have linked hospital data. If a patient has a diagnosis code in their hospital record, but not their GP record, should we include them? Considerations:
  - There could be some conditions (maybe lots) where there is an incentive to record them in HES data, but not in primary care data. Therefore finding patients based on both sources would dramatically increase the cohort size.
  - But conversely, there may be mis-coding in HES data, and the GP record could be more accurate.
  - So ultimately, if we did this, we should make it clear in the output files. E.g. columns like "DateOfFirstDiagnosis-GPRecord", "DateOfFirstDiagnosis-HESData", so the study team can do analyses with and without them.
- If we go down that route, for this study the following SQL is probably useful (though the ICD10 codes would need checking with the PI):

```sql
DROP TABLE IF EXISTS APCS_SLE;
CREATE TEMPORARY TABLE APCS_SLE AS
select SUBSTRING("Der_Pseudo_NHS_Number", 2)::INT AS "GmPseudo", MIN(CAST("Admission_Date" AS DATE)) AS "SLEDate"
from INTERMEDIATE.national_flows_apc."tbl_Data_SUS_APCS"
where contains(lower("Der_Diagnosis_All"), 'm321') -- Systemic lupus erythematosus with organ or system involvement
or contains(lower("Der_Diagnosis_All"), 'm328') -- Other forms of systemic lupus erythematosus
or contains(lower("Der_Diagnosis_All"), 'm329') -- Systemic lupus erythematosus, unspecified
group by SUBSTRING("Der_Pseudo_NHS_Number", 2)::INT;
```

# General

- Previously any code set used would be automatically extracted and put into the `clincial-code-sets.csv` file in the project root. This is still the case for any code sets used in the normal way. However we now can make use of NHS refsets (clusters in snowflake). For all projects we should either inform the PI which clusters have been used, or pull off the SNOMED codes for each cluster used. NB this is also needed for the code sets that are used to populate the "LongTermConditionRegister_SecondaryUses" table.

## Notes

- The request was for IMD quartiles, but they PI confirmed via email that quintiles were acceptable. Given we have easy access to quintiles I have provided that.
- For medication files 2-4, the PI confirmed that a single file with columns PatientId, Date, MedicationCategory, Medication, Dose would be fine.
- Comorbidities initially requested in long format (patientid, date, condition), but PI confirmed that wide format (which is what is already in Snowflake and so easier for us) would be fine.
- They also confirmed that hepatitis A, B, C and D should be given separately i.e. 4 columns instead of 1.
- Hospital infections. The PI requested "hospital admission for infection". It should be noted that:
  - The HES data contains a primary diagnosis code - BUT it is unclear exactly how this is coded. E.g. if a person is admitted with a myocardial infarction caused by an infection, then the primary diagnosis will be the MI, but presumably they study team would want this patient.
  - So probably best to use the secondary diagnosis codes as well.
  - This has the possibility that hospital acquired infections are counted - but there are specific ICD10 codes for hospital-acquired infections and so we don't think that our code sets will capture those patients.
  - Therefore we look at all diagnoses in hospital and provide details for any that contain any infection related code
