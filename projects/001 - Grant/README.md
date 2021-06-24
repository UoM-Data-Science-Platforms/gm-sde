# Reusable queries
  
This project required the following reusable queries:

- COVID-related secondary admissions
- Secondary admissions and length of stay
- Secondary discharges
- Classify secondary admissions
- Likely hospital for each LSOA
- Lower level super output area
- Long-term condition groups per patient
- GET practice and ccg for each patient
- CCG lookup table
- COVID utilisation from primary care data
- Index Multiple Deprivation
- GET No. LTCS per patient
- Long-term conditions
- First prescriptions from GP data

Further details for each query can be found below.

## COVID-related secondary admissions
To classify every admission to secondary care based on whether it is a COVID or non-COVID related. A COVID-related admission is classed as an admission within 4 weeks after, or up to 2 weeks before a positive test.

_Input_
```
Assumes there exists two temp tables as follows:
 #Patients (FK_Patient_Link_ID)
  A distinct list of FK_Patient_Link_IDs for each patient in the cohort
 #Admissions (FK_Patient_Link_ID, AdmissionDate, AcuteProvider)
  A distinct list of the admissions for each patient in the cohort
```

_Output_
```
A temp table as follows:
 #COVIDUtilisationAdmissions (FK_Patient_Link_ID, AdmissionDate, AcuteProvider, CovidHealthcareUtilisation)
 	- FK_Patient_Link_ID - unique patient id
	- AdmissionDate - date of discharge (YYYY-MM-DD)
	- AcuteProvider - Bolton, SRFT, Stockport etc..
  - CovidHealthcareUtilisation - 'TRUE' if admission within 4 weeks after, or up to 14 days before, a positive test
```
_File_: `query-admissions-covid-utilisation.sql`

_Link_: [https://github.com/rw251/.../query-admissions-covid-utilisation.sql](https://github.com/rw251/gm-idcr/tree/master/shared/Reusable%20queries%20for%20data%20extraction/query-admissions-covid-utilisation.sql)

---
## Secondary admissions and length of stay
To obtain a table with every secondary care admission, along with the acute provider, the date of admission, the date of discharge, and the length of stay.

_Input_
```
No pre-requisites
```

_Output_
```
Two temp table as follows:
 #Admissions (FK_Patient_Link_ID, AdmissionDate, AcuteProvider)
 	- FK_Patient_Link_ID - unique patient id
	- AdmissionDate - date of discharge (YYYY-MM-DD)
	- AcuteProvider - Bolton, SRFT, Stockport etc..
  (Limited to one admission per person per hospital per day, because if a patient has 2 admissions
   on the same day to the same hopsital then it's most likely data duplication rather than two short
   hospital stays)
 #LengthOfStay (FK_Patient_Link_ID, AdmissionDate)
 	- FK_Patient_Link_ID - unique patient id
	- AdmissionDate - date of discharge (YYYY-MM-DD)
	- DischargeDate - date of discharge (YYYY-MM-DD)
	- LengthOfStay - Number of days between admission and discharge. 1 = [0,1) days, 2 = [1,2) days, etc.
```
_File_: `query-get-admissions-and-length-of-stay.sql`

_Link_: [https://github.com/rw251/.../query-get-admissions-and-length-of-stay.sql](https://github.com/rw251/gm-idcr/tree/master/shared/Reusable%20queries%20for%20data%20extraction/query-get-admissions-and-length-of-stay.sql)

---
## Secondary discharges
To obtain a table with every secondary care discharge, along with the acute provider, and the date of discharge.

_Input_
```
No pre-requisites
```

_Output_
```
A temp table as follows:
 #Discharges (FK_Patient_Link_ID, DischargeDate, AcuteProvider)
 	- FK_Patient_Link_ID - unique patient id
	- DischargeDate - date of discharge (YYYY-MM-DD)
	- AcuteProvider - Bolton, SRFT, Stockport etc..
  (Limited to one discharge per person per hospital per day, because if a patient has 2 discharges
   on the same day to the same hopsital then it's most likely data duplication rather than two short
   hospital stays)
```
_File_: `query-get-discharges.sql`

_Link_: [https://github.com/rw251/.../query-get-discharges.sql](https://github.com/rw251/gm-idcr/tree/master/shared/Reusable%20queries%20for%20data%20extraction/query-get-discharges.sql)

---
## Classify secondary admissions
To categorise admissions to secondary care into 5 categories: Maternity, Unplanned, Planned, Transfer and Unknown.

_Assumptions_

- We assume patients can only have one admission per day. This is probably not true, but where we see multiple admissions it is more likely to be data duplication, or internal admissions, than an admission, discharge and another admission in the same day.
- Where patients have multiple admissions we choose the "highest" category for admission with the categories ranked as follows: Maternity > Unplanned > Planned > Transfer > Unknown
- We have used the following classifications based on the AdmissionTypeCode: PLANNED: PL (ELECTIVE PLANNED), 11 (Elective - Waiting List), WL (ELECTIVE WL), 13 (Elective - Planned), 12 (Elective - Booked), BL (ELECTIVE BOOKED), D (NULL), Endoscopy (Endoscopy), OP (DIRECT OUTPAT CLINIC), Venesection (X36.2 Venesection), Colonoscopy (H22.9 Colonoscopy), Medical (Medical) UNPLANNED: AE (AE.DEPT.OF PROVIDER), 21 (Emergency - Local A&E), I (NULL), GP (GP OR LOCUM GP), 22 (Emergency - GP), 23 (Emergency - Bed Bureau), 28 (Emergency - Other (inc other provider A&E)), 2D (Emergency - Other), 24 (Emergency - Clinic), EM (EMERGENCY OTHER), AI (ACUTE TO INTMED CARE), BB (EMERGENCY BED BUREAU), DO (EMERGENCY DOMICILE), 2A (A+E Department of another provider where the Patient has not been admitted), A+E (Admission	 A+E Admission), Emerg (GP	Emergency GP Patient) MATERNITY: 31 (Maternity ante-partum), BH (BABY BORN IN HOSP), AN (MATERNITY ANTENATAL), 82 (Birth in this Health Care Provider), PN (MATERNITY POST NATAL), B (NULL), 32 (Maternity post-partum), BHOSP (Birth in this Health Care Provider) TRANSFER: 81 (Transfer from other hosp (not A&E)), TR (PLAN TRANS TO TRUST), ET (EM TRAN (OTHER PROV)), HospTran (Transfer from other NHS Hospital), T (TRANSFER), CentTrans (Transfer from CEN Site) OTHER:

_Input_
```
No pre-requisites
```

_Output_
```
A temp table as follows:
 #AdmissionTypes (FK_Patient_Link_ID, AdmissionDate, AcuteProvider, AdmissionType)
 	- FK_Patient_Link_ID - unique patient id
	- AdmissionDate - date of admission (YYYY-MM-DD)
	- AcuteProvider - Bolton, SRFT, Stockport etc..
	- AdmissionType - One of: Maternity/Unplanned/Planned/Transfer/Unknown
```
_File_: `query-classify-secondary-admissions.sql`

_Link_: [https://github.com/rw251/.../query-classify-secondary-admissions.sql](https://github.com/rw251/gm-idcr/tree/master/shared/Reusable%20queries%20for%20data%20extraction/query-classify-secondary-admissions.sql)

---
## Likely hospital for each LSOA
For each LSOA to get the hospital that most residents would visit.

_Assumptions_

- We count the number of hospital admissions per LSOA
- If there is a single hospital with the most admissions then we assign that as the most likely hospital
- If there are 2 or more that tie for the most admissions then we randomly assign one of the tied hospitals

_Input_
```
No pre-requisites
```

_Output_
```
A temp table as follows:
 #LikelyLSOAHospital (LSOA, LikelyLSOAHospital)
	- LSOA - nationally recognised LSOA identifier
 	- LikelyLSOAHospital - name of most likely hospital for this LSOA
```
_File_: `query-patient-lsoa-likely-hospital.sql`

_Link_: [https://github.com/rw251/.../query-patient-lsoa-likely-hospital.sql](https://github.com/rw251/gm-idcr/tree/master/shared/Reusable%20queries%20for%20data%20extraction/query-patient-lsoa-likely-hospital.sql)

---
## Lower level super output area
To get the LSOA for each patient.

_Assumptions_

- Patient data is obtained from multiple sources. Where patients have multiple LSOAs we determine the LSOA as follows:
- If the patients has an LSOA in their primary care data feed we use that as most likely to be up to date
- If every LSOA for a paitent is the same, then we use that
- If there is a single most recently updated LSOA in the database then we use that
- Otherwise the patient's LSOA is considered unknown

_Input_
```
Assumes there exists a temp table as follows:
 #Patients (FK_Patient_Link_ID)
  A distinct list of FK_Patient_Link_IDs for each patient in the cohort
```

_Output_
```
A temp table as follows:
 #PatientLSOA (FK_Patient_Link_ID, LSOA)
 	- FK_Patient_Link_ID - unique patient id
	- LSOA - nationally recognised LSOA identifier
```
_File_: `query-patient-lsoa.sql`

_Link_: [https://github.com/rw251/.../query-patient-lsoa.sql](https://github.com/rw251/gm-idcr/tree/master/shared/Reusable%20queries%20for%20data%20extraction/query-patient-lsoa.sql)

---
## Long-term condition groups per patient
To provide the long-term condition group or groups for each patient. Examples of long term condition groups would be: Cardiovascular, Endocrine, Respiratory

_Input_
```
Assumes there exists a temp table as follows:
 #PatientsWithLTCs (FK_Patient_Link_ID, LTC)
 Therefore this is run after query-patient-ltcs.sql
```

_Output_
```
A temp table with a row for each patient and ltc group combo
 #LTCGroups (FK_Patient_Link_ID, LTCGroup)
```
_File_: `query-patient-ltcs-group.sql`

_Link_: [https://github.com/rw251/.../query-patient-ltcs-group.sql](https://github.com/rw251/gm-idcr/tree/master/shared/Reusable%20queries%20for%20data%20extraction/query-patient-ltcs-group.sql)

---
## GET practice and ccg for each patient
For each patient to get the practice id that they are registered to, and the CCG name that the practice belongs to.

_Input_
```
Assumes there exists a temp table as follows:
 #Patients (FK_Patient_Link_ID)
  A distinct list of FK_Patient_Link_IDs for each patient in the cohort
```

_Output_
```
Two temp tables as follows:
 #PatientPractice (FK_Patient_Link_ID, GPPracticeCode)
 	- FK_Patient_Link_ID - unique patient id
	- GPPracticeCode - the nationally recognised practice id for the patient
 #PatientPracticeAndCCG (FK_Patient_Link_ID, GPPracticeCode, CCG)
 	- FK_Patient_Link_ID - unique patient id
	- GPPracticeCode - the nationally recognised practice id for the patient
  - CCG - the name of the patient's CCG
```
_File_: `query-patient-practice-and-ccg.sql`

_Link_: [https://github.com/rw251/.../query-patient-practice-and-ccg.sql](https://github.com/rw251/gm-idcr/tree/master/shared/Reusable%20queries%20for%20data%20extraction/query-patient-practice-and-ccg.sql)

---
## CCG lookup table
To provide lookup table for CCG names. The GMCR provides the CCG id (e.g. '00T', '01G') but not the CCG name. This table can be used in other queries when the output is required to be a ccg name rather than an id.

_Input_
```
No pre-requisites
```

_Output_
```
A temp table as follows:
 #CCGLookup (CcgId, CcgName)
 	- CcgId - Nationally recognised ccg id
	- CcgName - Bolton, Stockport etc..
```
_File_: `query-ccg-lookup.sql`

_Link_: [https://github.com/rw251/.../query-ccg-lookup.sql](https://github.com/rw251/gm-idcr/tree/master/shared/Reusable%20queries%20for%20data%20extraction/query-ccg-lookup.sql)

---
## COVID utilisation from primary care data
Classifies a list of events as COVID or non-COVID. An event is classified as "COVID" if the date of the event is within 4 weeks after, or up to 14 days before, a positive COVID test.

_Input_
```
Assumes there exists two temp tables as follows:
 #Patients (FK_Patient_Link_ID)
  A distinct list of FK_Patient_Link_IDs for each patient in the cohort
 #PatientDates (FK_Patient_Link_ID, EventDate)
 	- FK_Patient_Link_ID - unique patient id
	- EventDate - date of the event to classify as COVID/non-COVID
  A distinct list of the dates of the event for each patient in the cohort
```

_Output_
```
A temp table as follows:
 #COVIDUtilisationPrimaryCare (FK_Patient_Link_ID, AdmissionDate, AcuteProvider, CovidHealthcareUtilisation)
 	- FK_Patient_Link_ID - unique patient id
	- EventDate - date of the event to classify as COVID/non-COVID
  - CovidHealthcareUtilisation - 'TRUE' if event within 4 weeks after, or up to 14 days before, a positive test
```
_File_: `query-primary-care-covid-utilisation.sql`

_Link_: [https://github.com/rw251/.../query-primary-care-covid-utilisation.sql](https://github.com/rw251/gm-idcr/tree/master/shared/Reusable%20queries%20for%20data%20extraction/query-primary-care-covid-utilisation.sql)

---
## Index Multiple Deprivation
To get the 2019 Index of Multiple Deprivation (IMD) decile for each patient.

_Input_
```
Assumes there exists a temp table as follows:
 #Patients (FK_Patient_Link_ID)
  A distinct list of FK_Patient_Link_IDs for each patient in the cohort
```

_Output_
```
A temp table as follows:
 #PatientIMDDecile (FK_Patient_Link_ID, IMD2019Decile1IsMostDeprived10IsLeastDeprived)
 	- FK_Patient_Link_ID - unique patient id
	- IMD2019Decile1IsMostDeprived10IsLeastDeprived - number 1 to 10 inclusive
```
_File_: `query-patient-imd.sql`

_Link_: [https://github.com/rw251/.../query-patient-imd.sql](https://github.com/rw251/gm-idcr/tree/master/shared/Reusable%20queries%20for%20data%20extraction/query-patient-imd.sql)

---
## GET No. LTCS per patient
To get the number of long-term conditions for each patient.

_Input_
```
Assumes there exists a temp table as follows:
 #PatientsWithLTCs (FK_Patient_Link_ID, LTC)
 Therefore this is run after query-patient-ltcs.sql
```

_Output_
```
A temp table with a row for each patient with the number of LTCs they have
 #NumLTCs (FK_Patient_Link_ID, NumberOfLTCs)
```
_File_: `query-patient-ltcs-number-of.sql`

_Link_: [https://github.com/rw251/.../query-patient-ltcs-number-of.sql](https://github.com/rw251/gm-idcr/tree/master/shared/Reusable%20queries%20for%20data%20extraction/query-patient-ltcs-number-of.sql)

---
## Long-term conditions
To get every long-term condition for each patient.

_Input_
```
Assumes there exists a temp table as follows:
 #Patients (FK_Patient_Link_ID)
 A distinct list of FK_Patient_Link_IDs for each patient in the cohort
```

_Output_
```
A temp table with a row for each patient and ltc combo
 #PatientsWithLTCs (FK_Patient_Link_ID, LTC)
```
_File_: `query-patient-ltcs.sql`

_Link_: [https://github.com/rw251/.../query-patient-ltcs.sql](https://github.com/rw251/gm-idcr/tree/master/shared/Reusable%20queries%20for%20data%20extraction/query-patient-ltcs.sql)

---
## First prescriptions from GP data
To obtain, for each patient, the first date for each medication they have ever been prescribed.

_Assumptions_

- The same medication can have multiple clinical codes. GraphNet attempt to standardize the coding across different providers by giving each code an id. Therefore the Readv2 code for a medication and the EMIS code for the same medication will have the same id. -

_Input_
```
No pre-requisites
```

_Output_
```
A temp table as follows:
 #FirstMedications (FK_Patient_Link_ID, FirstMedDate, Code)
 	- FK_Patient_Link_ID - unique patient id
	- FirstMedDate - first date for this medication (YYYY-MM-DD)
	- Code - The medication code as either:
					 "FNNNNNN" where 'NNNNNN' is a FK_Reference_Coding_ID or
					 "SNNNNNN" where 'NNNNNN' is a FK_Reference_SnomedCT_ID
```
_File_: `query-first-prescribing-of-medication.sql`

_Link_: [https://github.com/rw251/.../query-first-prescribing-of-medication.sql](https://github.com/rw251/gm-idcr/tree/master/shared/Reusable%20queries%20for%20data%20extraction/query-first-prescribing-of-medication.sql)
# Clinical code sets

This project required the following clinical code sets:

- bmi v1
- smoking-status v1
- blood-pressure v1
- cholesterol v1
- hba1c v1

Further details for each code set can be found below.

# Body Mass Index (BMI)

Any indication that a BMI has been recorded for a patient. This code set includes codes that indicates a patient's BMI (`22K6. - Body mass index less than 20`), as well as codes that are accompanied by a value (`22K.. - Body Mass Index`).

BMI codes retrieved from [GetSet](https://getset.ga) and metadata available in this directory.

**NB: This code set is intended to indicate whether a BMI has been recorded, NOT what the value was. If you require a patient's BMI then this is not the code set for you.**

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `66.22% - 79.69%` suggests that this code set is perhaps not well defined. However, as EMIS (80% of practices) and TPP (10% of practices) are close, it could simply be down to Vision automatically recording BMIs and therefore increasing the prevalence there.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2021-03-31 | EMIS            | 2604007    | 1724476 (66.22%) |  1724450 (66.22%) |
| 2021-03-31 | TPP             | 210535     |  134857 (64.05%) |   134853 (64.05%) |
| 2021-03-31 | Vision          | 333730     |  265960 (79.69%) |   265960 (79.69%) |

LINK: [https://github.com/rw251/.../patient/bmi/1](https://github.com/rw251/gm-idcr/tree/master/shared/clinical-code-sets/patient/bmi/1)

# Smoking status

Any indication that a smoking status has been recorded for a patient. This code set includes codes that indicates a patient's smoking status (`1378. - Ex-light smoker (1-9/day)`), as well as codes that are accompanied by a value (`137.. - Tobacco consumption`).

Smoking status codes retrieved from [GetSet](https://getset.ga) and metadata available in this directory.

**NB: This code set is intended to indicate whether a smoking status has been recorded, NOT what the value was. If you require a patient's smoking status then this is not the code set for you.**

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `68.17% - 73.64%` suggests that this code set is well defined.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2021-03-31 | EMIS            | 2604007    | 1917797 (73.65%) |  1917707 (73.64%) |
| 2021-03-31 | TPP             | 210535     |  143525 (68.17%) |   143525 (68.17%) |
| 2021-03-31 | Vision          | 333730     |  244403 (73.23%) |   244403 (73.23%) |

LINK: [https://github.com/rw251/.../patient/smoking-status/1](https://github.com/rw251/gm-idcr/tree/master/shared/clinical-code-sets/patient/smoking-status/1)

# Blood pressure

Any indication that a blood pressure has been recorded for a patient. This code set includes codes that indicates a patient's BMI (`2462. - O/E - BP reading low`), as well as codes that are accompanied by a value (`2469. - O/E - Systolic BP reading`).

Blood pressure codes retrieved from [GetSet](https://getset.ga) and metadata available in this directory.

**NB: This code set is intended to indicate whether a blood pressure has been recorded, NOT what the value was. If you require a patient's systolic or diastolic blood pressure then this is not the code set for you.**

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `64.46% - 67.00%` suggests that this code set is likely well defined.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2021-03-31 | EMIS            | 2604007    | 1727895 (66.36%) |  1727819 (66.35%) |
| 2021-03-31 | TPP             | 210535     |  135713 (64.46%) |   135713 (64.46%) |
| 2021-03-31 | Vision          | 333730     |  223597 (67.00%) |   223594 (67.00%) |

LINK: [https://github.com/rw251/.../tests/blood-pressure/1](https://github.com/rw251/gm-idcr/tree/master/shared/clinical-code-sets/tests/blood-pressure/1)

# Cholesterol

Any indication that a cholesterol measurement has been recorded for a patient. This code set includes codes that indicates a patient's cholesterol (`44P3. - Serum cholesterol raised`), as well as codes that are accompanied by a value (`44P.. Serum cholesterol`).

Cholesterol codes retrieved from [GetSet](https://getset.ga) and metadata available in this directory.

**NB: This code set is intended to indicate whether a cholesterol measurement has been recorded, NOT what the value was. If you require a patient's LDL or HDL then this is not the code set for you.**

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `44.49% - 49.56%` suggests that this code set is likely well defined.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2021-03-31 | EMIS            | 2604007    | 1158503 (44.49%) |  1158122 (44.47%) |
| 2021-03-31 | TPP             | 210535     |   98705 (46.88%) |    98683 (46.87%) |
| 2021-03-31 | Vision          | 333730     |  165396 (49.56%) |   165364 (49.55%) |

LINK: [https://github.com/rw251/.../tests/cholesterol/1](https://github.com/rw251/gm-idcr/tree/master/shared/clinical-code-sets/tests/cholesterol/1)

# HbA1c

Any indication that a HbA1c has been recorded for a patient. This code set includes codes that indicates a patient's BMI (`165679005 - Haemoglobin A1c (HbA1c) less than 7%`), as well as codes that are accompanied by a value (`1003671000000109 - Haemoglobin A1c level`).

HbA1c codes retrieved from [GetSet](https://getset.ga) and metadata available in this directory.

**NB: This code set is intended to indicate whether a HbA1c has been recorded, NOT what the value was. If you require a patient's HbA1c then this is not the code set for you.**

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range `44.92% - 50.88%` suggests that this code set is likely well defined.

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2021-03-31 | EMIS            | 2604007    | 1169681 (44.92%) |  1158122 (44.92%) |
| 2021-03-31 | TPP             | 210535     |   98801 (46.93%) |    98683 (46.93%) |
| 2021-03-31 | Vision          | 333730     |  169797 (50.88%) |   165364 (50.88%) |

LINK: [https://github.com/rw251/.../tests/hba1c/1](https://github.com/rw251/gm-idcr/tree/master/shared/clinical-code-sets/tests/hba1c/1)
# Clinical code sets

All code sets required for this analysis are listed here. Individual lists for each concept can also be found by using the links above.

| Clinical concept | Terminology | Code | Description |
| ---------------- | ----------- | ---- | ----------- |
|bmi v1|ctv3|22K..|Body Mass Index|
|bmi v1|ctv3|22K1.|Body Mass Index normal K/M2|
|bmi v1|ctv3|22K2.|Body Mass Index high K/M2|
|bmi v1|ctv3|22K3.|Body Mass Index low K/M2|
|bmi v1|ctv3|22K4.|Body mass index index 25-29 - overweight|
|bmi v1|ctv3|22K5.|Body mass index 30+ - obesity|
|bmi v1|ctv3|X76CO|Quetelet index|
|bmi v1|ctv3|Xa7wG|Observation of body mass index|
|bmi v1|ctv3|Xaa0k|Childhood obesity|
|bmi v1|ctv3|Xaatm|Child BMI centile|
|bmi v1|ctv3|Xabdn|Down's syndrome BMI centile|
|bmi v1|ctv3|XabHx|Obese class I (BMI 30.0-34.9)|
|bmi v1|ctv3|XabHy|Obese class II (BMI 35.0-39.9)|
|bmi v1|ctv3|XabHz|Obese cls III (BMI eq/gr 40.0)|
|bmi v1|ctv3|XabSe|Child BMI < 0.4th centile|
|bmi v1|ctv3|XabSf|Child BMI 0.4th-1.9th centile|
|bmi v1|ctv3|XabSg|Child BMI on 2nd centile|
|bmi v1|ctv3|XabSh|Child BMI 3rd-8th centile|
|bmi v1|ctv3|XabSj|Child BMI on 9th centile|
|bmi v1|ctv3|XabSk|Child BMI 10th-24th centile|
|bmi v1|ctv3|XabSl|Child BMI on 25th centile|
|bmi v1|ctv3|XabSm|Child BMI 26th-49th centile|
|bmi v1|ctv3|XabSn|Child BMI on 50th centile|
|bmi v1|ctv3|XabTe|Child BMI on 75th centile|
|bmi v1|ctv3|XabTf|Child BMI 76th-90th centile|
|bmi v1|ctv3|XabTg|Child BMI on 91st centile|
|bmi v1|ctv3|XabTh|Child BMI 92nd-97th centile|
|bmi v1|ctv3|XabTi|Child BMI on 98th centile|
|bmi v1|ctv3|XabTj|Child BMI 98.1-99.6 centile|
|bmi v1|ctv3|XabTk|Child BMI > 99.6th centile|
|bmi v1|ctv3|XabTZ|Child BMI 51st-74th centile|
|bmi v1|ctv3|XaCDR|Body mass index less than 20|
|bmi v1|ctv3|XaJJH|BMI 40+ - severely obese|
|bmi v1|ctv3|XaJqk|Body mass index 20-24 - normal|
|bmi v1|ctv3|XaVwA|Body mass index centile|
|bmi v1|ctv3|XaZck|Baseline BMI centile|
|bmi v1|ctv3|XaZcl|Baseline body mass index|
|bmi v1|emis|EMISNQBM1|BMI centile|
|bmi v1|readv2|22K..00|Body Mass Index|
|bmi v1|readv2|22KE.00|Obese class III (body mass index equal to or greater than 40.0)|
|bmi v1|readv2|22KD.00|Obese class II (body mass index 35.0 - 39.9)|
|bmi v1|readv2|22KC.00|Obese class I (body mass index 30.0 - 34.9)|
|bmi v1|readv2|22KB.00|Baseline body mass index|
|bmi v1|readv2|22KA.00|Target body mass index|
|bmi v1|readv2|22K9.00|Body mass index centile|
|bmi v1|readv2|22K9K00|Down's syndrome body mass index centile|
|bmi v1|readv2|22K9J00|Child body mass index greater than 99.6th centile|
|bmi v1|readv2|22K9H00|Child body mass index 98.1st-99.6th centile|
|bmi v1|readv2|22K9G00|Child body mass index on 98th centile|
|bmi v1|readv2|22K9F00|Child body mass index 92nd-97th centile|
|bmi v1|readv2|22K9E00|Child body mass index on 91st centile|
|bmi v1|readv2|22K9D00|Child body mass index 76th-90th centile|
|bmi v1|readv2|22K9C00|Child body mass index on 75th centile|
|bmi v1|readv2|22K9B00|Child body mass index 51st-74th centile|
|bmi v1|readv2|22K9A00|Child body mass index on 50th centile|
|bmi v1|readv2|22K9900|Child body mass index 26th-49th centile|
|bmi v1|readv2|22K9800|Child body mass index on 25th centile|
|bmi v1|readv2|22K9700|Child body mass index 10th-24th centile|
|bmi v1|readv2|22K9600|Child body mass index on 9th centile|
|bmi v1|readv2|22K9500|Child body mass index 3rd-8th centile|
|bmi v1|readv2|22K9400|Child body mass index on 2nd centile|
|bmi v1|readv2|22K9300|Child body mass index 0.4th-1.9th centile|
|bmi v1|readv2|22K9200|Child body mass index less than 0.4th centile|
|bmi v1|readv2|22K9100|Child body mass index centile|
|bmi v1|readv2|22K9000|Baseline body mass index centile|
|bmi v1|readv2|22K8.00|Body mass index 20-24 - normal|
|bmi v1|readv2|22K7.00|Body mass index 40+ - severely obese|
|bmi v1|readv2|22K6.00|Body mass index less than 20|
|bmi v1|readv2|22K5.00|Body mass index 30+ - obesity|
|bmi v1|readv2|22K4.00|Body mass index index 25-29 - overweight|
|bmi v1|readv2|22K3.00|Body Mass Index low K/M2|
|bmi v1|readv2|22K2.00|Body Mass Index high K/M2|
|bmi v1|readv2|22K1.00|Body Mass Index normal K/M2|
|bmi v1|readv2|C3808|Childhood obesity|
|bmi v1|snomed|6497000|Decreased body mass index (finding)|
|bmi v1|snomed|35425004|Normal body mass index (finding)|
|bmi v1|snomed|48499001|Increased body mass index (finding)|
|bmi v1|snomed|162863004|Body mass index 25-29 - overweight|
|bmi v1|snomed|162864005|BMI 30+ - obesity|
|bmi v1|snomed|301331008|Observation of body mass index|
|bmi v1|snomed|310252000|BMI less than 20|
|bmi v1|snomed|408512008|Body mass index 40+ - morbidly obese|
|bmi v1|snomed|412768003|Body mass index 20-24 - normal|
|bmi v1|snomed|427090001|Body mass index less than 16.5|
|bmi v1|snomed|450451007|Childhood overweight BMI greater than 85 percentile|
|bmi v1|snomed|722595002|Overweight in adulthood with BMI of 25 or more but less than 30|
|bmi v1|snomed|920141000000102|Child BMI (body mass index) less than 0.4th centile|
|bmi v1|snomed|920161000000101|Child BMI (body mass index) 0.4th-1.9th centile|
|bmi v1|snomed|920181000000105|Child BMI (body mass index) on 2nd centile|
|bmi v1|snomed|920201000000109|Child BMI (body mass index) 3rd-8th centile|
|bmi v1|snomed|920231000000103|Child BMI (body mass index) on 9th centile|
|bmi v1|snomed|920251000000105|Child BMI (body mass index) 10th-24th centile|
|bmi v1|snomed|920271000000101|Child BMI (body mass index) on 25th centile|
|bmi v1|snomed|920291000000102|Child BMI (body mass index) 26th-49th centile|
|bmi v1|snomed|920311000000101|Child BMI (body mass index) on 50th centile|
|bmi v1|snomed|920841000000108|Child BMI (body mass index) 51st-74th centile|
|bmi v1|snomed|920931000000108|Child BMI (body mass index) on 75th centile|
|bmi v1|snomed|920951000000101|Child BMI (body mass index) 76th-90th centile|
|bmi v1|snomed|920971000000105|Child BMI (body mass index) on 91st centile|
|bmi v1|snomed|920991000000109|Child BMI (body mass index) 92nd-97th centile|
|bmi v1|snomed|921011000000105|Child BMI (body mass index) on 98th centile|
|bmi v1|snomed|921031000000102|Child BMI (body mass index) 98.1st-99.6th centile|
|bmi v1|snomed|921051000000109|Child BMI (body mass index) greater than 99.6th centile|
|bmi v1|snomed|914721000000105|Obese class I (body mass index 30.0 - 34.9)|
|bmi v1|snomed|914731000000107|Obese class II (body mass index 35.0 - 39.9)|
|bmi v1|snomed|914741000000103|Obese class III (body mass index equal to or greater than 40.0)|
|bmi v1|snomed|443371000124107|Body mass index 30.00 to 34.99|
|bmi v1|snomed|443381000124105|Body mass index 35.00 to 39.99|
|bmi v1|snomed|60621009|Quetelet index|
|bmi v1|snomed|846931000000101|Baseline BMI (body mass index)|
|bmi v1|snomed|852451000000103|Maximum body mass index (observable entity)|
|bmi v1|snomed|852461000000100|Minimum body mass index (observable entity)|
|bmi v1|snomed|446974000|Body mass index centile|
|bmi v1|snomed|846911000000109|Baseline BMI (body mass index) centile|
|bmi v1|snomed|896691000000102|Child BMI (body mass index) centile|
|bmi v1|snomed|926011000000101|Down's syndrome BMI (body mass index) centile|
|bmi v1|snomed|722562008|Foetal or neonatal effect or suspected effect of maternal obesity with adult body mass index 30 or greater but less than 40|
|bmi v1|snomed|722563003|Foetal or neonatal effect of maternal obesity with adult body mass index equal to or greater than 40|
|bmi v1|snomed|705131003|Child at risk for overweight body mass index greater than 85 percentile|
|bmi v1|snomed|43991000119102|History of childhood obesity BMI 95-100 percentile|
|bmi v1|snomed|698094009|Calculation of body mass index|
|bmi v1|snomed|444862003|Childhood obesity BMI 95-100 percentile|
|smoking-status v1|ctv3|13p4.|Smoking free weeks|
|smoking-status v1|ctv3|13p7.|Smoking status at 12 weeks|
|smoking-status v1|ctv3|13p3.|Smoking status at 52 weeks|
|smoking-status v1|ctv3|13p2.|Smoking status between 4 and 52 weeks|
|smoking-status v1|ctv3|13p1.|Smoking status at 4 weeks|
|smoking-status v1|ctv3|137..|Tobacco consumption|
|smoking-status v1|ctv3|137..|Smoker - amount smoked|
|smoking-status v1|ctv3|137l.|Ex roll-up cigarette smoker|
|smoking-status v1|ctv3|137j.|Ex-cigarette smoker|
|smoking-status v1|ctv3|137U.|Not a passive smoker|
|smoking-status v1|ctv3|137S.|Ex smoker|
|smoking-status v1|ctv3|137R.|Current smoker|
|smoking-status v1|ctv3|137P.|Cigarette smoker|
|smoking-status v1|ctv3|137P.|Smoker|
|smoking-status v1|ctv3|137O.|Ex cigar smoker|
|smoking-status v1|ctv3|137N.|Ex pipe smoker|
|smoking-status v1|ctv3|137L.|Current non-smoker|
|smoking-status v1|ctv3|137J.|Cigar smoker|
|smoking-status v1|ctv3|137I.|Passive smoker|
|smoking-status v1|ctv3|137H.|Pipe smoker|
|smoking-status v1|ctv3|137F.|Ex-smoker - amount unknown|
|smoking-status v1|ctv3|137B.|Ex-very heavy smoker (40+/day)|
|smoking-status v1|ctv3|137A.|Ex-heavy smoker (20-39/day)|
|smoking-status v1|ctv3|1379.|Ex-moderate smoker (10-19/day)|
|smoking-status v1|ctv3|1378.|Ex-light smoker (1-9/day)|
|smoking-status v1|ctv3|1377.|Ex-trivial smoker (<1/day)|
|smoking-status v1|ctv3|1376.|Very heavy smoker - 40+cigs/d|
|smoking-status v1|ctv3|1375.|Heavy smoker - 20-39 cigs/day|
|smoking-status v1|ctv3|1374.|Moderate smoker - 10-19 cigs/d|
|smoking-status v1|ctv3|1373.|Light smoker - 1-9 cigs/day|
|smoking-status v1|ctv3|1372.|Trivial smoker - < 1 cig/day|
|smoking-status v1|ctv3|1372.|Occasional smoker|
|smoking-status v1|ctv3|137o.|Waterpipe tobacco consumption|
|smoking-status v1|ctv3|137n.|Total time smoked|
|smoking-status v1|ctv3|137m.|Failed attempt to stop smoking|
|smoking-status v1|ctv3|137k.|Refusal to give smoking status|
|smoking-status v1|ctv3|137i.|Ex-tobacco chewer|
|smoking-status v1|ctv3|137h.|Minutes from waking to first tobacco consumption|
|smoking-status v1|ctv3|137g.|Cigarette pack-years|
|smoking-status v1|ctv3|137f.|Reason for restarting smoking|
|smoking-status v1|ctv3|137e.|Smoking restarted|
|smoking-status v1|ctv3|137d.|Not interested in stopping smoking|
|smoking-status v1|ctv3|137c.|Thinking about stopping smoking|
|smoking-status v1|ctv3|137b.|Ready to stop smoking|
|smoking-status v1|ctv3|137a.|Pipe tobacco consumption|
|smoking-status v1|ctv3|137Z.|Tobacco consumption NOS|
|smoking-status v1|ctv3|137Y.|Cigar consumption|
|smoking-status v1|ctv3|137X.|Cigarette consumption|
|smoking-status v1|ctv3|137W.|Chews tobacco|
|smoking-status v1|ctv3|137V.|Smoking reduced|
|smoking-status v1|ctv3|137T.|Date ceased smoking|
|smoking-status v1|ctv3|137Q.|Smoking started|
|smoking-status v1|ctv3|137Q.|Smoking restarted|
|smoking-status v1|ctv3|137M.|Rolls own cigarettes|
|smoking-status v1|ctv3|137K.|Stopped smoking|
|smoking-status v1|ctv3|137K0|Recently stopped smoking|
|smoking-status v1|ctv3|137G.|Trying to give up smoking|
|smoking-status v1|ctv3|137E.|Tobacco consumption unknown|
|smoking-status v1|ctv3|137D.|Admitted tobacco cons untrue ?|
|smoking-status v1|ctv3|137C.|Keeps trying to stop smoking|
|smoking-status v1|ctv3|1371.|Never smoked tobacco|
|smoking-status v1|ctv3|1371.|Non-smoker|
|smoking-status v1|ctv3|13WF.|Family smoking history|
|smoking-status v1|ctv3|13WF4|Passive smoking risk|
|smoking-status v1|ctv3|Ub0oo|Smoking|
|smoking-status v1|ctv3|Ub0oq|Non-smoker|
|smoking-status v1|ctv3|Ub0p1|Time since stopped smoking|
|smoking-status v1|ctv3|Ub0p2|Total time smoked|
|smoking-status v1|ctv3|Ub0p3|Age at starting smoking|
|smoking-status v1|ctv3|Ub0pa|Time since stop chew tobacco|
|smoking-status v1|ctv3|Ub0pb|Total time chewed tobacco|
|smoking-status v1|ctv3|Ub0pc|Age at start chewing tobacco|
|smoking-status v1|ctv3|Ub0pF|Moist tobacco consumption|
|smoking-status v1|ctv3|Ub0pO|Tobacco chewing|
|smoking-status v1|ctv3|Ub0pP|Chewed tobacco consumption|
|smoking-status v1|ctv3|Ub0pQ|Does not chew tobacco|
|smoking-status v1|ctv3|Ub0pR|Never chewed tobacco|
|smoking-status v1|ctv3|Ub0pS|Ex-tobacco chewer|
|smoking-status v1|ctv3|Ub0pT|Chews tobacco|
|smoking-status v1|ctv3|Ub0pU|Chews plug tobacco|
|smoking-status v1|ctv3|Ub0pV|Chews twist tobacco|
|smoking-status v1|ctv3|Ub0pW|Chews loose leaf tobacco|
|smoking-status v1|ctv3|Ub0pX|Chews fine cut tobacco|
|smoking-status v1|ctv3|Ub0pY|Chews products contain tobacco|
|smoking-status v1|ctv3|Ub0pZ|Frequency of chewing tobacco|
|smoking-status v1|ctv3|Ub1na|Ex-smoker|
|smoking-status v1|ctv3|Ub1tI|Cigarette consumption|
|smoking-status v1|ctv3|Ub1tJ|Cigar consumption|
|smoking-status v1|ctv3|Ub1tK|Pipe tobacco consumption|
|smoking-status v1|ctv3|Ub1tR|Occasional cigarette smoker|
|smoking-status v1|ctv3|Ub1tS|Light cigarette smoker|
|smoking-status v1|ctv3|Ub1tT|Moderate cigarette smoker|
|smoking-status v1|ctv3|Ub1tU|Heavy cigarette smoker|
|smoking-status v1|ctv3|Ub1tV|Very heavy cigarette smoker|
|smoking-status v1|ctv3|Ub1tW|Chain smoker|
|smoking-status v1|ctv3|Xa1bv|Ex-cigarette smoker|
|smoking-status v1|ctv3|Xaa26|Num prev attempt stop smoking|
|smoking-status v1|ctv3|XaBSp|Smoking restarted|
|smoking-status v1|ctv3|XagO3|Occasional smoker|
|smoking-status v1|ctv3|XaIIu|Smoking reduced|
|smoking-status v1|ctv3|XaIkW|Thinking about stop smoking|
|smoking-status v1|ctv3|XaIkX|Ready to stop smoking|
|smoking-status v1|ctv3|XaIkY|Not interested stop smoking|
|smoking-status v1|ctv3|XaIQk|Smoking status at 4 weeks|
|smoking-status v1|ctv3|XaIQl|Smoking status 4 - 52 wks|
|smoking-status v1|ctv3|XaIQm|Smoking status at 52 weeks|
|smoking-status v1|ctv3|XaIr7|Smoking free weeks|
|smoking-status v1|ctv3|XaItg|Reason for restarting smoking|
|smoking-status v1|ctv3|XaIuQ|Cigarette pack-years|
|smoking-status v1|ctv3|XaJX2|Min from wake to 1st tobac con|
|smoking-status v1|ctv3|XaKlS|[V]PH of tobacco abuse|
|smoking-status v1|ctv3|XaLQh|Wants to stop smoking|
|smoking-status v1|ctv3|XaQ8V|Ex roll-up cigarette smoker|
|smoking-status v1|ctv3|XaQzw|Recently stopped smoking|
|smoking-status v1|ctv3|XaWNE|Failed attempt to stop smoking|
|smoking-status v1|ctv3|XaXP6|Stoppd smoking durin pregnancy|
|smoking-status v1|ctv3|XaXP8|Stoppd smoking befor pregnancy|
|smoking-status v1|ctv3|XaXP9|Smoker befor confirm pregnancy|
|smoking-status v1|ctv3|XaXPD|Smoker in household|
|smoking-status v1|ctv3|XaXPX|Smoking status at 12 weeks|
|smoking-status v1|ctv3|XaZIE|Waterpipe tobacco consumption|
|smoking-status v1|ctv3|XE0og|Amount+type of tobacco smoked|
|smoking-status v1|ctv3|XE0oh|Never smoked|
|smoking-status v1|ctv3|XE0oi|Occ cigarette smok, <1cig/day|
|smoking-status v1|ctv3|XE0oj|Ex-triv cigaret smoker, <1/day|
|smoking-status v1|ctv3|XE0ok|Ex-light cigaret smok, 1-9/day|
|smoking-status v1|ctv3|XE0ol|Ex-mod cigaret smok, 10-19/day|
|smoking-status v1|ctv3|XE0om|Ex-heav cigaret smok,20-39/day|
|smoking-status v1|ctv3|XE0on|Ex-very hv cigaret smk,40+/day|
|smoking-status v1|ctv3|XE0oo|Tobacco smok consumpt unknown|
|smoking-status v1|ctv3|XE0op|Ex-cigaret smoker amnt unknown|
|smoking-status v1|ctv3|XE0oq|Cigarette smoker|
|smoking-status v1|ctv3|XE0or|Smoking started|
|smoking-status v1|ctv3|XE0sl|Non-smoker|
|smoking-status v1|ctv3|XE2tc|Family smoking history|
|smoking-status v1|ctv3||undefined|
|smoking-status v1|readv2|13p4.00|Smoking free weeks|
|smoking-status v1|readv2|13p7.00|Smoking status at 12 weeks|
|smoking-status v1|readv2|13p3.00|Smoking status at 52 weeks|
|smoking-status v1|readv2|13p2.00|Smoking status between 4 and 52 weeks|
|smoking-status v1|readv2|13p1.00|Smoking status at 4 weeks|
|smoking-status v1|readv2|137..00|Tobacco consumption|
|smoking-status v1|readv2|137..11|Smoker - amount smoked|
|smoking-status v1|readv2|137l.00|Ex roll-up cigarette smoker|
|smoking-status v1|readv2|137j.00|Ex-cigarette smoker|
|smoking-status v1|readv2|137U.00|Not a passive smoker|
|smoking-status v1|readv2|137S.00|Ex smoker|
|smoking-status v1|readv2|137R.00|Current smoker|
|smoking-status v1|readv2|137P.00|Cigarette smoker|
|smoking-status v1|readv2|137P.11|Smoker|
|smoking-status v1|readv2|137O.00|Ex cigar smoker|
|smoking-status v1|readv2|137N.00|Ex pipe smoker|
|smoking-status v1|readv2|137L.00|Current non-smoker|
|smoking-status v1|readv2|137J.00|Cigar smoker|
|smoking-status v1|readv2|137I.00|Passive smoker|
|smoking-status v1|readv2|137H.00|Pipe smoker|
|smoking-status v1|readv2|137F.00|Ex-smoker - amount unknown|
|smoking-status v1|readv2|137B.00|Ex-very heavy smoker (40+/day)|
|smoking-status v1|readv2|137A.00|Ex-heavy smoker (20-39/day)|
|smoking-status v1|readv2|1379.00|Ex-moderate smoker (10-19/day)|
|smoking-status v1|readv2|1378.00|Ex-light smoker (1-9/day)|
|smoking-status v1|readv2|1377.00|Ex-trivial smoker (<1/day)|
|smoking-status v1|readv2|1376.00|Very heavy smoker - 40+cigs/d|
|smoking-status v1|readv2|1375.00|Heavy smoker - 20-39 cigs/day|
|smoking-status v1|readv2|1374.00|Moderate smoker - 10-19 cigs/d|
|smoking-status v1|readv2|1373.00|Light smoker - 1-9 cigs/day|
|smoking-status v1|readv2|1372.00|Trivial smoker - < 1 cig/day|
|smoking-status v1|readv2|1372.11|Occasional smoker|
|smoking-status v1|readv2|137o.00|Waterpipe tobacco consumption|
|smoking-status v1|readv2|137n.00|Total time smoked|
|smoking-status v1|readv2|137m.00|Failed attempt to stop smoking|
|smoking-status v1|readv2|137k.00|Refusal to give smoking status|
|smoking-status v1|readv2|137i.00|Ex-tobacco chewer|
|smoking-status v1|readv2|137h.00|Minutes from waking to first tobacco consumption|
|smoking-status v1|readv2|137g.00|Cigarette pack-years|
|smoking-status v1|readv2|137f.00|Reason for restarting smoking|
|smoking-status v1|readv2|137e.00|Smoking restarted|
|smoking-status v1|readv2|137d.00|Not interested in stopping smoking|
|smoking-status v1|readv2|137c.00|Thinking about stopping smoking|
|smoking-status v1|readv2|137b.00|Ready to stop smoking|
|smoking-status v1|readv2|137a.00|Pipe tobacco consumption|
|smoking-status v1|readv2|137Z.00|Tobacco consumption NOS|
|smoking-status v1|readv2|137Y.00|Cigar consumption|
|smoking-status v1|readv2|137X.00|Cigarette consumption|
|smoking-status v1|readv2|137W.00|Chews tobacco|
|smoking-status v1|readv2|137V.00|Smoking reduced|
|smoking-status v1|readv2|137T.00|Date ceased smoking|
|smoking-status v1|readv2|137Q.00|Smoking started|
|smoking-status v1|readv2|137Q.11|Smoking restarted|
|smoking-status v1|readv2|137M.00|Rolls own cigarettes|
|smoking-status v1|readv2|137K.00|Stopped smoking|
|smoking-status v1|readv2|137K000|Recently stopped smoking|
|smoking-status v1|readv2|137G.00|Trying to give up smoking|
|smoking-status v1|readv2|137E.00|Tobacco consumption unknown|
|smoking-status v1|readv2|137D.00|Admitted tobacco cons untrue ?|
|smoking-status v1|readv2|137C.00|Keeps trying to stop smoking|
|smoking-status v1|readv2|1371.00|Never smoked tobacco|
|smoking-status v1|readv2|1371.11|Non-smoker|
|smoking-status v1|readv2|13WF.00|Family smoking history|
|smoking-status v1|readv2|13WF400|Passive smoking risk|
|smoking-status v1|snomed|8392000|Non-smoker (finding)|
|smoking-status v1|snomed|8517006|Ex-smoker (finding)|
|smoking-status v1|snomed|43381005|Exposed to second hand tobacco smoke|
|smoking-status v1|snomed|53896009|Tolerant ex-smoker (finding)|
|smoking-status v1|snomed|56578002|Moderate smoker (20 or less per day) (finding)|
|smoking-status v1|snomed|56771006|Heavy smoker (over 20 per day) (finding)|
|smoking-status v1|snomed|59978006|Cigar smoker (finding)|
|smoking-status v1|snomed|65568007|Cigarette smoker (finding)|
|smoking-status v1|snomed|77176002|Smoker (finding)|
|smoking-status v1|snomed|81703003|Chews tobacco (finding)|
|smoking-status v1|snomed|82302008|Pipe smoker (finding)|
|smoking-status v1|snomed|87739003|Tolerant non-smoker (finding)|
|smoking-status v1|snomed|105539002|Non-smoker for personal reasons (finding)|
|smoking-status v1|snomed|105540000|Non-smoker for religious reasons (finding)|
|smoking-status v1|snomed|105541001|Non-smoker for medical reasons (finding)|
|smoking-status v1|snomed|134406006|Smoking reduced (finding)|
|smoking-status v1|snomed|160603005|Light cigarette smoker (1-9 cigs/day) (finding)|
|smoking-status v1|snomed|160604004|Moderate cigarette smoker (10-19 cigs/day) (finding)|
|smoking-status v1|snomed|160605003|Heavy cigarette smoker (20-39 cigs/day) (finding)|
|smoking-status v1|snomed|160606002|Very heavy cigarette smoker (40+ cigs/day) (finding)|
|smoking-status v1|snomed|160612007|Keeps trying to stop smoking (finding)|
|smoking-status v1|snomed|160613002|Admitted tobacco consumption possibly untrue|
|smoking-status v1|snomed|160614008|Tobacco consumption unknown (finding)|
|smoking-status v1|snomed|160616005|Trying to give up smoking (finding)|
|smoking-status v1|snomed|160617001|Stopped smoking (finding)|
|smoking-status v1|snomed|160618006|Current non-smoker (finding)|
|smoking-status v1|snomed|160619003|Rolls own cigarettes (finding)|
|smoking-status v1|snomed|160620009|Ex-pipe smoker (finding)|
|smoking-status v1|snomed|160621008|Ex-cigar smoker (finding)|
|smoking-status v1|snomed|228509002|Tobacco chewing|
|smoking-status v1|snomed|228511006|Does not chew tobacco (finding)|
|smoking-status v1|snomed|228512004|Never chewed tobacco (finding)|
|smoking-status v1|snomed|228513009|Ex-tobacco chewer (finding)|
|smoking-status v1|snomed|228514003|Chews plug tobacco (finding)|
|smoking-status v1|snomed|228515002|Chews twist tobacco (finding)|
|smoking-status v1|snomed|228516001|Chews loose leaf tobacco (finding)|
|smoking-status v1|snomed|228517005|Chews fine cut tobacco (finding)|
|smoking-status v1|snomed|228518000|Chews products containing tobacco (finding)|
|smoking-status v1|snomed|230059006|Occasional cigarette smoker (finding)|
|smoking-status v1|snomed|230060001|Light cigarette smoker (finding)|
|smoking-status v1|snomed|230062009|Moderate cigarette smoker (finding)|
|smoking-status v1|snomed|230063004|Heavy cigarette smoker (finding)|
|smoking-status v1|snomed|230064005|Very heavy cigarette smoker (finding)|
|smoking-status v1|snomed|230065006|Chain smoker (finding)|
|smoking-status v1|snomed|266919005|Never smoked tobacco (finding)|
|smoking-status v1|snomed|266920004|Trivial cigarette smoker (less than one cigarette/day) (finding)|
|smoking-status v1|snomed|266921000|Ex-trivial cigarette smoker (<1/day) (finding)|
|smoking-status v1|snomed|266922007|Ex-light cigarette smoker (1-9/day) (finding)|
|smoking-status v1|snomed|266923002|Ex-moderate cigarette smoker (10-19/day) (finding)|
|smoking-status v1|snomed|266924008|Ex-heavy cigarette smoker (20-39/day) (finding)|
|smoking-status v1|snomed|266925009|Ex-very heavy cigarette smoker (40+/day) (finding)|
|smoking-status v1|snomed|266927001|Tobacco smoking consumption unknown (finding)|
|smoking-status v1|snomed|266928006|Ex-cigarette smoker amount unknown (finding)|
|smoking-status v1|snomed|266929003|Smoking started|
|smoking-status v1|snomed|281018007|Ex-cigarette smoker (finding)|
|smoking-status v1|snomed|308438006|Smoking restarted|
|smoking-status v1|snomed|360890004|Intolerant ex-smoker (finding)|
|smoking-status v1|snomed|360900008|Aggressive ex-smoker (finding)|
|smoking-status v1|snomed|360918006|Aggressive non-smoker (finding)|
|smoking-status v1|snomed|360929005|Intolerant non-smoker (finding)|
|smoking-status v1|snomed|365981007|Finding of tobacco smoking behavior|
|smoking-status v1|snomed|365982000|Finding of tobacco smoking consumption|
|smoking-status v1|snomed|394871007|Thinking about stopping smoking (finding)|
|smoking-status v1|snomed|394872000|Ready to stop smoking|
|smoking-status v1|snomed|394873005|Not interested in stopping smoking|
|smoking-status v1|snomed|405746006|Current non smoker but past smoking history unknown|
|smoking-status v1|snomed|446172000|Failed attempt to stop smoking|
|smoking-status v1|snomed|449345000|Smoked before confirmation of pregnancy|
|smoking-status v1|snomed|449368009|Stopped smoking during pregnancy|
|smoking-status v1|snomed|449369001|Stopped smoking before pregnancy|
|smoking-status v1|snomed|449868002|Smokes tobacco daily (finding)|
|smoking-status v1|snomed|735128000|Ex-smoker for less than 1 year|
|smoking-status v1|snomed|1092031000000108|Ex-smoker amount unknown (finding)|
|smoking-status v1|snomed|1092041000000104|Ex-very heavy smoker (40+/day) (finding)|
|smoking-status v1|snomed|1092071000000105|Ex-heavy smoker (20-39/day) (finding)|
|smoking-status v1|snomed|1092091000000109|Ex-moderate smoker (10-19/day) (finding)|
|smoking-status v1|snomed|1092111000000104|Ex-light smoker (1-9/day) (finding)|
|smoking-status v1|snomed|1092131000000107|Ex-trivial smoker (<1/day) (finding)|
|smoking-status v1|snomed|48031000119106|Ex-smoker for more than 1 year|
|smoking-status v1|snomed|203191000000107|Wants to stop smoking|
|smoking-status v1|snomed|492191000000103|Ex roll-up cigarette smoker|
|smoking-status v1|snomed|428041000124106|Occasional tobacco smoker (finding)|
|smoking-status v1|snomed|517211000000106|Recently stopped smoking|
|smoking-status v1|snomed|160625004|Date ceased smoking (observable entity)|
|smoking-status v1|snomed|228486009|Time since stopped smoking (observable entity)|
|smoking-status v1|snomed|228487000|Total time smoked (observable entity)|
|smoking-status v1|snomed|228488005|Age at starting smoking (observable entity)|
|smoking-status v1|snomed|228500003|Moist tobacco consumption (observable entity)|
|smoking-status v1|snomed|228510007|Chewed tobacco consumption (observable entity)|
|smoking-status v1|snomed|228519008|Frequency of chewing tobacco (observable entity)|
|smoking-status v1|snomed|228520002|Time since stopped chewing tobacco (observable entity)|
|smoking-status v1|snomed|228521003|Total time chewed tobacco (observable entity)|
|smoking-status v1|snomed|228522005|Age at starting chewing tobacco (observable entity)|
|smoking-status v1|snomed|230056004|Cigarette consumption (observable entity)|
|smoking-status v1|snomed|230057008|Cigar consumption (observable entity)|
|smoking-status v1|snomed|230058003|Pipe tobacco consumption (observable entity)|
|smoking-status v1|snomed|266918002|Amount and type of tobacco smoked|
|smoking-status v1|snomed|363907005|Details of tobacco chewing (observable entity)|
|smoking-status v1|snomed|390902009|Smoking status at 4 weeks|
|smoking-status v1|snomed|390903004|Smoking status between 4 and 52 weeks|
|smoking-status v1|snomed|390904005|Smoking status at 52 weeks|
|smoking-status v1|snomed|395177003|Smoking free weeks|
|smoking-status v1|snomed|401159003|Reason for restarting smoking|
|smoking-status v1|snomed|401201003|Cigarette pack-years|
|smoking-status v1|snomed|413173009|Minutes from waking to first tobacco consumption|
|smoking-status v1|snomed|735112005|Date ceased using moist tobacco|
|smoking-status v1|snomed|864091000000103|Number of previous attempts to stop smoking|
|smoking-status v1|snomed|836001000000109|Waterpipe tobacco consumption|
|smoking-status v1|snomed|1092481000000104|Number of calculated smoking pack years (observable entity)|
|smoking-status v1|snomed|766931000000106|Smoking status at 12 weeks|
|smoking-status v1|snomed|26663004|Cigar smoking tobacco (substance)|
|smoking-status v1|snomed|66562002|Cigarette smoking tobacco (substance)|
|smoking-status v1|snomed|81911001|Chewing tobacco (substance)|
|smoking-status v1|snomed|84498003|Pipe smoking tobacco (substance)|
|smoking-status v1|snomed|94151000119101|Smoker in home environment|
|smoking-status v1|snomed|1104241000000108|Ex-smoker in household (situation)|
|smoking-status v1|snomed|443877004|Family history of smoking|
|smoking-status v1|snomed|698289004|Hookah pipe smoker (finding)|
|smoking-status v1|snomed|221000119102|Never smoked any substance (finding)|
|smoking-status v1|snomed|16077171000119107|Tobacco dependence caused by chewing tobacco|
|blood-pressure v1|ctv3|9ODC.|BP ABNORMAL - deleted|
|blood-pressure v1|ctv3|Ua1fM|Normal blood pressure|
|blood-pressure v1|ctv3|X76LJ|Raised jugular venous pressure|
|blood-pressure v1|ctv3|X76LK|JVP raised on inspiration|
|blood-pressure v1|ctv3|X773t|ABP - Arterial blood pressure|
|blood-pressure v1|ctv3|X779b|ABP - Arterial blood pressure|
|blood-pressure v1|ctv3|X779f|Post-vasodilatatn arter press|
|blood-pressure v1|ctv3|X779g|Segmental pressure|
|blood-pressure v1|ctv3|X779h|Labile blood pressure|
|blood-pressure v1|ctv3|X779Q|Non-invasive systol art press|
|blood-pressure v1|ctv3|X779R|Invasive systol arterial press|
|blood-pressure v1|ctv3|X779S|DAP-Diastolic arterial pressur|
|blood-pressure v1|ctv3|X779T|DAP-Diastolic arterial pressur|
|blood-pressure v1|ctv3|X779U|MAP - Mean arterial pressure|
|blood-pressure v1|ctv3|X779V|MAP - Mean arterial pressure|
|blood-pressure v1|ctv3|X779W|Invasive mean arterial press|
|blood-pressure v1|ctv3|X779X|Cuff blood pressure|
|blood-pressure v1|ctv3|X77UU|ABI - Arterial pressure index|
|blood-pressure v1|ctv3|X77UV|Upstroke time arter pressure|
|blood-pressure v1|ctv3|Xa42K|[D]BP raised,hyperten not diag|
|blood-pressure v1|ctv3|Xa42M|[D]BP abn, not diagnostic NOS|
|blood-pressure v1|ctv3|Xabhx|Baseline blood pressure|
|blood-pressure v1|ctv3|Xac5K|Baseline diastolic BP|
|blood-pressure v1|ctv3|Xac5L|Baseline systolic BP|
|blood-pressure v1|ctv3|Xaedn|Non-invasive central BP|
|blood-pressure v1|ctv3|Xaedo|Non-invasive central systlc BP|
|blood-pressure v1|ctv3|Xaedp|Non-invasive centrl diastlc BP|
|blood-pressure v1|ctv3|XaF4a|Ave day diastol blood pressure|
|blood-pressure v1|ctv3|XaF4b|Ave 24h diastol blood pressure|
|blood-pressure v1|ctv3|XaF4c|24 hour blood pressure|
|blood-pressure v1|ctv3|XaF4d|24h systolic blood pressure|
|blood-pressure v1|ctv3|XaF4D|Min systolic blood pressure|
|blood-pressure v1|ctv3|XaF4e|24h diastolic blood pressure|
|blood-pressure v1|ctv3|XaF4E|Max systolic blood pressure|
|blood-pressure v1|ctv3|XaF4F|Ave systolic blood pressure|
|blood-pressure v1|ctv3|XaF4G|Min day systol blood pressure|
|blood-pressure v1|ctv3|XaF4H|Min night syst blood pressure|
|blood-pressure v1|ctv3|XaF4I|Max night syst blood pressure|
|blood-pressure v1|ctv3|XaF4J|Max day syst blood pressure|
|blood-pressure v1|ctv3|XaF4K|Ave night syst blood pressure|
|blood-pressure v1|ctv3|XaF4L|Ave day systol blood pressure|
|blood-pressure v1|ctv3|XaF4M|Min 24h systol blood pressure|
|blood-pressure v1|ctv3|XaF4N|Max 24h systol blood pressure|
|blood-pressure v1|ctv3|XaF4O|Ave 24h systol blood pressure|
|blood-pressure v1|ctv3|XaF4Q|Min diastolic blood pressure|
|blood-pressure v1|ctv3|XaF4R|Max diastolic blood pressure|
|blood-pressure v1|ctv3|XaF4S|Ave diastolic blood pressure|
|blood-pressure v1|ctv3|XaF4T|Min day diastol blood pressure|
|blood-pressure v1|ctv3|XaF4U|Min night diast blood pressure|
|blood-pressure v1|ctv3|XaF4V|Min 24h diastol blood pressure|
|blood-pressure v1|ctv3|XaF4W|Max night diast blood pressure|
|blood-pressure v1|ctv3|XaF4X|Max day diast blood pressure|
|blood-pressure v1|ctv3|XaF4Y|Max 24h diastol blood pressure|
|blood-pressure v1|ctv3|XaF4Z|Ave night diast blood pressure|
|blood-pressure v1|ctv3|XaFr9|Borderline blood pressure|
|blood-pressure v1|ctv3|XaIwj|Standing systolic BP|
|blood-pressure v1|ctv3|XaIwk|Standing diastolic BP|
|blood-pressure v1|ctv3|XaJ2E|Sitting systolic BP|
|blood-pressure v1|ctv3|XaJ2F|Sitting diastolic BP|
|blood-pressure v1|ctv3|XaJ2G|Lying systolic blood pressure|
|blood-pressure v1|ctv3|XaJ2H|Lying diastolic blood pressure|
|blood-pressure v1|ctv3|XaKFw|Average home diastolic BP|
|blood-pressure v1|ctv3|XaKFx|Average home systolic BP|
|blood-pressure v1|ctv3|XaKjF|Ambulatory systolic BP|
|blood-pressure v1|ctv3|XaKjG|Ambulatory diastolic BP|
|blood-pressure v1|ctv3|XaOQP|Self measured BP reading|
|blood-pressure v1|ctv3|XaXfX|Post exerc sys BP respons norm|
|blood-pressure v1|ctv3|XaXfY|Post exer sys BP respon abnorm|
|blood-pressure v1|ctv3|XaXKa|JVP no abnormality detected|
|blood-pressure v1|ctv3|XaYg8|Diastolic BP centile|
|blood-pressure v1|ctv3|XaYg9|Systolic BP centile|
|blood-pressure v1|ctv3|XaZvo|Unequal blood pressure in arms|
|blood-pressure v1|ctv3|XaZxj|Unusual variability in BP|
|blood-pressure v1|ctv3|XM02T|Blood pressure unrecordable|
|blood-pressure v1|ctv3|XM02V|Elevated blood pressure|
|blood-pressure v1|ctv3|XM02W|Postural drop, blood pressure|
|blood-pressure v1|ctv3|XM02X|SAP - Systol arterial pressure|
|blood-pressure v1|ctv3|XM02Y|DAP-Diastolic arterial pressur|
|blood-pressure v1|ctv3|XM02Z|Stable blood pressure|
|blood-pressure v1|ctv3|XM09K|Raised blood pressure reading|
|blood-pressure v1|ctv3|XM09M|BP reading labile|
|blood-pressure v1|ctv3|XM0zx|BP abnorm,but not diagnost.[D]|
|blood-pressure v1|ctv3|246..|O/E - BP reading|
|blood-pressure v1|ctv3|246..|O/E - blood pressure|
|blood-pressure v1|ctv3|246..|O/E - blood pressure reading|
|blood-pressure v1|ctv3|246o.|Non-invasive central blood pressure|
|blood-pressure v1|ctv3|246o1|Non-invasive central diastolic blood pressure|
|blood-pressure v1|ctv3|246o0|Non-invasive central systolic blood pressure|
|blood-pressure v1|ctv3|246n.|Baseline blood pressure|
|blood-pressure v1|ctv3|246n1|Baseline systolic blood pressure|
|blood-pressure v1|ctv3|246n0|Baseline diastolic blood pressure|
|blood-pressure v1|ctv3|246m.|Average diastolic blood pressure|
|blood-pressure v1|ctv3|246l.|Average systolic blood pressure|
|blood-pressure v1|ctv3|246k.|Unequal blood pressure in arms|
|blood-pressure v1|ctv3|246j.|Systolic blood pressure centile|
|blood-pressure v1|ctv3|246i.|Diastolic blood pressure centile|
|blood-pressure v1|ctv3|246g.|Self measured blood pressure reading|
|blood-pressure v1|ctv3|246f.|Ambulatory diastolic blood pressure|
|blood-pressure v1|ctv3|246e.|Ambulatory systolic blood pressure|
|blood-pressure v1|ctv3|246d.|Average home systolic blood pressure|
|blood-pressure v1|ctv3|246c.|Average home diastolic blood pressure|
|blood-pressure v1|ctv3|246b.|Average night interval systolic blood pressure|
|blood-pressure v1|ctv3|246a.|Average night interval diastolic blood pressure|
|blood-pressure v1|ctv3|246Z.|O/E-blood pressure reading NOS|
|blood-pressure v1|ctv3|246Y.|Average day interval systolic blood pressure|
|blood-pressure v1|ctv3|246X.|Average day interval diastolic blood pressure|
|blood-pressure v1|ctv3|246W.|Average 24 hour systolic blood pressure|
|blood-pressure v1|ctv3|246V.|Average 24 hour diastolic blood pressure|
|blood-pressure v1|ctv3|246T.|Lying diastolic blood pressure|
|blood-pressure v1|ctv3|246S.|Lying systolic blood pressure|
|blood-pressure v1|ctv3|246R.|Sitting diastolic blood pressure|
|blood-pressure v1|ctv3|246Q.|Sitting systolic blood pressure|
|blood-pressure v1|ctv3|246P.|Standing diastolic blood pressure|
|blood-pressure v1|ctv3|246N.|Standing systolic blood pressure|
|blood-pressure v1|ctv3|246L.|Target diastolic blood pressure|
|blood-pressure v1|ctv3|246K.|Target systolic blood pressure|
|blood-pressure v1|ctv3|246F.|O/E - blood pressure decreased|
|blood-pressure v1|ctv3|246E.|Sitting blood pressure reading|
|blood-pressure v1|ctv3|246D.|Standing blood pressure reading|
|blood-pressure v1|ctv3|246C.|Lying blood pressure reading|
|blood-pressure v1|ctv3|246h.|Arterial pulse pressure|
|blood-pressure v1|ctv3|246J.|O/E - BP reading: no postural drop|
|blood-pressure v1|ctv3|246I.|O/E - Arterial pressure index abnormal|
|blood-pressure v1|ctv3|246H.|O/E - Arterial pressure index normal|
|blood-pressure v1|ctv3|246G.|O/E - BP labile|
|blood-pressure v1|ctv3|246B.|O/E - BP stable|
|blood-pressure v1|ctv3|246A.|O/E - Diastolic BP reading|
|blood-pressure v1|ctv3|2469.|O/E - Systolic BP reading|
|blood-pressure v1|ctv3|2468.|O/E - BP reading:postural drop|
|blood-pressure v1|ctv3|2467.|O/E - BP reading very high|
|blood-pressure v1|ctv3|2466.|O/E - BP reading raised|
|blood-pressure v1|ctv3|2465.|O/E - BP borderline raised|
|blood-pressure v1|ctv3|2464.|O/E - BP reading normal|
|blood-pressure v1|ctv3|2463.|O/E - BP borderline low|
|blood-pressure v1|ctv3|2462.|O/E - BP reading low|
|blood-pressure v1|ctv3|2461.|O/E - BP reading very low|
|blood-pressure v1|ctv3|2460.|O/E - BP unrecordable|
|blood-pressure v1|ctv3|662C.|O/E - check high BP|
|blood-pressure v1|ctv3|662B.|O/E - initial high BP|
|blood-pressure v1|ctv3|6623.|Pre-treatment BP reading|
|blood-pressure v1|ctv3|662j.|Blood pressure recorded by patient at home|
|blood-pressure v1|ctv3|662Q.|Borderline blood pressure|
|blood-pressure v1|ctv3|R1y4.|[D]BP reading labile|
|blood-pressure v1|ctv3|R1y3.|[D]Low blood pressure reading|
|blood-pressure v1|ctv3|R1y2.|[D]Raised blood pressure reading|
|blood-pressure v1|ctv3|315B.|Ambulatory blood pressure recording|
|blood-pressure v1|ctv3|ZV70B|[V]Examination of blood pressure|
|blood-pressure v1|readv2|246..11|O/E - BP reading|
|blood-pressure v1|readv2|246..12|O/E - blood pressure|
|blood-pressure v1|readv2|246..00|O/E - blood pressure reading|
|blood-pressure v1|readv2|246o.00|Non-invasive central blood pressure|
|blood-pressure v1|readv2|246o100|Non-invasive central diastolic blood pressure|
|blood-pressure v1|readv2|246o000|Non-invasive central systolic blood pressure|
|blood-pressure v1|readv2|246n.00|Baseline blood pressure|
|blood-pressure v1|readv2|246n100|Baseline systolic blood pressure|
|blood-pressure v1|readv2|246n000|Baseline diastolic blood pressure|
|blood-pressure v1|readv2|246m.00|Average diastolic blood pressure|
|blood-pressure v1|readv2|246l.00|Average systolic blood pressure|
|blood-pressure v1|readv2|246k.00|Unequal blood pressure in arms|
|blood-pressure v1|readv2|246j.00|Systolic blood pressure centile|
|blood-pressure v1|readv2|246i.00|Diastolic blood pressure centile|
|blood-pressure v1|readv2|246g.00|Self measured blood pressure reading|
|blood-pressure v1|readv2|246f.00|Ambulatory diastolic blood pressure|
|blood-pressure v1|readv2|246e.00|Ambulatory systolic blood pressure|
|blood-pressure v1|readv2|246d.00|Average home systolic blood pressure|
|blood-pressure v1|readv2|246c.00|Average home diastolic blood pressure|
|blood-pressure v1|readv2|246b.00|Average night interval systolic blood pressure|
|blood-pressure v1|readv2|246a.00|Average night interval diastolic blood pressure|
|blood-pressure v1|readv2|246Z.00|O/E-blood pressure reading NOS|
|blood-pressure v1|readv2|246Y.00|Average day interval systolic blood pressure|
|blood-pressure v1|readv2|246X.00|Average day interval diastolic blood pressure|
|blood-pressure v1|readv2|246W.00|Average 24 hour systolic blood pressure|
|blood-pressure v1|readv2|246V.00|Average 24 hour diastolic blood pressure|
|blood-pressure v1|readv2|246T.00|Lying diastolic blood pressure|
|blood-pressure v1|readv2|246S.00|Lying systolic blood pressure|
|blood-pressure v1|readv2|246R.00|Sitting diastolic blood pressure|
|blood-pressure v1|readv2|246Q.00|Sitting systolic blood pressure|
|blood-pressure v1|readv2|246P.00|Standing diastolic blood pressure|
|blood-pressure v1|readv2|246N.00|Standing systolic blood pressure|
|blood-pressure v1|readv2|246L.00|Target diastolic blood pressure|
|blood-pressure v1|readv2|246K.00|Target systolic blood pressure|
|blood-pressure v1|readv2|246F.00|O/E - blood pressure decreased|
|blood-pressure v1|readv2|246E.00|Sitting blood pressure reading|
|blood-pressure v1|readv2|246D.00|Standing blood pressure reading|
|blood-pressure v1|readv2|246C.00|Lying blood pressure reading|
|blood-pressure v1|readv2|246h.00|Arterial pulse pressure|
|blood-pressure v1|readv2|246J.00|O/E - BP reading: no postural drop|
|blood-pressure v1|readv2|246I.00|O/E - Arterial pressure index abnormal|
|blood-pressure v1|readv2|246H.00|O/E - Arterial pressure index normal|
|blood-pressure v1|readv2|246G.00|O/E - BP labile|
|blood-pressure v1|readv2|246B.00|O/E - BP stable|
|blood-pressure v1|readv2|246A.00|O/E - Diastolic BP reading|
|blood-pressure v1|readv2|2469.00|O/E - Systolic BP reading|
|blood-pressure v1|readv2|2468.00|O/E - BP reading:postural drop|
|blood-pressure v1|readv2|2467.00|O/E - BP reading very high|
|blood-pressure v1|readv2|2466.00|O/E - BP reading raised|
|blood-pressure v1|readv2|2465.00|O/E - BP borderline raised|
|blood-pressure v1|readv2|2464.00|O/E - BP reading normal|
|blood-pressure v1|readv2|2463.00|O/E - BP borderline low|
|blood-pressure v1|readv2|2462.00|O/E - BP reading low|
|blood-pressure v1|readv2|2461.00|O/E - BP reading very low|
|blood-pressure v1|readv2|2460.00|O/E - BP unrecordable|
|blood-pressure v1|readv2|662C.00|O/E - check high BP|
|blood-pressure v1|readv2|662B.00|O/E - initial high BP|
|blood-pressure v1|readv2|6623.00|Pre-treatment BP reading|
|blood-pressure v1|readv2|662j.00|Blood pressure recorded by patient at home|
|blood-pressure v1|readv2|662Q.00|Borderline blood pressure|
|blood-pressure v1|readv2|R1y4.00|[D]BP reading labile|
|blood-pressure v1|readv2|R1y3.00|[D]Low blood pressure reading|
|blood-pressure v1|readv2|R1y2.00|[D]Raised blood pressure reading|
|blood-pressure v1|readv2|315B.00|Ambulatory blood pressure recording|
|blood-pressure v1|readv2|ZV70B00|[V]Examination of blood pressure|
|blood-pressure v1|snomed|6797001|MBP - Mean blood pressure|
|blood-pressure v1|snomed|72313002|Systolic arterial pressure (observable entity)|
|blood-pressure v1|snomed|75367002|BP - Blood pressure|
|blood-pressure v1|snomed|163033001|Lying blood pressure (observable entity)|
|blood-pressure v1|snomed|163034007|Standing blood pressure (observable entity)|
|blood-pressure v1|snomed|163035008|Sitting blood pressure (observable entity)|
|blood-pressure v1|snomed|174255007|Non-invasive diastolic blood pressure|
|blood-pressure v1|snomed|251070002|Non-invasive systolic blood pressure|
|blood-pressure v1|snomed|251071003|Invasive systolic blood pressure|
|blood-pressure v1|snomed|251073000|Invasive diastolic blood pressure|
|blood-pressure v1|snomed|251074006|Non-invasive mean blood pressure|
|blood-pressure v1|snomed|251075007|MAP - Mean arterial pressure|
|blood-pressure v1|snomed|251076008|NIBP - Non-invasive blood pressure|
|blood-pressure v1|snomed|251078009|Post-vasodilatation arterial pressure (observable entity)|
|blood-pressure v1|snomed|251079001|Segmental pressure (blood pressure) (observable entity)|
|blood-pressure v1|snomed|271649006|SAP - Systolic arterial pressure|
|blood-pressure v1|snomed|271650006|Diastolic arterial pressure|
|blood-pressure v1|snomed|314438006|Minimum systolic blood pressure (observable entity)|
|blood-pressure v1|snomed|314439003|Maximum systolic blood pressure (observable entity)|
|blood-pressure v1|snomed|314440001|Average systolic blood pressure (observable entity)|
|blood-pressure v1|snomed|314441002|Minimum day interval systolic blood pressure (observable entity)|
|blood-pressure v1|snomed|314442009|Minimum night interval systolic blood pressure (observable entity)|
|blood-pressure v1|snomed|314443004|Maximum night interval systolic blood pressure (observable entity)|
|blood-pressure v1|snomed|314444005|Maximum day interval systolic blood pressure (observable entity)|
|blood-pressure v1|snomed|314445006|Average night interval systolic blood pressure (observable entity)|
|blood-pressure v1|snomed|314446007|Average day interval systolic blood pressure (observable entity)|
|blood-pressure v1|snomed|314447003|Minimum 24 hour systolic blood pressure (observable entity)|
|blood-pressure v1|snomed|314448008|Maximum 24 hour systolic blood pressure (observable entity)|
|blood-pressure v1|snomed|314449000|Average 24 hour systolic blood pressure (observable entity)|
|blood-pressure v1|snomed|314451001|Minimum diastolic blood pressure (observable entity)|
|blood-pressure v1|snomed|314452008|Maximum diastolic blood pressure (observable entity)|
|blood-pressure v1|snomed|314453003|Average diastolic blood pressure (observable entity)|
|blood-pressure v1|snomed|314454009|Minimum day interval diastolic blood pressure (observable entity)|
|blood-pressure v1|snomed|314455005|Minimum night interval diastolic blood pressure (observable entity)|
|blood-pressure v1|snomed|314456006|Minimum 24 hour diastolic blood pressure (observable entity)|
|blood-pressure v1|snomed|314457002|Maximum night interval diastolic blood pressure (observable entity)|
|blood-pressure v1|snomed|314458007|Maximum day interval diastolic blood pressure (observable entity)|
|blood-pressure v1|snomed|314459004|Maximum 24 hour diastolic blood pressure (observable entity)|
|blood-pressure v1|snomed|314460009|Average night interval diastolic blood pressure (observable entity)|
|blood-pressure v1|snomed|314461008|Average day interval diastolic blood pressure (observable entity)|
|blood-pressure v1|snomed|314462001|Average 24 hour diastolic blood pressure (observable entity)|
|blood-pressure v1|snomed|314463006|24 hour blood pressure (observable entity)|
|blood-pressure v1|snomed|314464000|24 hour systolic blood pressure (observable entity)|
|blood-pressure v1|snomed|314465004|24 hour diastolic blood pressure (observable entity)|
|blood-pressure v1|snomed|364090009|SAP - Systemic arterial pressure|
|blood-pressure v1|snomed|386532001|Invasive arterial pressure|
|blood-pressure v1|snomed|386533006|IBP - Invasive blood pressure|
|blood-pressure v1|snomed|386534000|ABP - Arterial blood pressure|
|blood-pressure v1|snomed|386536003|SBP - Systemic blood pressure|
|blood-pressure v1|snomed|399304008|Systolic blood pressure on admission|
|blood-pressure v1|snomed|400974009|Standing systolic blood pressure|
|blood-pressure v1|snomed|400975005|Standing diastolic blood pressure|
|blood-pressure v1|snomed|407554009|Sitting systolic blood pressure|
|blood-pressure v1|snomed|407555005|Sitting diastolic blood pressure|
|blood-pressure v1|snomed|407556006|Lying systolic blood pressure|
|blood-pressure v1|snomed|407557002|Lying diastolic blood pressure|
|blood-pressure v1|snomed|413605002|Average home diastolic blood pressure|
|blood-pressure v1|snomed|413606001|Average home systolic blood pressure|
|blood-pressure v1|snomed|445731001|Dorsalis pedis arterial pressure|
|blood-pressure v1|snomed|445886006|Posterior tibial arterial pressure|
|blood-pressure v1|snomed|446226005|Diastolic blood pressure on admission|
|blood-pressure v1|snomed|716579001|Baseline systolic blood pressure|
|blood-pressure v1|snomed|716632005|Baseline diastolic blood pressure|
|blood-pressure v1|snomed|723232008|Average blood pressure|
|blood-pressure v1|snomed|723235005|Maximum blood pressure|
|blood-pressure v1|snomed|723236006|Minimum blood pressure|
|blood-pressure v1|snomed|723237002|Non-invasive blood pressure|
|blood-pressure v1|snomed|852291000000105|Maximum mean blood pressure (observable entity)|
|blood-pressure v1|snomed|852301000000109|Minimum mean blood pressure (observable entity)|
|blood-pressure v1|snomed|335661000000109|Self measured blood pressure reading|
|blood-pressure v1|snomed|928021000000108|Baseline blood pressure|
|blood-pressure v1|snomed|1036531000000108|Non-invasive central blood pressure|
|blood-pressure v1|snomed|198081000000101|Ambulatory systolic blood pressure|
|blood-pressure v1|snomed|814101000000107|Systolic blood pressure centile|
|blood-pressure v1|snomed|198091000000104|Ambulatory diastolic blood pressure|
|blood-pressure v1|snomed|814081000000101|Diastolic blood pressure centile|
|blood-pressure v1|snomed|1091811000000102|Diastolic arterial pressure (observable entity)|
|blood-pressure v1|snomed|1036551000000101|Non-invasive central systolic blood pressure|
|blood-pressure v1|snomed|1036571000000105|Non-invasive central diastolic blood pressure|
|blood-pressure v1|snomed|1087991000000109|Level of reduction in systolic blood pressure on standing (observable entity)|
|blood-pressure v1|snomed|369001|Normal jugular venous pressure (finding)|
|blood-pressure v1|snomed|2004005|Normotensive|
|blood-pressure v1|snomed|12377007|Increased central venous pressure (finding)|
|blood-pressure v1|snomed|12763006|Finding of decreased blood pressure|
|blood-pressure v1|snomed|12929001|Normal systolic arterial pressure (finding)|
|blood-pressure v1|snomed|18050000|Increased systolic arterial pressure (finding)|
|blood-pressure v1|snomed|18352002|Abnormal systolic arterial pressure (finding)|
|blood-pressure v1|snomed|22447003|Raised jugular venous pressure (finding)|
|blood-pressure v1|snomed|23154005|Increased diastolic arterial pressure (finding)|
|blood-pressure v1|snomed|23520002|Decreased venous pressure (finding)|
|blood-pressure v1|snomed|24184005|Blood pressure elevation|
|blood-pressure v1|snomed|38398005|Decreased central venous pressure (finding)|
|blood-pressure v1|snomed|38936003|Abnormal blood pressure (finding)|
|blood-pressure v1|snomed|42689008|Decreased diastolic arterial pressure (finding)|
|blood-pressure v1|snomed|42788006|Decreased jugular venous pressure (finding)|
|blood-pressure v1|snomed|49844009|Abnormal diastolic arterial pressure (finding)|
|blood-pressure v1|snomed|53813002|Normal diastolic arterial pressure (finding)|
|blood-pressure v1|snomed|62436006|Abnormal jugular venous pressure (finding)|
|blood-pressure v1|snomed|69791001|Increased venous pressure (finding)|
|blood-pressure v1|snomed|70679005|Abnormal central venous pressure (finding)|
|blood-pressure v1|snomed|81010002|Decreased systolic arterial pressure (finding)|
|blood-pressure v1|snomed|91297005|Normal central venous pressure (finding)|
|blood-pressure v1|snomed|102584008|Unequal blood pressure in arms (finding)|
|blood-pressure v1|snomed|111971002|Abnormal venous pressure (finding)|
|blood-pressure v1|snomed|129899009|Blood pressure alteration (finding)|
|blood-pressure v1|snomed|163020007|On examination - blood pressure reading|
|blood-pressure v1|snomed|163021006|On examination - BP unrecordable|
|blood-pressure v1|snomed|163025002|On examination - BP reading normal|
|blood-pressure v1|snomed|163026001|On examination - BP borderline raised|
|blood-pressure v1|snomed|163027005|On examination - BP reading raised|
|blood-pressure v1|snomed|163028000|On examination - BP reading very high|
|blood-pressure v1|snomed|163029008|On examination - BP reading:postural drop|
|blood-pressure v1|snomed|163030003|On examination - Systolic blood pressure reading|
|blood-pressure v1|snomed|163031004|On examination - Diastolic BP reading|
|blood-pressure v1|snomed|163032006|On examination - BP stable|
|blood-pressure v1|snomed|163036009|On examination - blood pressure decreased|
|blood-pressure v1|snomed|163037000|On examination - BP labile|
|blood-pressure v1|snomed|170581003|On examination - initial high BP|
|blood-pressure v1|snomed|170582005|On examination - check high BP|
|blood-pressure v1|snomed|248729008|Jugular venous pressure raised on inspiration|
|blood-pressure v1|snomed|251080003|Labile blood pressure (finding)|
|blood-pressure v1|snomed|271645000|Blood pressure unrecordable (finding)|
|blood-pressure v1|snomed|271648003|Postural drop in blood pressure (finding)|
|blood-pressure v1|snomed|271651005|Stable blood pressure (finding)|
|blood-pressure v1|snomed|271871003|Blood pressure reading labile|
|blood-pressure v1|snomed|314956000|Borderline blood pressure (finding)|
|blood-pressure v1|snomed|366161004|Finding of venous pressure|
|blood-pressure v1|snomed|366162006|Finding of central venous pressure|
|blood-pressure v1|snomed|366163001|Finding of jugular venous pressure|
|blood-pressure v1|snomed|392570002|Blood pressure finding|
|blood-pressure v1|snomed|707303003|Post exercise systolic blood pressure response abnormal|
|blood-pressure v1|snomed|707304009|Post exercise systolic blood pressure response normal (finding)|
|blood-pressure v1|snomed|764531000000107|Jugular venous pressure no abnormality detected|
|blood-pressure v1|snomed|862121000000109|Unusual variability in blood pressure|
|blood-pressure v1|snomed|185676007|Blood pressure ABNORMAL - deleted|
|blood-pressure v1|snomed|252071000|ABI - Arterial pressure index|
|blood-pressure v1|snomed|252072007|Upstroke time of arterial pressure (observable entity)|
|blood-pressure v1|snomed|364097007|Feature of pulmonary arterial pressure (observable entity)|
|blood-pressure v1|snomed|417394002|Finding of central venous pressure waveform|
|blood-pressure v1|snomed|427732000|Speed of blood pressure response|
|cholesterol v1|ctv3|X772L|Cholesterol level|
|cholesterol v1|ctv3|X772M|High density lipoprot chol lev|
|cholesterol v1|ctv3|X772N|LDL-Low dens lipoprot chol lev|
|cholesterol v1|ctv3|X773m|Percentage chol as ester|
|cholesterol v1|ctv3|X773W|HDL/LDL ratio|
|cholesterol v1|ctv3|X80J1|HDL - High density lipoprotein|
|cholesterol v1|ctv3|X80Nb|Hi density lipoprot subfrac 2|
|cholesterol v1|ctv3|X80Nc|Hi density lipoprot subfrac 3|
|cholesterol v1|ctv3|X80Ne|LDL - Low density lipoprotein|
|cholesterol v1|ctv3|X80NT|Free cholesterol|
|cholesterol v1|ctv3|X80NU|Cholesterol ester|
|cholesterol v1|ctv3|XabE1|Se non HDL cholesterol level|
|cholesterol v1|ctv3|XabT0|Estim serum non-HDL cholest lv|
|cholesterol v1|ctv3|Xabub|Se HDL chol:triglyceride ratio|
|cholesterol v1|ctv3|XaEil|Hi dens lipoprt/tot chol ratio|
|cholesterol v1|ctv3|XaERR|Cholesterol/HDL ratio|
|cholesterol v1|ctv3|XaEUp|Lipoprotein cholesterol ratio|
|cholesterol v1|ctv3|XaEUq|Serum cholesterol/HDL ratio|
|cholesterol v1|ctv3|XaEUr|Plasma cholesterol/HDL ratio|
|cholesterol v1|ctv3|XaEUs|Serum cholesterol/LDL ratio|
|cholesterol v1|ctv3|XaEUt|Plasma cholesterol/LDL ratio|
|cholesterol v1|ctv3|XaEUu|Serum cholesterol/VLDL ratio|
|cholesterol v1|ctv3|XaEUv|Plasma cholesterol/VLDL ratio|
|cholesterol v1|ctv3|XaEVQ|Serum LDL/HDL ratio|
|cholesterol v1|ctv3|XaEVr|Plasma HDL cholesterol level|
|cholesterol v1|ctv3|XaEVR|Plasma LDL/HDL ratio|
|cholesterol v1|ctv3|XaEVs|Plasma LDL cholesterol level|
|cholesterol v1|ctv3|XaFs9|Fasting cholesterol level|
|cholesterol v1|ctv3|XaIp4|Calculated LDL cholesterol lev|
|cholesterol v1|ctv3|XaIqd|Pre-treatmnt serum cholest lev|
|cholesterol v1|ctv3|XaIRd|Plasma total cholesterol level|
|cholesterol v1|ctv3|XaIYp|Fluid sample cholesterol level|
|cholesterol v1|ctv3|XaJe9|Serum total cholesterol level|
|cholesterol v1|ctv3|XaLux|Serum fastng total cholesterol|
|cholesterol v1|ctv3|XaN3z|Non HDL cholesterol level|
|cholesterol v1|ctv3|XE28o|HDL : LDL ratio|
|cholesterol v1|ctv3|XE2eD|Serum cholesterol|
|cholesterol v1|ctv3|XE2mn|Ser HDL/non-HDL cholest ratio|
|cholesterol v1|ctv3|XSK14|Total cholesterol measurement|
|cholesterol v1|ctv3|44P..|Serum cholesterol|
|cholesterol v1|ctv3|44PZ.|Serum cholesterol NOS|
|cholesterol v1|ctv3|44PL.|Non HDL cholesterol level|
|cholesterol v1|ctv3|44PL1|Estimated serum non-high density lipoprotein cholesterol level|
|cholesterol v1|ctv3|44PL0|Serum non high density lipoprotein cholesterol level|
|cholesterol v1|ctv3|44PK.|Serum fasting total cholesterol|
|cholesterol v1|ctv3|44PJ.|Serum total cholesterol level|
|cholesterol v1|ctv3|44PI.|Calculated LDL cholesterol level|
|cholesterol v1|ctv3|44PH.|Total cholesterol measurement|
|cholesterol v1|ctv3|44PG.|HDL : total cholesterol ratio|
|cholesterol v1|ctv3|44PF.|Total cholesterol:HDL ratio|
|cholesterol v1|ctv3|44PE.|Serum random LDL cholesterol level|
|cholesterol v1|ctv3|44PD.|Serum fasting LDL cholesterol level|
|cholesterol v1|ctv3|44PC.|Serum random HDL cholesterol level|
|cholesterol v1|ctv3|44PB.|Serum fasting HDL cholesterol level|
|cholesterol v1|ctv3|44P9.|Serum cholesterol studies|
|cholesterol v1|ctv3|44P8.|Serum HDL:non-HDL cholesterol ratio|
|cholesterol v1|ctv3|44P7.|Serum VLDL cholesterol level|
|cholesterol v1|ctv3|44P6.|Serum LDL cholesterol level|
|cholesterol v1|ctv3|44P5.|Serum HDL cholesterol level|
|cholesterol v1|ctv3|44P4.|Serum cholesterol very high|
|cholesterol v1|ctv3|44P3.|Serum cholesterol raised|
|cholesterol v1|ctv3|44P2.|Serum cholesterol borderline|
|cholesterol v1|ctv3|44P1.|Serum cholesterol normal|
|cholesterol v1|ctv3|44PA.|HDL : LDL ratio|
|cholesterol v1|ctv3|44lM.|Plasma LDL/HDL ratio|
|cholesterol v1|ctv3|44lL.|Serum LDL/HDL ratio|
|cholesterol v1|ctv3|44lK.|Plasma cholesterol/VLDL ratio|
|cholesterol v1|ctv3|44lJ.|Serum cholesterol/VLDL ratio|
|cholesterol v1|ctv3|44lI.|Plasma cholesterol/LDL ratio|
|cholesterol v1|ctv3|44lH.|Serum cholesterol/LDL ratio|
|cholesterol v1|ctv3|44lG.|Plasma cholesterol/HDL ratio|
|cholesterol v1|ctv3|44lF.|Serum cholesterol/HDL ratio|
|cholesterol v1|ctv3|44l2.|Cholesterol/HDL ratio|
|cholesterol v1|ctv3|44dB.|Plasma LDL cholesterol level|
|cholesterol v1|ctv3|44dA.|Plasma HDL cholesterol level|
|cholesterol v1|ctv3|44d5.|Plasma fasting LDL cholesterol level|
|cholesterol v1|ctv3|44d4.|Plasma random LDL cholesterol level|
|cholesterol v1|ctv3|44d3.|Plasma fasting HDL cholesterol level|
|cholesterol v1|ctv3|44d2.|Plasma random HDL cholesterol level|
|cholesterol v1|ctv3|44R4.|LDL - electrophoresis|
|cholesterol v1|ctv3|44R4.|Lipoprotein electroph. - LDL|
|cholesterol v1|ctv3|44R3.|HDL - electrophoresis|
|cholesterol v1|ctv3|44R3.|Lipoprotein electroph. - HDL|
|cholesterol v1|ctv3|662a.|Pre-treatment serum cholesterol level|
|cholesterol v1|ctv3|44OE.|Plasma total cholesterol level|
|cholesterol v1|ctv3|44lzY|Serum high density lipoprotein cholesterol:triglyceride ratio|
|cholesterol v1|ctv3|4I3O.|Fluid sample cholesterol level|
|cholesterol v1|readv2|44P..00|Serum cholesterol|
|cholesterol v1|readv2|44PZ.00|Serum cholesterol NOS|
|cholesterol v1|readv2|44PL.00|Non HDL cholesterol level|
|cholesterol v1|readv2|44PL100|Estimated serum non-high density lipoprotein cholesterol level|
|cholesterol v1|readv2|44PL000|Serum non high density lipoprotein cholesterol level|
|cholesterol v1|readv2|44PK.00|Serum fasting total cholesterol|
|cholesterol v1|readv2|44PJ.00|Serum total cholesterol level|
|cholesterol v1|readv2|44PI.00|Calculated LDL cholesterol level|
|cholesterol v1|readv2|44PH.00|Total cholesterol measurement|
|cholesterol v1|readv2|44PG.00|HDL : total cholesterol ratio|
|cholesterol v1|readv2|44PF.00|Total cholesterol:HDL ratio|
|cholesterol v1|readv2|44PE.00|Serum random LDL cholesterol level|
|cholesterol v1|readv2|44PD.00|Serum fasting LDL cholesterol level|
|cholesterol v1|readv2|44PC.00|Serum random HDL cholesterol level|
|cholesterol v1|readv2|44PB.00|Serum fasting HDL cholesterol level|
|cholesterol v1|readv2|44P9.00|Serum cholesterol studies|
|cholesterol v1|readv2|44P8.00|Serum HDL:non-HDL cholesterol ratio|
|cholesterol v1|readv2|44P7.00|Serum VLDL cholesterol level|
|cholesterol v1|readv2|44P6.00|Serum LDL cholesterol level|
|cholesterol v1|readv2|44P5.00|Serum HDL cholesterol level|
|cholesterol v1|readv2|44P4.00|Serum cholesterol very high|
|cholesterol v1|readv2|44P3.00|Serum cholesterol raised|
|cholesterol v1|readv2|44P2.00|Serum cholesterol borderline|
|cholesterol v1|readv2|44P1.00|Serum cholesterol normal|
|cholesterol v1|readv2|44PA.00|HDL : LDL ratio|
|cholesterol v1|readv2|44lM.00|Plasma LDL/HDL ratio|
|cholesterol v1|readv2|44lL.00|Serum LDL/HDL ratio|
|cholesterol v1|readv2|44lK.00|Plasma cholesterol/VLDL ratio|
|cholesterol v1|readv2|44lJ.00|Serum cholesterol/VLDL ratio|
|cholesterol v1|readv2|44lI.00|Plasma cholesterol/LDL ratio|
|cholesterol v1|readv2|44lH.00|Serum cholesterol/LDL ratio|
|cholesterol v1|readv2|44lG.00|Plasma cholesterol/HDL ratio|
|cholesterol v1|readv2|44lF.00|Serum cholesterol/HDL ratio|
|cholesterol v1|readv2|44l2.00|Cholesterol/HDL ratio|
|cholesterol v1|readv2|44dB.00|Plasma LDL cholesterol level|
|cholesterol v1|readv2|44dA.00|Plasma HDL cholesterol level|
|cholesterol v1|readv2|44d5.00|Plasma fasting LDL cholesterol level|
|cholesterol v1|readv2|44d4.00|Plasma random LDL cholesterol level|
|cholesterol v1|readv2|44d3.00|Plasma fasting HDL cholesterol level|
|cholesterol v1|readv2|44d2.00|Plasma random HDL cholesterol level|
|cholesterol v1|readv2|44R4.11|LDL - electrophoresis|
|cholesterol v1|readv2|44R4.00|Lipoprotein electroph. - LDL|
|cholesterol v1|readv2|44R3.11|HDL - electrophoresis|
|cholesterol v1|readv2|44R3.00|Lipoprotein electroph. - HDL|
|cholesterol v1|readv2|662a.00|Pre-treatment serum cholesterol level|
|cholesterol v1|readv2|44OE.00|Plasma total cholesterol level|
|cholesterol v1|readv2|44lzY00|Serum high density lipoprotein cholesterol:triglyceride ratio|
|cholesterol v1|readv2|4I3O.00|Fluid sample cholesterol level|
|cholesterol v1|snomed|13067005|Cholesteryl esters measurement (procedure)|
|cholesterol v1|snomed|17888004|High density lipoprotein measurement (procedure)|
|cholesterol v1|snomed|28036006|High density lipoprotein cholesterol level|
|cholesterol v1|snomed|77068002|Cholesterol measurement (procedure)|
|cholesterol v1|snomed|104583003|High density lipoprotein/total cholesterol ratio measurement|
|cholesterol v1|snomed|104584009|Intermediate density lipoprotein cholesterol measurement|
|cholesterol v1|snomed|104585005|Very low density lipoprotein cholesterol measurement (procedure)|
|cholesterol v1|snomed|104586006|Cholesterol/triglyceride ratio measurement (procedure)|
|cholesterol v1|snomed|104594004|Cholesterol esterase measurement (procedure)|
|cholesterol v1|snomed|104777003|Lecithin cholesterol acyltransferase measurement (procedure)|
|cholesterol v1|snomed|104781003|Lipids, cholesterol measurement (procedure)|
|cholesterol v1|snomed|104990004|Triglyceride and ester in high density lipoprotein measurement (procedure)|
|cholesterol v1|snomed|104992007|Triglyceride and ester in low density lipoprotein measurement|
|cholesterol v1|snomed|113079009|Low density lipoprotein cholesterol level|
|cholesterol v1|snomed|121751004|Cholesterol sulfate measurement (procedure)|
|cholesterol v1|snomed|121868005|Total cholesterol measurement (procedure)|
|cholesterol v1|snomed|166832000|Serum high density lipoprotein cholesterol measurement (procedure)|
|cholesterol v1|snomed|166833005|Serum low density lipoprotein cholesterol measurement (procedure)|
|cholesterol v1|snomed|166834004|Serum very low density lipoprotein cholesterol measurement (procedure)|
|cholesterol v1|snomed|166838001|Serum fasting high density lipoprotein cholesterol measurement|
|cholesterol v1|snomed|166839009|Serum random high density lipoprotein cholesterol measurement (procedure)|
|cholesterol v1|snomed|166840006|Serum fasting low density lipoprotein cholesterol measurement (procedure)|
|cholesterol v1|snomed|166841005|Serum random low density lipoprotein cholesterol measurement|
|cholesterol v1|snomed|166842003|Total cholesterol:high density lipoprotein ratio measurement|
|cholesterol v1|snomed|167072001|Plasma random high density lipoprotein cholesterol measurement (procedure)|
|cholesterol v1|snomed|167073006|Plasma fasting high density lipoprotein cholesterol measurement (procedure)|
|cholesterol v1|snomed|167074000|Plasma random low density lipoprotein cholesterol measurement (procedure)|
|cholesterol v1|snomed|167075004|Plasma fasting low density lipoprotein cholesterol measurement|
|cholesterol v1|snomed|250743005|HDL/LDL ratio|
|cholesterol v1|snomed|250759005|Measurement of percentage cholesterol as ester (procedure)|
|cholesterol v1|snomed|271059008|Serum high density lipoprotein/non-high density lipoprotein cholesterol ratio measurement (procedure)|
|cholesterol v1|snomed|313811003|Cholesterol/High density lipoprotein ratio measurement|
|cholesterol v1|snomed|313988001|Lipoprotein cholesterol ratio measurement (procedure)|
|cholesterol v1|snomed|313989009|Serum cholesterol/high density lipoprotein ratio measurement|
|cholesterol v1|snomed|313990000|Plasma cholesterol/high density lipoprotein ratio measurement|
|cholesterol v1|snomed|313991001|Serum cholesterol/low density lipoprotein ratio measurement (procedure)|
|cholesterol v1|snomed|313992008|Plasma cholesterol/low density lipoprotein ratio measurement (procedure)|
|cholesterol v1|snomed|313993003|Serum cholesterol/very low density lipoprotein ratio measurement (procedure)|
|cholesterol v1|snomed|313994009|Plasma cholesterol/very low density lipoprotein ratio measurement|
|cholesterol v1|snomed|314012003|Serum low density lipoprotein/high density lipoprotein ratio measurement|
|cholesterol v1|snomed|314013008|Plasma low density lipoprotein/high density lipoprotein ratio measurement (procedure)|
|cholesterol v1|snomed|314035000|Plasma high density lipoprotein cholesterol measurement (procedure)|
|cholesterol v1|snomed|314036004|Plasma low density lipoprotein cholesterol measurement|
|cholesterol v1|snomed|315017003|Fasting cholesterol level (procedure)|
|cholesterol v1|snomed|390956002|Plasma total cholesterol level|
|cholesterol v1|snomed|391291008|Fluid sample cholesterol level|
|cholesterol v1|snomed|395065005|Calculated low density lipoprotein cholesterol level (procedure)|
|cholesterol v1|snomed|395153009|Pre-treatment serum cholesterol level|
|cholesterol v1|snomed|412808005|Serum total cholesterol level|
|cholesterol v1|snomed|443915001|Measurement of total cholesterol and triglycerides|
|cholesterol v1|snomed|789381000000104|Cholesterol/phospholipid ratio measurement (procedure)|
|cholesterol v1|snomed|195861000000108|Cholesterol content measurement (procedure)|
|cholesterol v1|snomed|293821000000103|Non high density lipoprotein cholesterol level|
|cholesterol v1|snomed|194351000000100|Cholesterol/low density lipoprotein ratio measurement (procedure)|
|cholesterol v1|snomed|194361000000102|Cholesterol/very low density lipoprotein ratio measurement (procedure)|
|cholesterol v1|snomed|247801000000106|Serum fasting total cholesterol|
|cholesterol v1|snomed|194801000000108|High density lipoprotein/non-high density lipoprotein cholesterol ratio measurement (procedure)|
|cholesterol v1|snomed|912151000000109|Serum non high density lipoprotein cholesterol level|
|cholesterol v1|snomed|920471000000100|Estimated serum non-high density lipoprotein cholesterol level|
|cholesterol v1|snomed|1006191000000106|Serum non HDL (high density lipoprotein) cholesterol level|
|cholesterol v1|snomed|1102851000000101|Estimated serum non high density lipoprotein cholesterol level (observable entity)|
|cholesterol v1|snomed|1030411000000101|Non HDL cholesterol level|
|cholesterol v1|snomed|1005681000000107|Serum HDL (high density lipoprotein) cholesterol level|
|cholesterol v1|snomed|1015271000000109|Serum HDL (high density lipoprotein):non-HDL (high density lipoprotein) cholesterol ratio|
|cholesterol v1|snomed|1015681000000109|Serum cholesterol/HDL (high density lipoprotein) ratio|
|cholesterol v1|snomed|1015741000000109|Serum LDL (low density lipoprotein)/HDL (high density lipoprotein) ratio|
|cholesterol v1|snomed|1015751000000107|Plasma LDL/HDL (low density lipoprotein/high density lipoprotein) ratio|
|cholesterol v1|snomed|1010581000000101|Plasma HDL (high density lipoprotein) cholesterol level|
|cholesterol v1|snomed|1015701000000106|Serum cholesterol/LDL (low density lipoprotein) ratio|
|cholesterol v1|snomed|1015711000000108|Plasma cholesterol/LDL (low density lipoprotein) ratio|
|cholesterol v1|snomed|1010591000000104|Plasma LDL (low density lipoprotein) cholesterol level|
|cholesterol v1|snomed|1014501000000104|Calculated LDL (low density lipoprotein) cholesterol level|
|cholesterol v1|snomed|1022191000000100|Serum LDL (low density lipoprotein) cholesterol level|
|cholesterol v1|snomed|1003441000000101|Serum VLDL (very low density lipoprotein) cholesterol level|
|cholesterol v1|snomed|1015721000000102|Serum cholesterol/VLDL (very low density lipoprotein) ratio|
|cholesterol v1|snomed|1015731000000100|Plasma cholesterol/VLDL (very low density lipoprotein) ratio|
|cholesterol v1|snomed|1024231000000104|Fluid sample cholesterol level|
|cholesterol v1|snomed|1031421000000101|High density lipoprotein/total cholesterol ratio|
|cholesterol v1|snomed|1026451000000102|Serum fasting HDL (high density lipoprotein) cholesterol level|
|cholesterol v1|snomed|1026461000000104|Serum random HDL (high density lipoprotein) cholesterol level|
|cholesterol v1|snomed|1107681000000108|HDL (high density lipoprotein) cholesterol molar concentration in serum|
|cholesterol v1|snomed|1028831000000106|Plasma random HDL (high density lipoprotein) cholesterol level|
|cholesterol v1|snomed|1028841000000102|Plasma fasting HDL (high density lipoprotein) cholesterol level|
|cholesterol v1|snomed|1107661000000104|HDL (high density lipoprotein) cholesterol molar concentration in plasma|
|cholesterol v1|snomed|1028861000000101|Plasma fasting LDL (low density lipoprotein) cholesterol level|
|cholesterol v1|snomed|1028851000000104|Plasma random LDL (low density lipoprotein) cholesterol level|
|cholesterol v1|snomed|1026471000000106|Serum fasting LDL (low density lipoprotein) cholesterol level|
|cholesterol v1|snomed|1026481000000108|Serum random LDL (low density lipoprotein) cholesterol level|
|cholesterol v1|snomed|1015691000000106|Plasma cholesterol/HDL (high density lipoprotein) ratio|
|cholesterol v1|snomed|994351000000103|Serum total cholesterol level|
|cholesterol v1|snomed|1005671000000105|Serum cholesterol level|
|cholesterol v1|snomed|1017161000000104|Plasma total cholesterol level|
|cholesterol v1|snomed|1107731000000104|Ratio of high density lipoprotein cholesterol to total cholesterol in plasma (observable entity)|
|cholesterol v1|snomed|1107741000000108|Ratio of high density lipoprotein cholesterol to total cholesterol in serum (observable entity)|
|cholesterol v1|snomed|1028551000000102|Total cholesterol:HDL (high density lipoprotein) ratio|
|cholesterol v1|snomed|1029071000000109|HDL/LDL ratio|
|cholesterol v1|snomed|1083861000000102|Serum HDL (high density lipoprotein) cholesterol/triglyceride ratio|
|cholesterol v1|snomed|1083761000000106|Serum fasting total cholesterol level (observable entity)|
|cholesterol v1|snomed|1106541000000101|Cholesterol molar concentration in serum|
|cholesterol v1|snomed|1106531000000105|Cholesterol molar concentration in plasma|
|cholesterol v1|snomed|9422000|Alpha-lipoprotein|
|cholesterol v1|snomed|9556009|Acyl CoA cholesterol acyltransferase|
|cholesterol v1|snomed|22244007|LDL - Low density lipoprotein|
|cholesterol v1|snomed|73427004|Cholesterol ester|
|cholesterol v1|snomed|88557001|LCAT - Lecithin cholesterol acyltransferase|
|cholesterol v1|snomed|102741009|Free cholesterol|
|cholesterol v1|snomed|115332003|High density lipoprotein subfraction 2|
|cholesterol v1|snomed|115333008|High density lipoprotein subfraction 3|
|cholesterol v1|snomed|416724002|Cholesterol derivative|
|cholesterol v1|snomed|707084003|HDL cholesterol 2|
|cholesterol v1|snomed|707086001|HDL cholesterol 2a|
|cholesterol v1|snomed|707091000|IDL cholesterol 1|
|cholesterol v1|snomed|707092007|IDL cholesterol 2|
|cholesterol v1|snomed|707093002|LDL cholesterol pattern A|
|cholesterol v1|snomed|707094008|LDL cholesterol pattern BI|
|cholesterol v1|snomed|707095009|LDL cholesterol pattern BII|
|cholesterol v1|snomed|707096005|LDL cholesterol, acetylated|
|cholesterol v1|snomed|707097001|LDL cholesterol, narrow density|
|cholesterol v1|snomed|707098006|Cholesterol in lipoprotein a|
|cholesterol v1|snomed|707099003|VLDL cholesterol 3|
|cholesterol v1|snomed|707100006|VLDL cholesterol, acetylated|
|cholesterol v1|snomed|707101005|VLDL cholesterol, beta|
|cholesterol v1|snomed|707124003|HDL cholesterol 2b|
|cholesterol v1|snomed|707125002|HDL cholesterol 3|
|cholesterol v1|snomed|707126001|HDL cholesterol 3a|
|cholesterol v1|snomed|707127005|HDL cholesterol 3c|
|cholesterol v1|snomed|707128000|HDL cholesterol 3b|
|cholesterol v1|snomed|712626002|Cholesterol in chylomicrons|
|cholesterol v1|snomed|13644009|High cholesterol|
|cholesterol v1|snomed|124055002|Decreased cholesterol esters (finding)|
|cholesterol v1|snomed|166828006|Serum cholesterol normal (finding)|
|cholesterol v1|snomed|166830008|Serum cholesterol raised (finding)|
|cholesterol v1|snomed|166831007|Serum cholesterol very high (finding)|
|cholesterol v1|snomed|365793008|Finding of cholesterol level|
|cholesterol v1|snomed|365794002|Finding of serum cholesterol level|
|cholesterol v1|snomed|370992007|High blood cholesterol/triglycerides|
|cholesterol v1|snomed|398036000|Low density lipoprotein catabolic defect|
|cholesterol v1|snomed|442234001|Serum cholesterol borderline high (finding)|
|cholesterol v1|snomed|442350007|Serum cholesterol borderline low (finding)|
|cholesterol v1|snomed|445445006|Raised low density lipoprotein cholesterol|
|cholesterol v1|snomed|67991000119104|Serum cholesterol abnormal (finding)|
|cholesterol v1|snomed|850981000000101|Cholesterol level (observable entity)|
|cholesterol v1|snomed|852401000000104|Maximum cholesterol level (observable entity)|
|cholesterol v1|snomed|852411000000102|Minimum cholesterol level (observable entity)|
|cholesterol v1|snomed|853681000000104|Total cholesterol level (observable entity)|
|cholesterol v1|snomed|404670008|Hollenhorst plaque|
|cholesterol v1|snomed|166854003|Lipoprotein electrophoresis - High density lipoprotein (procedure)|
|cholesterol v1|snomed|166855002|Lipoprotein electrophoresis - Low density lipoprotein|
|cholesterol v1|snomed|124054003|Increased cholesterol esters (finding)|
|cholesterol v1|snomed|439953004|Elevated cholesterol/high density lipoprotein ratio|
|cholesterol v1|snomed|102857004|Urinary crystal, cholesterol (finding)|
|cholesterol v1|snomed|939391000000100|Serum high density lipoprotein cholesterol:triglyceride ratio|
|hba1c v1|ctv3|X772q|Haemoglobin A1c level|
|hba1c v1|ctv3|XE24t|Hb. A1C - diabetic control|
|hba1c v1|ctv3|42W1.|Hb. A1C < 7% - good control|
|hba1c v1|ctv3|42W2.|Hb. A1C 7-10% - borderline|
|hba1c v1|ctv3|42W3.|Hb. A1C > 10% - bad control|
|hba1c v1|ctv3|42WZ.|Hb. A1C - diabetic control NOS|
|hba1c v1|ctv3|X80U4|Glycosylat haemoglobin-c frac|
|hba1c v1|ctv3|XaCES|HbA1 - diabetic control|
|hba1c v1|ctv3|XaCET|HbA1 <7% - good control|
|hba1c v1|ctv3|XaCEV|HbA1 >10% - bad control|
|hba1c v1|ctv3|XaCEU|HbA1 7-10% - borderline contrl|
|hba1c v1|ctv3|XaERp|HbA1c level (DCCT aligned)|
|hba1c v1|ctv3|XaPbt|HbA1c levl - IFCC standardised|
|hba1c v1|ctv3|XabrE|HbA1c (diagnostic refrn range)|
|hba1c v1|ctv3|XabrF|HbA1c (monitoring ranges)|
|hba1c v1|ctv3|Xaezd|HbA1c(diagnos ref rnge)IFCC st|
|hba1c v1|ctv3|Xaeze|HbA1c(monitoring rnges)IFCC st|
|hba1c v1|ctv3|42W..|Hb. A1C - diabetic control|
|hba1c v1|ctv3|42W5.|Haemoglobin A1c level - International Federation of Clinical Chemistry and Laboratory Medicine standardised|
|hba1c v1|ctv3|42W51|HbA1c (haemoglobin A1c) level (monitoring ranges) - IFCC (International Federation of Clinical Chemistry and Laboratory Medicine) standardised|
|hba1c v1|ctv3|42W50|HbA1c (haemoglobin A1c) level (diagnostic reference range) - IFCC (International Federation of Clinical Chemistry and Laboratory Medicine) standardised|
|hba1c v1|ctv3|42W4.|HbA1c level (DCCT aligned)|
|hba1c v1|ctv3|44TB.|Haemoglobin A1c level|
|hba1c v1|ctv3|44TB1|Haemoglobin A1c (monitoring ranges)|
|hba1c v1|ctv3|44TB0|Haemoglobin A1c (diagnostic reference range)|
|hba1c v1|readv2|42c..00|HbA1 - diabetic control|
|hba1c v1|readv2|42c3.00|HbA1 level (DCCT aligned)|
|hba1c v1|readv2|42c2.00|HbA1 > 10% - bad control|
|hba1c v1|readv2|42c1.00|HbA1 7 - 10% - borderline control|
|hba1c v1|readv2|42c0.00|HbA1 < 7% - good control|
|hba1c v1|readv2|42W..11|Glycosylated Hb|
|hba1c v1|readv2|42W..12|Glycated haemoglobin|
|hba1c v1|readv2|42W..00|Hb. A1C - diabetic control|
|hba1c v1|readv2|42WZ.00|Hb. A1C - diabetic control NOS|
|hba1c v1|readv2|42W3.00|Hb. A1C > 10% - bad control|
|hba1c v1|readv2|42W2.00|Hb. A1C 7-10% - borderline|
|hba1c v1|readv2|42W1.00|Hb. A1C < 7% - good control|
|hba1c v1|readv2|42W5.00|Haemoglobin A1c level - International Federation of Clinical Chemistry and Laboratory Medicine standardised|
|hba1c v1|readv2|42W5100|HbA1c (haemoglobin A1c) level (monitoring ranges) - IFCC (International Federation of Clinical Chemistry and Laboratory Medicine) standardised|
|hba1c v1|readv2|42W5000|HbA1c (haemoglobin A1c) level (diagnostic reference range) - IFCC (International Federation of Clinical Chemistry and Laboratory Medicine) standardised|
|hba1c v1|readv2|42W4.00|HbA1c level (DCCT aligned)|
|hba1c v1|readv2|44TL.00|Total glycosylated haemoglobin level|
|hba1c v1|readv2|44TB.00|Haemoglobin A1c level|
|hba1c v1|readv2|44TB100|Haemoglobin A1c (monitoring ranges)|
|hba1c v1|readv2|44TB000|Haemoglobin A1c (diagnostic reference range)|
|hba1c v1|snomed|1019431000000105|HbA1c level (Diabetes Control and Complications Trial aligned)|
|hba1c v1|snomed|1003671000000109|Haemoglobin A1c level|
|hba1c v1|snomed|1049301000000100|HbA1c (haemoglobin A1c) level (diagnostic reference range) - IFCC (International Federation of Clinical Chemistry and Laboratory Medicine) standardised|
|hba1c v1|snomed|1049321000000109|HbA1c (haemoglobin A1c) level (monitoring ranges) - IFCC (International Federation of Clinical Chemistry and Laboratory Medicine) standardised|
|hba1c v1|snomed|1107481000000106|HbA1c (haemoglobin A1c) molar concentration in blood|
|hba1c v1|snomed|999791000000106|Haemoglobin A1c level - International Federation of Clinical Chemistry and Laboratory Medicine standardised|
|hba1c v1|snomed|1010941000000103|Haemoglobin A1c (monitoring ranges)|
|hba1c v1|snomed|1010951000000100|Haemoglobin A1c (diagnostic reference range)|
|hba1c v1|snomed|165679005|Haemoglobin A1c (HbA1c) less than 7% indicating good diabetic control|
|hba1c v1|snomed|165680008|Haemoglobin A1c (HbA1c) between 7%-10% indicating borderline diabetic control|
|hba1c v1|snomed|165681007|Hemoglobin A1c (HbA1c) greater than 10% indicating poor diabetic control|
|hba1c v1|snomed|365845005|Haemoglobin A1C - diabetic control finding|
|hba1c v1|snomed|444751005|High hemoglobin A1c level|
|hba1c v1|snomed|43396009|Hemoglobin A1c measurement (procedure)|
|hba1c v1|snomed|313835008|Hemoglobin A1c measurement aligned to the Diabetes Control and Complications Trial|
|hba1c v1|snomed|371981000000106|Hb A1c (Haemoglobin A1c) level - IFCC (International Federation of Clinical Chemistry and Laboratory Medicine) standardised|
|hba1c v1|snomed|444257008|Calculation of estimated average glucose based on haemoglobin A1c|
|hba1c v1|snomed|269823000|Haemoglobin A1C - diabetic control interpretation|
|hba1c v1|snomed|443911005|Ordinal level of hemoglobin A1c|
|hba1c v1|snomed|733830002|HbA1c - Glycated haemoglobin-A1c|