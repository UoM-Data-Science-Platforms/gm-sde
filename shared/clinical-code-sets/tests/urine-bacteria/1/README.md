# Urine bacteria test

This code set includes codes that indicate the result of bacteria in urine test. Posiive and negative results are included. When using this code set, your script will need to use a case_when statement, using the individual codes to classify which results are positive and which are negative.

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `%0.01 - 0.05%` suggests either underreporting or just not many occurences.


| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2022-05-11 | EMIS            | 2662570    | 	1206 (0.05%)   |  	1206 (0.05%)   |
| 2022-05-11 | TPP             | 212696     |     14 (0.01%)   |      14 (0.01%)   |
| 2022-05-11 | Vision          | 342344     |     55 (0.02%)   |      55 (0.02%)   |
