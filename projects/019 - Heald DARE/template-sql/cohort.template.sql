--┌────────────────────────────────┐
--│ Diabetes and COVID cohort file │
--└────────────────────────────────┘

------------------------ RDE CHECK ---------------------
-- George Tilston  - 16 March 2022 - via pull request --
--------------------------------------------------------

-- Cohort is patients included in the DARE study. The below queries produce the data
-- that is required for each patient. However, a filter needs to be applied to only
-- provide this data for patients in the DARE study. Adrian Heald will provide GraphNet
-- with a list of NHS numbers, then they will execute the below but filtered to the list
-- of NHS numbers.

-- We assume that a temporary table will exist as follows:
-- CREATE TABLE #DAREPatients (NhsNo NVARCHAR(30));

-- DEMOGRAPHIC
-- PatientId, YearOfBirth, DeathDate, DeathWithin28Days, Frailty,
-- Sex, LSOA, EthnicCategoryDescription, TownsendScoreHigherIsMoreDeprived, TownsendQuintileHigherIsMoreDeprived,
-- COHORT SPECIFIC
-- FirstDiagnosisDate, FirstT1DiagnosisDate, FirstT2DiagnosisDate, 1stCOVIDPositiveTestDate, 2ndCOVIDPositiveTestDate,
-- 3rdCOVIDPositiveTestDate, 4thCOVIDPositiveTestDate, 5thCOVIDPositiveTestDate,
-- 1stAdmissionPost1stCOVIDTest, LengthOfStay1stAdmission1stCOVIDTest, 1stAdmissionPost2ndCOVIDTest, LengthOfStay1stAdmission2ndCOVIDTest,
-- 1stAdmissionPost3rdCOVIDTest, LengthOfStay1stAdmission3rdCOVIDTest, 1stAdmissionPost4thCOVIDTest, LengthOfStay1stAdmission4thCOVIDTest,
-- 1stAdmissionPost5thCOVIDTest, LengthOfStay1stAdmission5thCOVIDTest, 
-- DateOf1stVaccine, DateOf2ndVaccine, DateOf3rdVaccine, DateOf4thVaccine, DateOf5thVaccine, DateOf6thVaccine,
-- PATIENT STATUS
-- IsPassiveSmoker, WorstSmokingStatus, CurrentSmokingStatus
-- DIAGNOSES
-- PatientHasCOPD, PatientHasASTHMA, PatientHasSMI, PatientHasHYPERTENSION
-- MEDICATIONS
-- IsOnACEIorARB, IsOnAspirin, IsOnClopidogrel, IsOnMetformin, IsOnInsulin, 
-- IsOnSGLTI, IsOnGLP1A, IsOnSulphonylurea

--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2020-01-01';

-- Only need medications if in 6 months prior to COVID test
DECLARE @MedicationsFromDate datetime;
SET @MedicationsFromDate = DATEADD(month, -6, @StartDate);

-- Define #Patients temp table for getting future things like age/sex etc.
-- NB this is where the filter to just DARE patients via NHS number occurs
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT p.FK_Patient_Link_ID INTO #Patients
FROM [RLS].vw_Patient p
INNER JOIN #DAREPatients dp ON dp.NhsNo = p.NhsNo;

--Below is for testing without access to DARE nhs numbers
--IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
--SELECT TOP 200 FK_Patient_Link_ID INTO #Patients
--FROM [RLS].vw_Patient p
--GROUP BY FK_Patient_Link_ID;

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
FROM [RLS].vw_GP_Events
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);

IF OBJECT_ID('tempdb..#PatientMedicationData') IS NOT NULL DROP TABLE #PatientMedicationData;
SELECT 
  FK_Patient_Link_ID,
  CAST(MedicationDate AS DATE) AS MedicationDate,
  SuppliedCode,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID
INTO #PatientMedicationData
FROM [RLS].vw_GP_Medications
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);

-- First get all the diabetic (type 1/type 2/other) patients and the date of first diagnosis
--> CODESET diabetes:1
IF OBJECT_ID('tempdb..#DiabeticPatients') IS NOT NULL DROP TABLE #DiabeticPatients;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS FirstDiagnosisDate INTO #DiabeticPatients
FROM #PatientEventData
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('diabetes') AND [Version]=1) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('diabetes') AND [Version]=1)
)
GROUP BY FK_Patient_Link_ID;

-- Get separate cohorts for paients with type 1 diabetes and type 2 diabetes
--> CODESET diabetes-type-i:1
IF OBJECT_ID('tempdb..#DiabeticTypeIPatients') IS NOT NULL DROP TABLE #DiabeticTypeIPatients;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS FirstT1DiagnosisDate INTO #DiabeticTypeIPatients
FROM #PatientEventData
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('diabetes-type-i') AND [Version]=1) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('diabetes-type-i') AND [Version]=1)
)
GROUP BY FK_Patient_Link_ID;

--> CODESET diabetes-type-ii:1
IF OBJECT_ID('tempdb..#DiabeticTypeIIPatients') IS NOT NULL DROP TABLE #DiabeticTypeIIPatients;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS FirstT2DiagnosisDate INTO #DiabeticTypeIIPatients
FROM #PatientEventData
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('diabetes-type-ii') AND [Version]=1) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('diabetes-type-ii') AND [Version]=1)
)
GROUP BY FK_Patient_Link_ID;

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
  [1stAdmissionPost1stCOVIDTest] DATE,
  [1stAdmissionPost2ndCOVIDTest] DATE,
  [1stAdmissionPost3rdCOVIDTest] DATE,
  [1stAdmissionPost4thCOVIDTest] DATE,
  [1stAdmissionPost5thCOVIDTest] DATE
);

-- Populate table with patient IDs
INSERT INTO #PatientsAdmissionsPostTest (FK_Patient_Link_ID)
SELECT FK_Patient_Link_ID FROM #CovidPatientsMultipleDiagnoses;

-- Find 1st hospital stay following 1st COVID positive test (but before 2nd)
UPDATE t1
SET t1.[1stAdmissionPost1stCOVIDTest] = NextAdmissionDate
FROM #PatientsAdmissionsPostTest AS t1
INNER JOIN (
SELECT cp.FK_Patient_Link_ID, MIN(los.AdmissionDate) AS NextAdmissionDate FROM #CovidPatientsMultipleDiagnoses cp
INNER JOIN #LengthOfStay los ON cp.FK_Patient_Link_ID = los.FK_Patient_Link_ID 
	AND los.AdmissionDate >= DATEADD(day, -2, FirstCovidPositiveDate) -- hospital AFTER COVID test
	AND (los.AdmissionDate < SecondCovidPositiveDate OR SecondCovidPositiveDate IS NULL) --hospital BEFORE next COVID test
GROUP BY cp.FK_Patient_Link_ID) AS sub ON sub.FK_Patient_Link_ID = t1.FK_Patient_Link_ID;

-- Find 1st hospital stay following 2nd COVID positive test (but before 3rd)
UPDATE t1
SET t1.[1stAdmissionPost2ndCOVIDTest] = NextAdmissionDate
FROM #PatientsAdmissionsPostTest AS t1
INNER JOIN (
SELECT cp.FK_Patient_Link_ID, MIN(los.AdmissionDate) AS NextAdmissionDate FROM #CovidPatientsMultipleDiagnoses cp
INNER JOIN #LengthOfStay los ON cp.FK_Patient_Link_ID = los.FK_Patient_Link_ID 
	AND los.AdmissionDate >= DATEADD(day, -2, SecondCovidPositiveDate) -- hospital AFTER COVID test
	AND (los.AdmissionDate < ThirdCovidPositiveDate OR ThirdCovidPositiveDate IS NULL)  --hospital BEFORE next COVID test
GROUP BY cp.FK_Patient_Link_ID) AS sub ON sub.FK_Patient_Link_ID = t1.FK_Patient_Link_ID;

-- Find 1st hospital stay following 3rd COVID positive test (but before 4th)
UPDATE t1
SET t1.[1stAdmissionPost3rdCOVIDTest] = NextAdmissionDate
FROM #PatientsAdmissionsPostTest AS t1
INNER JOIN (
SELECT cp.FK_Patient_Link_ID, MIN(los.AdmissionDate) AS NextAdmissionDate FROM #CovidPatientsMultipleDiagnoses cp
INNER JOIN #LengthOfStay los ON cp.FK_Patient_Link_ID = los.FK_Patient_Link_ID 
	AND los.AdmissionDate >= DATEADD(day, -2, ThirdCovidPositiveDate) -- hospital AFTER COVID test
	AND (los.AdmissionDate < FourthCovidPositiveDate OR FourthCovidPositiveDate IS NULL)  --hospital BEFORE next COVID test
GROUP BY cp.FK_Patient_Link_ID) AS sub ON sub.FK_Patient_Link_ID = t1.FK_Patient_Link_ID;

-- Find 1st hospital stay following 4th COVID positive test (but before 5th)
UPDATE t1
SET t1.[1stAdmissionPost4thCOVIDTest] = NextAdmissionDate
FROM #PatientsAdmissionsPostTest AS t1
INNER JOIN (
SELECT cp.FK_Patient_Link_ID, MIN(los.AdmissionDate) AS NextAdmissionDate FROM #CovidPatientsMultipleDiagnoses cp
INNER JOIN #LengthOfStay los ON cp.FK_Patient_Link_ID = los.FK_Patient_Link_ID 
	AND los.AdmissionDate >= DATEADD(day, -2, FourthCovidPositiveDate) -- hospital AFTER COVID test
	AND (los.AdmissionDate < FifthCovidPositiveDate OR FifthCovidPositiveDate IS NULL)  --hospital BEFORE next COVID test
GROUP BY cp.FK_Patient_Link_ID) AS sub ON sub.FK_Patient_Link_ID = t1.FK_Patient_Link_ID;

-- Find 1st hospital stay following 5th COVID positive test
UPDATE t1
SET t1.[1stAdmissionPost5thCOVIDTest] = NextAdmissionDate
FROM #PatientsAdmissionsPostTest AS t1
INNER JOIN (
SELECT cp.FK_Patient_Link_ID, MIN(los.AdmissionDate) AS NextAdmissionDate FROM #CovidPatientsMultipleDiagnoses cp
INNER JOIN #LengthOfStay los ON cp.FK_Patient_Link_ID = los.FK_Patient_Link_ID 
	AND los.AdmissionDate >= DATEADD(day, -2, FifthCovidPositiveDate) -- hospital AFTER COVID test
GROUP BY cp.FK_Patient_Link_ID) AS sub ON sub.FK_Patient_Link_ID = t1.FK_Patient_Link_ID;

-- Get length of stay for each admission just calculated
IF OBJECT_ID('tempdb..#PatientsLOSPostTest') IS NOT NULL DROP TABLE #PatientsLOSPostTest;
SELECT p.FK_Patient_Link_ID, 
		MAX(l1.LengthOfStay) AS LengthOfStay1stAdmission1stCOVIDTest,
		MAX(l2.LengthOfStay) AS LengthOfStay1stAdmission2ndCOVIDTest,
		MAX(l3.LengthOfStay) AS LengthOfStay1stAdmission3rdCOVIDTest,
		MAX(l4.LengthOfStay) AS LengthOfStay1stAdmission4thCOVIDTest,
		MAX(l5.LengthOfStay) AS LengthOfStay1stAdmission5thCOVIDTest
INTO #PatientsLOSPostTest
FROM #PatientsAdmissionsPostTest p
	LEFT OUTER JOIN #LengthOfStay l1 ON p.FK_Patient_Link_ID = l1.FK_Patient_Link_ID AND p.[1stAdmissionPost1stCOVIDTest] = l1.AdmissionDate
	LEFT OUTER JOIN #LengthOfStay l2 ON p.FK_Patient_Link_ID = l2.FK_Patient_Link_ID AND p.[1stAdmissionPost2ndCOVIDTest] = l2.AdmissionDate
	LEFT OUTER JOIN #LengthOfStay l3 ON p.FK_Patient_Link_ID = l3.FK_Patient_Link_ID AND p.[1stAdmissionPost3rdCOVIDTest] = l3.AdmissionDate
	LEFT OUTER JOIN #LengthOfStay l4 ON p.FK_Patient_Link_ID = l4.FK_Patient_Link_ID AND p.[1stAdmissionPost4thCOVIDTest] = l4.AdmissionDate
	LEFT OUTER JOIN #LengthOfStay l5 ON p.FK_Patient_Link_ID = l5.FK_Patient_Link_ID AND p.[1stAdmissionPost5thCOVIDTest] = l5.AdmissionDate
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
);

--> CODESET asthma:1
IF OBJECT_ID('tempdb..#PatientDiagnosesASTHMA') IS NOT NULL DROP TABLE #PatientDiagnosesASTHMA;
SELECT DISTINCT FK_Patient_Link_ID
INTO #PatientDiagnosesASTHMA
FROM #PatientEventData
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('asthma') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('asthma') AND [Version]=1))
);

--> CODESET severe-mental-illness:1
IF OBJECT_ID('tempdb..#PatientDiagnosesSEVEREMENTALILLNESS') IS NOT NULL DROP TABLE #PatientDiagnosesSEVEREMENTALILLNESS;
SELECT DISTINCT FK_Patient_Link_ID
INTO #PatientDiagnosesSEVEREMENTALILLNESS
FROM #PatientEventData
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('severe-mental-illness') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('severe-mental-illness') AND [Version]=1))
);

--> CODESET hypertension:1
IF OBJECT_ID('tempdb..#PatientDiagnosesHYPERTENSION') IS NOT NULL DROP TABLE #PatientDiagnosesHYPERTENSION;
SELECT DISTINCT FK_Patient_Link_ID
INTO #PatientDiagnosesHYPERTENSION
FROM #PatientEventData
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('hypertension') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('hypertension') AND [Version]=1))
);


-- medications
--> CODESET metformin:1
IF OBJECT_ID('tempdb..#PatientMedicationsMETFORMIN') IS NOT NULL DROP TABLE #PatientMedicationsMETFORMIN;
SELECT DISTINCT	FK_Patient_Link_ID
INTO #PatientMedicationsMETFORMIN
FROM #PatientMedicationData
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('metformin') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('metformin') AND [Version]=1))
)
AND MedicationDate > @MedicationsFromDate;

--> CODESET glp1-receptor-agonists:1
IF OBJECT_ID('tempdb..#PatientMedicationsGLP1') IS NOT NULL DROP TABLE #PatientMedicationsGLP1;
SELECT DISTINCT	FK_Patient_Link_ID
INTO #PatientMedicationsGLP1
FROM #PatientMedicationData
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('glp1-receptor-agonists') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('glp1-receptor-agonists') AND [Version]=1))
)
AND MedicationDate > @MedicationsFromDate;

--> CODESET insulin:1
IF OBJECT_ID('tempdb..#PatientMedicationsINSULIN') IS NOT NULL DROP TABLE #PatientMedicationsINSULIN;
SELECT DISTINCT	FK_Patient_Link_ID
INTO #PatientMedicationsINSULIN
FROM #PatientMedicationData
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('insulin') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('insulin') AND [Version]=1))
)
AND MedicationDate > @MedicationsFromDate;

--> CODESET sglt2-inhibitors:1
IF OBJECT_ID('tempdb..#PatientMedicationsSGLT2I') IS NOT NULL DROP TABLE #PatientMedicationsSGLT2I;
SELECT DISTINCT	FK_Patient_Link_ID
INTO #PatientMedicationsSGLT2I
FROM #PatientMedicationData
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('sglt2-inhibitors') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('sglt2-inhibitors') AND [Version]=1))
)
AND MedicationDate > @MedicationsFromDate;

--> CODESET sulphonylureas:1
IF OBJECT_ID('tempdb..#PatientMedicationsSULPHONYLUREAS') IS NOT NULL DROP TABLE #PatientMedicationsSULPHONYLUREAS;
SELECT DISTINCT	FK_Patient_Link_ID
INTO #PatientMedicationsSULPHONYLUREAS
FROM #PatientMedicationData
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('sulphonylureas') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('sulphonylureas') AND [Version]=1))
)
AND MedicationDate > @MedicationsFromDate;

--> CODESET ace-inhibitor:1
IF OBJECT_ID('tempdb..#PatientMedicationsACEI') IS NOT NULL DROP TABLE #PatientMedicationsACEI;
SELECT DISTINCT	FK_Patient_Link_ID
INTO #PatientMedicationsACEI
FROM #PatientMedicationData
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('ace-inhibitor') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('ace-inhibitor') AND [Version]=1))
)
AND MedicationDate > @MedicationsFromDate;

--> CODESET aspirin:1
IF OBJECT_ID('tempdb..#PatientMedicationsASPIRIN') IS NOT NULL DROP TABLE #PatientMedicationsASPIRIN;
SELECT DISTINCT	FK_Patient_Link_ID
INTO #PatientMedicationsASPIRIN
FROM #PatientMedicationData
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('aspirin') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('aspirin') AND [Version]=1))
)
AND MedicationDate > @MedicationsFromDate;

--> CODESET clopidogrel:1
IF OBJECT_ID('tempdb..#PatientMedicationsCLOPIDOGREL') IS NOT NULL DROP TABLE #PatientMedicationsCLOPIDOGREL;
SELECT DISTINCT	FK_Patient_Link_ID
INTO #PatientMedicationsCLOPIDOGREL
FROM #PatientMedicationData
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('clopidogrel') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('clopidogrel') AND [Version]=1))
)
AND MedicationDate > @MedicationsFromDate;

-- collate on meds
IF OBJECT_ID('tempdb..#PatientMedications') IS NOT NULL DROP TABLE #PatientMedications;
SELECT 
  p.FK_Patient_Link_ID,
  CASE WHEN acei.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS IsOnACEIorARB,
  CASE WHEN aspirin.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS IsOnAspirin,
  CASE WHEN clop.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS IsOnClopidogrel,
  CASE WHEN insu.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS IsOnInsulin,
  CASE WHEN sglt.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS IsOnSGLTI,
  CASE WHEN glp1.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS IsOnGLP1A,
  CASE WHEN sulp.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS IsOnSulphonylurea,
  CASE WHEN met.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS IsOnMetformin
INTO #PatientMedications
FROM #Patients p
LEFT OUTER JOIN #PatientMedicationsACEI acei ON acei.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientMedicationsASPIRIN aspirin ON aspirin.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientMedicationsCLOPIDOGREL clop ON clop.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientMedicationsMETFORMIN met ON met.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientMedicationsGLP1 glp1 ON glp1.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientMedicationsINSULIN insu ON insu.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientMedicationsSGLT2I sglt ON sglt.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientMedicationsSULPHONYLUREAS sulp ON sulp.FK_Patient_Link_ID = p.FK_Patient_Link_ID;
  
-- Get patient list of those with COVID death within 28 days of positive test
IF OBJECT_ID('tempdb..#COVIDDeath') IS NOT NULL DROP TABLE #COVIDDeath;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #COVIDDeath FROM RLS.vw_COVID19
WHERE DeathWithin28Days = 'Y'
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);

-- Bring together for final output
SELECT 
  m.FK_Patient_Link_ID AS PatientId,
  YearOfBirth,
  DeathDate,
  CASE WHEN covidDeath.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS DeathWithin28DaysCovidPositiveTest,
  FrailtyScore,
  Sex,
  LSOA_Code AS LSOA,
  EthnicCategoryDescription,
  TownsendScoreHigherIsMoreDeprived,
  TownsendQuintileHigherIsMoreDeprived,
  FirstDiagnosisDate,
  FirstT1DiagnosisDate,
  FirstT2DiagnosisDate,
  FirstCovidPositiveDate,
  SecondCovidPositiveDate,
  ThirdCovidPositiveDate,
  FourthCovidPositiveDate,
  FifthCovidPositiveDate,
  1stAdmissionPost1stCOVIDTest,
  LengthOfStay1stAdmission1stCOVIDTest,
  1stAdmissionPost2ndCOVIDTest,
  LengthOfStay1stAdmission2ndCOVIDTest,
  1stAdmissionPost3rdCOVIDTest,
  LengthOfStay1stAdmission3rdCOVIDTest,
  1stAdmissionPost4thCOVIDTest,
  LengthOfStay1stAdmission4thCOVIDTest,
  1stAdmissionPost5thCOVIDTest,
  LengthOfStay1stAdmission5thCOVIDTest,
  smok.PassiveSmoker AS IsPassiveSmoker,
  smok.WorstSmokingStatus,
  smok.CurrentSmokingStatus,
  CASE WHEN copd.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PatientHasCOPD,
  CASE WHEN asthma.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PatientHasASTHMA,
  CASE WHEN smi.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PatientHasSMI,
  IsOnACEIorARB,
  IsOnAspirin,
  IsOnClopidogrel,
  IsOnMetformin,
  CASE WHEN htn.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PatientHasHYPERTENSION,
  VaccineDose1Date AS FirstVaccineDate,
  VaccineDose2Date AS SecondVaccineDate,
  IsOnInsulin,
  IsOnSGLTI,
  IsOnGLP1A,
  IsOnSulphonylurea
FROM #Patients m
LEFT OUTER JOIN RLS.vw_Patient_Link pl ON pl.PK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientLSOA lsoa ON lsoa.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientFrailtyScore frail ON frail.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #DiabeticPatients dm ON dm.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #DiabeticTypeIPatients t1 ON t1.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #DiabeticTypeIIPatients t2 ON t2.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientTownsend town ON town.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosesCOPD copd ON copd.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosesASTHMA asthma ON asthma.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosesSEVEREMENTALILLNESS smi ON smi.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosesHYPERTENSION htn ON htn.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientMedications pm ON pm.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSmokingStatus smok ON smok.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDDeath covidDeath ON covidDeath.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDVaccinations v ON v.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #CovidPatientsMultipleDiagnoses cov ON cov.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientsAdmissionsPostTest admit ON admit.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientsLOSPostTest los ON los.FK_Patient_Link_ID = m.FK_Patient_Link_ID;