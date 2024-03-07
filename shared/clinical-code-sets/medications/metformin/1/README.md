# Metformin

This code set was originally created for the SMASH safe medication dashboard and has been validated in practice. It is also validated agains the NHS drug refsets.

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `4.75% - 5.19%` suggests that this code set is well defined.

_Update **2024-03-06**: Prevalence is now in the range `5.4% - 6.1%`._

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2021-05-07 | EMIS            | 2605681    |   135082 (5.18%) |    135136 (5.19%) |
| 2021-05-07 | TPP             | 210817     |    10016 (4.75%) |     10016 (4.75%) |
| 2021-05-07 | Vision          | 334632     |    16809 (5.02%) |     16809 (5.02%) |
| 2024-03-06 | EMIS            | 2525894    |   141124 (5.59%) |    141146 (5.59%) |
| 2024-03-06 | TPP             | 201753     |    12294 (6.09%) |     12296 (6.09%) |
| 2024-03-06 | Vision          | 335117     |    17914 (5.35%) |     17917 (5.35%) |

## Audit log

- Find_missing_codes last run 2024-03-06
