# Reusable queries

***Do not manually edit this file. To recreate run `npm start` and follow the onscreen instructions.***

---

This document describes the SQL query components that have potential to be reused. Each one has a brief objective, an optional
input, and an output. The inputs and outputs are in the form of temporary SQL tables.

---

## All dates
To obtain a table with every date. Useful for output where every date is required but the linked tables might not contain every date.

_Input_
```
No pre-requisites
```

_Output_
```
A temp table with all dates within a range.
 #AllDates ([date])
```
_File_: `query-generate-all-dates.sql`

_Link_: [https://github.com/rw251/.../query-generate-all-dates.sql](https://github.com/rw251/gm-idcr/tree/master/shared/Reusable%20queries%20for%20data%20extraction/query-generate-all-dates.sql)

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
Takes one parameter
  - start-date: string - (YYYY-MM-DD) the date to count COVID diagnoses from. Usually this should be 2020-01-01.
 And assumes there exists two temp tables as follows:
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
## COVID vaccinations
To obtain a table with first and second vaccine doses per patient.

_Assumptions_

- GP records can often be duplicated. The assumption is that if a patient receives two vaccines within 14 days of each other then it is likely that both codes refer to the same vaccine. However, it is possible that the first code's entry into the record was delayed and therefore the second code is in fact a second dose. This query simply gives the earliest and latest vaccine for each person together with the number of days since the first vaccine.
- The vaccine can appear as a procedure or as a medication. We assume that the presence of either represents a vaccination

_Input_
```
No pre-requisites
```

_Output_
```
A temp table as follows:
 #COVIDVaccinations (FK_Patient_Link_ID, VaccineDate, DaysSinceFirstVaccine)
 	- FK_Patient_Link_ID - unique patient id
	- VaccineDate - date of vaccine (YYYY-MM-DD)
	- DaysSinceFirstVaccine - 0 if first vaccine, > 0 otherwise
```
_File_: `query-get-covid-vaccines.sql`

_Link_: [https://github.com/rw251/.../query-get-covid-vaccines.sql](https://github.com/rw251/gm-idcr/tree/master/shared/Reusable%20queries%20for%20data%20extraction/query-get-covid-vaccines.sql)

---
## COVID-related secondary admissions
To classify every admission to secondary care based on whether it is a COVID or non-COVID related. A COVID-related admission is classed as an admission within 4 weeks after, or up to 2 weeks before a positive test.

_Input_
```
Takes one parameter
  - start-date: string - (YYYY-MM-DD) the date to count diagnoses from. Usually this should be 2020-01-01.
 And assumes there exists two temp tables as follows:
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
	- AdmissionDate - date of admission (YYYY-MM-DD)
	- AcuteProvider - Bolton, SRFT, Stockport etc..
	- CovidHealthcareUtilisation - 'TRUE' if admission within 4 weeks after, or up to 14 days before, a positive test
```
_File_: `query-admissions-covid-utilisation.sql`

_Link_: [https://github.com/rw251/.../query-admissions-covid-utilisation.sql](https://github.com/rw251/gm-idcr/tree/master/shared/Reusable%20queries%20for%20data%20extraction/query-admissions-covid-utilisation.sql)

---
## Cancer cohort matching for 004-Finn
Defines the cohort (cancer and non cancer patients) that will be used for the study, based on: Main cohort (cancer patients): - Cancer diagnosis between 1st February 2015 and 1st February 2020 - >= 18 year old - Alive on 1st Feb 2020 Control group (non cancer patients): -	Alive on 1st February 2020 -	no current or history of cancer diagnosis. Matching is 1:5 based on sex and year of birth with a flexible year of birth = 0 Index date is: 1st February 2020

_Input_
```
Assumes that @StartDate has already been defined
```

_Output_
```
A temp table as follows:
 #Patients
  - FK_Patient_Link_ID
  - YearOfBirth
  - Sex
  - HasCancer
  - NumberOfMatches
```
_File_: `query-cancer-cohort-matching.sql`

_Link_: [https://github.com/rw251/.../query-cancer-cohort-matching.sql](https://github.com/rw251/gm-idcr/tree/master/shared/Reusable%20queries%20for%20data%20extraction/query-cancer-cohort-matching.sql)

---
## Care home status
To get the care home status for each patient.

_Assumptions_

- If any of the patient records suggests the patients lives in a care home we will assume that they do

_Input_
```
Assumes there exists a temp table as follows:
 #Patients (FK_Patient_Link_ID)
  A distinct list of FK_Patient_Link_IDs for each patient in the cohort
```

_Output_
```
A temp table as follows:
 #PatientCareHomeStatus (FK_Patient_Link_ID, IsCareHomeResident)
 	- FK_Patient_Link_ID - unique patient id
	- IsCareHomeResident - Y/N
```
_File_: `query-patient-care-home-resident.sql`

_Link_: [https://github.com/rw251/.../query-patient-care-home-resident.sql](https://github.com/rw251/gm-idcr/tree/master/shared/Reusable%20queries%20for%20data%20extraction/query-patient-care-home-resident.sql)

---
## Classify secondary admissions
To categorise admissions to secondary care into 5 categories: Maternity, Unplanned, Planned, Transfer and Unknown.

_Assumptions_

- We assume patients can only have one admission per day. This is probably not true, but where we see multiple admissions it is more likely to be data duplication, or internal admissions, than an admission, discharge and another admission in the same day.
- Where patients have multiple admissions we choose the "highest" category for admission with the categories ranked as follows: Maternity > Unplanned > Planned > Transfer > Unknown
- We have used the following classifications based on the AdmissionTypeCode:
	- PLANNED: PL (ELECTIVE PLANNED), 11 (Elective - Waiting List), WL (ELECTIVE WL), 13 (Elective - Planned), 12 (Elective - Booked), BL (ELECTIVE BOOKED), D (NULL), Endoscopy (Endoscopy), OP (DIRECT OUTPAT CLINIC), Venesection (X36.2 Venesection), Colonoscopy (H22.9 Colonoscopy), Medical (Medical)
	- UNPLANNED: AE (AE.DEPT.OF PROVIDER), 21 (Emergency - Local A&E), I (NULL), GP (GP OR LOCUM GP), 22 (Emergency - GP), 23 (Emergency - Bed Bureau), 28 (Emergency - Other (inc other provider A&E)), 2D (Emergency - Other), 24 (Emergency - Clinic), EM (EMERGENCY OTHER), AI (ACUTE TO INTMED CARE), BB (EMERGENCY BED BUREAU), DO (EMERGENCY DOMICILE), 2A (A+E Department of another provider where the Patient has not been admitted), A+E (Admission	 A+E Admission), Emerg (GP	Emergency GP Patient)
	- MATERNITY: 31 (Maternity ante-partum), BH (BABY BORN IN HOSP), AN (MATERNITY ANTENATAL), 82 (Birth in this Health Care Provider), PN (MATERNITY POST NATAL), B (NULL), 32 (Maternity post-partum), BHOSP (Birth in this Health Care Provider)
	- TRANSFER: 81 (Transfer from other hosp (not A&E)), TR (PLAN TRANS TO TRUST), ET (EM TRAN (OTHER PROV)), HospTran (Transfer from other NHS Hospital), T (TRANSFER), CentTrans (Transfer from CEN Site)
	- OTHER: Anything else not previously classified

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
## Cohort matching on year of birth / sex
To take a primary cohort and find a 1:n matched cohort based on year of birth and sex.

_Input_
```
Takes two parameters
  - yob-flex: integer - number of years each way that still allow a year of birth match
  - num-matches: integer - number of matches for each patient in the cohort
 Requires two temp tables to exist as follows:
 #MainCohort (FK_Patient_Link_ID, Sex, YearOfBirth)
 	- FK_Patient_Link_ID - unique patient id
	- Sex - M/F
	- YearOfBirth - Integer
 #PotentialMatches (FK_Patient_Link_ID, Sex, YearOfBirth)
 	- FK_Patient_Link_ID - unique patient id
	- Sex - M/F
	- YearOfBirth - Integer
```

_Output_
```
A temp table as follows:
 #CohortStore (FK_Patient_Link_ID, YearOfBirth, Sex, MatchingPatientId, MatchingYearOfBirth)
  - FK_Patient_Link_ID - unique patient id for primary cohort patient
  - YearOfBirth - of the primary cohort patient
  - Sex - of the primary cohort patient
  - MatchingPatientId - id of the matched patient
  - MatchingYearOfBirth - year of birth of the matched patient
```
_File_: `query-cohort-matching-yob-sex-alt.sql`

_Link_: [https://github.com/rw251/.../query-cohort-matching-yob-sex-alt.sql](https://github.com/rw251/gm-idcr/tree/master/shared/Reusable%20queries%20for%20data%20extraction/query-cohort-matching-yob-sex-alt.sql)

---
## Cohort matching on year of birth / sex / and an index date
To take a primary cohort and find a 1:5 matched cohort based on year of birth, sex, and an index date of an event.

_Input_
```
Takes two parameters
  - yob-flex: integer - number of years each way that still allow a year of birth match
  - index-date-flex: integer - number of days either side of the index date that we allow matching
 Requires two temp tables to exist as follows:
 #MainCohort (FK_Patient_Link_ID, IndexDate, Sex, YearOfBirth)
 	- FK_Patient_Link_ID - unique patient id
	- IndexDate - date of event of interest (YYYY-MM-DD)
	- Sex - M/F
	- YearOfBirth - Integer
 #PotentialMatches (FK_Patient_Link_ID, IndexDate, Sex, YearOfBirth)
 	- FK_Patient_Link_ID - unique patient id
	- IndexDate - date of event of interest (YYYY-MM-DD)
	- Sex - M/F
	- YearOfBirth - Integer
```

_Output_
```
A temp table as follows:
 #CohortStore (FK_Patient_Link_ID, YearOfBirth, Sex, IndexDate, MatchingPatientId, MatchingYearOfBirth, MatchingIndexDate)
  - FK_Patient_Link_ID - unique patient id for primary cohort patient
  - YearOfBirth - of the primary cohort patient
  - Sex - of the primary cohort patient
  - IndexDate - date of event of interest (YYYY-MM-DD)
  - MatchingPatientId - id of the matched patient
  - MatchingYearOfBirth - year of birth of the matched patient
  - MatchingIndexDate - index date for the matched patient
```
_File_: `query-cohort-matching-yob-sex-index-date.sql`

_Link_: [https://github.com/rw251/.../query-cohort-matching-yob-sex-index-date.sql](https://github.com/rw251/gm-idcr/tree/master/shared/Reusable%20queries%20for%20data%20extraction/query-cohort-matching-yob-sex-index-date.sql)

---
## Create a cohort of patients based on QOF definitions
To obtain a cohort of patients defined by a particular QOF condition.

_Input_
```
Takes two parameters
  - condition: string - the name of the QOF condition as recorded in the SharedCare.Cohort_Category table
  - outputtable: string - the name of the temp table that will be created to store the cohort
```

_Output_
```
A temp table as follows:
 #[outputtable] (FK_Patient_Link_ID)
  - FK_Patient_Link_ID - unique patient id for cohort patient
```
_File_: `query-qof-cohort.sql`

_Link_: [https://github.com/rw251/.../query-qof-cohort.sql](https://github.com/rw251/gm-idcr/tree/master/shared/Reusable%20queries%20for%20data%20extraction/query-qof-cohort.sql)

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

---
## Flu vaccine eligibile patients
To obtain a table with a list of patients who are currently entitled to a flu vaccine.

_Input_
```
No pre-requisites
```

_Output_
```
A temp table as follows:
 #FluVaccPatients (FK_Patient_Link_ID)
 	- FK_Patient_Link_ID - unique patient id
```
_File_: `query-get-flu-vaccine-eligible.sql`

_Link_: [https://github.com/rw251/.../query-get-flu-vaccine-eligible.sql](https://github.com/rw251/gm-idcr/tree/master/shared/Reusable%20queries%20for%20data%20extraction/query-get-flu-vaccine-eligible.sql)

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
	- LSOA_Code - nationally recognised LSOA identifier
```
_File_: `query-patient-lsoa.sql`

_Link_: [https://github.com/rw251/.../query-patient-lsoa.sql](https://github.com/rw251/gm-idcr/tree/master/shared/Reusable%20queries%20for%20data%20extraction/query-patient-lsoa.sql)

---
## Patient GP history
To produce a table showing the start and end dates for each practice the patient has been registered at.

_Assumptions_

- We do not have data on patients who move out of GM, though we do know that it happened. For these patients we record the GPPracticeCode as OutOfArea
- Where two adjacent time periods either overlap, or have a gap between them, we assume that the most recent registration is more accurate and adjust the end date of the first time period accordingly. This is an infrequent occurrence.

_Input_
```
No pre-requisites
```

_Output_
```
A temp table as follows:
 #PatientGPHistory (FK_Patient_Link_ID, GPPracticeCode, StartDate, EndDate)
	- FK_Patient_Link_ID - unique patient id
	- GPPracticeCode - national GP practice id system
	- StartDate - date the patient registered at the practice
	- EndDate - date the patient left the practice
```
_File_: `query-patient-gp-history.sql`

_Link_: [https://github.com/rw251/.../query-patient-gp-history.sql](https://github.com/rw251/gm-idcr/tree/master/shared/Reusable%20queries%20for%20data%20extraction/query-patient-gp-history.sql)

---
## Patient received flu vaccine in a given time period
To find patients who received a flu vaccine in a given time period

_Assumptions_

- We look for codes related to the administration of flu vaccines and codes for the vaccine itself

_Input_
```
Takes two parameters
  - date-from: YYYY-MM-DD - the start date of the time period (inclusive)
  - date-to: YYYY-MM-DD - the end date of the time period (inclusive)
 Requires one temp table to exist as follows:
 #Patients (FK_Patient_Link_ID)
  A distinct list of FK_Patient_Link_IDs for each patient in the cohort
```

_Output_
```
A temp table as follows:
 #PatientHadFluVaccine (FK_Patient_Link_ID, FluVaccineDate)
	- FK_Patient_Link_ID - unique patient id
	- FluVaccineDate - YYYY-MM-DD (first date of flu vaccine in given time period)
```
_File_: `query-received-flu-vaccine.sql`

_Link_: [https://github.com/rw251/.../query-received-flu-vaccine.sql](https://github.com/rw251/gm-idcr/tree/master/shared/Reusable%20queries%20for%20data%20extraction/query-received-flu-vaccine.sql)

---
## Patients with COVID
To get tables of all patients with a COVID diagnosis in their record.

_Input_
```
Takes one parameter
  - start-date: string - (YYYY-MM-DD) the date to count diagnoses from. Usually this should be 2020-01-01.
```

_Output_
```
Two temp tables as follows:
 #CovidPatients (FK_Patient_Link_ID, FirstCovidPositiveDate)
 	- FK_Patient_Link_ID - unique patient id
	- FirstCovidPositiveDate - earliest COVID diagnosis
 #CovidPatientsAllDiagnoses (FK_Patient_Link_ID, CovidPositiveDate)
 	- FK_Patient_Link_ID - unique patient id
	- CovidPositiveDate - any COVID diagnosis
```
_File_: `query-patients-with-covid.sql`

_Link_: [https://github.com/rw251/.../query-patients-with-covid.sql](https://github.com/rw251/gm-idcr/tree/master/shared/Reusable%20queries%20for%20data%20extraction/query-patients-with-covid.sql)

---
## Practice system lookup table
To provide lookup table for GP systems. The GMCR doesn't hold this information in the data so here is a lookup. This was accurate on 27th Jan 2021 and will likely drift out of date slowly as practices change systems. Though this doesn't happen very often.

_Input_
```
No pre-requisites
```

_Output_
```
A temp table as follows:
 #PracticeSystemLookup (PracticeId, System)
 	- PracticeId - Nationally recognised practice id
	- System - EMIS, TPP, VISION
```
_File_: `query-practice-systems-lookup.sql`

_Link_: [https://github.com/rw251/.../query-practice-systems-lookup.sql](https://github.com/rw251/gm-idcr/tree/master/shared/Reusable%20queries%20for%20data%20extraction/query-practice-systems-lookup.sql)

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
	- AdmissionDate - date of admission (YYYY-MM-DD)
	- AcuteProvider - Bolton, SRFT, Stockport etc..
  (Limited to one admission per person per hospital per day, because if a patient has 2 admissions
   on the same day to the same hopsital then it's most likely data duplication rather than two short
   hospital stays)
 #LengthOfStay (FK_Patient_Link_ID, AdmissionDate)
 	- FK_Patient_Link_ID - unique patient id
	- AdmissionDate - date of admission (YYYY-MM-DD)
	- AcuteProvider - Bolton, SRFT, Stockport etc..
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
## Sex
To get the Sex for each patient.

_Assumptions_

- Patient data is obtained from multiple sources. Where patients have multiple sexes we determine the sex as follows:
- If the patients has a sex in their primary care data feed we use that as most likely to be up to date
- If every sex for a patient is the same, then we use that
- If there is a single most recently updated sex in the database then we use that
- Otherwise the patient's sex is considered unknown

_Input_
```
Assumes there exists a temp table as follows:
 #Patients (FK_Patient_Link_ID)
  A distinct list of FK_Patient_Link_IDs for each patient in the cohort
```

_Output_
```
A temp table as follows:
 #PatientSex (FK_Patient_Link_ID, Sex)
 	- FK_Patient_Link_ID - unique patient id
	- Sex - M/F
```
_File_: `query-patient-sex.sql`

_Link_: [https://github.com/rw251/.../query-patient-sex.sql](https://github.com/rw251/gm-idcr/tree/master/shared/Reusable%20queries%20for%20data%20extraction/query-patient-sex.sql)

---
## Smoking status
To get the smoking status for each patient in a cohort.

_Assumptions_

- We take the most recent smoking status in a patient's record to be correct
- However, there is likely confusion between the "non smoker" and "never smoked" codes. Especially as sometimes the synonyms for these codes overlap. Therefore, a patient wih a most recent smoking status of "never", but who has previous smoking codes, would be classed as WorstSmokingStatus=non-trivial-smoker / CurrentSmokingStatus=non-smoker

_Input_
```
Assumes there exists a temp table as follows:
 #Patients (FK_Patient_Link_ID)
  A distinct list of FK_Patient_Link_IDs for each patient in the cohort
```

_Output_
```
A temp table as follows:
 #PatientSmokingStatus (FK_Patient_Link_ID, PassiveSmoker, WorstSmokingStatus, CurrentSmokingStatus)
	- FK_Patient_Link_ID - unique patient id
	- PassiveSmoker - Y/N (whether a patient has ever had a code for passive smoking)
	- WorstSmokingStatus - [non-trivial-smoker/trivial-smoker/non-smoker]
	- CurrentSmokingStatus - [non-trivial-smoker/trivial-smoker/non-smoker]
```
_File_: `query-patient-smoking-status.sql`

_Link_: [https://github.com/rw251/.../query-patient-smoking-status.sql](https://github.com/rw251/gm-idcr/tree/master/shared/Reusable%20queries%20for%20data%20extraction/query-patient-smoking-status.sql)

---
## Townsend Score (2011)
To get the 2011 Townsend score and quintile for each patient.

_Input_
```
Assumes there exists a temp table as follows:
 #Patients (FK_Patient_Link_ID)
  A distinct list of FK_Patient_Link_IDs for each patient in the cohort
```

_Output_
```
A temp table as follows:
 #PatientTownsend (FK_Patient_Link_ID, TownsendScoreHigherIsMoreDeprived, TownsendQuintileHigherIsMoreDeprived)
 	- FK_Patient_Link_ID - unique patient id
	- TownsendScoreHigherIsMoreDeprived - number range approx [-7,13]
	- TownsendQuintileHigherIsMoreDeprived - number 1 to 5 inclusive
```
_File_: `query-patient-townsend.sql`

_Link_: [https://github.com/rw251/.../query-patient-townsend.sql](https://github.com/rw251/gm-idcr/tree/master/shared/Reusable%20queries%20for%20data%20extraction/query-patient-townsend.sql)

---
## Year of birth
To get the year of birth for each patient.

_Assumptions_

- Patient data is obtained from multiple sources. Where patients have multiple YOBs we determine the YOB as follows:
- If the patients has a YOB in their primary care data feed we use that as most likely to be up to date
- If every YOB for a patient is the same, then we use that
- If there is a single most recently updated YOB in the database then we use that
- Otherwise we take the highest YOB for the patient that is not in the future

_Input_
```
Assumes there exists a temp table as follows:
 #Patients (FK_Patient_Link_ID)
  A distinct list of FK_Patient_Link_IDs for each patient in the cohort
```

_Output_
```
A temp table as follows:
 #PatientYearOfBirth (FK_Patient_Link_ID, YearOfBirth)
 	- FK_Patient_Link_ID - unique patient id
	- YearOfBirth - INT
```
_File_: `query-patient-year-of-birth.sql`

_Link_: [https://github.com/rw251/.../query-patient-year-of-birth.sql](https://github.com/rw251/gm-idcr/tree/master/shared/Reusable%20queries%20for%20data%20extraction/query-patient-year-of-birth.sql)
