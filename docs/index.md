## Index

- [Overview](../README.md)
- **DATA DESCRIPTION**
- [Current projects](current-projects.md)
- [Clinical code sets](clinical-code-sets.md)
- [Additional technical information](additional-technical-information.md)

# Greater Manchester Care Record - data description

This page describes the data that is available within the GMCR. It is likely useful for researchers who would like to use the data for their research. It is not exhaustive, so researchers are encouraged to contact us if they are unsure whether this data is fit for their purposes.

## Overview

The GMCR contains linked data from primary and secondary care from the 10 CCGs in Greater Manchester (Bolton, Bury, Heywood Middleton and Rochdale, Manchester, Oldham, Salford, Stockport, Tameside and Glossop, Trafford, and Wigan). This includes:

- all information that is typically held within GP systems
- secondary care data related to A&E admissions, in-patient stays, and out-patient appointments for all hospital trusts (acute and community) in Greater Manchester

Further detail on the data is set out below.

## De-identification

The data is de-identified by removing all identifiers such as: NHS number, name, address, date of birth. In some cases, identifiable data is aggregated to a higher level which keeps the data de-identified while retaining utility for researchers. Examples of this are:

- year of birth is available instead of date of birth so that age can be used as a covariate
- LSOA ([lower level super output area](https://datadictionary.nhs.uk/nhs_business_definitions/lower_layer_super_output_area.html)) is available instead of address so that geography and linked deprivation scores can be used

## Demographic data

The following patient specific data is available for each patient. This data is only available if the care setting where the record originates has capture the information.

- Sex
- Year of birth
- Ethnicity
- Lower level super output area (geographic identifier - [LSOA](https://datadictionary.nhs.uk/nhs_business_definitions/lower_layer_super_output_area.html))
- Index of multiple deprivation ([IMD](https://www.gov.uk/government/collections/english-indices-of-deprivation))
- Month and year of death
- Registered GP practice
- Whether the patient lives in a care home

## Primary care

The primary care data comes from GP systems within Greater Manchester. It has close to 100% coverage, with only 1 practice (out of ~450) not contributing data.

The data comes from a mixture of GP systems. The majority (~80%) is EMIS web, but there is also data from Vision and TPP practices (~10% each).

The data is "coded" - i.e. it contains clinical codes (a mixture of [Read v2, CTV3](https://digital.nhs.uk/services/terminology-and-classifications/read-codes), EMIS and [SNOMED](https://termbrowser.nhs.uk/)) along with the date the code was entered into the patient's record, and optionally a value and a unit. It does not contain any free-text data as that may circumvent the de-identification process. Clinical code dictionaries allow pretty much any clinical concept to be captured. The GP data therefore contains:

- Diagnoses
- Medications
- Lab results
- Observations
- Symptoms
- Procedures

## Secondary care

The secondary care data is not as complete as the primary care data, but it is still useful. There is data on:

- A&E attendances
- In-patient admissions and discharges classified as planned or unplanned
- Out-patient appointments

This data is available for the following hospitals within GM:

| Hospital                                | A&E data from | In-patient from | Out-patient from |
| --------------------------------------- | ------------- | --------------- | ---------------- |
| Bolton NHS Foundation Trust             | 2020-11       | 2018-02         | No data          |
| Central Manchester University Hospitals | 2018-01       | 2017-01         | 2017-01          |
| Pennine Acute Hospitals                 | 2018-02       | 2018-02         | 2018-01          |
| Salford Royal NHS Foundation Trust      | 2020-07       | 2020-07         | 2020-05          |
| Stockport NHSFT                         | 2020-12       | 2020-05         | 2020-09          |
| Tameside Hospital - TGICFT              | 2014-01       | 2014-04         | 2014-04          |
| University Hospital of South Manchester | 2017-12       | 2017-11         | 2016-11          |
| Wrightington Wigan and Leigh NHSFT      | 2020-05       | 2021-03         | No data          |

## Potential issues

There are certain limitations with the data. Health care data is collected for the primary purpose of providing patient care. It is not collected for research. The following are issues that may affect research performed on the GMCR:

- Missing dead patients

  In some cases, the data of patients who died prior to 2019 is not included in the GMCR. This is an issue for studies that need historic comparisons prior to this date.

- Acute data feeds

  The feeds from hospitals are not backdated from before the feed went live. So if a hospital started providing data in 2018, then there are no records for that hospital prior to 2018.

- Covid tests only currently coming from primary care. Those done in hospitals will be missed.
