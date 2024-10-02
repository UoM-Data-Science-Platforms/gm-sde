# Height

A patient's height as recorded via clinical code and value. This code set only includes codes that are accompanied by a value (`229.. - O/E - Height`).

Codes taken from https://www.medrxiv.org/content/medrxiv/suppl/2020/05/19/2020.05.14.20101626.DC1/2020.05.14.20101626-1.pdf

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `69.4% - 71.8%` suggests that this code set is well defined.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2021-10-13 | EMIS            | 26929848   | 1885015 (71.68%) |  1884110 (71.64%) |
| 2021-10-13 | TPP             | 211812     |  140013 (66.10%) |   140013 (66.10%) |
| 2021-10-13 | Vision          | 338205     |  245440 (72.59%) |   245440 (72.57%) |
| 2023-11-07 | EMIS            | 2482563    |  1797419 (72.4%) |   1797473 (72.4%) |
| 2023-11-07 | TPP             | 201030     |   149385 (74.3%) |    149388 (74.3%) |
| 2023-11-07 | Vision          | 333490     |   236514 (70.9%) |    236518 (70.9%) |

SDE:

| Date       | Practice system | Population | Patient from code |
| ---------- | --------------- | ---------- | ----------------: |
| 2024-10-02 | Vision | 352474 | 252978 (71.8%) | 
| 2024-10-02 | EMIS | 2712966 | 1883010 (69.4%) | 
| 2024-10-02 | TPP | 216508 | 155172 (71.7%) | 

## Audit log

- Find_missing_codes last run 2023-11-07


