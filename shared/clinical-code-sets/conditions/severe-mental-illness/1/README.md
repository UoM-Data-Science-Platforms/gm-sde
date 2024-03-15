# Severe mental illness

Defined as any diagnosis of:

- Psychotic disorder
- Bipolar disorder
- Schizophrenia

or patients on the severe mental illness register.

CTV3 code sets from OpenSafely and the NHS PCD refsets.

SNOMED code set supplemented from the following codes and all their descendants:

| SNOMED code | Description                                 |
| ----------- | ------------------------------------------- |
| 391193001   | On severe mental illness register (finding) |
| 69322001    | Psychotic disorder (disorder)               |
| 13746004    | Bipolar disorder (disorder)                 |
| 58214004    | Schizophrenia (disorder)                    |

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set.

The discrepancy between the patients counted when using the IDs vs using the clinical codes is due to these being new codes which haven't all filtered through to the main Graphnet dictionary. The prevalence range `1.04% - 1.77%` is perhaps too wide suggesting there is an underreporting from TPP practices - or the CTV3 code set differs from the others.

_Update **2024-03-15**: Prevalence now 1.14% - 1.18% which suggests it is now well defined._

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2021-03-11 | EMIS            | 2600658    |    46405 (1.78%) |     46081 (1.77%) |
| 2021-03-11 | TPP             | 210333     |     2200 (1.05%) |      2196 (1.04%) |
| 2021-03-11 | Vision          | 333251     |     6770 (2.03%) |      5338 (1.60%) |
| 2024-03-15 | EMIS            | 2526522    |    44626 (1.77%) |     29709 (1.18%) |
| 2024-03-15 | TPP             | 201758     |     2455 (1.22%) |      2294 (1.14%) |
| 2024-03-15 | Vision          | 335186     |     5667 (1.69%) |      3830 (1.14%) |

## Audit log

- Find_missing_codes last run 2024-03-15
