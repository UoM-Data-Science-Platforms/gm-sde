# Heart failure

Any code indicating a diagnosis, or presence of heart failure. Does not include "History of" heart failure codes.

- Excludes "Cor pulmonale" as although this usually leads to heart failure, but is not heart failure.
- Also does not include "Chronic pulmonary heart disease" or "pulmonary oedema". Both of which can lead to heart failure but are not heart failure.

## Notes

The code `G581.` (read v2 and CTV3) includes "Left ventricular failure" and "Pulmonary oedema - acute" as synonyms for CTV3 but not read v2. These are not synonyms and we want the former but not the latter. Given the read v2 code is just "left ventricular failure" we include this code, but it is possible we match some patients with only a pulmonary oedema.

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set.

The discrepancy between the patients counted when using the IDs vs using the clinical codes is due to these being new codes which haven't all filtered through to the main Graphnet dictionary. The prevalence range `0.92% - 1.15%` is sufficiently narrow that this code set is likely well defined.

_Update **2023-10-27**: Prevalence now 1.03% - 1.26%. TPP still with slightly higher prevalence, but sufficiently close to EMIS and Vision._

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2021-03-11 | EMIS            | 2600658    |    23923 (0.92%) |     23923 (0.92%) |
| 2021-03-11 | TPP             | 210333     |     2415 (1.15%) |      2416 (1.15%) |
| 2021-03-11 | Vision          | 333251     |     3157 (0.95%) |      3157 (0.95%) |
| 2023-10-31 | EMIS            | 2472595    |    25714 (1.04%) |     25591 (1.03%) |
| 2023-10-31 | TPP             | 200603     |     2515 (1.25%) |      2519 (1.26%) |
| 2023-10-31 | Vision          | 332447     |     3552 (1.07%) |      3538 (1.06%) |

## Audit log

- Find_missing_codes last run 2024-01-17
