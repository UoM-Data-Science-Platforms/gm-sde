# Cancer

This version of the code set is based on the PCD ref set for cancer QOF reporting. The large size of the code set means it has yet to be fully validated. If using as a co-variate in an analysis it is sufficient, but if using as a primary outcome or exposure variable then should be checked further.

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `3.36% - 3.48%` for EMIS and Vision suggests that this code set is well defined. TPP practices are a bit higher at `4.84%` which may be down to the way cancer is recorded there, or a higher prevalence in those practices.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2023-10-31 | EMIS            | 2472595    |    81360 (3.29%) |     81210 (3.28%) |
| 2023-10-31 | TPP             | 200603     |     7909 (3.94%) |      7674 (3.83%) |
| 2023-10-31 | Vision          | 332447     |    11410 (3.43%) |     11506 (3.46%) |
| 2024-01-19 | EMIS            | 2519438    |    84634 (3.36%) |     84610 (3.36%) |
| 2024-01-19 | TPP             | 201469     |     9847 (4.89%) |      9748 (4.84%) |
| 2024-01-19 | Vision          | 334528     |    11545 (3.45%) |     11645 (3.48%) |

## Audit log

- Find_missing_codes last run 2024-01-19
