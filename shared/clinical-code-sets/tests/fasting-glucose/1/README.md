# Fasting glucose level

A patient's fasting glucose as recorded via clinical code and value. This does not include non-fasting blood glucose which is in a separate code set.

Codes were retrieved from https://getset.ga.

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range by code `21.6% - 25.8%` suggests this is probably well defined. TPP is a bit high, but EMIS and VISION (>90% GM) are very similar, suggesting the higher prevalence in the TPP practices is an artefact of how often those practices get people to take fasting glucose tests.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2022-07-05 | EMIS            | 2664831    |     585156 (22%) |      586162 (22%) |
| 2022-07-05 | TPP             | 212907     |      57478 (27%) |     54891 (25.8%) |
| 2022-07-05 | Vision          | 343146     |    74116 (21.6%) |     74131 (21.6%) |
