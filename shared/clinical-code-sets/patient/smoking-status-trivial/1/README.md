# Smoking status trivial

Any code suggesting the patient is currently smoking a trivial amount (on average less than 1 per day).

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `1.2% - 1.7%` is sufficiently narrow that this code set is likely well defined.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2024-01-19 | EMIS            | 2519438    |    38988 (1.55%) |     38950 (1.55%) |
| 2024-01-19 | TPP             | 201469     |     2919 (1.45%) |       2426 (1.2%) |
| 2024-01-19 | Vision          | 334528     |     5709 (1.71%) |      5708 (1.71%) |

## Audit log

- Find_missing_codes last run 2024-01-17
