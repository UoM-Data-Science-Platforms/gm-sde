# Urinary tract infection

Codes taken from https://phenotypes.healthdatagateway.org/concepts/C2679/version/6771/detail/#home

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set.

The discrepancy between the patients counted when using the IDs vs using the clinical codes is due to these being new codes which haven't all filtered through to the main Graphnet dictionary. The prevalence range `14.03% - 20.68%` suggests there are potential missing codes from TPP practices. Perhaps some Readv2 codes are missing.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2022-04-11 | EMIS            | 2660237    |  526473 (19.79%) |   523378 (19.67%) |
| 2022-04-11 | TPP             | 212647     |   29844 (14.03%) |     13227 (6.22%) |
| 2022-04-11 | Vision          | 341912     |   70709 (20.68%) |    70355 (20.58%) |
