--┌────────────────────────────────┐
--│ Diabetes and COVID cohort file │
--└────────────────────────────────┘
/*
TODO
- Update all code sets (except maybe meds) when RLS is back cos at the moment it's way off hte charts
- Check prevalence of:
  - bipolar:2
  - schizophrenia-psychosis:2
  - history-of-bipolar:1
  - history-of-psychosis-or-schizophrenia:1
- Check fasting glucose prevalence
- Check prevalance of medications
- Revisit the "bnf-" ones where there was an existing set. Particularly lithium which seems lacking.
*/

----------------------- RDE CHECK ---------------------
-- George Tilston  - 7 April 2022 - via pull request --
-------------------------------------------------------

-- Cohort is patients diagnosed with severe mental illness.

-- DEMOGRAPHIC
-- PatientId, YearOfBirth, DeathDate, DeathWithin28Days, Frailty,
-- Sex, LSOA, EthnicCategoryDescription, TownsendScoreHigherIsMoreDeprived, TownsendQuintileHigherIsMoreDeprived,
-- COHORT SPECIFIC
-- FirstBipolarDate, FirstBipolarHistoryCode, FirstPsychosisSchizophreniaDate, FirstPsychosisSchizophreniaHistoryCode
-- FirstDementiaDate, FirstAntipsycoticDate, FirstCOVIDPositiveTestDate, SecondCOVIDPositiveTestDate,
-- ThirdCOVIDPositiveTestDate, FourthCOVIDPositiveTestDate, FifthCOVIDPositiveTestDate,
-- FirstAdmissionPost1stCOVIDTest, LengthOfStayFirstAdmission1stCOVIDTest, FirstAdmissionPost2ndCOVIDTest, LengthOfStayFirstAdmission2ndCOVIDTest,
-- FirstAdmissionPost3rdCOVIDTest, LengthOfStayFirstAdmission3rdCOVIDTest, FirstAdmissionPost4thCOVIDTest, LengthOfStayFirstAdmission4thCOVIDTest,
-- FirstAdmissionPost5thCOVIDTest, LengthOfStayFirstAdmission5thCOVIDTest, 
-- FirstVaccineDate, SecondVaccineDate, ThirdVaccineDate, FourthVaccineDate, FifthVaccineDate, SixthVaccineDate,
-- PATIENT STATUS
-- IsPassiveSmoker, WorstSmokingStatus, CurrentSmokingStatus
-- DIAGNOSES
-- PatientHasCOPD, PatientHasASTHMA, PatientHasSMI, PatientHasHYPERTENSION

--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2020-01-01';

-- Only include patients who were first registered at a GP practice prior
-- to June 2022. This is 1 month before COPI expired and so acts as a buffer.
-- If we only looked at patients who first registered before July 2022, then
-- there is a chance that their data was processed after COPI expired.
IF OBJECT_ID('tempdb..#PatientsToInclude') IS NOT NULL DROP TABLE #PatientsToInclude;
SELECT FK_Patient_Link_ID INTO #PatientsToInclude
FROM SharedCare.Patient_GP_History
GROUP BY FK_Patient_Link_ID
HAVING MIN(StartDate) < '2022-06-01';

-- First get all the SMI patients and the date of first diagnosis
--> CODESET bipolar:2 schizophrenia-psychosis:2 history-of-bipolar:1 antipsychotics:1
--> CODESET history-of-psychosis-or-schizophrenia:1
--> CODESET amisulpride:1 aripiprazole:1 asenapine:1 chlorpromazine:1 clozapine:1 flupentixol:1 fluphenazine:1
--> CODESET haloperidol:1 levomepromazine:1 loxapine:1 lurasidone:1 olanzapine:1 paliperidone:1 perphenazine:1
--> CODESET pimozide:1 quetiapine:1 risperidone:1 sertindole:1 sulpiride:1 thioridazine:1 trifluoperazine:1
--> CODESET zotepine:1 zuclopenthixol:1
IF OBJECT_ID('tempdb..#BipolarPatients') IS NOT NULL DROP TABLE #BipolarPatients;
SELECT FK_Patient_Link_ID, MIN(CAST(EventDate AS DATE)) AS FirstBipolarDate INTO #BipolarPatients
FROM SharedCare.GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('bipolar') AND [Version]=2) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('bipolar') AND [Version]=2)
)
AND EventDate IS NOT NULL
AND EventDate < '2022-06-01'
GROUP BY FK_Patient_Link_ID;

IF OBJECT_ID('tempdb..#PsychosisSchizoPatients') IS NOT NULL DROP TABLE #PsychosisSchizoPatients;
SELECT FK_Patient_Link_ID, MIN(CAST(EventDate AS DATE)) AS FirstPsychosisSchizophreniaDate INTO #PsychosisSchizoPatients
FROM SharedCare.GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('schizophrenia-psychosis') AND [Version]=2) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('schizophrenia-psychosis') AND [Version]=2)
)
AND EventDate IS NOT NULL
AND EventDate < '2022-06-01'
GROUP BY FK_Patient_Link_ID;

IF OBJECT_ID('tempdb..#BipolarHistoryPatients') IS NOT NULL DROP TABLE #BipolarHistoryPatients;
SELECT FK_Patient_Link_ID, MIN(CAST(EventDate AS DATE)) AS FirstBipolarHistoryCode INTO #BipolarHistoryPatients
FROM SharedCare.GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('history-of-bipolar') AND [Version]=1) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('history-of-bipolar') AND [Version]=1)
)
AND EventDate IS NOT NULL
AND EventDate < '2022-06-01'
GROUP BY FK_Patient_Link_ID;

IF OBJECT_ID('tempdb..#PsychSchizoHistoryPatients') IS NOT NULL DROP TABLE #PsychSchizoHistoryPatients;
SELECT FK_Patient_Link_ID, MIN(CAST(EventDate AS DATE)) AS FirstPsychosisSchizophreniaHistoryCode INTO #PsychSchizoHistoryPatients
FROM SharedCare.GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('history-of-psychosis-or-schizophrenia') AND [Version]=1) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('history-of-psychosis-or-schizophrenia') AND [Version]=1)
)
AND EventDate IS NOT NULL
AND EventDate < '2022-06-01'
GROUP BY FK_Patient_Link_ID;


IF OBJECT_ID('tempdb..#AntipsycoticPatients') IS NOT NULL DROP TABLE #AntipsycoticPatients;
SELECT FK_Patient_Link_ID, MIN(CAST(MedicationDate AS DATE)) AS FirstAntipsycoticDate INTO #AntipsycoticPatients
FROM SharedCare.GP_Medications
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('amisulpride', 'aripiprazole', 'asenapine', 'chlorpromazine', 'clozapine', 'flupentixol', 'fluphenazine', 'haloperidol', 'levomepromazine', 'loxapine', 'lurasidone', 'olanzapine', 'paliperidone', 'perphenazine', 'pimozide', 'quetiapine', 'risperidone', 'sertindole', 'sulpiride', 'thioridazine', 'trifluoperazine', 'zotepine', 'zuclopenthixol') AND [Version]=1) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('amisulpride', 'aripiprazole', 'asenapine', 'chlorpromazine', 'clozapine', 'flupentixol', 'fluphenazine', 'haloperidol', 'levomepromazine', 'loxapine', 'lurasidone', 'olanzapine', 'paliperidone', 'perphenazine', 'pimozide', 'quetiapine', 'risperidone', 'sertindole', 'sulpiride', 'thioridazine', 'trifluoperazine', 'zotepine', 'zuclopenthixol') AND [Version]=1)
)
AND MedicationDate IS NOT NULL
AND MedicationDate < '2022-06-01'
GROUP BY FK_Patient_Link_ID;

-- Table of all patients with SMI or antipsycotic
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
(
  SELECT FK_Patient_Link_ID INTO #Patients FROM #BipolarPatients
  UNION
  SELECT FK_Patient_Link_ID FROM #BipolarHistoryPatients
  UNION
  SELECT FK_Patient_Link_ID FROM #PsychosisSchizoPatients
  UNION
  SELECT FK_Patient_Link_ID FROM #PsychSchizoHistoryPatients
  UNION
  SELECT FK_Patient_Link_ID FROM #AntipsycoticPatients
)
INTERSECT
SELECT FK_Patient_Link_ID FROM #PatientsToInclude;

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
FROM [SharedCare].GP_Events
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate < '2022-06-01';

IF OBJECT_ID('tempdb..#PatientMedicationData') IS NOT NULL DROP TABLE #PatientMedicationData;
SELECT 
  FK_Patient_Link_ID,
  CAST(MedicationDate AS DATE) AS MedicationDate,
  SuppliedCode,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID
INTO #PatientMedicationData
FROM [SharedCare].GP_Medications
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND MedicationDate < '2022-06-01';

-- Then get all the positive covid test patients
--> EXECUTE query-patients-with-covid.sql start-date:2020-01-01 all-patients:false gp-events-table:#PatientEventData
--> EXECUTE query-patient-year-of-birth.sql
--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-smoking-status.sql gp-events-table:#PatientEventData
--> EXECUTE query-patient-lsoa.sql
--> EXECUTE query-patient-townsend.sql
--> EXECUTE query-get-covid-vaccines.sql gp-events-table:#PatientEventData gp-medications-table:#PatientMedicationData
--> EXECUTE query-patient-frailty-score.sql
--> EXECUTE query-get-admissions-and-length-of-stay.sql all-patients:false

-- Now find hospital admission following each of up to 5 covid positive tests
IF OBJECT_ID('tempdb..#PatientsAdmissionsPostTest') IS NOT NULL DROP TABLE #PatientsAdmissionsPostTest;
CREATE TABLE #PatientsAdmissionsPostTest (
  FK_Patient_Link_ID BIGINT,
  [FirstAdmissionPost1stCOVIDTest] DATE,
  [FirstAdmissionPost2ndCOVIDTest] DATE,
  [FirstAdmissionPost3rdCOVIDTest] DATE,
  [FirstAdmissionPost4thCOVIDTest] DATE,
  [FirstAdmissionPost5thCOVIDTest] DATE
);

-- Populate table with patient IDs
INSERT INTO #PatientsAdmissionsPostTest (FK_Patient_Link_ID)
SELECT FK_Patient_Link_ID FROM #CovidPatientsMultipleDiagnoses;

-- Find 1st hospital stay following 1st COVID positive test (but before 2nd)
UPDATE t1
SET t1.[FirstAdmissionPost1stCOVIDTest] = NextAdmissionDate
FROM #PatientsAdmissionsPostTest AS t1
INNER JOIN (
SELECT cp.FK_Patient_Link_ID, MIN(los.AdmissionDate) AS NextAdmissionDate FROM #CovidPatientsMultipleDiagnoses cp
INNER JOIN #LengthOfStay los ON cp.FK_Patient_Link_ID = los.FK_Patient_Link_ID 
	AND los.AdmissionDate >= DATEADD(day, -2, FirstCovidPositiveDate) -- hospital AFTER COVID test
	AND (los.AdmissionDate < SecondCovidPositiveDate OR SecondCovidPositiveDate IS NULL) --hospital BEFORE next COVID test
GROUP BY cp.FK_Patient_Link_ID) AS sub ON sub.FK_Patient_Link_ID = t1.FK_Patient_Link_ID;

-- Find 1st hospital stay following 2nd COVID positive test (but before 3rd)
UPDATE t1
SET t1.[FirstAdmissionPost2ndCOVIDTest] = NextAdmissionDate
FROM #PatientsAdmissionsPostTest AS t1
INNER JOIN (
SELECT cp.FK_Patient_Link_ID, MIN(los.AdmissionDate) AS NextAdmissionDate FROM #CovidPatientsMultipleDiagnoses cp
INNER JOIN #LengthOfStay los ON cp.FK_Patient_Link_ID = los.FK_Patient_Link_ID 
	AND los.AdmissionDate >= DATEADD(day, -2, SecondCovidPositiveDate) -- hospital AFTER COVID test
	AND (los.AdmissionDate < ThirdCovidPositiveDate OR ThirdCovidPositiveDate IS NULL)  --hospital BEFORE next COVID test
GROUP BY cp.FK_Patient_Link_ID) AS sub ON sub.FK_Patient_Link_ID = t1.FK_Patient_Link_ID;

-- Find 1st hospital stay following 3rd COVID positive test (but before 4th)
UPDATE t1
SET t1.[FirstAdmissionPost3rdCOVIDTest] = NextAdmissionDate
FROM #PatientsAdmissionsPostTest AS t1
INNER JOIN (
SELECT cp.FK_Patient_Link_ID, MIN(los.AdmissionDate) AS NextAdmissionDate FROM #CovidPatientsMultipleDiagnoses cp
INNER JOIN #LengthOfStay los ON cp.FK_Patient_Link_ID = los.FK_Patient_Link_ID 
	AND los.AdmissionDate >= DATEADD(day, -2, ThirdCovidPositiveDate) -- hospital AFTER COVID test
	AND (los.AdmissionDate < FourthCovidPositiveDate OR FourthCovidPositiveDate IS NULL)  --hospital BEFORE next COVID test
GROUP BY cp.FK_Patient_Link_ID) AS sub ON sub.FK_Patient_Link_ID = t1.FK_Patient_Link_ID;

-- Find 1st hospital stay following 4th COVID positive test (but before 5th)
UPDATE t1
SET t1.[FirstAdmissionPost4thCOVIDTest] = NextAdmissionDate
FROM #PatientsAdmissionsPostTest AS t1
INNER JOIN (
SELECT cp.FK_Patient_Link_ID, MIN(los.AdmissionDate) AS NextAdmissionDate FROM #CovidPatientsMultipleDiagnoses cp
INNER JOIN #LengthOfStay los ON cp.FK_Patient_Link_ID = los.FK_Patient_Link_ID 
	AND los.AdmissionDate >= DATEADD(day, -2, FourthCovidPositiveDate) -- hospital AFTER COVID test
	AND (los.AdmissionDate < FifthCovidPositiveDate OR FifthCovidPositiveDate IS NULL)  --hospital BEFORE next COVID test
GROUP BY cp.FK_Patient_Link_ID) AS sub ON sub.FK_Patient_Link_ID = t1.FK_Patient_Link_ID;

-- Find 1st hospital stay following 5th COVID positive test
UPDATE t1
SET t1.[FirstAdmissionPost5thCOVIDTest] = NextAdmissionDate
FROM #PatientsAdmissionsPostTest AS t1
INNER JOIN (
SELECT cp.FK_Patient_Link_ID, MIN(los.AdmissionDate) AS NextAdmissionDate FROM #CovidPatientsMultipleDiagnoses cp
INNER JOIN #LengthOfStay los ON cp.FK_Patient_Link_ID = los.FK_Patient_Link_ID 
	AND los.AdmissionDate >= DATEADD(day, -2, FifthCovidPositiveDate) -- hospital AFTER COVID test
GROUP BY cp.FK_Patient_Link_ID) AS sub ON sub.FK_Patient_Link_ID = t1.FK_Patient_Link_ID;

-- Get length of stay for each admission just calculated
IF OBJECT_ID('tempdb..#PatientsLOSPostTest') IS NOT NULL DROP TABLE #PatientsLOSPostTest;
SELECT p.FK_Patient_Link_ID, 
		MAX(l1.LengthOfStay) AS LengthOfStayFirstAdmission1stCOVIDTest,
		MAX(l2.LengthOfStay) AS LengthOfStayFirstAdmission2ndCOVIDTest,
		MAX(l3.LengthOfStay) AS LengthOfStayFirstAdmission3rdCOVIDTest,
		MAX(l4.LengthOfStay) AS LengthOfStayFirstAdmission4thCOVIDTest,
		MAX(l5.LengthOfStay) AS LengthOfStayFirstAdmission5thCOVIDTest
INTO #PatientsLOSPostTest
FROM #PatientsAdmissionsPostTest p
	LEFT OUTER JOIN #LengthOfStay l1 ON p.FK_Patient_Link_ID = l1.FK_Patient_Link_ID AND p.[FirstAdmissionPost1stCOVIDTest] = l1.AdmissionDate
	LEFT OUTER JOIN #LengthOfStay l2 ON p.FK_Patient_Link_ID = l2.FK_Patient_Link_ID AND p.[FirstAdmissionPost2ndCOVIDTest] = l2.AdmissionDate
	LEFT OUTER JOIN #LengthOfStay l3 ON p.FK_Patient_Link_ID = l3.FK_Patient_Link_ID AND p.[FirstAdmissionPost3rdCOVIDTest] = l3.AdmissionDate
	LEFT OUTER JOIN #LengthOfStay l4 ON p.FK_Patient_Link_ID = l4.FK_Patient_Link_ID AND p.[FirstAdmissionPost4thCOVIDTest] = l4.AdmissionDate
	LEFT OUTER JOIN #LengthOfStay l5 ON p.FK_Patient_Link_ID = l5.FK_Patient_Link_ID AND p.[FirstAdmissionPost5thCOVIDTest] = l5.AdmissionDate
GROUP BY p.FK_Patient_Link_ID;

-- diagnoses
--> CODESET copd:1
IF OBJECT_ID('tempdb..#PatientDiagnosesCOPD') IS NOT NULL DROP TABLE #PatientDiagnosesCOPD;
SELECT DISTINCT FK_Patient_Link_ID
INTO #PatientDiagnosesCOPD
FROM #PatientEventData
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('copd') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('copd') AND [Version]=1))
)
AND EventDate < '2022-06-01'
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);

--> CODESET asthma:1
IF OBJECT_ID('tempdb..#PatientDiagnosesASTHMA') IS NOT NULL DROP TABLE #PatientDiagnosesASTHMA;
SELECT DISTINCT FK_Patient_Link_ID
INTO #PatientDiagnosesASTHMA
FROM #PatientEventData
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('asthma') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('asthma') AND [Version]=1))
)
AND EventDate < '2022-06-01'
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);

--> CODESET hypertension:1
IF OBJECT_ID('tempdb..#PatientDiagnosesHYPERTENSION') IS NOT NULL DROP TABLE #PatientDiagnosesHYPERTENSION;
SELECT DISTINCT FK_Patient_Link_ID
INTO #PatientDiagnosesHYPERTENSION
FROM #PatientEventData
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('hypertension') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('hypertension') AND [Version]=1))
)
AND EventDate < '2022-06-01'
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);

-- Get patient list of those with COVID death within 28 days of positive test
IF OBJECT_ID('tempdb..#COVIDDeath') IS NOT NULL DROP TABLE #COVIDDeath;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #COVIDDeath FROM SharedCare.COVID19
WHERE (
	(GroupDescription = 'Confirmed' AND SubGroupDescription != 'Negative') OR
	(GroupDescription = 'Tested' AND SubGroupDescription = 'Positive')
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND DATEDIFF(day,EventDate,DeathDate) <= 28
AND EventDate < '2022-06-01';

-- Get first dementia diagnosis date
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:dementia version:1 temp-table-name:#PatientDiagnosisDementia

-- Bring together for final output
SELECT 
  m.FK_Patient_Link_ID AS PatientId,
  yob.YearOfBirth,
  CASE WHEN pl.DeathDate < '2022-06-01' THEN pl.DeathDate ELSE NULL END AS DeathDate,
  CASE WHEN covidDeath.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS DeathWithin28DaysCovidPositiveTest,
  frail.FrailtyScore,
  sex.Sex,
  lsoa.LSOA_Code AS LSOA,
  pl.EthnicCategoryDescription,
  town.TownsendScoreHigherIsMoreDeprived,
  town.TownsendQuintileHigherIsMoreDeprived,
  bad.FirstBipolarDate,
  badhist.FirstBipolarHistoryCode,
  fep.FirstPsychosisSchizophreniaDate, 
  fephist.FirstPsychosisSchizophreniaHistoryCode,
  dementia.DateOfFirstDiagnosis AS FirstDementiaDiagnosisDate,
  anti.FirstAntipsycoticDate,
  cov.FirstCovidPositiveDate,
  cov.SecondCovidPositiveDate,
  cov.ThirdCovidPositiveDate,
  cov.FourthCovidPositiveDate,
  cov.FifthCovidPositiveDate,
  admit.FirstAdmissionPost1stCOVIDTest,
  los.LengthOfStayFirstAdmission1stCOVIDTest,
  admit.FirstAdmissionPost2ndCOVIDTest,
  los.LengthOfStayFirstAdmission2ndCOVIDTest,
  admit.FirstAdmissionPost3rdCOVIDTest,
  los.LengthOfStayFirstAdmission3rdCOVIDTest,
  admit.FirstAdmissionPost4thCOVIDTest,
  los.LengthOfStayFirstAdmission4thCOVIDTest,
  admit.FirstAdmissionPost5thCOVIDTest,
  los.LengthOfStayFirstAdmission5thCOVIDTest,
  smok.PassiveSmoker AS IsPassiveSmoker,
  smok.WorstSmokingStatus,
  smok.CurrentSmokingStatus,
  CASE WHEN copd.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PatientHasCOPD,
  CASE WHEN asthma.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PatientHasASTHMA,
  CASE WHEN htn.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PatientHasHYPERTENSION,
  vacc.VaccineDose1Date AS FirstVaccineDate,
  vacc.VaccineDose2Date AS SecondVaccineDate,
  vacc.VaccineDose3Date AS ThirdVaccineDate,
  vacc.VaccineDose4Date AS FourthVaccineDate,
  vacc.VaccineDose5Date AS FifthVaccineDate,
  vacc.VaccineDose6Date AS SixthVaccineDate
FROM #Patients m
LEFT OUTER JOIN #BipolarPatients bad ON bad.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #BipolarHistoryPatients badhist ON badhist.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PsychosisSchizoPatients fep ON fep.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PsychSchizoHistoryPatients fephist ON fephist.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #AntipsycoticPatients anti ON anti.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN SharedCare.Patient_Link pl ON pl.PK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientLSOA lsoa ON lsoa.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientFrailtyScore frail ON frail.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientTownsend town ON town.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosesCOPD copd ON copd.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosesASTHMA asthma ON asthma.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosesHYPERTENSION htn ON htn.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSmokingStatus smok ON smok.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDDeath covidDeath ON covidDeath.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDVaccinations vacc ON vacc.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #CovidPatientsMultipleDiagnoses cov ON cov.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientsAdmissionsPostTest admit ON admit.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientsLOSPostTest los ON los.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosisDementia dementia ON dementia.FK_Patient_Link_ID = m.FK_Patient_Link_ID;