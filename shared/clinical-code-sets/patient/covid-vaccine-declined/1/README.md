# Covid vaccine declined

Any codes indicating the patient has declined the vaccine for COVID-19.

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set.

The discrepancy between the patients counted when using the IDs vs using the clinical codes is due to these being new codes which haven't all filtered through to the main Graphnet dictionary. The prevalence range `0.78% - 0.82%` for EMIS and TPP seems plausible. But in comparison the `0.40%` for Vision systems seems on the low side. There may be some extra Read v2 codes we haven't identified.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2021-03-25 | EMIS            | 2602984    |     1783 (0.07%) |     21305 (0.82%) |
| 2021-03-25 | TPP             | 210441     |        2 (0.00%) |      1650 (0.78%) |
| 2021-03-25 | Vision          | 333572     |        0 (0.00%) |      1319 (0.40%) |
