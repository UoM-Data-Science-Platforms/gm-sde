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

To recreate these tables first execute this:

```sql
IF OBJECT_ID('tempdb..#AdmissionTypeCounts') IS NOT NULL DROP TABLE #AdmissionTypeCounts;
SELECT AdmissionTypeCode, AdmissionTypeDescription, count(*) as tot INTO #AdmissionTypeCounts
FROM [RLS].[vw_Acute_Inpatients]
where EventType ='Admission'
and AdmissionTypeCode is not null
group by AdmissionTypeCode, AdmissionTypeDescription
having count(*) > 100;
```

Then execute the sql in each section to get each table.

### PLANNED

```sql
SELECT a.AdmissionTypeCode, MAX(a.AdmissionTypeDescription) as [Description], MAX(a.tot) as [Count] FROM #AdmissionTypeCounts a
INNER JOIN (
	SELECT AdmissionTypeCode, MAX(tot) as maxCount
	FROM #AdmissionTypeCounts
	GROUP BY AdmissionTypeCode
) b ON b.AdmissionTypeCode = a.AdmissionTypeCode AND a.tot = b.maxCount
WHERE a.AdmissionTypeCode IN ('PL','11','WL','13','12','BL','D','Endoscopy','OP','Venesection','Colonoscopy','Flex sigmoidosco','Infliximab','IPPlannedAd','S.I. joint inj','Daycase','Extraction Multi','Chemotherapy','Total knee rep c','Total rep hip ce')
GROUP BY a.AdmissionTypeCode
ORDER BY MAX(a.tot) DESC
```

| Code             | Description                                        | Frequency | Comment     |
| ---------------- | -------------------------------------------------- | --------: | ----------- |
| PL               | ELECTIVE PLANNED                                   |    204845 |             |
| 11               | Elective - Waiting List                            |    161183 |             |
| WL               | ELECTIVE WL                                        |     75933 |             |
| 13               | Elective - Planned                                 |     58921 |             |
| 12               | Elective - Booked                                  |     37468 |             |
| BL               | ELECTIVE BOOKED                                    |     36475 |             |
| D                | NULL                                               |     11805 | see note #3 |
| Endoscopy        | Endoscopy                                          |      1537 | see note #5 |
| OP               | DIRECT OUTPAT CLINIC                               |      1474 |             |
| Venesection      | X36.2 Venesection                                  |       830 | see note #6 |
| Colonoscopy      | H22.9 Colonoscopy                                  |       591 | see note #6 |
| Flex sigmoidosco | H25.9 Flexible sigmoidoscopy FOS                   |       270 | see note #6 |
| Infliximab       | X92.1 Infliximab                                   |       244 | see note #6 |
| IPPlannedAd      | IP Planned Admission                               |       205 |             |
| S.I. joint inj   | W90.3 S.I. joint injections                        |       191 | see note #6 |
| Daycase          | Daycase                                            |       190 |             |
| Extraction Multi | F10.4 Extraction of Multi Teeth                    |       174 | see note #6 |
| Chemotherapy     | X35.2 Chemotherapy                                 |       133 | see note #6 |
| Total knee rep c | W40.1 Primary total prosthetic replacement of knee |       111 | see note #6 |
| Total rep hip ce | W37.1 Primary total prosthetic replacement of hip  |       111 | see note #6 |

### UNPLANNED

```sql
SELECT a.AdmissionTypeCode, MAX(a.AdmissionTypeDescription) as [Description], MAX(a.tot) as [Count] FROM #AdmissionTypeCounts a
INNER JOIN (
	SELECT AdmissionTypeCode, MAX(tot) as maxCount
	FROM #AdmissionTypeCounts
	GROUP BY AdmissionTypeCode
) b ON b.AdmissionTypeCode = a.AdmissionTypeCode AND a.tot = b.maxCount
WHERE a.AdmissionTypeCode IN ('AE','21','I','GP','22','23','EM','28','2D','24','AI','BB','DO','2A','A+E Admission','Emerg GP')
GROUP BY a.AdmissionTypeCode
ORDER BY MAX(a.tot) DESC
```

| Code          | Description                                                    | Frequency | Comment     |
| ------------- | -------------------------------------------------------------- | --------: | ----------- |
| AE            | AE.DEPT.OF PROVIDER                                            |    315265 |             |
| 21            | Emergency - Local A&E                                          |    252606 |             |
| I             | NULL                                                           |     45379 | see note #4 |
| GP            | GP OR LOCUM GP                                                 |     30651 | see note #1 |
| 22            | Emergency - GP                                                 |     26028 |             |
| 23            | Emergency - Bed Bureau                                         |     25329 |             |
| EM            | EMERGENCY OTHER                                                |     11103 |             |
| 28            | Emergency - Other (inc other provider A&E)                     |      7102 |             |
| 2D            | Emergency - Other                                              |      6466 |             |
| 24            | Emergency - Clinic                                             |      6078 |             |
| AI            | ACUTE TO INTMED CARE                                           |      2754 |             |
| BB            | EMERGENCY BED BUREAU                                           |      1028 |             |
| DO            | EMERGENCY DOMICILE                                             |       995 |             |
| 2A            | A+E Dept of other provider where Patient has not been admitted |       342 |             |
| A+E Admission | A+E Admission                                                  |       266 |             |
| Emerg GP      | Emergency GP Patient                                           |       170 |             |

### MATERNITY

```sql
SELECT a.AdmissionTypeCode, MAX(a.AdmissionTypeDescription) as [Description], MAX(a.tot) as [Count] FROM #AdmissionTypeCounts a
INNER JOIN (
	SELECT AdmissionTypeCode, MAX(tot) as maxCount
	FROM #AdmissionTypeCounts
	GROUP BY AdmissionTypeCode
) b ON b.AdmissionTypeCode = a.AdmissionTypeCode AND a.tot = b.maxCount
WHERE a.AdmissionTypeCode IN ('31','BH','AN','82','PN','B','32','BHOSP')
GROUP BY a.AdmissionTypeCode
ORDER BY MAX(a.tot) DESC
```

| Code  | Description                        | Frequency | Comment     |
| ----- | ---------------------------------- | --------: | ----------- |
| 31    | Maternity ante-partum              |     78648 |             |
| BH    | BABY BORN IN HOSP                  |     67736 |             |
| AN    | MATERNITY ANTENATAL                |     36778 |             |
| 82    | Birth in this Health Care Provider |     11062 |             |
| PN    | MATERNITY POST NATAL               |      3024 |             |
| B     | NULL                               |      2494 | See note #2 |
| 32    | Maternity post-partum              |      2166 |             |
| BHOSP | Birth in this Health Care Provider |      1954 |             |

### TRANSFER

```sql
SELECT a.AdmissionTypeCode, MAX(a.AdmissionTypeDescription) as [Description], MAX(a.tot) as [Count] FROM #AdmissionTypeCounts a
INNER JOIN (
	SELECT AdmissionTypeCode, MAX(tot) as maxCount
	FROM #AdmissionTypeCounts
	GROUP BY AdmissionTypeCode
) b ON b.AdmissionTypeCode = a.AdmissionTypeCode AND a.tot = b.maxCount
WHERE a.AdmissionTypeCode IN ('81','TR','ET','HospTran','T','CentTrans')
GROUP BY a.AdmissionTypeCode
ORDER BY MAX(a.tot) DESC
```

| Code      | Description                        | Frequency |
| --------- | ---------------------------------- | --------: |
| 81        | Transfer from other hosp (not A&E) |      3401 |
| TR        | PLAN TRANS TO TRUST                |      3164 |
| ET        | EM TRAN (OTHER PROV)               |      1652 |
| HospTran  | Transfer from other NHS Hospital   |      1074 |
| T         | TRANSFER                           |       541 |
| CentTrans | Transfer from CEN Site             |       118 |

### UNKNOWN

```sql
SELECT a.AdmissionTypeCode, MAX(a.AdmissionTypeDescription) as [Description], MAX(a.tot) as [Count] FROM #AdmissionTypeCounts a
INNER JOIN (
	SELECT AdmissionTypeCode, MAX(tot) as maxCount
	FROM #AdmissionTypeCounts
	GROUP BY AdmissionTypeCode
) b ON b.AdmissionTypeCode = a.AdmissionTypeCode AND a.tot = b.maxCount
WHERE a.AdmissionTypeCode NOT IN ('PL','11','WL','13','12','BL','D','Endoscopy','OP','Venesection','Colonoscopy','Flex sigmoidosco','Infliximab','IPPlannedAd','S.I. joint inj','Daycase','Extraction Multi','Chemotherapy','Total knee rep c','Total rep hip ce','AE','21','I','GP','22','23','EM','28','2D','24','AI','BB','DO','2A','A+E Admission','Emerg GP','31','BH','AN','82','PN','B','32','BHOSP','81','TR','ET','HospTran','T','CentTrans')
GROUP BY a.AdmissionTypeCode
ORDER BY MAX(a.tot) DESC
```

| Code             | Description             | Frequency |
| ---------------- | ----------------------- | --------: |
| 18               | CHILDRENS ONLY          |      1053 |
| Medical          | Medical                 |       486 |
| NSP              | Not Specified           |       455 |
| Blood test       | X36.9 Blood test        |       317 |
| Blood transfusio | X33.9 Blood transfusion |       201 |
| IC               | INTERMEDIATE CARE       |       118 |

## Other classification

Some of the above codes are not specific enough without further searching. This explains how the codes have been categorised.

### #1 Code: GP

The code "GP" occurs 30651 times. We classify it as `UNPLANNED` based on the following.

It is assumed that any hospital visit triggered by a GP is likely to be unplanned. If we explore the `ReasonForAdmissionCode` this supports this assumptions as all the descriptions suggest the patient visited a GP and was then directed to a hospital.

```sql
SELECT
	REPLACE(ReasonForAdmissionCode, '? ', '?') AS ReasonForAdmissionCode,
	COUNT(*) AS Frequency
FROM [RLS].[vw_Acute_Inpatients]
WHERE EventType='Admission'
AND AdmissionTypeCode = 'GP'
GROUP BY REPLACE(ReasonForAdmissionCode, '? ', '?')
ORDER BY COUNT(*) DESC;
```

| ReasonForAdmissionCode | Frequency |
| ---------------------- | --------: |
| NULL                   |      8551 |
| ?DVT                   |      2486 |
| UNWELL                 |      2250 |
| ?PE                    |       715 |
| CHEST PAIN             |       613 |
| SOB                    |       560 |
| ABDO PAIN              |       521 |
| JAUNDICE               |       291 |
| HEADACHE               |       287 |
| RASH                   |       287 |
| VOMITING               |       279 |
| COUGH                  |       217 |
| LOW HB                 |       209 |
| HEADACHES              |       182 |
| FEVER                  |       176 |
| PYREXIA                |       136 |

### #2 Code: B

The code "B" occurs 2494 times. We classify it as `MATERNITY` based on the following.

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

### #3 Code: D

The code "D" occurs 11805 times. We classify it as `PLANNED` based on the following.

If we explore the `WardDescription` and `SpecialtyCode`, we see that these all appear to be planned admission.

```sql
SELECT WardDescription, SpecialtyCode, COUNT(*) AS Frequency
FROM [RLS].[vw_Acute_Inpatients]
WHERE EventType='Admission'
AND AdmissionTypeCode = 'D'
GROUP BY WardDescription, SpecialtyCode
ORDER BY COUNT(*) DESC;
```

| WardDescription                         | SpecialtyCode | Frequency |
| --------------------------------------- | ------------- | --------: |
| Endoscopy Suite                         | SURG          |      1799 |
| The Eye Centre                          | OPTH          |      1535 |
| Laurel Suite                            | HAEM          |       967 |
| Endoscopy Suite                         | GMED          |       692 |
| Medical Day Case Unit                   | GMED          |       644 |
| Department Of Medicine For Older People | GER           |       485 |
| Department Of Medicine For Older People | RHEU          |       392 |
| Maple Suite                             | TO            |       385 |
| Alexandra Hospital Ward                 | SURG          |       379 |
| Alexandra Hospital Ward                 | UROL          |       295 |
| Ward D5                                 | OSUR          |       264 |
| Maple Suite                             | UROL          |       230 |
| Ward D5                                 | UROL          |       217 |
| Ward D5                                 | TO            |       214 |
| Cardiac Catheterisation Suite           | CARD          |       200 |
| Jasmine Ward                            | GYN           |       178 |

### #4 Code: I

The code "I" occurs 45379 times. We classify it as `UNPLANNED` based on the following.

If we explore the `WardDescription` and `SpecialtyCode`, we see that these all appear to be unplanned admission.

```sql
SELECT WardDescription, SpecialtyCode, COUNT(*) AS Frequency
FROM [RLS].[vw_Acute_Inpatients]
WHERE EventType='Admission'
AND AdmissionTypeCode = 'I'
GROUP BY WardDescription, SpecialtyCode
ORDER BY COUNT(*) DESC;
```

| WardDescription               | SpecialtyCode | Frequency |
| ----------------------------- | ------------- | --------: |
| Acute Medical Unit            | GMED          |     15901 |
| Ward D4                       | GMED          |      4183 |
| Ambulatory Care Unit          | GMED          |      2371 |
| Ambulatory Care Unit          | SURG          |      2140 |
| Assessment Ward (Paediatrics) | PAED          |      2109 |
| Delivery Suite                | OBST          |      1806 |
| Jasmine Ward                  | GYN           |      1587 |
| Ward D1                       | SURG          |      1204 |
| Ambulatory Care Unit          | TO            |       999 |
| Ambulatory Care Unit          | UROL          |       914 |
| Jasmine Assessment Unit       | GYN           |       805 |
| Ward A10                      | GER           |       681 |
| THW                           | PAED          |       659 |
| Ward A10                      | GMED          |       496 |
| Ward D1                       | UROL          |       478 |
| Ward D2                       | TO            |       426 |

### #5 Code: Endoscopy

The code "Endoscopy" occurs 1537 times. We classify it as `PLANNED` based on the following.

If we explore the `SpecialtyDescription` we see that most are day cases and therefore planned.

```sql
SELECT SpecialtyDescription, count(*) AS Frequency
FROM [RLS].[vw_Acute_Inpatients]
WHERE EventType='Admission'
AND AdmissionTypeCode = 'Endoscopy'
GROUP BY SpecialtyDescription
ORDER BY count(*) DESC;
```

| SpecialtyDescription | Frequency |
| -------------------- | --------: |
| ENDOSCOPY DAY CASE   |      1213 |
| UNCLASSIFIED         |       324 |

If we further explore the `UNCLASSIFIED` cases by examining the `ReasonForAdmissionDescription` we see that they are also all planned.

```sql
SELECT ReasonForAdmissionDescription, COUNT(*) AS Frequency FROM [RLS].[vw_Acute_Inpatients]
WHERE EventType='Admission'
AND AdmissionTypeCode = 'Endoscopy'
AND SpecialtyDescription = 'UNCLASSIFIED'
GROUP BY ReasonForAdmissionDescription
ORDER BY COUNT(*) DESC;
```

| ReasonForAdmissionDescription | Frequency |
| ----------------------------- | --------: |
| Elective booked               |       320 |
| Elective Planned              |         2 |
| Elective Waiting List         |         2 |

### #6 Other - planned

The codes `Colonoscopy`, `Venesection`, `Flex sigmoidosco`, `Infliximab`, `S.I. joint inj`, `Extraction Multi`, `Total knee rep c`, `Total rep hip ce`, `Chemotherapy` occur a total of 2655 times. We classify it as `PLANNED` based on the following.

If we examine the `ReasonForAdmissionDescription` we see that they are also all elective and therefore planned.

```sql
SELECT ReasonForAdmissionDescription,AdmissionTypeCode, COUNT(*) AS Frequency
FROM [RLS].[vw_Acute_Inpatients]
WHERE EventType='Admission'
AND AdmissionTypeCode IN ('Colonoscopy','Venesection','Flex sigmoidosco','Infliximab','S.I. joint inj','Extraction Multi','Total knee rep c','Total rep hip ce','Chemotherapy')
GROUP BY ReasonForAdmissionDescription,AdmissionTypeCode
ORDER BY COUNT(*) DESC;
```

| ReasonForAdmissionDescription | AdmissionTypeCode | Frequency |
| ----------------------------- | ----------------- | --------: |
| Elective Planned              | Venesection       |      1492 |
| Elective booked               | Colonoscopy       |      1111 |
| Elective Planned              | Infliximab        |       458 |
| Elective booked               | Flex sigmoidosco  |       454 |
| Elective Planned              | Chemotherapy      |       224 |
| Elective Waiting List         | S.I. joint inj    |       223 |
| Elective booked Extraction    | Multi             |       174 |
| Elective Waiting List         | Total knee rep c  |       111 |
| Elective Waiting List         | Total rep hip ce  |       111 |
| Elective booked               | S.I. jointinj     |        26 |
| Elective booked               | Venesection       |         5 |
| Elective Planned              | Colonoscopy       |         4 |
| Elective Waiting List         | Flex sigmoidosco  |         2 |

### #7 Other - mixed

The codes `Medical`, `Blood test` and `Blood transfusio` occur a total of 1004 times. We classify it as a mixture of `PLANNED` and `UNPLANNED`, that can be classified by using the `ReasonForAdmissionDescription` based on the following. These codes are almost always `PLANNED`.

```sql
SELECT AdmissionTypeCode, ReasonForAdmissionDescription,COUNT(*) AS Frequency
FROM [RLS].[vw_Acute_Inpatients]
WHERE EventType='Admission'
AND AdmissionTypeCode IN ('Medical','Blood test','Blood transfusio')
GROUP BY ReasonForAdmissionDescription,AdmissionTypeCode
ORDER BY AdmissionTypeCode, COUNT(*) DESC;
```

| AdmissionTypeCode | ReasonForAdmissionDescription | Frequency |
| ----------------- | ----------------------------- | --------- |
| Blood test        | Elective Planned              | 520       |
| Blood test        | Emergency OPD                 | 20        |
| Blood transfusio  | Elective Planned              | 381       |
| Blood transfusio  | Emergency OPD                 | 2         |
| Medical           | Elective Planned              | 850       |
| Medical           | Elective booked               | 33        |
| Medical           | Emergency Other               | 2         |
