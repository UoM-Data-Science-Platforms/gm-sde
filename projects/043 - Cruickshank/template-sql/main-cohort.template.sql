--┌──────────────────┐
--│ Main cohort file │
--└──────────────────┘

---------------------- RDE CHECK ---------------------
-- Le Mai Parkes  - 10 June 2022 - via pull request --
------------------------------------------------------

-- Cohort is everyone who tested positive with COVID-19 infection. 

-- PI also wanted Occupation, but there is a higher risk of re-identification if we supply it raw
-- e.g. if person is an MP, university VC, head teacher, professional sports person etc. Also there
-- are sensitive occupations like sex worker. Agreed to supply as is, then PI can decide what processing
-- is required e.g. mapping occupations to key/non-key worker etc. Also PI is aware that occupation
-- is poorly recorded ~10% of patients.

-- OUTPUT: Data with the following fields
-- 	- PatientId (int)
--  - FirstCovidPositiveDate (DDMMYYYY)
--  - SecondCovidPositiveDate (DDMMYYYY)
--  - ThirdCovidPositiveDate (DDMMYYYY)
--  - FirstAdmissionPost1stCOVIDTest (DDMMYYYY)
--  - FirstAdmissionPost2ndCOVIDTest (DDMMYYYY)
--  - FirstAdmissionPost3rdCOVIDTest (DDMMYYYY)
--  - DateOfDeath (DDMMYYYY)
--  - DeathWithin28Days (Y/N)
--  - LSOA
--  - LSOAStartDate (NB - this is either when they moved there OR when the data feed started)
--  - Months at this LSOA (if possible)
--  - YearOfBirth (YYYY)
--  - Sex (M/F)
--  - Ethnicity
--  - IMD2019Decile1IsMostDeprived10IsLeastDeprived
--  - HasAsthma (Y/N) (at time of 1st COVID dx)
--  - HasIschemic heart disease (Y/N) (at time of 1st COVID dx)
--  - HasOther heart disease (Y/N) (at time of 1st COVID dx)
--  - HasStroke (Y/N) (at time of 1st COVID dx)
--  - HasDiabetes (Y/N) (at time of 1st COVID dx)
--  - HasCOPD (Y/N) (at time of 1st COVID dx)
--  - HasHypertension (Y/N) (at time of 1st COVID dx)
--  - WorstSmokingStatus (non-smoker / trivial smoker / non-trivial smoker)
--  - CurrentSmokingStatus (non-smoker / trivial smoker / non-trivial smoker)
--  - BMI (at time of 1st COVID dx)
--  - VaccineDose1Date (DDMMYYYY)
--  - VaccineDose2Date (DDMMYYYY)
--  - VaccineDose3Date (DDMMYYYY)
--  - VaccineDose4Date (DDMMYYYY)
--  - VaccineDose5Date (DDMMYYYY)

--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2020-01-01';

-- Get all the positive covid test patients
--> EXECUTE query-patients-with-covid.sql start-date:2020-01-01 all-patients:true gp-events-table:RLS.vw_GP_Events

IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT FK_Patient_Link_ID INTO #Patients
FROM #CovidPatients;

--> EXECUTE query-patient-year-of-birth.sql
--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-smoking-status.sql gp-events-table:RLS.vw_GP_Events
--> EXECUTE query-patient-lsoa.sql
--> EXECUTE query-patient-imd.sql
--> EXECUTE query-get-covid-vaccines.sql gp-events-table:RLS.vw_GP_Events gp-medications-table:RLS.vw_GP_Medications
--> EXECUTE query-get-admissions-and-length-of-stay.sql all-patients:false

-- Now find hospital admission following each of up to 5 covid positive tests
IF OBJECT_ID('tempdb..#PatientsAdmissionsPostTest') IS NOT NULL DROP TABLE #PatientsAdmissionsPostTest;
CREATE TABLE #PatientsAdmissionsPostTest (
  FK_Patient_Link_ID BIGINT,
  [FirstAdmissionPost1stCOVIDTest] DATE,
  [FirstAdmissionPost2ndCOVIDTest] DATE,
  [FirstAdmissionPost3rdCOVIDTest] DATE
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

-- Get length of stay for each admission just calculated
IF OBJECT_ID('tempdb..#PatientsLOSPostTest') IS NOT NULL DROP TABLE #PatientsLOSPostTest;
SELECT p.FK_Patient_Link_ID, 
		MAX(l1.LengthOfStay) AS LengthOfStayFirstAdmission1stCOVIDTest,
		MAX(l2.LengthOfStay) AS LengthOfStayFirstAdmission2ndCOVIDTest,
		MAX(l3.LengthOfStay) AS LengthOfStayFirstAdmission3rdCOVIDTest
INTO #PatientsLOSPostTest
FROM #PatientsAdmissionsPostTest p
	LEFT OUTER JOIN #LengthOfStay l1 ON p.FK_Patient_Link_ID = l1.FK_Patient_Link_ID AND p.[FirstAdmissionPost1stCOVIDTest] = l1.AdmissionDate
	LEFT OUTER JOIN #LengthOfStay l2 ON p.FK_Patient_Link_ID = l2.FK_Patient_Link_ID AND p.[FirstAdmissionPost2ndCOVIDTest] = l2.AdmissionDate
	LEFT OUTER JOIN #LengthOfStay l3 ON p.FK_Patient_Link_ID = l3.FK_Patient_Link_ID AND p.[FirstAdmissionPost3rdCOVIDTest] = l3.AdmissionDate
GROUP BY p.FK_Patient_Link_ID;

-- diagnoses
--> CODESET asthma:1
IF OBJECT_ID('tempdb..#PatientDiagnosesASTHMA') IS NOT NULL DROP TABLE #PatientDiagnosesASTHMA;
SELECT DISTINCT FK_Patient_Link_ID
INTO #PatientDiagnosesASTHMA
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('asthma') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('asthma') AND [Version]=1))
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);

--> CODESET coronary-heart-disease:1
IF OBJECT_ID('tempdb..#PatientDiagnosesCHD') IS NOT NULL DROP TABLE #PatientDiagnosesCHD;
SELECT DISTINCT FK_Patient_Link_ID
INTO #PatientDiagnosesCHD
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('coronary-heart-disease') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('coronary-heart-disease') AND [Version]=1))
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);

--> CODESET stroke:1
IF OBJECT_ID('tempdb..#PatientDiagnosesSTROKE') IS NOT NULL DROP TABLE #PatientDiagnosesSTROKE;
SELECT DISTINCT FK_Patient_Link_ID
INTO #PatientDiagnosesSTROKE
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('stroke') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('stroke') AND [Version]=1))
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);

--> CODESET diabetes:1
IF OBJECT_ID('tempdb..#PatientDiagnosesDIABETES') IS NOT NULL DROP TABLE #PatientDiagnosesDIABETES;
SELECT DISTINCT FK_Patient_Link_ID
INTO #PatientDiagnosesDIABETES
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('diabetes') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('diabetes') AND [Version]=1))
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);

--> CODESET copd:1
IF OBJECT_ID('tempdb..#PatientDiagnosesCOPD') IS NOT NULL DROP TABLE #PatientDiagnosesCOPD;
SELECT DISTINCT FK_Patient_Link_ID
INTO #PatientDiagnosesCOPD
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('copd') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('copd') AND [Version]=1))
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);

--> CODESET hypertension:1
IF OBJECT_ID('tempdb..#PatientDiagnosesHYPERTENSION') IS NOT NULL DROP TABLE #PatientDiagnosesHYPERTENSION;
SELECT DISTINCT FK_Patient_Link_ID
INTO #PatientDiagnosesHYPERTENSION
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('hypertension') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('hypertension') AND [Version]=1))
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);

--> CODESET bmi:2
IF OBJECT_ID('tempdb..#PatientValuesWithIds') IS NOT NULL DROP TABLE #PatientValuesWithIds;
SELECT 
	FK_Patient_Link_ID,
	CAST(EventDate AS DATE) AS EventDate,
	[Value]
INTO #PatientValuesWithIds
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('bmi') AND [Version]=2)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('bmi') AND [Version]=2))
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND [Value] IS NOT NULL
AND [Value] != '0';

-- get most recent value at in the period [index date - 2 years, index date]
IF OBJECT_ID('tempdb..#PatientValuesBMI') IS NOT NULL DROP TABLE #PatientValuesBMI;
SELECT main.FK_Patient_Link_ID, MAX(main.[Value]) AS LatestValue
INTO #PatientValuesBMI
FROM #PatientValuesWithIds main
INNER JOIN (
  SELECT p.FK_Patient_Link_ID, MAX(EventDate) AS LatestDate FROM #PatientValuesWithIds pv
  INNER JOIN #CovidPatients p 
    ON p.FK_Patient_Link_ID = pv.FK_Patient_Link_ID
    AND pv.EventDate <= p.FirstCovidPositiveDate
  GROUP BY p.FK_Patient_Link_ID
) sub on sub.FK_Patient_Link_ID = main.FK_Patient_Link_ID and sub.LatestDate = main.EventDate
GROUP BY main.FK_Patient_Link_ID;

-- Not needed. Tidy up.
DROP TABLE #PatientValuesWithIds;

-- Get patient list of those with COVID death within 28 days of positive test
IF OBJECT_ID('tempdb..#COVIDDeath') IS NOT NULL DROP TABLE #COVIDDeath;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #COVIDDeath FROM RLS.vw_COVID19
WHERE DeathWithin28Days = 'Y';

-- Get start date at LSOA from address history.
-- NB !! Virtually all start dates are post 2019 i.e. the start date
-- is either when they moved in OR when the data feed started OR
-- when they first registered with a GM GP. So not great, but PI is
-- aware of this.

-- First find the earliest start date for their current LSOA
IF OBJECT_ID('tempdb..#PatientLSOAEarliestStart') IS NOT NULL DROP TABLE #PatientLSOAEarliestStart;
select l.FK_Patient_Link_ID, MIN(StartDate) AS EarliestStartDate
into #PatientLSOAEarliestStart
from #PatientLSOA l
left outer join RLS.vw_Patient_Address_History h
	on h.FK_Patient_Link_ID = l.FK_Patient_Link_ID
	and h.LSOA_Code = l.LSOA_Code
group by l.FK_Patient_Link_ID;

-- Now find the most recent end date for not their current LSOA
IF OBJECT_ID('tempdb..#PatientLSOALatestEnd') IS NOT NULL DROP TABLE #PatientLSOALatestEnd;
select l.FK_Patient_Link_ID, MAX(EndDate) AS LatestEndDate
into #PatientLSOALatestEnd
from #PatientLSOA l
left outer join RLS.vw_Patient_Address_History h
	on h.FK_Patient_Link_ID = l.FK_Patient_Link_ID
	and h.LSOA_Code != l.LSOA_Code
where EndDate is not null
group by l.FK_Patient_Link_ID;

-- Bring together. Either earliest start date or most recent end date of a different LSOA (if it exists).
IF OBJECT_ID('tempdb..#PatientLSOAStartDates') IS NOT NULL DROP TABLE #PatientLSOAStartDates;
select 
	s.FK_Patient_Link_ID,
	CAST (
	CASE
		WHEN LatestEndDate is null THEN EarliestStartDate
		WHEN EarliestStartDate > LatestEndDate THEN EarliestStartDate
		ELSE LatestEndDate
	END AS DATE) AS LSOAStartDate
into #PatientLSOAStartDates
from #PatientLSOAEarliestStart s
left outer join #PatientLSOALatestEnd e
on e.FK_Patient_Link_ID = s.FK_Patient_Link_ID;

SELECT 
  m.FK_Patient_Link_ID AS PatientId,
  FirstCovidPositiveDate,
  SecondCovidPositiveDate,
  ThirdCovidPositiveDate,
  FirstAdmissionPost1stCOVIDTest,
  LengthOfStayFirstAdmission1stCOVIDTest,
  FirstAdmissionPost2ndCOVIDTest,
  LengthOfStayFirstAdmission2ndCOVIDTest,
  FirstAdmissionPost3rdCOVIDTest,
  LengthOfStayFirstAdmission3rdCOVIDTest,
  MONTH(DeathDate) AS MonthOfDeath,
  YEAR(DeathDate) AS YearOfDeath,
  CASE WHEN covidDeath.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS DeathWithin28DaysCovidPositiveTest,
  LSOA_Code AS LSOA,
  lsoaStart.LSOAStartDate AS LSOAStartDate,
  YearOfBirth,
  Sex,
  EthnicCategoryDescription,
  IMD2019Decile1IsMostDeprived10IsLeastDeprived,
  CASE WHEN asthma.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PatientHasASTHMA,
  CASE WHEN chd.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PatientHasCHD,
  CASE WHEN stroke.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PatientHasSTROKE,
  CASE WHEN dm.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PatientHasDIABETES,
  CASE WHEN copd.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PatientHasCOPD,
  CASE WHEN htn.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PatientHasHYPERTENSION,
  smok.WorstSmokingStatus,
  smok.CurrentSmokingStatus,
  bmi.LatestValue AS LatestBMIValue,
  VaccineDose1Date,
  VaccineDose2Date,
  VaccineDose3Date,
  VaccineDose4Date,
  VaccineDose5Date
  --,Occupation
FROM #Patients m
LEFT OUTER JOIN RLS.vw_Patient_Link pl ON pl.PK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientLSOA lsoa ON lsoa.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientLSOAStartDates lsoaStart ON lsoaStart.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientIMDDecile imd ON imd.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosesASTHMA asthma ON asthma.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosesCHD chd ON chd.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosesSTROKE stroke ON stroke.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosesDIABETES dm ON dm.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosesCOPD copd ON copd.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosesHYPERTENSION htn ON htn.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSmokingStatus smok ON smok.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDDeath covidDeath ON covidDeath.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDVaccinations v ON v.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #CovidPatientsMultipleDiagnoses cov ON cov.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientsAdmissionsPostTest admit ON admit.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientsLOSPostTest los ON los.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientValuesBMI bmi ON bmi.FK_Patient_Link_ID = m.FK_Patient_Link_ID;