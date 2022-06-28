# Fasting glucose level

A patient's fasting glucose as recorded via clinical code and value. This does not include non-fasting blood glucose which is in a separate code set.

Codes were retrieved from https://getset.ga.

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `21.5% - 27.0%` is quite wide. However EMIS and VISION (>90% GM) are very similar, suggesting the higher prevalence in the TPP practices is an artefact of how often those practices get people to take fasting glucose tests.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2022-06-28 | EMIS            | 2664831    |   581474 (21.8%) |    586162 (22.0%) |
| 2022-06-28 | TPP             | 212907     |    57473 (27.0%) |     54891 (25.8%) |
| 2022-06-28 | Vision          | 343146     |    73687 (21.5%) |     74131 (21.6%) |
