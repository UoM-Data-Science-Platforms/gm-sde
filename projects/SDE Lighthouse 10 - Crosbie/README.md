_This file is autogenerated. Please do not edit._

# Optimising lung cancer screening for individuals from underserved communities within Greater Manchester.

## Summary

Lung cancer is the UK’s leading cause of cancer death. Screening can save lives by finding lung cancer early. However, people at risk of lung cancer are also at risk of dying from other diseases. Understanding who benefits most from screening and whether people with multiple diseases benefit is important.
Screening for lung cancer using low-dose CT scans is being rolled out across Greater Manchester (GM) for smokers at high-risk (called the Targeted Lung Health Check programme). We have shown that more lung cancers are detected by screening. Importantly, most are found at an early stage and can therefore be cured.
In this proposal we want to better understand who is most likely to benefit from screening. One way to do this is to predict how many years of life individuals may gain from lung screening. This is called ‘life years gained’. This is a new approach that has not been examined in real-world screening programmes before. 
The Lighthouse Study provides the opportunity to achieve this by allowing us to have a far greater understanding of the overall health of people being screened, whether they have other diseases (comorbidities), how often they visit hospital and when they die. We will use this data to model and analyse the ‘life-years gained’ approach to risk prediction, and whether it can help us to focus screening on those who stand to benefit most from it.
This research will help us understand the best ways to invite people for screening using existing healthcare records. This is a priority to maximise the benefits of screening, avoid harms, and reduce health inequalities to inform how is rolled out nationally.

## Table of contents

- [Introduction](#introduction)
- [Methodology](#methodology)
- [Reusable queries](#reusable-queries)
- [Clinical code sets](#clinical-code-sets)

## Introduction

The aim of this document is to provide full transparency for all parts of the data extraction process.
This includes:

- The methodology around how the data extraction process is managed and quality is maintained.
- A full list of all queries used in the extraction, and their associated objectives and assumptions.
- A full list of all clinical codes used for the extraction.

## Methodology

After each proposal is approved, a Research Data Engineer (RDE) works closely with the research team to establish precisely what data they require and in what format.
The RDE has access to the entire de-identified database and so builds up an expertise as to which projects are feasible and how best to extract the relevant data.
The RDE has access to a library of resusable SQL queries for common tasks, and sets of clinical codes for different phenotypes, built up from previous studies.
Prior to data extraction, the code is checked and signed off by another RDE.

## Reusable queries
  
This project required the following reusable queries:

- Create table of patients who were alive at the study start date

Further details for each query can be found below.

### Create table of patients who were alive at the study start date
undefined

_Input_
```
undefined
```

_Output_
```
undefined
```
_File_: `query-get-possible-patients.sql`

_Link_: [https://github.com/rw251/.../query-get-possible-patients.sql](https://github.com/rw251/gm-idcr/tree/master/shared/Reusable%20queries%20for%20data%20extraction/query-get-possible-patients.sql)
## Clinical code sets

This project required the following clinical code sets:

- reasonable-adjustment-category5 v1
- reasonable-adjustment-category6 v1
- reasonable-adjustment-category7 v1
- reasonable-adjustment-category8 v1
- reasonable-adjustment-category9 v1
- reasonable-adjustment-category10 v1
- myocardial-infarction v1
- angina v1
- tuberculosis v1
- venous-thromboembolism v1
- pneumonia v1
- copd v1
- emphysema v1
- chronic-bronchitis v1
- efi-mobility-problems v1
- lung-cancer v1

Further details for each code set can be found below.

### Reasonable adjustment category 5 - additional communication needs and support

Codes from: https://digital.nhs.uk/services/reasonable-adjustment-flag/impairment-and-adjustment-codes

Categories 1 to 4 are already available as clusters in snowflake.

FYI the prevalence of these code sets is the same with only snowflake codes as it is with ctv3,readv2 and emis too. So categories 6 to 10 only have snomed.
#### Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `0.23% - 1.62%` suggests that this code set is well defined.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2024-10-25 | EMIS | 2492880 | 1877 (0.0753%) | 1877 (0.0753%) | 
| 2024-10-25 | TPP | 200929 | 10 (0.00498%) | 4 (0.00199%) | 
| 2024-10-25 | Vision | 332966 | 393 (0.118%) | 393 (0.118%) | 
LINK: [https://github.com/rw251/.../patient/reasonable-adjustment-category5/1](https://github.com/rw251/gm-idcr/tree/master/shared/clinical-code-sets/patient/reasonable-adjustment-category5/1)

### Reasonable adjustment category 6 - community language support

Codes from: https://digital.nhs.uk/services/reasonable-adjustment-flag/impairment-and-adjustment-codes

Categories 1 to 4 are already available as clusters in snowflake.

FYI the prevalence of these code sets is the same with only snowflake codes as it is with ctv3,readv2 and emis too. So categories 6 to 10 only have snomed.
#### Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `1.0% - 2.4%` suggests that this code set is well defined.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2024-10-25 | EMIS | 2492880 | 59210 (2.38%) | 59132 (2.37%) | 
| 2024-10-25 | TPP | 200929 | 2032 (1.01%) | 550 (0.274%) | 
| 2024-10-25 | Vision | 332966 | 5226 (1.57%) | 5219 (1.57%) | 
LINK: [https://github.com/rw251/.../patient/reasonable-adjustment-category6/1](https://github.com/rw251/gm-idcr/tree/master/shared/clinical-code-sets/patient/reasonable-adjustment-category6/1)

### Reasonable adjustment category 7 - adjustments for providing additional support to patients

Codes from: https://digital.nhs.uk/services/reasonable-adjustment-flag/impairment-and-adjustment-codes

Categories 1 to 4 are already available as clusters in snowflake.

FYI the prevalence of these code sets is the same with only snowflake codes as it is with ctv3,readv2 and emis too. So categories 6 to 10 only have snomed.
#### Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `0.2% - 0.3%` suggests that this code set is well defined.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |

| 2024-10-25 | EMIS | 2492880 | 6385 (0.256%) | 6358 (0.255%) | 
| 2024-10-25 | TPP | 200929 | 402 (0.2%) | 52 (0.0259%) | 
| 2024-10-25 | Vision | 332966 | 534 (0.16%) | 532 (0.16%) | 
LINK: [https://github.com/rw251/.../patient/reasonable-adjustment-category7/1](https://github.com/rw251/gm-idcr/tree/master/shared/clinical-code-sets/patient/reasonable-adjustment-category7/1)

### Reasonable adjustment category 8 - adjustments for individual care requirements

Codes from: https://digital.nhs.uk/services/reasonable-adjustment-flag/impairment-and-adjustment-codes

Categories 1 to 4 are already available as clusters in snowflake.

FYI the prevalence of these code sets is the same with only snowflake codes as it is with ctv3,readv2 and emis too. So categories 6 to 10 only have snomed.
#### Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `0.5% - 0.9%` suggests that this code set is well defined.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2024-10-25 | EMIS | 2492880 | 16941 (0.68%) | 16851 (0.676%) | 
| 2024-10-25 | TPP | 200929 | 1854 (0.923%) | 149 (0.0742%) | 
| 2024-10-25 | Vision | 332966 | 1513 (0.454%) | 1505 (0.452%) | 
LINK: [https://github.com/rw251/.../patient/reasonable-adjustment-category8/1](https://github.com/rw251/gm-idcr/tree/master/shared/clinical-code-sets/patient/reasonable-adjustment-category8/1)

### Reasonable adjustment category 9 - adjustments in relation to the environment of care

Codes from: https://digital.nhs.uk/services/reasonable-adjustment-flag/impairment-and-adjustment-codes

Categories 1 to 4 are already available as clusters in snowflake.

FYI the prevalence of these code sets is the same with only snowflake codes as it is with ctv3,readv2 and emis too. So categories 6 to 10 only have snomed.
#### Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `0.% - 0.%` suggests that this code set is well defined.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2024-10-25 | EMIS | 2492880 | 2698 (0.108%) | 2679 (0.107%) | 
| 2024-10-25 | TPP | 200929 | 211 (0.105%) | 16 (0.00796%) | 
| 2024-10-25 | Vision | 332966 | 252 (0.0757%) | 249 (0.0748%) | 
LINK: [https://github.com/rw251/.../patient/reasonable-adjustment-category9/1](https://github.com/rw251/gm-idcr/tree/master/shared/clinical-code-sets/patient/reasonable-adjustment-category9/1)

### Reasonable adjustment category 10 - adjustments to support additional needs

Codes from: https://digital.nhs.uk/services/reasonable-adjustment-flag/impairment-and-adjustment-codes

Categories 1 to 4 are already available as clusters in snowflake.

FYI the prevalence of these code sets is the same with only snowflake codes as it is with ctv3,readv2 and emis too. So categories 6 to 10 only have snomed.
#### Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `0.0% - 0.0%` suggests that this code set is rarely used.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2024-10-25 | EMIS | 2492880 | 46 (0.00185%) | 46 (0.00185%) | 
| 2024-10-25 | TPP | 200929 | 0 (0%) | 0 (0%) | 
| 2024-10-25 | Vision | 332966 | 0 (0%) | 0 (0%) | 
LINK: [https://github.com/rw251/.../patient/reasonable-adjustment-category10/1](https://github.com/rw251/gm-idcr/tree/master/shared/clinical-code-sets/patient/reasonable-adjustment-category10/1)

### Myocardial infarction (MI)

Any code that indicates that a person has had a myocardial infarction. NB This includes "history" codes as well so is not best suited if you solely want to know when a diagnosis occurred.

- Includes acute coronary syndrome
- Includes aborted myocardial infarction
#### Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `1.36% - 1.62%` suggests that this code set is well defined.

_Update **2024-01-19**: Prevalence now 1.5% - 1.8%. TPP still with slightly higher prevalence, but sufficiently close to EMIS and Vision._

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2022-12-07 | EMIS            | 2438760    |    33211 (1.36%) |     33876 (1.39%) |
| 2022-12-07 | TPP             | 198672     |     3210 (1.62%) |      5353 (2.69%) |
| 2022-12-07 | Vision          | 327081     |     4447 (1.36%) |      4454 (1.36%) |
| 2024-01-19 | EMIS            | 2519438    |     37720 (1.5%) |      37757 (1.5%) |
| 2024-01-19 | TPP             | 201469     |     3571 (1.77%) |      3572 (1.77%) |
| 2024-01-19 | Vision          | 334528     |     4945 (1.48%) |      4950 (1.48%) |
#### Audit log

- Find_missing_codes last run 2024-01-17

LINK: [https://github.com/rw251/.../conditions/myocardial-infarction/1](https://github.com/rw251/gm-idcr/tree/master/shared/clinical-code-sets/conditions/myocardial-infarction/1)

### Angina

Any code indicating a diagnosis of angina. Does not include codes that indicate angina but are not diagnoses e.g. "h/o angina", "angina plan discussed".
#### Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `1.03% - 1.37%` suggests that this code set is well defined.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2022-12-07 | EMIS            | 2438760    |    26698 (1.09%) |     27181 (1.11%) |
| 2022-12-07 | TPP             | 198672     |     2658 (1.34%) |      4448 (2.24%) |
| 2022-12-07 | Vision          | 327081     |     3537 (1.08%) |      3530 (1.08%) |
| 2024-01-19 | EMIS            | 2519438    |    26111 (1.04%) |     25927 (1.03%) |
| 2024-01-19 | TPP             | 201469     |     2758 (1.37%) |      2759 (1.37%) |
| 2024-01-19 | Vision          | 334528     |     3465 (1.04%) |      3451 (1.03%) |
#### Audit log

- Find_missing_codes last run 2024-01-16

LINK: [https://github.com/rw251/.../conditions/angina/1](https://github.com/rw251/gm-idcr/tree/master/shared/clinical-code-sets/conditions/angina/1)

### Tuberculosis

Any code indicating a diagnosis of tuberculosis. This code set was developed using the reference coding table in the GMCR environment, converting from ICD10 codes A15 - A19, followed by a complete cross reference check with SNOMED and mapping to other terminologies.
#### Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `0.33 -0.46%` suggests that this code set is well defined.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2024-05-09 | EMIS            | 2516912    |   11598 (0.461%) |    11598 (0.461%) |
| 2024-05-09 | TPP             | 200013     |     689 (0.344%) |      689 (0.344%) |
| 2024-05-09 | Vision          | 334384     |    1058 (0.316%) |     1058 (0.316%) |
| 2024-07-16 | EMIS            | 2696332    |   125681 (4.66%) |    12455 (0.462%) |
| 2024-07-16 | TPP             | 215597     |    1346 (0.624%) |      767 (0.356%) |
| 2024-07-16 | Vision          | 351153     |    13197 (3.76%) |     1142 (0.325%) |

LINK: [https://github.com/rw251/.../conditions/tuberculosis/1](https://github.com/rw251/gm-idcr/tree/master/shared/clinical-code-sets/conditions/tuberculosis/1)

### Venous thromboembolism

Any code indicating a diagnosis of venous thromboembolism. Includes personal history of the condition.
#### Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `1.25% - 1.67%` suggests that this code set is well defined.


| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2024-09-10 | EMIS | 2539735 | 42678 (1.68%) | 42492 (1.67%) | 
| 2024-09-10 | TPP | 202189 | 4070 (2.01%) | 2537 (1.25%) | 
| 2024-09-10 | Vision | 336595 | 5527 (1.64%) | 5446 (1.62%) | 
LINK: [https://github.com/rw251/.../conditions/venous-thromboembolism/1](https://github.com/rw251/gm-idcr/tree/master/shared/clinical-code-sets/conditions/venous-thromboembolism/1)

### Pneumonia 

Code set for patients with a code related to pneumonia

Developed from https://www.opencodelists.org/codelist/bristol/pneumonia/44622d57/#full-list
#### Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, 
we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set.
The prevalence range `%1.61 - 2.06%` suggests that this code set is well defined.


|    Date    | Practice system |  Population | Patients from ID | Patient from code |
| ---------- | ----------------| ------------| ---------------- | ----------------- |
| 2023-09-14 | EMIS | 2463856 | 50870 (2.06%) | 50899 (2.07%) | 
| 2023-09-14 | TPP | 200590 | 4117 (2.05%) | 4117 (2.05%) | 
| 2023-09-14 | Vision | 332095 | 5351 (1.61%) | 5354 (1.61%) | 
LINK: [https://github.com/rw251/.../conditions/pneumonia/1](https://github.com/rw251/gm-idcr/tree/master/shared/clinical-code-sets/conditions/pneumonia/1)

### COPD

Any suggestion of a diagnosis of COPD.

Developed from https://getset.ga.

- Includes "obliterative bronchiolitis" as a similar condition to COPD. Might not be required for all studies.
#### Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `2.19% - 2.49%` in 2023 suggests that this code set is well defined.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2021-05-07 | EMIS            | 2605681    |    54668 (2.10%) |     54669 (2.10%) |
| 2021-05-07 | TPP             | 210817     |     4537 (2.15%) |      4538 (2.15%) |
| 2021-05-07 | Vision          | 334632     |     7789 (2.33%) |      7789 (2.33%) |
| 2023-09-15 | EMIS            | 2463856    |    53577 (2.17%) |     53551 (2.17%) |
| 2023-09-15 | TPP             | 200590     |     4959 (2.47%) |      4966 (2.48%) |
| 2023-09-15 | Vision          | 332095     |     7382 (2.22%) |      7374 (2.22%) |
| 2024-01-19 | EMIS            | 2519438    |    54964 (2.18%) |     55097 (2.19%) |
| 2024-01-19 | TPP             | 201469     |     5016 (2.49%) |      5023 (2.49%) |
| 2024-01-19 | Vision          | 334528     |     7434 (2.22%) |      7444 (2.23%) |
#### Audit log

- Find_missing_codes last run 2024-01-17

LINK: [https://github.com/rw251/.../conditions/copd/1](https://github.com/rw251/gm-idcr/tree/master/shared/clinical-code-sets/conditions/copd/1)

### Emphysema

Any suggestion of a diagnosis of emphysema. This is a subset of the COPD code set. For more information on where the codes came from, see COPD code set v1.

#### Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `% - %` suggests that this code set is well defined.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2024-09-12 | EMIS | 2539735 | 10400 (0.409%) | 10332 (0.407%) | 
| 2024-09-12 | TPP | 202189 | 1064 (0.526%) | 1059 (0.524%) | 
| 2024-09-12 | Vision | 336595 | 1031 (0.306%) | 1025 (0.305%) | 



LINK: [https://github.com/rw251/.../conditions/emphysema/1](https://github.com/rw251/gm-idcr/tree/master/shared/clinical-code-sets/conditions/emphysema/1)

### Chronic bronchitis

Any suggestion of a diagnosis of chronic bronchitis. This is a subset of the COPD code set. For more information on where the codes came from, see COPD code set v1.

  ## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `0.8% - 0.9%` suggests that this code set is well defined.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2023-10-25 | EMIS            | 2472595    |    20089 (0.8%)  |    20102 (0.8%)   |
| 2023-10-25 | TPP             | 200603     |     1808 (0.9%)  |     1808 (0.9%)   |
| 2023-10-25 | Vision          | 332447     |     2900 (0.9%)  |     2901 (0.9%)   |
LINK: [https://github.com/rw251/.../conditions/chronic-bronchitis/1](https://github.com/rw251/gm-idcr/tree/master/shared/clinical-code-sets/conditions/chronic-bronchitis/1)

### Mobility problems (for electronic frailty index)

These are the codes from the original electronic frailty index (EFI). Our aim is to produce an EFI comparably to that used in practice and so we simply reproduce the codes sets and do not attempt further validation.
#### Prevalence

| Date       | Practice system | Population | Patients from ID | Patient from code |
| 2024-10-16 | EMIS | 2709725 | 47567 (1.76%) | 47566 (1.76%) | 
| 2024-10-16 | TPP | 216275 | 3752 (1.73%) | 3732 (1.73%) | 
| 2024-10-16 | Vision | 352021 | 5078 (1.44%) | 5078 (1.44%) | 
LINK: [https://github.com/rw251/.../patient/efi-mobility-problems/1](https://github.com/rw251/gm-idcr/tree/master/shared/clinical-code-sets/patient/efi-mobility-problems/1)

###  Lung cancer codes

Developed from https://getset.ga with inclusion terms and exclusion terms as below:

"includeTerms": [
    "lung cancer"
  ],
  "excludeTerms": [
    "family history of",
    "screening declined",
    "no fh of",
    "lung cancer risk calculator",
    "fh: lung cancer",
    "lung cancer screening",
    "qcancer lung cancer risk"
  ]


  ## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `0.18% - 0.24%` suggests that this code set is well defined.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2023-10-12 | EMIS            | 2470460    |    5882 (0.24%)  |    5886 (0.24%)   |
| 2023-10-12 | TPP             | 200512     |     374 (0.18%)  |     374 (0.18%)   |
| 2023-10-12 | Vision          | 332318     |     695 (0.21%)  |     692 (0.21%)   |
LINK: [https://github.com/rw251/.../conditions/lung-cancer/1](https://github.com/rw251/gm-idcr/tree/master/shared/clinical-code-sets/conditions/lung-cancer/1)
# Clinical code sets

All code sets required for this analysis are available here: [https://github.com/rw251/.../SDE Lighthouse 10 - Crosbie/clinical-code-sets.csv](https://github.com/rw251/gm-idcr/tree/master/projects/SDE%20Lighthouse%2010%20-%20Crosbie/clinical-code-sets.csv). Individual lists for each concept can also be found by using the links above.