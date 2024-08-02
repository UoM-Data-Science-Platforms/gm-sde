# Anxiety

Any code indicating a diagnosis of anxiety or other somatoform disorder. Developed from SNOMED searches and the opencodelist code set: https://www.opencodelists.org/codelist/opensafely/anxiety-disorders/6aef605a/.

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set.

The discrepancy between the patients counted when using the IDs vs using the clinical codes is due to these being new codes which haven't all filtered through to the main Graphnet dictionary. The prevalence range `21.3% - 22%` suggests that this code set is well defined.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2022-05-16 | EMIS            | 2662570    |  499713 (18.77%) |   502416 (18.87%) |
| 2022-05-16 | TPP             | 212696     |   38757 (18.22%) |    38769 (18.23%) |
| 2022-05-16 | Vision          | 342344     |   65130 (19.02%) |    64271 (18.77%) |
| 2024-04-30 | EMIS            | 2530927    |   766186 (30.3%) |    549512 (21.7%) |
| 2024-04-30 | TPP             | 201816     |      46335 (23%) |     42913 (21.3%) |
| 2024-04-30 | Vision          | 335411     |    77888 (23.2%) |       73817 (22%) |

## Audit log

- Find_missing_codes last run 2024-04-30
