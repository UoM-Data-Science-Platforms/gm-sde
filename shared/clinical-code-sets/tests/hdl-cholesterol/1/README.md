# HDL Cholesterol

A patient's HDL cholesterol as recorded via clinical code and value. This code set only includes codes that are accompanied by a value (`44P5.00 - Serum HDL cholesterol level`).

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `43.66% - 48.97%` suggests that this code set is likely well defined.

_Update **2024/03/01**: prevalence now `46% - 55%%`._

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2021-10-13 | EMIS            | 26929848   | 1168326 (44.42%) |  1168326 (44.42%) |
| 2021-10-13 | TPP             | 211812     |  100823 (47.60%) |   100823 (47.60%) |
| 2021-10-13 | Vision          | 338205     |  165935 (49.06%) |   165935 (49.06%) |
| 2024-03-06 | EMIS            | 2525894    |    1162124 (46%) |     1162354 (46%) |
| 2024-03-06 | TPP             | 201753     |   110692 (54.9%) |    110708 (54.9%) |
| 2024-03-06 | Vision          | 335117     |   163929 (48.9%) |    163958 (48.9%) |

## Audit log

- Find_missing_codes last run 2024-03-01
