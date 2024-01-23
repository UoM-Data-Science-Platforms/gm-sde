# Rheumatoid arthritis

Any code indicating a diagnosis of rheumatoid arthritis.

- Does not include lupus
- Does not include ankylosing spondylitis

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set.

The discrepancy between the patients counted when using the IDs vs using the clinical codes is due to these being new codes which haven't all filtered through to the main Graphnet dictionary. The prevalence range `0.53% - 0.62%` suggests that this code set is well defined.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2022-05-16 | EMIS            | 2662570    |    15603 (0.59%) |     15603 (0.59%) |
| 2022-05-16 | TPP             | 212696     |     1130 (0.53%) |      1137 (0.53%) |
| 2022-05-16 | Vision          | 342344     |     2126 (0.62%) |      2126 (0.62%) |
| 2024-01-19 | EMIS            | 2519438    |    40728 (1.62%) |     36996 (1.47%) |
| 2024-01-19 | TPP             | 201469     |     2206 (1.09%) |     1423 (0.706%) |
| 2024-01-19 | Vision          | 334528     |     6262 (1.87%) |       5683 (1.7%) |

## Audit log

- Find_missing_codes last run 2024-01-17
