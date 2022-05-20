# Urine blood test

This code set includes codes that indicate the result of blood in urine test. Posiive and negative results are included. When using this code set, your script will need to use a case_when statement, using the individual codes to classify which results are positive and which are negative.

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `2.99% - 14.79%` suggests underreporting from Vision practices.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2022-05-19 | EMIS            | 2662570    | 393799 (14.79%)  |  383716 (14.41%)  |
| 2022-05-19 | TPP             | 212696     |  26798 (12.60%)  |   26763 (12.58%)  |
| 2022-05-19 | Vision          | 342344     |   10231 (2.99%)  |     9915 (2.90%)  |
