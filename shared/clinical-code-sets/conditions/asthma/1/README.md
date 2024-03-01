# Asthma

This code set was originally created for the SMASH safe medication dashboard and has been validated in practice.

- Includes byssinosis and other forms of occupational asthma
- Includes "asthmatic bronchitis" but not "allergic bronchitis"

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `12.7% - 13.6%` suggests that this code set is well defined.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2021-05-11 | EMIS            | 2606497    |  335219 (12.86%) |   335223 (12.86%) |
| 2021-05-11 | TPP             | 210810     |   25596 (12.14%) |    25596 (12.14%) |
| 2021-05-11 | Vision          | 334784     |   44764 (13.37%) |    44764 (13.37%) |
| 2024-01-19 | EMIS            | 2519438    |   320421 (12.7%) |    320849 (12.7%) |
| 2024-01-19 | TPP             | 201469     |    27456 (13.6%) |     27465 (13.6%) |
| 2024-01-19 | Vision          | 334528     |      43457 (13%) |       43511 (13%) |

## Audit log

- Find_missing_codes last run 2024-01-17
