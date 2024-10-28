# Reasonable adjustment category 7 - adjustments for providing additional support to patients

Codes from: https://digital.nhs.uk/services/reasonable-adjustment-flag/impairment-and-adjustment-codes

Categories 1 to 4 are already available as clusters in snowflake.

FYI the prevalence of these code sets is the same with only snowflake codes as it is with ctv3,readv2 and emis too. So categories 6 to 10 only have snomed.

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `0.2% - 0.3%` suggests that this code set is well defined.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |

| 2024-10-25 | EMIS | 2492880 | 6385 (0.256%) | 6358 (0.255%) | 
| 2024-10-25 | TPP | 200929 | 402 (0.2%) | 52 (0.0259%) | 
| 2024-10-25 | Vision | 332966 | 534 (0.16%) | 532 (0.16%) | 