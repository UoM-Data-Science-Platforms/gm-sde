--┌──────────────────────┐
--│ Diabetes cohort file │
--└──────────────────────┘

-- ACTION
-- Add testosterone
-- Add SHBG
-- Add hospital admissions
-- Add length of stay
-- Add smoking (current / never / ex)
-- Add diabetes type

-- Cohort is diabetic patients with a positive covid test

--> EXECUTE load-code-sets.sql diabetes bmi hba1c cholesterol ldl hdl vitamin-d severe-mental-illness metformin ace-inhibitor

-- First get all the diabetic patients and the date of first diagnosis
IF OBJECT_ID('tempdb..#DiabeticPatients') IS NOT NULL DROP TABLE #DiabeticPatients;
SELECT FK_Patient_Link_ID, MIN(CAST(EventDate AS DATE)) AS FirstDiagnosisDate INTO #DiabeticPatients
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('diabetes') AND [Version]=1) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('diabetes') AND [Version]=1)
)
GROUP BY FK_Patient_Link_ID;

-- Then get all the positive covid test patients
IF OBJECT_ID('tempdb..#CovidPatients') IS NOT NULL DROP TABLE #CovidPatients;
SELECT FK_Patient_Link_ID, MIN(CONVERT(DATE, [EventDate])) AS FirstCovidPositiveDate INTO #CovidPatients
FROM [RLS].[vw_COVID19]
WHERE GroupDescription = 'Confirmed'
AND EventDate > '2020-01-01'
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

-- Primary cohort is all diabetic patients with a positive covid test
IF OBJECT_ID('tempdb..#DiabeticPatientsWithCovid') IS NOT NULL DROP TABLE #DiabeticPatientsWithCovid;
SELECT FK_Patient_Link_ID, FirstDiagnosisDate INTO #DiabeticPatientsWithCovid
FROM #DiabeticPatients
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #CovidPatients);

-- Define #Patients temp table for getting future things like age/sex etc.
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT FK_Patient_Link_ID INTO #Patients
FROM #CovidPatients;

--> EXECUTE query-patient-year-of-birth.sql
--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-lsoa.sql

-- Define the main cohort that will be matched
IF OBJECT_ID('tempdb..#MainCohort') IS NOT NULL DROP TABLE #MainCohort;
SELECT c.FK_Patient_Link_ID, FirstCovidPositiveDate AS IndexDate, Sex, YearOfBirth
INTO #MainCohort
FROM #CovidPatients c
LEFT OUTER JOIN #PatientLSOA lsoa ON lsoa.FK_Patient_Link_ID = c.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = c.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = c.FK_Patient_Link_ID
WHERE c.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #DiabeticPatients);
--8582

-- Define the population of potential matches for the cohort
IF OBJECT_ID('tempdb..#PotentialMatches') IS NOT NULL DROP TABLE #PotentialMatches;
SELECT c.FK_Patient_Link_ID, FirstCovidPositiveDate AS IndexDate, Sex, YearOfBirth
INTO #PotentialMatches
FROM #CovidPatients c
LEFT OUTER JOIN #PatientLSOA lsoa ON lsoa.FK_Patient_Link_ID = c.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = c.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = c.FK_Patient_Link_ID
EXCEPT
SELECT * FROM #MainCohort;
-- 88197

--> EXECUTE query-cohort-matching-yob-sex-index-date.sql index-date-flex:14 yob-flex:5

IF OBJECT_ID('tempdb..#PatientValues') IS NOT NULL DROP TABLE #PatientValues;
SELECT 
	FK_Patient_Link_ID,
	CAST(EventDate AS DATE) AS EventDate,
	[Value] AS BMI
INTO #PatientValues
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (
    SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (
      Concept IN ('bmi') AND [Version]=2 OR
      Concept IN ('hba1c') AND [Version]=2 OR
      Concept IN ('cholesterol') AND [Version]=2 OR
      Concept IN ('ldl') AND [Version]=1 OR
      Concept IN ('hdl') AND [Version]=1 OR
      Concept IN ('vitamin-d') AND [Version]=1
    )
  ) OR
  FK_Reference_Coding_ID IN (
    SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (
      Concept IN ('bmi') AND [Version]=2 OR
      Concept IN ('hba1c') AND [Version]=2 OR
      Concept IN ('cholesterol') AND [Version]=2 OR
      Concept IN ('ldl') AND [Version]=1 OR
      Concept IN ('hdl') AND [Version]=1 OR
      Concept IN ('vitamin-d') AND [Version]=1
    )
  )
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate > '2018-01-01'
AND [Value] IS NOT NULL
AND [Value] != '0';

-- get most recent value at in the period [index date - 2 years, index date]

-- diagnoses

-- medications
IF OBJECT_ID('tempdb..#PatientMedications') IS NOT NULL DROP TABLE #PatientMedications;
SELECT 
	FK_Patient_Link_ID,
	CAST(MedicationDate AS DATE) AS MedicationDate
INTO #PatientMedications
FROM RLS.vw_GP_Medications
WHERE (
	FK_Reference_SnomedCT_ID IN (
    SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (
      Concept IN ('metformin') AND [Version]=1 OR
      Concept IN ('ace-inhibitor') AND [Version]=1
    )
  ) OR
  FK_Reference_Coding_ID IN (
    SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (
      Concept IN ('metformin') AND [Version]=1 OR
      Concept IN ('ace-inhibitor') AND [Version]=1
    )
  )
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND MedicationDate > '2019-07-01';

-- record as on med if value within 6 months on index date