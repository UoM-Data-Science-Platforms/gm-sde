--┌──────────────────┐
--│ Main cohort file │
--└──────────────────┘

-- OUTPUT: Data with the following fields
-- 	All individuals alive in Greater Manchester on 1 January 2020 who were 60 years of age 
--  or older on that day and who have had at least one COVID-19 positive test recorded in
--  their GP record. There are no exclusion criteria. Follow-up is until 30 June 2022

--  DEMOGRAPHIC DATA 
--  PatientId, YearOfBirth, Sex, Ethnicity, Townsend index, Townsend Quintile, LSOA, MonthOfDeath, YearOfDeath
--  COVID DATA
--  DateofNthCovidPositive, DateOfHospitalisationFollowingNthCovid, LengthOfStayFollowingNthCovid, DeathWithin28DaysCovidTest,
--  DateOfNthVaccine, DateOfLongCovid
--  COMORBIDITIES
--  DateOfPagetsDisease, DateOfDiabetes, DateOfCOPD, DateOfAsthma, DataOfSMI, DateOfDementia, DateOfMI, DateOfAngina, DateOfHeartFailure,
--  DateOfStroke, DateOfRA
--  BIOMARKERS
--  BMI, SBP, DBP, eGFR, HbA1x, VitD, FBC

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

-- Build the main cohort
--> EXECUTE query-build-rq038-cohort.sql

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