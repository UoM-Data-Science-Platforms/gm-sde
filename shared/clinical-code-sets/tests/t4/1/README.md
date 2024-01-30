# T4 (Thyroxine) test

Codes for a "Free T4" level test. Only includes codes that will have a value, i.e. not codes such as "T4 normal" which indicate the result without a numeric value.

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `27.1 - 38.7%` suggests that the code set is not complete. Either there are missing codes, or the way that T4 is recorded in practice systems differs in some way. E.g. if a GP requests TSH from a thyroid function test, then T4 will also be calculated, but if not explicitly requested it may not have automatically been entered into the record.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2023-12-21 | EMIS            | 2516480    |   974896 (38.7%) |    975076 (38.7%) |
| 2023-12-21 | TPP             | 201282     |    55648 (27.6%) |     55658 (27.7%) |
| 2023-12-21 | Vision          | 334130     |    90417 (27.1%) |     90434 (27.1%) |

## Audit log

- Find_missing_codes last run 2023-12-21
