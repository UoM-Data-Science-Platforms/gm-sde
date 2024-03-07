# Vitamin D

A patient's vitamin D level as recorded via clinical code and value. This code set only includes codes that are accompanied by a value (`44P6.00 - Serum LDL cholesterol level`). This only includes codes for total vitamin D level and does not use codes that measure a patient's D2 or D3 levels.

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `4.30% - 14.10%` suggests that this code set is not well defined and there are TPP codes that are missing.

_Update **2024-03-06**: prevalence now `16% - 18.6%` for EMIS and VISION. TPP much lower at 3.4% suggesting a potential issue._

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2021-05-11 | EMIS            | 2606497    |  282971 (10.86%) |   282971 (10.86%) |
| 2021-05-11 | TPP             | 210810     |     9056 (4.30%) |      9056 (4.30%) |
| 2021-05-11 | Vision          | 334784     |   47198 (14.10%) |    47198 (14.10%) |
| 2024-03-06 | EMIS            | 2525894    |     404510 (16%) |      404532 (16%) |
| 2024-03-06 | TPP             | 201753     |     6837 (3.39%) |      6836 (3.39%) |
| 2024-03-06 | Vision          | 335117     |    62329 (18.6%) |     62334 (18.6%) |

## Audit log

- Find_missing_codes last run 2024-03-06
