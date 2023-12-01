# Social care referral

Codes indicating that patient had a referral to social care services. Data engineers should use this code set via the supplied codes rather than the linked IDs.
Created using getset:

{
  "includeTerms": [
    "social care plan",
    "hospital discharge notification to social care",
    "referral to social services department care manager",
    "signposting to social services",
    "referral to social services"
  ],
  "excludeTerms": [
    "child in need",
    "declined",
	"sending client copy"
  ],
  "terminology": "SNOMED CT",
  "version": "uk_sct2cl_29.3.0_20200610000001",
  "createdOn": "2023-11-30T11:00:13.255Z",
  "lastUpdated": "2023-11-30T11:00:13.255Z"
}


## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `%0.07 - 0.15%` suggests code set is well defined but not used often.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2023-11-30 | EMIS | 2514435 | 1786 (0.071%) | 1786 (0.071%) | 
| 2023-11-30 | TPP | 201265 | 293 (0.146%) | 293 (0.146%) | 
| 2023-11-30 | Vision | 333774 | 68 (0.0204%) | 68 (0.0204%) | 