# HbA1c

A patient's HbA1c as recorded via clinical code and value. This code set only includes codes that are accompanied by a value (`1003671000000109 - Haemoglobin A1c level`). It does not include codes that indicate a patient's HbA1c (`165679005 - Haemoglobin A1c (HbA1c) less than 7%`) without giving the actual value.

**NB: This code set is intended to indicate a patient's HbA1c. If you need to know whether a HbA1c was recorded then please use v1 of the code set.**

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `44.93% - 50.88%` suggests that this code set is likely well defined.

_Update **2024/03/01**: prevalence now `50 - 53%`._

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2021-05-07 | EMIS            | 2605681    | 1170688 (44.93%) |  1170688 (44.93%) |
| 2021-05-07 | TPP             | 210817     |   98972 (46.95%) |    98972 (46.95%) |
| 2021-05-07 | Vision          | 334632     |  170245 (50.88%) |   170245 (50.88%) |
| 2024-03-01 | EMIS            | 2525130    |  1265760 (50.1%) |   1265887 (50.1%) |
| 2024-03-01 | TPP             | 201782     |   101663 (50.4%) |    101673 (50.4%) |
| 2024-03-01 | Vision          | 335118     |     177455 (53%) |      177464 (53%) |

## Audit log

- Find_missing_codes last run 2024-03-01
