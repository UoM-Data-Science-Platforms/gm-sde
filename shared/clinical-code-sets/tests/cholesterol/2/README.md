# Cholesterol

A patient's total cholesterol as recorded via clinical code and value. This code set only includes codes that are accompanied by a value (`44P.. Serum cholesterol`). It does not include codes that indicate a patient's BMI (`44P3. - Serum cholesterol raised`) without giving the actual value.

Includes fasting and non-fasting cholesterol levels as current guidance is that it does not make a clinically significant difference.

**NB: This code set is intended to indicate a patient's total cholesterol. If you need to know whether a cholesterol was recorded then please use v1 of the code set.**

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `43.99% - 49.34%` suggests that this code set is likely well defined.

_Update **2024/03/01**: prevalence now `47% - 55%`._

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2021-05-11 | EMIS            | 2606497    | 1146925 (44.00%) |  1146651 (43.99%) |
| 2021-05-11 | TPP             | 210810     |   98627 (46.78%) |    98627 (46.78%) |
| 2021-05-11 | Vision          | 334784     |  165186 (49.34%) |   165186 (49.34%) |
| 2024-03-06 | EMIS            | 2525894    |  1173276 (46.4%) |   1173510 (46.5%) |
| 2024-03-06 | TPP             | 201753     |     110983 (55%) |      111001 (55%) |
| 2024-03-06 | Vision          | 335117     |   165017 (49.2%) |    165039 (49.2%) |

## Audit log

- Find_missing_codes last run 2024-03-01
