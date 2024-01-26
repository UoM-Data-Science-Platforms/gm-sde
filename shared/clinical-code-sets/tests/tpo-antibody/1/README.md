# TPO antibody (thyroid peroxidase antibody test)

Codes for a TPO antibody test. Only includes codes that will have a value, i.e. not codes such as "normal" which indicate the result without a numeric value. SNOMED codes taken from https://termbrowser.nhs.uk/ and then mapped to Readv2 and CTV3 for backward compatibility.

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `1.33 - 1.41%` for EMIS and Vision suggests that this code set is likely well defined. TPP slightly lower.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2023-12-21 | EMIS            | 2516480    |    35471 (1.41%) |     35489 (1.41%) |
| 2023-12-21 | TPP             | 201282     |    1898 (0.943%) |     1897 (0.942%) |
| 2023-12-21 | Vision          | 334130     |     4441 (1.33%) |      4442 (1.33%) |

## Audit log

- Find_missing_codes last run 2023-12-21
