--┌────────────────────────────────--------─┐
--│ Cancer cohort matching for 004-Finn     │
--└───────────────────────────────--------──┘

-- Study index date: 1st Feb 2020

-- OBJECTIVE: Defines the cohort (cancer and non cancer patients) that will be used for the study, based on: 
-- Main cohort (cancer patients):
--	- Cancer diagnosis between 1st February 2015 and 1st February 2020
--	- >= 18 year old 
--	- Alive on 1st Feb 2020 
-- Control group (non cancer patients):
--  -	Alive on 1st February 2020 
--  -	no current or history of cancer diagnosis.
-- Matching is 1:5 based on sex and year of birth with a flexible year of birth = 0
-- Index date is: 1st February 2020


-- INPUT: Assumes that @StartDate has already been defined 

-- OUTPUT: A temp table as follows: 
-- #Patients
--  - FK_Patient_Link_ID
--  - YearOfBirth
--  - Sex
--  - HasCancer
--  - NumberOfMatches

--> CODESET cancer:1

-- Get the first cancer diagnosis date of cancer patients 
IF OBJECT_ID('tempdb..#AllCancerPatients') IS NOT NULL DROP TABLE #AllCancerPatients;
SELECT 
  FK_Patient_Link_ID,
  MIN(CAST(EventDate AS DATE)) AS FirstDiagnosisDate
INTO #AllCancerPatients
FROM RLS.vw_GP_Events
WHERE (
  FK_Reference_SnomedCT_ID IN (
      SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('cancer') AND [Version]=1
  ) OR
  FK_Reference_Coding_ID IN (
      SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('cancer') AND [Version]=1
  ) 
)
GROUP BY FK_Patient_Link_ID;

-- Get patients with a first cancer diagnosis in the time period 1st Feb 2015 - 1st Feb 2020 
IF OBJECT_ID('tempdb..#CancerPatients') IS NOT NULL DROP TABLE #CancerPatients;
Select *
INTO #CancerPatients
From #AllCancerPatients
WHERE FirstDiagnosisDate BETWEEN DATEADD(YEAR, -5, @StartDate) AND @StartDate;
-- 61.720 patients with a first cancer diagnosis in the last 5 years.


--> CODESET cancer:2

-- Get patients with the first date with a secondary cancer diagnosis of patients 
IF OBJECT_ID('tempdb..#AllSecondaryCancerPatients') IS NOT NULL DROP TABLE #AllSecondaryCancerPatients;
SELECT 
  FK_Patient_Link_ID,
  MIN(CAST(EventDate AS DATE)) AS FirstDiagnosisDate
INTO #AllSecondaryCancerPatients
FROM RLS.vw_GP_Events
WHERE (
  FK_Reference_SnomedCT_ID IN (
      SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('cancer') AND [Version]=2
  ) OR
  FK_Reference_Coding_ID IN (
      SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('cancer') AND [Version]=2
  ) 
)
GROUP BY FK_Patient_Link_ID;
-- 7.529 patients with a secondary cancer diagnosis code captured in GP records.




-- Get patients with a first secondary cancer diagnosis in the time period 1st Feb 2015 - 1st Feb 2020 
IF OBJECT_ID('tempdb..#SecondaryCancerPatients') IS NOT NULL DROP TABLE #SecondaryCancerPatients;
Select *
INTO #SecondaryCancerPatients
From #AllSecondaryCancerPatients
WHERE FirstDiagnosisDate BETWEEN DATEADD(YEAR, -5, @StartDate) AND @StartDate;
-- 3.820 rows

-- Get unique patients with a first cancer diagnosis or a secondary diagnosis within the time period 1st Feb 2015 - 1st Feb 2020
-- `UNION` will exclude duplicates
IF OBJECT_ID('tempdb..#FirstAndSecondaryCancerPatients') IS NOT NULL DROP TABLE #FirstAndSecondaryCancerPatients;
SELECT 
  FK_Patient_Link_ID
INTO #FirstAndSecondaryCancerPatients 
FROM #CancerPatients
UNION
SELECT 
  FK_Patient_Link_ID
FROM #SecondaryCancerPatients;
-- 63.095

-- Define #Patients temp table to get age/sex and other demographics details.
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
CREATE TABLE #Patients
(
  FK_Patient_Link_ID bigint,
  YearOfBirth int,
  Sex nchar(2), 
  HasCancer varchar(1), 
  NumberOfMatches int
);

INSERT INTO #Patients
SELECT 
  PK_Patient_Link_ID AS FK_Patient_Link_ID,
  NULL AS YearOfBirth,
  NULL as Sex,
  NULL AS HasCancer,
  NULL AS NumberOfMatches
FROM RLS.vw_Patient_Link
GROUP BY PK_Patient_Link_ID;

--> EXECUTE query-patient-year-of-birth.sql
--> EXECUTE query-patient-sex.sql

-- Get adult cancer patients for the main cohort.
IF OBJECT_ID('tempdb..#AdultCancerCohort') IS NOT NULL DROP TABLE #AdultCancerCohort;
SELECT 
  p.FK_Patient_Link_ID,
  sex.Sex,
  yob.YearOfBirth
INTO #AdultCancerCohort
FROM #FirstAndSecondaryCancerPatients p
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE 
  YearOfBirth <= (YEAR(@StartDate) - 18);
-- This includes anyone born on Jan 2002. Index date should be Feb 2002.

-- Get cancer patients alive on index date
IF OBJECT_ID('tempdb..#MainCohort') IS NOT NULL DROP TABLE #MainCohort;
SELECT 
  acc.FK_Patient_Link_ID,
  acc.Sex,
  acc.YearOfBirth,
  pl.Deceased AS DeathStatus,
  CONVERT(DATE, pl.DeathDate) AS DateOfDeath
INTO #MainCohort
FROM #AdultCancerCohort acc
LEFT OUTER JOIN [RLS].[vw_Patient_Link] pl ON pl.PK_Patient_Link_ID = acc.FK_Patient_Link_ID
WHERE  
  (pl.DeathDate is null and pl.Deceased = 'N') 
  OR
  (pl.DeathDate is not null and (pl.DeathDate >= @StartDate));

-- 56.344 adult, alive patients with a first cancer diagnosis in the 5-year period



-- Define the population of potential matches for the cohort
-- Get patients from tenancy =2 and GP practice code in GM. 
-- If patients have a tenancy id of 2 we take this as their most likely GP practice
-- as this is the GP data feed and so most likely to be up to date
IF OBJECT_ID('tempdb..#PatientsGP') IS NOT NULL DROP TABLE #PatientsGP;
SELECT FK_Patient_Link_ID, MIN(GPPracticeCode) as GPPracticeCode INTO #PatientsGP FROM RLS.vw_Patient
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_Tenancy_ID = 2
AND GPPracticeCode IS NOT NULL 
AND GPPracticeCode NOT LIKE 'ZZZ%'
GROUP BY FK_Patient_Link_ID;



--	Get all patients alive on 1st February 2020 
IF OBJECT_ID('tempdb..#PatientsAliveIndex') IS NOT NULL DROP TABLE #PatientsAliveIndex;
SELECT pGP.FK_Patient_Link_ID, sex.Sex, yob.YearOfBirth
INTO #PatientsAliveIndex
FROM #PatientsGP pGP
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = pGP.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = pGP.FK_Patient_Link_ID
LEFT OUTER JOIN RLS.vw_Patient_Link pl ON pl.PK_Patient_Link_ID = pGP.FK_Patient_Link_ID
WHERE  
  ((pl.DeathDate is null and pl.Deceased = 'N') 
  OR
  (pl.DeathDate is not null and (pl.DeathDate >= @StartDate)))

-- previous: (5.342.653 rows)


-- Get patients with no current or history of cancer diagnosis (in GP records).
IF OBJECT_ID('tempdb..#PotentialMatches') IS NOT NULL DROP TABLE #PotentialMatches;
SELECT pa.*
INTO #PotentialMatches
FROM #PatientsAliveIndex pa
LEFT OUTER JOIN #AllCancerPatients AS cp 
  ON pa.FK_Patient_Link_ID = cp.FK_Patient_Link_ID
WHERE cp.FK_Patient_Link_ID IS NULL;
-- previous: (5.174.028 rows)



--> EXECUTE query-cohort-matching-yob-sex-alt.sql yob-flex:0 num-matches:5
-- OUTPUT: A temp table as follows:
-- #CohortStore (FK_Patient_Link_ID, YearOfBirth, Sex, MatchingPatientId, MatchingYearOfBirth)
-- 281.720 rows. running time: 2 hours.

-- Define a table with all the patients for the entire cohort (main cohort and the matched cohort) and add a column to indicate whether they had cancer.
IF OBJECT_ID('tempdb..#AllPatientsCohort') IS NOT NULL DROP TABLE #AllPatientsCohort;
SELECT 
  PatientId As FK_Patient_Link_ID, 
  YearOfBirth, 
  Sex,
  'Y' AS HasCancer
INTO #AllPatientsCohort 
FROM #CohortStore

UNION ALL
SELECT 
  MatchingPatientId,
  MatchingYearOfBirth,
  Sex,
  'N' AS HasCancer
FROM #CohortStore;

-- Remove all rows from the patients table to add only the patients from the study cohort. 
TRUNCATE TABLE #Patients;

-- Get a table with unique patients for the entire cohort 
--   Find how many matches each cancer patient had. 
--   This will also remove any duplicates.
INSERT INTO #Patients
SELECT 
  FK_Patient_Link_ID, 
  YearOfBirth, 
  Sex, 
  HasCancer, 
  count(1) as NumberOfMatches
FROM #AllPatientsCohort
GROUP BY FK_Patient_Link_ID, YearOfBirth, Sex, HasCancer;
-- 338.010 distinct patients, running time: 19min, as of 4th July.
-- 338.034 distinct patients, running time: 28min, all cancer patients have 5 matches each, cancer cohort = 56.339, as of 23rd June 
-- 338.064 distinct patients, all cancer patients have 5 matches each, as of 9th June 
