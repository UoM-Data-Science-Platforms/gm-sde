# Myocardial infarction (MI)

Any code that indicates that a person has had a myocardial infarction. NB This includes "history" codes as well so is not best suited if you solely want to know when a diagnosis occurred.

- Includes acute coronary syndrome
- Includes aborted myocardial infarction

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `1.36% - 1.62%` suggests that this code set is well defined.

_Update **2024-01-19**: Prevalence now 1.5% - 1.8%. TPP still with slightly higher prevalence, but sufficiently close to EMIS and Vision._

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2022-12-07 | EMIS            | 2438760    |    33211 (1.36%) |     33876 (1.39%) |
| 2022-12-07 | TPP             | 198672     |     3210 (1.62%) |      5353 (2.69%) |
| 2022-12-07 | Vision          | 327081     |     4447 (1.36%) |      4454 (1.36%) |
| 2024-01-19 | EMIS            | 2519438    |     37720 (1.5%) |      37757 (1.5%) |
| 2024-01-19 | TPP             | 201469     |     3571 (1.77%) |      3572 (1.77%) |
| 2024-01-19 | Vision          | 334528     |     4945 (1.48%) |      4950 (1.48%) |

## Audit log

- Find_missing_codes last run 2024-01-17
