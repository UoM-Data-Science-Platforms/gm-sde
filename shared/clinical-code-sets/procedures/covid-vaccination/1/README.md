## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set.

The discrepancy between the patients counted when using the IDs vs using the clinical codes is due to these being new codes which haven't all filtered through to the main Graphnet dictionary. The prevalence range `1.19% - 26.55%` as of 11th March 2021 is too wide. However the prevalence figure of 26.55% from EMIS is close to public data and is likely ok.

**UPDATE - 25th March 2021** Missing Read and CTV3 codes were added to the vaccination list and now the range of `26.91% - 32.96%` seems reasonable. It should be noted that there is an approx 2 week lag between events occurring and them being entered in the record.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2021-03-11 | EMIS            | 2600658    |           2 (0%) |   690414 (26.55%) |
| 2021-03-11 | TPP             | 210333     |           0 (0%) |      2525 (1.20%) |
| 2021-03-11 | Vision          | 333251     |           0 (0%) |      3955 (1.19%) |
| 2021-03-25 | EMIS            | 2602984    |     4550 (0.17%) |   857956 (32.96%) |
| 2021-03-25 | TPP             | 210441     |        5 (0.00%) |    56620 (26.91%) |
| 2021-03-25 | Vision          | 333572     |        1 (0.00%) |    93113 (27.91%) |
