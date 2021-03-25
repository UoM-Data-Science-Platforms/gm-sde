# Immunosuppression

Codes that indicate a patient has a diagnosis of temporary or permanent immunosuppression, excluding HIV. SNOMED and CTV3 codelist are from the OpenSAFELY team (see below for links). The Read 2 codelist is from the LSHTM Data Compass.

- [Immunosuppression - permanent (CTV3)](https://codelists.opensafely.org/codelist/opensafely/permanent-immunosuppression/2020-06-02/)
- [Immunosuppression - temporary (CTV3)](https://codelists.opensafely.org/codelist/opensafely/temporary-immunosuppression/2020-04-24/)
- [Immunosuppression - permanent (SNOMED)](https://codelists.opensafely.org/codelist/opensafely/permanent-immunosuppression-snomed/2020-06-02/)
- [Immunosuppression - temporary (SNOMED)](https://codelists.opensafely.org/codelist/opensafely/temporary-immunosuppression-snomed/2020-04-24/)

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set.

The discrepancy between the patients counted when using the IDs vs using the clinical codes is due to these being new codes which haven't all filtered through to the main Graphnet dictionary. The prevalence range `0.30% - 0.50%` is sufficiently narrow that this code set is likely well defined.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2021-03-11 | EMIS            | 2600658    |    11815 (0.45%) |     11453 (0.44%) |
| 2021-03-11 | TPP             | 210333     |      625 (0.30%) |       625 (0.30%) |
| 2021-03-11 | Vision          | 333251     |     1766 (0.53%) |      1667 (0.50%) |
