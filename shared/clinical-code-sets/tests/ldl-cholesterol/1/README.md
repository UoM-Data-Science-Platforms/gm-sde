# LDL Cholesterol

A patient's LDL cholesterol as recorded via clinical code and value. This code set only includes codes that are accompanied by a value (`44P6.00 - Serum LDL cholesterol level`).

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `41.22% - 45.54%` suggests that this code set is likely well defined.

_Update **2024/03/01**: prevalence now `43% - 48%%`._

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2021-10-13 | EMIS            | 26929848   | 1102872 (41.94%) |  1102872 (41.94%) |
| 2021-10-13 | TPP             | 211812     |   91673 (43.28%) |    91673 (43.28%) |
| 2021-10-13 | Vision          | 338205     |  154055 (45.55%) |   154055 (45.55%) |
| 2024-03-06 | EMIS            | 2525894    |    1086503 (43%) |     1086736 (43%) |
| 2024-03-06 | TPP             | 201753     |      96837 (48%) |       96849 (48%) |
| 2024-03-06 | Vision          | 335117     |   149075 (44.5%) |    149103 (44.5%) |

## Audit log

- Find_missing_codes last run 2024-03-01
