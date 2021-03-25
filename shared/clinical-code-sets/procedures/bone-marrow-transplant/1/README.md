# Bone marrow transplant

Codes indicating a bone marrow transplant has been carried out. [CTV3](https://codelists.opensafely.org/codelist/opensafely/bone-marrow-transplant/2020-04-15/) and [SNOMED](https://codelists.opensafely.org/codelist/opensafely/bone-marrow-transplant-snomed/2020-04-15/) codelist are from the OpenSAFELY project. The Read 2 codelist is from the [LSHTM Data Compass](https://github.com/ebmdatalab/tpp-sql-notebook/files/4409744/bonemarrow_stemcell_July18.xlsx).

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set.

The discrepancy between the patients counted when using the IDs vs using the clinical codes is due to these being new codes which haven't all filtered through to the main Graphnet dictionary. The prevalence range `0.024% - 0.036%` is sufficiently narrow that this code set is likely well defined.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2021-03-11 | EMIS            | 2600658    |     941 (0.036%) |      940 (0.036%) |
| 2021-03-11 | TPP             | 210333     |      53 (0.025%) |       53 (0.025%) |
| 2021-03-11 | Vision          | 333251     |      86 (0.026%) |       81 (0.024%) |
