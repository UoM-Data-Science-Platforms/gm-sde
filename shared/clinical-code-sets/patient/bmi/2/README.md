# Body Mass Index (BMI)

A patient's BMI as recorded via clinical code and value. This code set only includes codes that are accompanied by a value (`22K.. - Body Mass Index`). It does not include codes that indicate a patient's BMI (`22K6. - Body mass index less than 20`) without giving the actual value.

**NB: This code set is intended to indicate a patient's BMI. If you need to know whether a BMI was recorded then please use v1 of the code set.**

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `63.96% - 79.69%` suggests that this code set is perhaps not well defined. However, as EMIS (80% of practices) and TPP (10% of practices) are close, it could simply be down to Vision automatically recording BMIs and therefore increasing the prevalence there.

**UPDATE** By looking at the prevalence of patients with a BMI code that also has a non-zero value the range becomes `62.48% - 64.93%` which suggests that this code set is well defined.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2021-05-07 | EMIS            | 2605681    | 1709250 (65.60%) |  1709224 (65.60%) |
| 2021-05-07 | TPP             | 210817     |  134841 (63.96%) |   134835 (63.96%) |
| 2021-05-07 | Vision          | 334632     |  266612 (79.67%) |   266612 (79.67%) |
| 2021-05-11 | EMIS            | 2606497    | 1692442 (64.93%) |  1692422 (64.93%) |
| 2021-05-11 | TPP             | 210810     |  134652 (63.87%) |   134646 (63.87%) |
| 2021-05-11 | Vision          | 334784     |  209175 (62.48%) |   209175 (62.48%) |
