## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set.

The discrepancy between the patients counted when using the IDs vs using the clinical codes is due to these being new codes which haven't all filter through to the main Graphnet dictionary. The prevalence range `1.19% - 26.55%` is too wide. However the prevalence figure of 26.55% from EMIS is close to public data and is likely ok. Graphnet are working on integrating TPP and Vision data.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2021-03-11 | EMIS            | 2600658    |           2 (0%) |   690414 (26.55%) |
| 2021-03-11 | TPP             | 210333     |           0 (0%) |      2525 (1.20%) |
| 2021-03-11 | Vision          | 333251     |           0 (0%) |      3955 (1.19%) |
