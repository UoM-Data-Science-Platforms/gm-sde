# Underweight
Codes indicating that patient is underweight.

Codes taken from https://www.medrxiv.org/content/medrxiv/suppl/2020/05/19/2020.05.14.2003103.DC1/2020.05.14.2003103-1.pdf 

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `0.03% - 0.09%` suggests no issue between the GP systems, however it looks massively underestimated. Consider using BMI values also to find underweight patients. 


| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2022-03-03 | EMIS            |  2656596   |    1331 (0.05%)  |      1331 (0.05%) |
| 2022-03-03 | TPP             |   212503   |      67 (0.03%)  |        67 (0.03%) |
| 2022-03-03 | Vision          |   341299   |     291 (0.09%)  |       291 (0.09%) |