--┌──────────────────┐
--│ Main cohort file │
--└──────────────────┘

-- OUTPUT: Data with the following fields
-- 	All individuals alive in Greater Manchester on 1 January 2020 who were 60 years of age 
--  or older on that day and who have had at least one COVID-19 positive test recorded in
--  their GP record. There are no exclusion criteria. Follow-up is until 30 June 2022

--  Month of birth, sex, ethnicity, Townsend Index, Lower layer super output area (LSOA),
--  body mass index (BMI), blood pressure (systolic and diastolic)

--  The Component variables needed to calculate the Electronic Frailty Index (EFI) will be 
--  drawn from the GMCR for the dates closest to 1 January 2020

--  Date of COVID-19 Positive Test (s)
--  Dates of hospitalisation within 28 days of COVID-19 test positive confirmed
--  Month of death for deaths within 28 days of COVID-19 test positive confirmed
--  Dates of all vaccinations for COVID-19
--  Diagnosis of Long Covid
--  Pagets disease
--  Major comorbidities: Diabetes (Type 1 or 2), COPD, Asthma, Severe Enduring Mental Illness,
--  Dementia, MI, Angina, Heart Failure, Stroke, Rheumatoid Arthritis Metabolic and 
--  haematological variables such as eGFR, HbA1c and Vitamin D level (where available) and FBC 
--  (closest to 1 January 2020)

--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the temp end date until new legal basis
DECLARE @TEMPRQ038EndDate datetime;
SET @TEMPRQ038EndDate = '2022-06-01';

-- Only include patients who were first registered at a GP practice prior
-- to June 2022. This is 1 month before COPI expired and so acts as a buffer.
-- If we only looked at patients who first registered before July 2022, then
-- there is a chance that their data was processed after COPI expired.
IF OBJECT_ID('tempdb..#PatientsToInclude') IS NOT NULL DROP TABLE #PatientsToInclude;
SELECT FK_Patient_Link_ID INTO #PatientsToInclude
FROM SharedCare.Patient_GP_History
GROUP BY FK_Patient_Link_ID
HAVING MIN(StartDate) < @TEMPRQ038EndDate;

-- First get all people with COVID positive test
--> EXECUTE query-patients-with-covid.sql start-date:2020-01-01 all-patients:true gp-events-table:RLS.vw_GP_Events

-- Table of all patients with COVID at least once
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT FK_Patient_Link_ID INTO #Patients FROM #CovidPatientsMultipleDiagnoses

--> EXECUTE query-patient-year-of-birth.sql

-- Now restrict to those >=60 on 1st January 2020
TRUNCATE TABLE #Patients;
INSERT INTO #Patients
SELECT FK_Patient_Link_ID FROM #PatientYearOfBirth
WHERE YearOfBirth <= 1959;

-- Now the other stuff we need
--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-lsoa.sql
--> EXECUTE query-patient-townsend.sql

--> CODESET hypertension:1
SELECT FK_Patient_Link_ID AS PatientId, MIN(EventDate) AS DateOfFirstDiagnosis FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'hypertension' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'hypertension' AND Version = 1)
)
GROUP BY FK_Patient_Link_ID;