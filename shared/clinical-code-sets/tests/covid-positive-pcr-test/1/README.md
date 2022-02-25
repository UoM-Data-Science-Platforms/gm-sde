# COVID-19 positive pcr test

A code that indicates that a person has a positive pcr test for COVID-19.

## COVID positive tests in primary care

The codes used in primary care to indicate a positive COVID test can be split into 3 types: antigen test, PCR test and other. We keep these as separate code sets. However due to the way that COVID diagnoses are recorded in different ways in different GP systems, and because some codes are ambiguous, currently it only makes sense to group these 3 code sets together. Therefore the prevalence log below is for the combined code sets of `covid-positive-antigen-test`, `covid-positive-pcr-test` and `covid-positive-test-other`.

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `18.6% - 20.5%` suggests that this code set is likely well defined. _NB - this code set needs to rely on the SuppliedCode in the database rather than the foreign key ids._

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2022-02-25 | EMIS            | 2656041    |   152972 (5.76%) |    545759 (20.5%) |
| 2022-02-25 | TPP             | 212453     |      256 (0.12%) |     39503 (18.6%) |
| 2022-02-25 | Vision          | 341354     |     9440 (2.77%) |     65963 (19.3%) |
