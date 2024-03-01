# T3 (Triiodothyronine) test

Codes for a "Free T3" level test. Only includes codes that will have a value, i.e. not codes such as "T3 normal" which indicate the result without a numeric value.

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `1.44 - 1.91%` suggests that this code set is likely well defined. NB T3 is not part of the standard thyroid function test in the UK and so it's prevalence is a lot lower than T4.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2023-12-21 | EMIS            | 2516480    |    37279 (1.48%) |     37298 (1.48%) |
| 2023-12-21 | TPP             | 201282     |     2903 (1.44%) |      2904 (1.44%) |
| 2023-12-21 | Vision          | 334130     |     6373 (1.91%) |      6374 (1.91%) |

## Audit log

- Find_missing_codes last run 2023-12-21
