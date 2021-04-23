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

---
## COVID vaccinations
To obtain a table with first and second vaccine doses per patient.

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

---
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

---
## Care home status
To get the care home status for each patient.

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

---
## Classify secondary admissions
To categorise admissions to secondary care into 5 categories: Maternity, Unplanned, Planned, Transfer and Unknown.

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

---
## Clinical code sets
To populate temporary tables with the existing clinical code sets. See the [SQL-generation-process.md](SQL-generation-process.md) for more details.

_Input_
```
No pre-requisites
```

_Output_
```
Five temp tables as follows:
  #AllCodes (Concept, Version, Code)
  #CodeSets (FK_Reference_Coding_ID, Concept)
  #SnomedSets (FK_Reference_SnomedCT_ID, FK_SNOMED_ID)
  #VersionedCodeSets (FK_Reference_Coding_ID, Concept, Version)
  #VersionedSnomedSets (FK_Reference_SnomedCT_ID, Version, FK_SNOMED_ID)
```
_File_: `load-code-sets.sql`

---
## First prescriptions from GP data
To obtain, for each patient, the first date for each medication they have ever been prescribed.

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

---
## Lower level super output area
To get the LSOA for each patient.

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

---
## Sex
To get the Sex for each patient.

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

---
## Year of birth
To get the year of birth for each patient.

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
