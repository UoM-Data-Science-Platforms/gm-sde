--┌─────────────────────────────────┐
--│ Cancer cohort matching for 004-Finn       │
--└─────────────────────────────────┘

-- Study index date: 1st Feb 2020

-- Defines the cohort (cancer and non cancer patients) that will be used for the study, based on: 
-- Main cohort (cancer patients):
--	- Cancer diagnosis between 1st February 2015 and 1st February 2020
--	- >= 18 year old 
--	- Alive on 1st Feb 2020 
-- Control group (non cancer patients):
--  -	Alive on 1st February 2020 
--  -	no current or history of cancer diagnosis.
-- Matching is 1:5 based on sex and year of birth with a flexible year of birth = ??
-- Index date is: 1st February 2020



-- Set the start date
DECLARE @IndexDate datetime;
SET @IndexDate = '2020-02-01';

--> CODESET cancer

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
WHERE FirstDiagnosisDate BETWEEN '2015-02-01' AND @IndexDate;
-- 61.720 patients with a first cancer diagnosis in the last 5 years.

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
WHERE FirstDiagnosisDate BETWEEN '2015-02-01' AND @IndexDate;
-- 3.820

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
  YearOfBirth <= 2002;
-- (179.082) adult cancer patients
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
  (pl.DeathDate is not null and (pl.DeathDate >= @IndexDate));

-- 56.344 
-- (55.530) adult, alive patients with a first cancer diagnosis in the 5-year period
-- (165.623) adult cancer patients alive on index date


-- Define the population of potential matches for the cohort
--	Get all patients alive on 1st February 2020 
IF OBJECT_ID('tempdb..#PatientsAliveIndex') IS NOT NULL DROP TABLE #PatientsAliveIndex;
SELECT pl.PK_Patient_Link_ID AS FK_Patient_Link_ID, sex.Sex, yob.YearOfBirth
INTO #PatientsAliveIndex
FROM RLS.vw_Patient_Link pl
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = pl.PK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = pl.PK_Patient_Link_ID
WHERE  
  (pl.DeathDate is null and pl.Deceased = 'N') 
  OR
  (pl.DeathDate is not null and (pl.DeathDate >= @IndexDate));
-- 5.342.653
-- (5.332.329)

-- Get patients with no current or history of cancer diagnosis (in GP records).
IF OBJECT_ID('tempdb..#PotentialMatches') IS NOT NULL DROP TABLE #PotentialMatches;
SELECT pa.*
INTO #PotentialMatches
FROM #PatientsAliveIndex pa
LEFT OUTER JOIN #AllCancerPatients AS cp 
  ON pa.FK_Patient_Link_ID = cp.FK_Patient_Link_ID
WHERE cp.FK_Patient_Link_ID IS NULL;
-- 5.174.028
-- (5.163.938) alive non-cancer patients


--> EXECUTE query-cohort-matching-yob-sex-alt.sql yob-flex:0 num-matches:5
-- OUTPUT: A temp table as follows:
-- #CohortStore (FK_Patient_Link_ID, YearOfBirth, Sex, MatchingPatientId, MatchingYearOfBirth)
-- 281.720 rows. running time: 2 hours.