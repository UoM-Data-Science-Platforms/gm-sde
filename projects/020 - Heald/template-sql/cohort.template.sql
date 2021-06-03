--┌────────────────────────────────┐
--│ Diabetes and COVID cohort file │
--└────────────────────────────────┘

------------------------ RDE CHECK -------------------------
-- RDE NAME: GEORGE TILSTON, DATE OF CHECK: 11/05/21 -------
------------------------------------------------------------

-- Cohort is diabetic patients with a positive covid test. Also a 1:5 matched cohort, 
-- matched on year of birth (+-5 years), sex, and date of positive covid test (+-14 days).
-- For each we provide the following:

-- DEMOGRAPHIC
-- PatientId, MainCohortMatchedPatientId (NULL if patient in main cohort), YearOfBirth, DeathDate,
-- Sex, LSOA, EthnicCategoryDescription, TownsendScoreHigherIsMoreDeprived, TownsendQuintileHigherIsMoreDeprived,
-- COHORT SPECIFIC
-- FirstDiagnosisDate, FirstT1DiagnosisDate, FirstT2DiagnosisDate, COVIDPositiveTestDate, FirstAdmissionPostCOVIDTest, LengthOfStay,
-- BIOMARKERS
-- LatestBMIValue, LatestHBA1CValue, LatestCHOLESTEROLValue, LatestLDLValue, LatestHDLValue,
-- LatestVITAMINDValue, LatestTESTOSTERONEValue, LatestSHBGValue
-- PATIENT STATUS
-- IsPassiveSmoker, WorstSmokingStatus, CurrentSmokingStatus
-- DIAGNOSES
-- PatientHasCOPD, PatientHasASTHMA, PatientHasSMI
-- MEDICATIONS
-- IsOnACEI, IsOnAspirin, IsOnClopidogrel, IsOnMetformin

--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2020-01-01';

-- Only need medications if in 6 months prior to COVID test
DECLARE @MedicationsFromDate datetime;
SET @MedicationsFromDate = DATEADD(month, -6, @StartDate);

-- Only need bp/bmi etc if in 2 years prior to COVID test
DECLARE @EventsFromDate datetime;
SET @EventsFromDate = DATEADD(year, -2, @StartDate);

-- First get all the diabetic (type 1/type 2/other) patients and the date of first diagnosis
--> CODESET diabetes
IF OBJECT_ID('tempdb..#DiabeticPatients') IS NOT NULL DROP TABLE #DiabeticPatients;
SELECT FK_Patient_Link_ID, MIN(CAST(EventDate AS DATE)) AS FirstDiagnosisDate INTO #DiabeticPatients
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('diabetes') AND [Version]=1) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('diabetes') AND [Version]=1)
)
GROUP BY FK_Patient_Link_ID;

-- Get separate cohorts for paients with type 1 diabetes and type 2 diabetes
--> CODESET diabetes-type-i
IF OBJECT_ID('tempdb..#DiabeticTypeIPatients') IS NOT NULL DROP TABLE #DiabeticTypeIPatients;
SELECT FK_Patient_Link_ID, MIN(CAST(EventDate AS DATE)) AS FirstT1DiagnosisDate INTO #DiabeticTypeIPatients
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('diabetes-type-i') AND [Version]=1) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('diabetes-type-i') AND [Version]=1)
)
GROUP BY FK_Patient_Link_ID;

--> CODESET diabetes-type-ii
IF OBJECT_ID('tempdb..#DiabeticTypeIIPatients') IS NOT NULL DROP TABLE #DiabeticTypeIIPatients;
SELECT FK_Patient_Link_ID, MIN(CAST(EventDate AS DATE)) AS FirstT2DiagnosisDate INTO #DiabeticTypeIIPatients
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('diabetes-type-ii') AND [Version]=1) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('diabetes-type-ii') AND [Version]=1)
)
GROUP BY FK_Patient_Link_ID;

-- Then get all the positive covid test patients
IF OBJECT_ID('tempdb..#CovidPatients') IS NOT NULL DROP TABLE #CovidPatients;
SELECT FK_Patient_Link_ID, MIN(CONVERT(DATE, [EventDate])) AS FirstCovidPositiveDate INTO #CovidPatients
FROM [RLS].[vw_COVID19]
WHERE GroupDescription = 'Confirmed'
AND EventDate > @StartDate
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

-- Define #Patients temp table for getting future things like age/sex etc.
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT FK_Patient_Link_ID INTO #Patients
FROM #CovidPatients;

--> EXECUTE query-patient-smoking-status.sql
--> EXECUTE query-patient-year-of-birth.sql
--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-lsoa.sql
--> EXECUTE query-patient-townsend.sql

-- Define the main cohort that will be matched
IF OBJECT_ID('tempdb..#MainCohort') IS NOT NULL DROP TABLE #MainCohort;
SELECT 
  c.FK_Patient_Link_ID,
  FirstCovidPositiveDate AS IndexDate,
  FirstDiagnosisDate,
  FirstT1DiagnosisDate,
  FirstT2DiagnosisDate,
  Sex,
  YearOfBirth,
  LSOA_Code
INTO #MainCohort
FROM #CovidPatients c
LEFT OUTER JOIN #PatientLSOA lsoa ON lsoa.FK_Patient_Link_ID = c.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = c.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = c.FK_Patient_Link_ID
LEFT OUTER JOIN #DiabeticPatients dm ON dm.FK_Patient_Link_ID = c.FK_Patient_Link_ID
LEFT OUTER JOIN #DiabeticTypeIPatients t1 ON t1.FK_Patient_Link_ID = c.FK_Patient_Link_ID
LEFT OUTER JOIN #DiabeticTypeIIPatients t2 ON t2.FK_Patient_Link_ID = c.FK_Patient_Link_ID
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
SELECT FK_Patient_Link_ID, IndexDate, Sex, YearOfBirth FROM #MainCohort;
-- 88197

--> EXECUTE query-cohort-matching-yob-sex-index-date.sql index-date-flex:14 yob-flex:5

-- Get the matched cohort detail - same as main cohort
IF OBJECT_ID('tempdb..#MatchedCohort') IS NOT NULL DROP TABLE #MatchedCohort;
SELECT 
  c.MatchingPatientId AS FK_Patient_Link_ID,
  MatchingCovidPositiveDate AS IndexDate,
  Sex,
  MatchingYearOfBirth,
  LSOA_Code,
  PatientId AS PatientWhoIsMatched
INTO #MatchedCohort
FROM #CohortStore c
LEFT OUTER JOIN #PatientLSOA lsoa ON lsoa.FK_Patient_Link_ID = c.MatchingPatientId
WHERE c.PatientId IN (SELECT FK_Patient_Link_ID FROM #DiabeticPatients);

-- Define a table with all the patient ids and index dates for the main cohort and the matched cohort
IF OBJECT_ID('tempdb..#PatientIdsAndIndexDates') IS NOT NULL DROP TABLE #PatientIdsAndIndexDates;
SELECT PatientId AS FK_Patient_Link_ID, IndexDate INTO #PatientIdsAndIndexDates FROM #CohortStore
UNION
SELECT MatchingPatientId, MatchingCovidPositiveDate FROM #CohortStore;

--> EXECUTE query-get-admissions-and-length-of-stay.sql

-- For each patient find the first hospital admission following their positive covid test
IF OBJECT_ID('tempdb..#PatientsFirstAdmissionPostTest') IS NOT NULL DROP TABLE #PatientsFirstAdmissionPostTest;
SELECT l.FK_Patient_Link_ID, MAX(l.AdmissionDate) AS FirstAdmissionPostCOVIDTest, MAX(LengthOfStay) AS LengthOfStay
INTO #PatientsFirstAdmissionPostTest
FROM #LengthOfStay l
INNER JOIN (
  SELECT p.FK_Patient_Link_ID, MIN(AdmissionDate) AS FirstAdmission
  FROM #PatientIdsAndIndexDates p
  LEFT OUTER JOIN #LengthOfStay los
    ON los.FK_Patient_Link_ID = p.FK_Patient_Link_ID
    AND los.AdmissionDate >= p.IndexDate
  GROUP BY p.FK_Patient_Link_ID
) sub ON sub.FK_Patient_Link_ID = l.FK_Patient_Link_ID AND sub.FirstAdmission = l.AdmissionDate
GROUP BY l.FK_Patient_Link_ID;

--> CODESET bmi hba1c cholesterol ldl-cholesterol hdl-cholesterol vitamin-d testosterone sex-hormone-binding-globulin
IF OBJECT_ID('tempdb..#PatientValuesWithIds') IS NOT NULL DROP TABLE #PatientValuesWithIds;
SELECT 
	FK_Patient_Link_ID,
	CAST(EventDate AS DATE) AS EventDate,
  FK_Reference_Coding_ID,
  FK_Reference_SnomedCT_ID,
	[Value]
INTO #PatientValuesWithIds
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (
    SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (
      Concept IN ('bmi') AND [Version]=2 OR
      Concept IN ('hba1c') AND [Version]=2 OR
      Concept IN ('cholesterol') AND [Version]=2 OR
      Concept IN ('ldl-cholesterol') AND [Version]=1 OR
      Concept IN ('hdl-cholesterol') AND [Version]=1 OR
      Concept IN ('vitamin-d') AND [Version]=1 OR
      Concept IN ('testosterone') AND [Version]=1 OR
      Concept IN ('sex-hormone-binding-globulin') AND [Version]=1
    )
  ) OR
  FK_Reference_Coding_ID IN (
    SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (
      Concept IN ('bmi') AND [Version]=2 OR
      Concept IN ('hba1c') AND [Version]=2 OR
      Concept IN ('cholesterol') AND [Version]=2 OR
      Concept IN ('ldl-cholesterol') AND [Version]=1 OR
      Concept IN ('hdl-cholesterol') AND [Version]=1 OR
      Concept IN ('vitamin-d') AND [Version]=1 OR
      Concept IN ('testosterone') AND [Version]=1 OR
      Concept IN ('sex-hormone-binding-globulin') AND [Version]=1
    )
  )
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate > @EventsFromDate
AND [Value] IS NOT NULL
AND [Value] != '0';

IF OBJECT_ID('tempdb..#PatientValuesWithNames') IS NOT NULL DROP TABLE #PatientValuesWithNames;
SELECT 
	FK_Patient_Link_ID,
	EventDate,
  CASE WHEN c.Concept IS NULL THEN s.Concept ELSE c.Concept END AS Concept,
	[Value]
INTO #PatientValuesWithNames
FROM #PatientValuesWithIds p
LEFT OUTER JOIN #VersionedCodeSets c on c.FK_Reference_Coding_ID = p.FK_Reference_Coding_ID
LEFT OUTER JOIN #VersionedSnomedSets s on s.FK_Reference_SnomedCT_ID = p.FK_Reference_SnomedCT_ID;

-- get most recent value at in the period [index date - 2 years, index date]
IF OBJECT_ID('tempdb..#PatientValues') IS NOT NULL DROP TABLE #PatientValues;
SELECT main.FK_Patient_Link_ID, main.Concept, MAX(main.[Value]) AS LatestValue
INTO #PatientValues
FROM #PatientValuesWithNames main
INNER JOIN (
  SELECT p.FK_Patient_Link_ID, Concept, MAX(EventDate) AS LatestDate FROM #PatientValuesWithNames pv
  INNER JOIN #PatientIdsAndIndexDates p 
    ON p.FK_Patient_Link_ID = pv.FK_Patient_Link_ID
    AND pv.EventDate <= p.IndexDate
    AND pv.EventDate >= DATEADD(year, -2, p.IndexDate)
  GROUP BY p.FK_Patient_Link_ID, Concept
) sub on sub.FK_Patient_Link_ID = main.FK_Patient_Link_ID and sub.LatestDate = main.EventDate and sub.Concept = main.Concept
GROUP BY main.FK_Patient_Link_ID, main.Concept;

IF OBJECT_ID('tempdb..#PatientValuesBMI') IS NOT NULL DROP TABLE #PatientValuesBMI;
SELECT FK_Patient_Link_ID, LatestValue AS LatestBMIValue INTO #PatientValuesBMI
FROM #PatientValues
WHERE Concept = 'bmi';

IF OBJECT_ID('tempdb..#PatientValuesHBA1C') IS NOT NULL DROP TABLE #PatientValuesHBA1C;
SELECT FK_Patient_Link_ID, LatestValue AS LatestHBA1CValue INTO #PatientValuesHBA1C
FROM #PatientValues
WHERE Concept = 'hba1c';

IF OBJECT_ID('tempdb..#PatientValuesCHOLESTEROL') IS NOT NULL DROP TABLE #PatientValuesCHOLESTEROL;
SELECT FK_Patient_Link_ID, LatestValue AS LatestCHOLESTEROLValue INTO #PatientValuesCHOLESTEROL
FROM #PatientValues
WHERE Concept = 'cholesterol';

IF OBJECT_ID('tempdb..#PatientValuesLDL') IS NOT NULL DROP TABLE #PatientValuesLDL;
SELECT FK_Patient_Link_ID, LatestValue AS LatestLDLValue INTO #PatientValuesLDL
FROM #PatientValues
WHERE Concept = 'ldl-cholesterol';

IF OBJECT_ID('tempdb..#PatientValuesHDL') IS NOT NULL DROP TABLE #PatientValuesHDL;
SELECT FK_Patient_Link_ID, LatestValue AS LatestHDLValue INTO #PatientValuesHDL
FROM #PatientValues
WHERE Concept = 'hdl-cholesterol';

IF OBJECT_ID('tempdb..#PatientValuesVITAMIND') IS NOT NULL DROP TABLE #PatientValuesVITAMIND;
SELECT FK_Patient_Link_ID, LatestValue AS LatestVITAMINDValue INTO #PatientValuesVITAMIND
FROM #PatientValues
WHERE Concept = 'vitamin-d';

IF OBJECT_ID('tempdb..#PatientValuesTESTOSTERONE') IS NOT NULL DROP TABLE #PatientValuesTESTOSTERONE;
SELECT FK_Patient_Link_ID, LatestValue AS LatestTESTOSTERONEValue INTO #PatientValuesTESTOSTERONE
FROM #PatientValues
WHERE Concept = 'testosterone';

IF OBJECT_ID('tempdb..#PatientValuesSHBG') IS NOT NULL DROP TABLE #PatientValuesSHBG;
SELECT FK_Patient_Link_ID, LatestValue AS LatestSHBGValue INTO #PatientValuesSHBG
FROM #PatientValues
WHERE Concept = 'sex-hormone-binding-globulin';


-- diagnoses
--> CODESET copd
IF OBJECT_ID('tempdb..#PatientDiagnosesCOPD') IS NOT NULL DROP TABLE #PatientDiagnosesCOPD;
SELECT DISTINCT FK_Patient_Link_ID
INTO #PatientDiagnosesCOPD
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('copd') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('copd') AND [Version]=1))
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);

--> CODESET asthma
IF OBJECT_ID('tempdb..#PatientDiagnosesASTHMA') IS NOT NULL DROP TABLE #PatientDiagnosesASTHMA;
SELECT DISTINCT FK_Patient_Link_ID
INTO #PatientDiagnosesASTHMA
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('asthma') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('asthma') AND [Version]=1))
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);

--> CODESET severe-mental-illness
IF OBJECT_ID('tempdb..#PatientDiagnosesSEVEREMENTALILLNESS') IS NOT NULL DROP TABLE #PatientDiagnosesSEVEREMENTALILLNESS;
SELECT DISTINCT FK_Patient_Link_ID
INTO #PatientDiagnosesSEVEREMENTALILLNESS
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('severe-mental-illness') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('severe-mental-illness') AND [Version]=1))
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);


-- medications
--> CODESET metformin
IF OBJECT_ID('tempdb..#PatientMedicationsMETFORMIN') IS NOT NULL DROP TABLE #PatientMedicationsMETFORMIN;
SELECT 
	FK_Patient_Link_ID,
	CAST(MedicationDate AS DATE) AS MedicationDate
INTO #PatientMedicationsMETFORMIN
FROM RLS.vw_GP_Medications
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('metformin') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('metformin') AND [Version]=1))
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND MedicationDate > @MedicationsFromDate;

--> CODESET ace-inhibitor
IF OBJECT_ID('tempdb..#PatientMedicationsACEI') IS NOT NULL DROP TABLE #PatientMedicationsACEI;
SELECT 
	FK_Patient_Link_ID,
	CAST(MedicationDate AS DATE) AS MedicationDate
INTO #PatientMedicationsACEI
FROM RLS.vw_GP_Medications
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('ace-inhibitor') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('ace-inhibitor') AND [Version]=1))
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND MedicationDate > @MedicationsFromDate;

--> CODESET aspirin
IF OBJECT_ID('tempdb..#PatientMedicationsASPIRIN') IS NOT NULL DROP TABLE #PatientMedicationsASPIRIN;
SELECT 
	FK_Patient_Link_ID,
	CAST(MedicationDate AS DATE) AS MedicationDate
INTO #PatientMedicationsASPIRIN
FROM RLS.vw_GP_Medications
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('aspirin') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('aspirin') AND [Version]=1))
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND MedicationDate > @MedicationsFromDate;

--> CODESET clopidogrel
IF OBJECT_ID('tempdb..#PatientMedicationsCLOPIDOGREL') IS NOT NULL DROP TABLE #PatientMedicationsCLOPIDOGREL;
SELECT 
	FK_Patient_Link_ID,
	CAST(MedicationDate AS DATE) AS MedicationDate
INTO #PatientMedicationsCLOPIDOGREL
FROM RLS.vw_GP_Medications
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('clopidogrel') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('clopidogrel') AND [Version]=1))
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND MedicationDate > @MedicationsFromDate;

-- record as on med if value within 6 months on index date
IF OBJECT_ID('tempdb..#PatientMedications') IS NOT NULL DROP TABLE #PatientMedications;
SELECT 
  p.FK_Patient_Link_ID,
  CASE WHEN MAX(acei.MedicationDate) IS NULL THEN 'N' ELSE 'Y' END AS IsOnACEI,
  CASE WHEN MAX(aspirin.MedicationDate) IS NULL THEN 'N' ELSE 'Y' END AS IsOnAspirin,
  CASE WHEN MAX(clop.MedicationDate) IS NULL THEN 'N' ELSE 'Y' END AS IsOnClopidogrel,
  CASE WHEN MAX(met.MedicationDate) IS NULL THEN 'N' ELSE 'Y' END AS IsOnMetformin
INTO #PatientMedications
FROM #PatientIdsAndIndexDates p
LEFT OUTER JOIN #PatientMedicationsACEI acei
  ON acei.FK_Patient_Link_ID = p.FK_Patient_Link_ID
  AND acei.MedicationDate <= p.IndexDate
  AND acei.MedicationDate >= DATEADD(day, -183, p.IndexDate)
LEFT OUTER JOIN #PatientMedicationsASPIRIN aspirin
  ON aspirin.FK_Patient_Link_ID = p.FK_Patient_Link_ID
  AND aspirin.MedicationDate <= p.IndexDate
  AND aspirin.MedicationDate >= DATEADD(day, -183, p.IndexDate)
LEFT OUTER JOIN #PatientMedicationsCLOPIDOGREL clop
  ON clop.FK_Patient_Link_ID = p.FK_Patient_Link_ID
  AND clop.MedicationDate <= p.IndexDate
  AND clop.MedicationDate >= DATEADD(day, -183, p.IndexDate)
LEFT OUTER JOIN #PatientMedicationsMETFORMIN met
  ON met.FK_Patient_Link_ID = p.FK_Patient_Link_ID
  AND met.MedicationDate <= p.IndexDate
  AND met.MedicationDate >= DATEADD(day, -183, p.IndexDate)
GROUP BY p.FK_Patient_Link_ID;

-- Bring together for final output
-- Patients in main cohort
SELECT 
  m.FK_Patient_Link_ID AS PatientId,
  NULL AS MainCohortMatchedPatientId,
  YearOfBirth,
  DeathDate,
  Sex,
  LSOA_Code AS LSOA,
  TownsendScoreHigherIsMoreDeprived,
  TownsendQuintileHigherIsMoreDeprived,
  FirstDiagnosisDate,
  FirstT1DiagnosisDate,
  FirstT2DiagnosisDate,
  IndexDate AS COVIDPositiveTestDate,
  FirstAdmissionPostCOVIDTest,
  LengthOfStay,
  EthnicCategoryDescription,
  LatestBMIValue,
  LatestHBA1CValue,
  LatestCHOLESTEROLValue,
  LatestLDLValue,
  LatestHDLValue,
  LatestVITAMINDValue,
  LatestTESTOSTERONEValue,
  LatestSHBGValue,
  CASE WHEN copd.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PatientHasCOPD,
  CASE WHEN asthma.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PatientHasASTHMA,
  CASE WHEN smi.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PatientHasSMI,
  IsOnACEI,
  IsOnAspirin,
  IsOnClopidogrel,
  IsOnMetformin
FROM #MainCohort m
LEFT OUTER JOIN RLS.vw_Patient_Link pl ON pl.PK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientValuesBMI bmi ON bmi.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientTownsend town ON town.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientValuesHBA1C hba1c ON hba1c.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientValuesCHOLESTEROL cholesterol ON cholesterol.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientValuesLDL ldl ON ldl.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientValuesHDL hdl ON hdl.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientValuesVITAMIND vitamind ON vitamind.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientValuesTESTOSTERONE testosterone ON testosterone.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientValuesSHBG shbg ON shbg.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosesCOPD copd ON copd.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosesASTHMA asthma ON asthma.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosesSEVEREMENTALILLNESS smi ON smi.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientMedications pm ON pm.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientsFirstAdmissionPostTest fa ON fa.FK_Patient_Link_ID = m.FK_Patient_Link_ID
UNION
--Patients in matched cohort
SELECT 
  m.FK_Patient_Link_ID AS PatientId,
  m.PatientWhoIsMatched AS MainCohortMatchedPatientId,
  MatchingYearOfBirth,
  DeathDate,
  Sex,
  LSOA_Code AS LSOA,
  TownsendScoreHigherIsMoreDeprived,
  TownsendQuintileHigherIsMoreDeprived,
  NULL AS FirstDiagnosisDate,
  NULL AS FirstT1DiagnosisDate,
  NULL AS FirstT2DiagnosisDate,
  IndexDate AS COVIDPositiveTestDate,
  FirstAdmissionPostCOVIDTest,
  LengthOfStay,
  EthnicCategoryDescription,
  LatestBMIValue,
  LatestHBA1CValue,
  LatestCHOLESTEROLValue,
  LatestLDLValue,
  LatestHDLValue,
  LatestVITAMINDValue,
  LatestTESTOSTERONEValue,
  LatestSHBGValue,
  smok.PassiveSmoker AS IsPassiveSmoker,
  smok.WorstSmokingStatus,
  smok.CurrentSmokingStatus,
  CASE WHEN copd.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PatientHasCOPD,
  CASE WHEN asthma.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PatientHasASTHMA,
  CASE WHEN smi.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PatientHasSMI,
  IsOnACEI,
  IsOnAspirin,
  IsOnClopidogrel,
  IsOnMetformin
FROM #MatchedCohort m
LEFT OUTER JOIN RLS.vw_Patient_Link pl ON pl.PK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientValuesBMI bmi ON bmi.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientTownsend town ON town.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientValuesHBA1C hba1c ON hba1c.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientValuesCHOLESTEROL cholesterol ON cholesterol.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientValuesLDL ldl ON ldl.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientValuesHDL hdl ON hdl.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientValuesVITAMIND vitamind ON vitamind.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientValuesTESTOSTERONE testosterone ON testosterone.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientValuesSHBG shbg ON shbg.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosesCOPD copd ON copd.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosesASTHMA asthma ON asthma.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosesSEVEREMENTALILLNESS smi ON smi.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientMedications pm ON pm.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSmokingStatus smok ON smok.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientsFirstAdmissionPostTest fa ON fa.FK_Patient_Link_ID = m.FK_Patient_Link_ID;