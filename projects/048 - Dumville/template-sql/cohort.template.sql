--┌──────────────────┐
--│ Main cohort file │
--└──────────────────┘

--------------------- RDE CHECK ---------------------
-- Le Mai Parkes  - 25 May 2022 - via pull request --
-----------------------------------------------------

-- OUTPUT: Data with the following fields
--  - PatientId (int)
--  - MatchingPatientId (int)
--  - OximetryAtHomeStart (YYYYMMDD - or blank if not used)
--  - OximetryAtHomeEnd (YYYYMMDD - or blank if not used or not discharged)
--  - FirstCovidPositiveDate (DDMMYYYY)
--  - SecondCovidPositiveDate (DDMMYYYY)
--  - ThirdCovidPositiveDate (DDMMYYYY)
--  - YearOfBirth (YYYY)
--  - Sex (M/F)
--  - LSOA
--  - Ethnicity
--  - IMD2019Decile1IsMostDeprived10IsLeastDeprived
--  - MonthOfDeath (MM)
--  - YearOfDeath (YYYY)
--  - IsCareHomeResident (Y/N)


--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the end date
DECLARE @EndDate datetime;
SET @EndDate = '2022-07-01';

-- Assume temp table #OxAtHome (FK_Patient_Link_ID, AdmissionDate, DischargeDate)

-- Remove admissions ahead of our cut-off date
DELETE FROM #OxAtHome WHERE AdmissionDate > '2022-06-01';

-- Censor discharges after cut-off to appear as NULL
UPDATE #OxAtHome SET DischargeDate = NULL WHERE DischargeDate > '2022-06-01';

-- Table of all patients (not matching cohort - will do that subsequently)
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT FK_Patient_Link_ID INTO #Patients FROM #OxAtHome
WHERE AdmissionDate < @EndDate
AND (DischargeDate IS NULL OR DischargeDate < @EndDate);

-- As it's a small cohort, it's quicker to get all data in to a temp table
-- and then all subsequent queries will target that data
IF OBJECT_ID('tempdb..#PatientEventData') IS NOT NULL DROP TABLE #PatientEventData;
SELECT 
  FK_Patient_Link_ID,
  CAST(EventDate AS DATE) AS EventDate,
  SuppliedCode,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID,
  [Value]
INTO #PatientEventData
FROM SharedCare.GP_Events
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate < @EndDate;

IF OBJECT_ID('tempdb..#PatientMedicationData') IS NOT NULL DROP TABLE #PatientMedicationData;
SELECT 
  FK_Patient_Link_ID,
  CAST(MedicationDate AS DATE) AS MedicationDate,
  SuppliedCode,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID
INTO #PatientMedicationData
FROM SharedCare.GP_Medications
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND MedicationDate < @EndDate;

--> EXECUTE query-patients-with-covid.sql start-date:2020-01-01 all-patients:false gp-events-table:#PatientEventData
--> EXECUTE query-patient-year-of-birth.sql
--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-lsoa.sql
--> EXECUTE query-patient-imd.sql

-- Get patient care home status
IF OBJECT_ID('tempdb..#PatientCareHomeStatus') IS NOT NULL DROP TABLE #PatientCareHomeStatus;
SELECT 
	FK_Patient_Link_ID,
	MAX(NursingCareHomeFlag) AS IsCareHomeResident -- max as Y > N > NULL
INTO #PatientCareHomeStatus
FROM SharedCare.Patient p
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND NursingCareHomeFlag IS NOT NULL
GROUP BY FK_Patient_Link_ID;

-- Bring together for final output
SELECT 
  m.FK_Patient_Link_ID AS PatientId,
  m.AdmissionDate AS OximetryAtHomeStart,
  m.DischargeDate AS OximetryAtHomeEnd,
  FirstCovidPositiveDate,
  SecondCovidPositiveDate,
  ThirdCovidPositiveDate,
  YearOfBirth,
  Sex,
  LSOA_Code AS LSOA,
  EthnicCategoryDescription,
  IMD2019Decile1IsMostDeprived10IsLeastDeprived,
  MONTH(DeathDate) AS MonthOfDeath,
  YEAR(DeathDate) AS YearOfDeath,
  IsCareHomeResident
FROM #OxAtHome m
LEFT OUTER JOIN #CovidPatientsMultipleDiagnoses cov ON cov.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientLSOA lsoa ON lsoa.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN SharedCare.Patient_Link pl ON pl.PK_Patient_Link_ID = m.FK_Patient_Link_ID --ethnicity and deathdate
LEFT OUTER JOIN #PatientIMDDecile imd ON imd.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientCareHomeStatus chs ON chs.FK_Patient_Link_ID = m.FK_Patient_Link_ID;