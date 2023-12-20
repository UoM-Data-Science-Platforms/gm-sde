# Hypothyroidism

Any code indicating a diagnosis of hypothyroidism. Modified from the NHS PCD refset (https://digital.nhs.uk/data-and-information/data-collections-and-data-sets/data-collections/quality-and-outcomes-framework-qof/quality-and-outcome-framework-qof-business-rules/primary-care-domain-reference-set-portal)

- Does not include "history of" codes
- Does not include "goitre" unless code explicitly relates it to hypothyroidism
- Does not include "hypopituitarism" or "pituitary hypofunction" as these relate to a hormone deficiency in the pituitary gland, but TSH is just one of the hormones that it could refer to
- Does not include neonatal codes e.g. neonatal hypothyroidism, or thyroid aplasia
- Does include post-surgical and other transient hypothyroidism
- Does include hypothyrotropinaemia and hypothyroxinemia

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `3-4%` suggests that this code set is well defined.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2023-12-20 | EMIS            | 2516480    |    84375 (3.35%) |     84430 (3.36%) |
| 2023-12-20 | TPP             | 201282     |     8123 (4.04%) |      8125 (4.04%) |
| 2023-12-20 | Vision          | 334130     |     9883 (2.96%) |      9891 (2.96%) |

## Audit log

- Find_missing_codes last run 2023-12-20
