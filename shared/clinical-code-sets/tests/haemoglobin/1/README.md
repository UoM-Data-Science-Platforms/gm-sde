# Haemoglobin

A patient's haemoglobin as recorded via clinical code and value. This code set only includes codes that are accompanied by a value (`423.. - Haemoglobin estimation`). It does not include codes that indicate a patient's haemoglobin (`4235 - Haemoglobin low`) without giving the actual value.

Haemoglobin codes were retrieved from https://www.medrxiv.org/content/medrxiv/suppl/2020/05/19/2020.05.14.20101626.DC1/2020.05.14.20101626-1.pdf.

**NB: This code set is intended to only indicate a patient's haemoglobin values.**

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `61% - 68.1%` suggests that this code set is likely well defined.

_Update **2024-03-15**: Prevalence now 60% - 62%._

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2023-09-18 | EMIS            | 2463856    |    1501968 (61%) |     1502094 (61%) |
| 2023-09-18 | TPP             | 200590     |   136648 (68.1%) |    136654 (68.1%) |
| 2023-09-18 | Vision          | 332095     |   206665 (62.2%) |    206678 (62.2%) |
| 2024-03-15 | EMIS            | 2526522    |  1539133 (60.9%) |   1539250 (60.9%) |
| 2024-03-15 | TPP             | 201758     |   120785 (59.9%) |    120796 (59.9%) |
| 2024-03-15 | Vision          | 335186     |   208861 (62.3%) |    208874 (62.3%) |

## Audit log

- Find_missing_codes last run 2024-03-15
