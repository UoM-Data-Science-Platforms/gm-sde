# Solid organ transplant

Codes indicating a solid organ transplantation has been carried out. SNOMED and CTV3 codelist are from the [OpenSafely project](https://codelists.opensafely.org/codelist/opensafely/solid-organ-transplantation/2020-04-10/). The Read 2 codelist is from the [LSHTM Data Compass](https://github.com/ebmdatalab/tpp-sql-notebook/files/4409772/organ_tx_simple_July18.xlsx).

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set.

The discrepancy between the patients counted when using the IDs vs using the clinical codes is due to these being new codes which haven't all filtered through to the main Graphnet dictionary. The prevalence range `0.10% - 0.13%` is sufficiently narrow that this code set is likely well defined.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2021-03-11 | EMIS            | 2600658    |     3433 (0.13%) |      3426 (0.13%) |
| 2021-03-11 | TPP             | 210333     |      209 (0.10%) |       210 (0.10%) |
| 2021-03-11 | Vision          | 333251     |      410 (0.12%) |       388 (0.12%) |
