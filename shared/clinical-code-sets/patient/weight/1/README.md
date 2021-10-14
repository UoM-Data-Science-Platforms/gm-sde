# Weight

A patient's weight as recorded via clinical code and value. This code set only includes codes that are accompanied by a value.

Codes taken from https://www.medrxiv.org/content/medrxiv/suppl/2020/05/19/2020.05.14.20101626.DC1/2020.05.14.20101626-1.pdf

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `63.96% - 79.69%` suggests that this code set is perhaps not well defined. However, as EMIS (80% of practices) and TPP (10% of practices) are close, it could simply be down to Vision automatically recording BMIs and therefore increasing the prevalence there.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2021-10-13 | EMIS            | 26929848   | 2054449 (78.12%) |  2053717 (78.09%) |
| 2021-10-13 | TPP             | 211812     |  154813 (73.09%) |   154813 (73.09%) |
| 2021-10-13 | Vision          | 338205     |  269496 (79.68%) |   269496 (79.68%) |