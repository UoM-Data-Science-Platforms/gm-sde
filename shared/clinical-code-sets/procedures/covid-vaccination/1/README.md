## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set.

The discrepancy between the patients counted when using the IDs vs using the clinical codes is due to these being new codes which haven't all filtered through to the main Graphnet dictionary. The prevalence range `1.19% - 26.55%` as of 11th March 2021 is too wide. However the prevalence figure of 26.55% from EMIS is close to public data and is likely ok.

**UPDATE - 25th March 2021** Missing Read and CTV3 codes were added to the vaccination list and now the range of `26.91% - 32.96%` seems reasonable. It should be noted that there is an approx 2 week lag between events occurring and them being entered in the record.

**UPDATE - 12th April 2021, latest prevalence figures:

MED

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2021-05-12 | EMIS            | 2606497    |           0 (0%) |    379577(14.56%) |
| 2021-05-12 | TPP             | 210810	    |           0 (0%) |       1637(0.78%) |
| 2021-05-12 | Vision          | 334784	    |           0 (0%) |         93(0.03%) |

EVENT

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2021-05-12 | 	EMIS	       | 2606497    |	4446 (0.17%)   |  1101577 (42.26%) |
| 2021-05-12 |	TPP	       | 210810	    |	7 (0.00%)      |    87841 (41.66%) |
| 2021-05-12 |	Vision	       | 334784	    |	1 (0.00%)      |   142724 (42.63%) |
