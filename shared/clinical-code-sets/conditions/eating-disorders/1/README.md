# Eating disorders

Any code indicating a diagnosis of anorexia or bulimia or similar eating disorders. SNOMED codes from the NHS PCD refset.

- Does not include "loss of appetite codes" unless there is an indication that it is a symptom of anorexia.

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set.

The discrepancy between the patients counted when using the IDs vs using the clinical codes is due to these being new codes which haven't all filtered through to the main Graphnet dictionary. The prevalence range `0.68% - 0.85%` suggests that this code set is well defined.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2022-05-06 | EMIS            | 2662112    |    22407 (0.84%) |     22407 (0.84%) |
| 2022-05-06 | TPP             | 212726     |      885 (0.42%) |       885 (0.42%) |
| 2022-05-06 | Vision          | 342310     |     1999 (0.58%) |      1935 (0.57%) |
| 2024-04-30 | EMIS            | 2530927    |    34267 (1.35%) |    21377 (0.845%) |
| 2024-04-30 | TPP             | 201816     |     3067 (1.52%) |     1362 (0.675%) |
| 2024-04-30 | Vision          | 335411     |     3719 (1.11%) |     2472 (0.737%) |

## Audit log

- Find_missing_codes last run 2024-04-30
