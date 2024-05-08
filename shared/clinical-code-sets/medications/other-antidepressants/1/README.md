# Other antidepressants

This code set was created as the union of the following drugs as specified from the PI of RQ051:

- Agomelatine
- Bupropion
- Esketamine
- Ketamine
- Oxitriptan
- Tryptophan

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `0.73 - 0.85%` for EMIS and Vision practices suggests this is well defined. However TPP practices have a rate of `1.4%`, nearly double that of EMIS and Vision, suggesting extra prescribing in those practices. TPP has the smallest footprint in terms of patient numbers which may also be a contributing factor.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2022-09-08 | EMIS            | 2448237    |     31860 (1.3%) |      31877 (1.3%) |
| 2022-09-08 | TPP             | 198144     |      3840 (1.9%) |       3894 (1.9%) |
| 2022-09-08 | Vision          | 325732     |      4692 (1.4%) |       4693 (1.4%) |
| 2024-05-08 | EMIS            | 2516912    |   18340 (0.729%) |    18340 (0.729%) |
| 2024-05-08 | TPP             | 200013     |     2779 (1.39%) |      2779 (1.39%) |
| 2024-05-08 | Vision          | 334384     |    2856 (0.854%) |     2856 (0.854%) |

## Audit log

- Find_missing_codes last run 2024-05-08
