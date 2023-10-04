# Urine bacteria test

This code set includes codes that indicate the result of bacteria in urine test. Posiive and negative results are included. When using this code set, your script will need to use a case_when statement, using the individual codes to classify which results are positive and which are negative.

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `%0.02 - 0.52%` suggests a discrepancy between code sets.


| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2023-09-20 | EMIS | 2466262 | 1117 (0.0453%) | 1062 (0.0431%) | 
| 2023-09-20 | TPP | 200680 | 1052 (0.524%) | 1050 (0.523%) | 
| 2023-09-20 | Vision | 332105 | 53 (0.016%) | 47 (0.0142%) | 
