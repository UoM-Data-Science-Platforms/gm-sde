--┌─────────────────────────────────┐
--│ Patients demographics           │
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


-- OUTPUT: A single table with the following:
--  •	PatientID (int)
--  •	YearOfBirth (int in this format YYYY)
--  •	Sex (M/F/U)
--  •	HasCancer (Y/N)
--  •	FirstDiagnosisDate (YYYY-MM-DD)
--  •	NumberOfMatches (No from 1-5. Note: Non cancer patients will have 1 in this field.)
--	•	PassiveSmoker - Y/N (whether a patient has ever had a code for passive smoking)
--	•	WorstSmokingStatus - (non-trivial-smoker/trivial-smoker/non-smoker)
--	•	CurrentSmokingStatus - (non-trivial-smoker/trivial-smoker/non-smoker)
--  •	LSOA (nationally recognised LSOA identifier)
--  •	IndicesOfDeprivation (IMD 2019: number 1 to 10 inclusive)
--  •	BMIValue ()
--  •	BMILatestDate (YYYY-MM-DD) Latest date that a BMI value has been captured on or before 1 month prior to index date
--  •	Ethnicity (TODO)
--  •	FrailtyScore (as captured in PatientLink)
--  •	FrailtyDeficits 
--  •	FrailtyDeficitList 
--  •	VaccineDate (date of vaccine (YYYY-MM-DD)) TODO
--  •	DaysSinceFirstVaccine - 0 if first vaccine, > 0 otherwise TODO
--  •	DeathStatus (Alive/Dead)
--  •	DateOfDeath (YYYY-MM-01 - with precision to month, this will always be the first of the month)

--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @IndexDate datetime;
SET @IndexDate = '2020-02-01';

--> CODESET cancer

-- Define #Patients temp table to get age/sex and other demographics details.
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT PK_Patient_Link_ID AS FK_Patient_Link_ID INTO #Patients
FROM RLS.vw_Patient_Link
GROUP BY PK_Patient_Link_ID;



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


-- What does this do??? Do i need this?
-- SELECT ncp.*
-- INTO #PotentialMatches
-- FROM #NonCancerPatients AS ncp
-- LEFT OUTER JOIN #AllCancerPatients AS cp 
--   ON ncp.FK_Patient_Link_ID = cp.FK_Patient_Link_ID
-- WHERE cp.FK_Patient_Link_ID IS NULL;



--> EXECUTE query-cohort-matching-yob-sex.sql yob-flex:0
-- OUTPUT: A temp table as follows:
-- #CohortStore (FK_Patient_Link_ID, YearOfBirth, Sex, MatchingPatientId, MatchingYearOfBirth)
-- 281.720 rows. running time: 2 hours.

-- Define a table with all the patient ids for the entire cohort (main cohort and the matched cohort)
IF OBJECT_ID('tempdb..#AllPatientCohortIds') IS NOT NULL DROP TABLE #AllPatientCohortIds;
SELECT 
  PatientId As FK_Patient_Link_ID, 
  YearOfBirth, 
  Sex,
  'Y' AS HasCancer
INTO #AllPatientCohortIds 
FROM #CohortStore

UNION ALL
SELECT 
  MatchingPatientId,
  MatchingYearOfBirth,
  Sex,
  'N' AS HasCancer
FROM #CohortStore;





-- Get a table with unique patients for the entire cohort 
-- TODO
--   Find how many matches each cancer patient had. 
--   This will also remove any duplicates.
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT *, count(1) as NumberOfMatches
INTO #Patients
FROM #AllPatientCohortIds
GROUP BY FK_Patient_Link_ID, YearOfBirth, Sex, HasCancer;
-- 338.064 distinct patients
-- All cancer patients have 5 matches each.


-- Following query has copied in and adjusted to extract current smoking status on index date. 
--┌────────────────┐
--│ Smoking status │
--└────────────────┘

-- OBJECTIVE: To get the smoking status for each patient in a cohort.

-- INPUT: Assumes there exists a temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: A temp table as follows:
-- #PatientSmokingStatus (FK_Patient_Link_ID, PassiveSmoker, WorstSmokingStatus, CurrentSmokingStatus)
-- 	- FK_Patient_Link_ID - unique patient id
--	-	PassiveSmoker - Y/N (whether a patient has ever had a code for passive smoking)
--	-	WorstSmokingStatus - [non-trivial-smoker/trivial-smoker/non-smoker]
--	-	CurrentSmokingStatus - [non-trivial-smoker/trivial-smoker/non-smoker]

-- ASSUMPTIONS:
--	- We take the most recent smoking status in a patient's record to be correct
--	-	However, there is likely confusion between the "non smoker" and "never smoked" codes. Especially as sometimes the synonyms for these codes overlap. Therefore, a patient wih a most recent smoking status of "never", but who has previous smoking codes, would be classed as WorstSmokingStatus=non-trivial-smoker / CurrentSmokingStatus=non-smoker

--> CODESETS smoking-status-current smoking-status-currently-not smoking-status-ex smoking-status-ex-trivial smoking-status-never smoking-status-passive smoking-status-trivial
-- Get all patients year of birth for the cohort
IF OBJECT_ID('tempdb..#AllPatientSmokingStatusCodes') IS NOT NULL DROP TABLE #AllPatientSmokingStatusCodes;
SELECT 
	FK_Patient_Link_ID,
	CAST(EventDate AS DATE) AS EventDate,
	FK_Reference_Coding_ID,
	FK_Reference_SnomedCT_ID
INTO #AllPatientSmokingStatusCodes
FROM RLS.vw_GP_Events
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND (
	FK_Reference_SnomedCT_ID IN (
		SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets 
		WHERE Concept IN (
			'smoking-status-current',
			'smoking-status-currently-not',
			'smoking-status-ex',
			'smoking-status-ex-trivial',
			'smoking-status-never',
			'smoking-status-passive',
			'smoking-status-trivial'
		)
		AND [Version]=1
	) OR
  FK_Reference_Coding_ID IN (
		SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets 
		WHERE Concept IN (
			'smoking-status-current',
			'smoking-status-currently-not',
			'smoking-status-ex',
			'smoking-status-ex-trivial',
			'smoking-status-never',
			'smoking-status-passive',
			'smoking-status-trivial'
		)
		AND [Version]=1
	)
);

IF OBJECT_ID('tempdb..#AllPatientSmokingStatusConcept') IS NOT NULL DROP TABLE #AllPatientSmokingStatusConcept;
SELECT 
	a.FK_Patient_Link_ID,
	EventDate,
	CASE WHEN c.Concept IS NULL THEN s.Concept ELSE c.Concept END AS Concept,
	-1 AS Severity
INTO #AllPatientSmokingStatusConcept
FROM #AllPatientSmokingStatusCodes a
LEFT OUTER JOIN #VersionedCodeSets c on c.FK_Reference_Coding_ID = a.FK_Reference_Coding_ID
LEFT OUTER JOIN #VersionedSnomedSets s on s.FK_Reference_SnomedCT_ID = a.FK_Reference_SnomedCT_ID;

UPDATE #AllPatientSmokingStatusConcept
SET Severity = 2
WHERE Concept IN ('smoking-status-current');
UPDATE #AllPatientSmokingStatusConcept
SET Severity = 2
WHERE Concept IN ('smoking-status-ex');
UPDATE #AllPatientSmokingStatusConcept
SET Severity = 1
WHERE Concept IN ('smoking-status-ex-trivial');
UPDATE #AllPatientSmokingStatusConcept
SET Severity = 1
WHERE Concept IN ('smoking-status-trivial');
UPDATE #AllPatientSmokingStatusConcept
SET Severity = 0
WHERE Concept IN ('smoking-status-never');
UPDATE #AllPatientSmokingStatusConcept
SET Severity = 0
WHERE Concept IN ('smoking-status-currently-not');

-- passive smokers
IF OBJECT_ID('tempdb..#TempPassiveSmokers') IS NOT NULL DROP TABLE #TempPassiveSmokers;
select DISTINCT FK_Patient_Link_ID into #TempPassiveSmokers from #AllPatientSmokingStatusConcept
where Concept = 'smoking-status-passive';

-- For "worst" smoking status
IF OBJECT_ID('tempdb..#TempWorst') IS NOT NULL DROP TABLE #TempWorst;
SELECT 
	FK_Patient_Link_ID, 
	CASE 
		WHEN MAX(Severity) = 2 THEN 'non-trivial-smoker'
		WHEN MAX(Severity) = 1 THEN 'trivial-smoker'
		WHEN MAX(Severity) = 0 THEN 'non-smoker'
	END AS [Status]
INTO #TempWorst
FROM #AllPatientSmokingStatusConcept
WHERE Severity >= 0
GROUP BY FK_Patient_Link_ID;

-- For "current" smoking status
IF OBJECT_ID('tempdb..#TempCurrent') IS NOT NULL DROP TABLE #TempCurrent;
SELECT 
	a.FK_Patient_Link_ID, 
	CASE 
		WHEN MAX(Severity) = 2 THEN 'non-trivial-smoker'
		WHEN MAX(Severity) = 1 THEN 'trivial-smoker'
		WHEN MAX(Severity) = 0 THEN 'non-smoker'
	END AS [Status]
INTO #TempCurrent
FROM #AllPatientSmokingStatusConcept a
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(EventDate) AS MostRecentDate FROM #AllPatientSmokingStatusConcept
	WHERE (Severity >= 0 AND EventDate <= @IndexDate)
	GROUP BY FK_Patient_Link_ID
) sub ON sub.MostRecentDate = a.EventDate and sub.FK_Patient_Link_ID = a.FK_Patient_Link_ID
GROUP BY a.FK_Patient_Link_ID;

-- Bring all together in final table
IF OBJECT_ID('tempdb..#PatientSmokingStatus') IS NOT NULL DROP TABLE #PatientSmokingStatus;
SELECT 
	p.FK_Patient_Link_ID,
	CASE WHEN ps.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PassiveSmoker,
	CASE WHEN w.[Status] IS NULL THEN 'non-smoker' ELSE w.[Status] END AS WorstSmokingStatus,
	CASE WHEN c.[Status] IS NULL THEN 'non-smoker' ELSE c.[Status] END AS CurrentSmokingStatus
INTO #PatientSmokingStatus FROM #Patients p
LEFT OUTER JOIN #TempPassiveSmokers ps on ps.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #TempWorst w on w.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #TempCurrent c on c.FK_Patient_Link_ID = p.FK_Patient_Link_ID;









--> EXECUTE query-patient-lsoa.sql
--> EXECUTE query-patient-imd.sql

-- Uncomment when approved by ERG
-- --> EXECUTE query-get-covid-vaccines.sql

-- Get the first and second vaccine dates of our cohort. 
-- IF OBJECT_ID('tempdb..#COVIDVaccinations') IS NOT NULL DROP TABLE #COVIDVaccinations;
-- SELECT 
-- 	FK_Patient_Link_ID,
-- 	FirstVaccineDate = MAX(CASE WHEN VaccineDate IS NOT NULL AND DaysSinceFirstVaccine = 0 THEN VaccineDate ELSE NULL END), 
-- 	SecondVaccineDate = MAX(CASE WHEN VaccineDate IS NOT NULL AND DaysSinceFirstVaccine != 0 THEN VaccineDate ELSE NULL END) 
-- INTO #COVIDVaccinations
-- FROM #COVIDVaccinations
-- GROUP BY FK_Patient_Link_ID




--> CODESET bmi 

-- Get BMI for all patients in the cohort on 1 month prior to index date - 1st Jan 2020
-- Uses the BMI codeset version 2 to get the BMI values
IF OBJECT_ID('tempdb..#PatientBMIValues') IS NOT NULL DROP TABLE #PatientBMIValues;
SELECT 
	FK_Patient_Link_ID,
	CAST(EventDate AS DATE) AS EventDate,
	[Value] AS BMIValue
INTO #PatientBMIValues
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (
    SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets 
    WHERE 
      Concept IN ('bmi') AND [Version]=2
  ) OR
  FK_Reference_Coding_ID IN (
    SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets 
    WHERE 
      Concept IN ('bmi') AND [Version]=2
  )
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= DATEADD(month, -1, @IndexDate)
AND [Value] IS NOT NULL
AND [Value] != '0';

-- Get the latest BMI value before the index date 1st Jan 2020
IF OBJECT_ID('tempdb..#PatientLatestBMIValues') IS NOT NULL DROP TABLE #PatientLatestBMIValues;
SELECT
  FK_Patient_Link_ID,
	BMIValue,
  sub.BMILatestDate
INTO #PatientLatestBMIValues
FROM #PatientBMIValues
INNER JOIN (
  SELECT 
  	FK_Patient_Link_ID,
	  MAX(EventDate) as BMILatestDate
  FROM #PatientBMIValues
  GROUP BY FK_Patient_Link_ID
) sub on sub.FK_Patient_Link_ID = FK_Patient_Link_ID and sub.BMILatestDate = EventDate;




-- Get additional demographics information for all the patients in the cohort.
IF OBJECT_ID('tempdb..#MatchedCohort') IS NOT NULL DROP TABLE #MatchedCohort;
SELECT 
  FK_Patient_Link_ID, 
  YearOfBirth, 
  Sex, 
  HasCancer,
  NumberOfMatches,
  PassiveSmoker,
	WorstSmokingStatus,
	CurrentSmokingStatus,
  LSOA,
  IMD2019Decile1IsMostDeprived10IsLeastDeprived As IndicesOfDeprivation,
  EthnicCategoryDescription,
  BMIValue,
  BMILatestDate,
  FrailtyScore,
  FrailtyDeficits,
  FrailtyDeficitList,
  Deceased,
  DeathDate
INTO #MatchedCohort
FROM #Patients p
LEFT OUTER JOIN #PatientSmokingStatus sm ON sm.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientLSOA lsoa ON lsoa.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientIMDDecile imd ON imd.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN RLS.vw_Patient_Link pl ON pl.PK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientLatestBMIValues bmi ON bmi.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN RLS.vw_Patient pa ON pa.FK_Patient_Link_ID = p.FK_Patient_Link_ID;


