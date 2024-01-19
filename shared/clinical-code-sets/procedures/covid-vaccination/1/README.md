## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set.

The discrepancy between the patients counted when using the IDs vs using the clinical codes is due to these being new codes which haven't all filtered through to the main Graphnet dictionary. The prevalence range `1.19% - 26.55%` as of 11th March 2021 is too wide. However the prevalence figure of 26.55% from EMIS is close to public data and is likely ok.

**UPDATE - 25th March 2021** Missing Read and CTV3 codes were added to the vaccination list and now the range of `26.91% - 32.96%` seems reasonable. It should be noted that there is an approx 2 week lag between events occurring and them being entered in the record.

**UPDATE - 12th April 2021**, latest prevalence figures.

**UPDATE - 18th March 2022** There are now new codes for things like 3rd/4th/booster dose of vaccine. The latest prevalence shows `65.0% - 66.3%` have at least one vaccine code in the GP_Events table, and `88.2% - 93.6%` have at least one code for the vaccine in the GP_Medications table.

### MED

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2021-05-12 | EMIS            | 2606497    |           0 (0%) |    379577(14.56%) |
| 2021-05-12 | TPP             | 210810     |           0 (0%) |       1637(0.78%) |
| 2021-05-12 | Vision          | 334784     |           0 (0%) |         93(0.03%) |
| 2022-03-18 | EMIS            | 2658131    |  1750506 (65.9%) |    1763420(66.3%) |
| 2022-03-18 | TPP             | 212662     |      8207 (3.9%) |     138285(65.0%) |
| 2022-03-18 | Vision          | 341594     |   122060 (35.7%) |     225844(66.1%) |
| 2024-01-19 | EMIS            | 2519438    |  1548887 (61.5%) |   1548887 (61.5%) |
| 2024-01-19 | TPP             | 201469     |     8768 (4.35%) |      8768 (4.35%) |
| 2024-01-19 | Vision          | 334528     |   127550 (38.1%) |    127550 (38.1%) |

### EVENT

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2021-05-12 | EMIS            | 2606497    |     4446 (0.17%) |  1101577 (42.26%) |
| 2021-05-12 | TPP             | 210810     |        7 (0.00%) |    87841 (41.66%) |
| 2021-05-12 | Vision          | 334784     |        1 (0.00%) |   142724 (42.63%) |
| 2022-03-18 | EMIS            | 2658131    |  2486786 (93.6%) |   1676951 (63.1%) |
| 2022-03-18 | TPP             | 212662     |   187463 (88.2%) |      7314 (3.44%) |
| 2022-03-18 | Vision          | 341594     |   312617 (91.5%) |     62512 (18.3%) |
| 2024-01-19 | EMIS            | 2519438    |   240495 (9.55%) |   1556149 (61.8%) |
| 2024-01-19 | TPP             | 201469     |     2290 (1.14%) |    137382 (68.2%) |
| 2024-01-19 | Vision          | 334528     |    31846 (9.52%) |    207703 (62.1%) |

## Audit log

- Find_missing_codes last run 2024-01-17
