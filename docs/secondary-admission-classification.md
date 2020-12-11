# Secondary In-patient Admission Classification

It is often useful to classify in-patient admissions depending on whether it was an elective or an emergency procedure. This page explains how this is done with the GMCR.

## Current best classification

The current SQL code that operationalises the below is here `TODO insert link`.

## Background

Different hosptials use different IT systems. Even when two hospitals use the same system, the records can be different due to the large degree of configuration that is possible. This makes the classification of encounters a non-trivial task.

It is often useful to classify admissions depending on whether it was planned (e.g. elective procedures) or unplanned (e.g. emergency admissions). However there are 2 other situations that should be kept separate - births and transfers. Births (and other maternity admissions) could be split into planned and unplanned... Transfers can occur between hospitals and between wards, but don't represent a "new" admission therefore it makes sense to keep them as a separate category.

Therefore the current classification of admissions groups them into 5 categories: PLANNED, UNPLANNED, MATERNITY, TRANSFER and UNKNOWN.

## Categorising the records

Each admission has an `AdmissionTypeCode`. Here we list all codes that occur more than 100 times, along with their description, frequency and classification as of 11th December 2020.

### PLANNED

| Code | Description             | Frequency |
| ---- | ----------------------- | --------: |
| PL   | ELECTIVE PLANNED        |    204845 |
| 11   | Elective - Waiting List |    161183 |
| WL   | ELECTIVE WL             |     75933 |
| 13   | Elective - Planned      |     58921 |
| 12   | Elective - Booked       |     37468 |
| BL   | ELECTIVE BOOKED         |     36475 |
| OP   | DIRECT OUTPAT CLINIC    |      1474 |

### UNPLANNED

| Code          | Description                                                    | Frequency |
| ------------- | -------------------------------------------------------------- | --------: |
| AE            | AE.DEPT.OF PROVIDER                                            |    315265 |
| 21            | Emergency - Local A&E                                          |    252606 |
| 22            | Emergency - GP                                                 |     26028 |
| 23            | Emergency - Bed Bureau                                         |     25329 |
| EM            | EMERGENCY OTHER                                                |     11103 |
| 28            | Emergency - Other (inc other provider A&E)                     |      7102 |
| 2D            | Emergency - Other                                              |      6466 |
| 24            | Emergency - Clinic                                             |      6078 |
| AI            | ACUTE TO INTMED CARE                                           |      2754 |
| BB            | EMERGENCY BED BUREAU                                           |      1028 |
| DO            | EMERGENCY DOMICILE                                             |       995 |
| 2A            | A+E Dept of other provider where Patient has not been admitted |       342 |
| A+E Admission | A+E Admission                                                  |       266 |
| Emerg GP      | Emergency GP Patient                                           |       170 |

### MATERNITY

| Code  | Description                        | Frequency | Comment        |
| ----- | ---------------------------------- | --------: | -------------- |
| 31    | Maternity ante-partum              |     78648 |                |
| BH    | BABY BORN IN HOSP                  |     67736 |                |
| AN    | MATERNITY ANTENATAL                |     36778 |                |
| 82    | Birth in this Health Care Provider |     11062 |                |
| PN    | MATERNITY POST NATAL               |      3024 |                |
| B     | NULL                               |      2494 | See note below |
| 32    | Maternity post-partum              |      2166 |                |
| BHOSP | Birth in this Health Care Provider |      1954 |                |

### TRANSFER

| Code      | Description                        | Frequency |
| --------- | ---------------------------------- | --------: |
| 81        | Transfer from other hosp (not A&E) |      3401 |
| TR        | PLAN TRANS TO TRUST                |      3164 |
| ET        | EM TRAN (OTHER PROV)               |      1652 |
| HospTran  | Transfer from other NHS Hospital   |      1074 |
| T         | TRANSFER                           |       541 |
| CentTrans | Transfer from CEN Site             |       118 |

### UNKNOWN

| Code             | Description                                        | Frequency |
| ---------------- | -------------------------------------------------- | --------: |
| I                | NULL                                               |     45379 |
| GP               | GP OR LOCUM GP                                     |     30651 |
| D                | NULL                                               |     11805 |
| Endoscopy        | Endoscopy                                          |      1537 |
| 18               | CHILDRENS ONLY                                     |      1053 |
| Venesection      | X36.2 Venesection                                  |       830 |
| Colonoscopy      | H22.9 Colonoscopy                                  |       591 |
| Medical          | Medical                                            |       486 |
| NSP              | Not Specified                                      |       455 |
| Blood test       | X36.9 Blood test                                   |       317 |
| Flex sigmoidosco | H25.9 Flexible sigmoidoscopy FOS                   |       270 |
| Infliximab       | X92.1 Infliximab                                   |       244 |
| IPPlannedAd      | IP Planned Admission                               |       205 |
| Blood transfusio | X33.9 Blood transfusion                            |       201 |
| S.I. joint inj   | W90.3 S.I. joint injections                        |       191 |
| Daycase          | Daycase                                            |       190 |
| Extraction Multi | F10.4 Extraction of Multi Teeth                    |       174 |
| Chemotherapy     | X35.2 Chemotherapy                                 |       133 |
| IC               | INTERMEDIATE CARE                                  |       118 |
| Total knee rep c | W40.1 Primary total prosthetic replacement of knee |       111 |
| Total rep hip ce | W37.1 Primary total prosthetic replacement of hip  |       111 |

## Other classification

Some of the above codes are not specific enough without further searching. This explains how the codes have been categorised.

### Code: B

The code "B" occurs 2494 times.

If we explore the `WardDescription` and `SpecialtyCode`, we see that these are all maternity related.

```sql
SELECT WardDescription, SpecialtyCode, COUNT(*) AS Frequency FROM [RLS]. [vw_Acute_Inpatients]
WHERE EventType='Admission' AND AdmissionTypeCode = 'B'
GROUP BY WardDescription, SpecialtyCode
HAVING COUNT(*) > 20 ORDER BY COUNT(*) DESC;
```

| WardDescription     | SpecialtyCode | Frequency |
| ------------------- | ------------- | --------: |
| Delivery Suite Cots | PAED          |      2006 |
| Birth Centre Cots   | PAED          |       291 |
| M2 Cots             | PAED          |        57 |
| Home Address        | MW            |        37 |
| Delivery Suite Cots | MW            |        28 |
| Home Address        | PAED          |        25 |
| Neonatal Unit       | PAED          |        23 |
