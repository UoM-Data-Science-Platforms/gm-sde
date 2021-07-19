--┌─────────────────────────────────┐
--│ Patients demographics           │
--└─────────────────────────────────┘


-- Defines the cohort (cancer and non cancer patients) that will be used for the study, based on: 
-- Main cohort (cancer patients) includes:
--	- First cancer diagnosis between 1st February 2015 and 1st February 2020 
--  - First secondary cancer diagnosis between 1st February 2015 and 1st February 2020
--	- >= 18 year old 
--	- Alive on 1st Feb 2020 
-- Control group (non cancer patients):
--  -	Alive on 1st February 2020 
--  -	no current or history of cancer diagnosis.
-- Matching is 1:5 based on sex and year of birth with a flexible year of birth = 0
-- Index date is: 1st February 2020


-- OUTPUT: A single table with the following:
--  •	PatientId (int)
--  •	YearOfBirth (int in this format YYYY)
--  •	Sex (M/F/U)
--  •	HasCancer (Y/N)
--  •	NumberOfMatches (No from 1-5. Note: Non cancer patients will have 1 in this field.)
--	•	PassiveSmoker - Y/N (whether a patient has ever had a code for passive smoking)
--	•	WorstSmokingStatus - (non-trivial-smoker/trivial-smoker/non-smoker)
--	•	CurrentSmokingStatus - (non-trivial-smoker/trivial-smoker/non-smoker)
--  •	LSOA (nationally recognised LSOA identifier)
--  •	IndicesOfDeprivation (IMD 2019: number 1 to 10 inclusive)
--  •	BMIValue ()
--  •	BMILatestDate (YYYY-MM-DD) Latest date that a BMI value has been captured on or before 1 month prior to index date
--  •	Ethnicity 
--  •	FrailtyScore (as captured in PatientLink)
--  •	FrailtyDeficits 
--  •	FrailtyDeficitList 
--  •	FirstVaccineDate (date of vaccine (YYYY-MM-DD)) 
--  •	SecondVaccineDate (date of second vaccine (YYYY-MM-DD), null otherwise)
--  •	DeathStatus (Alive/Dead)
--  •	DeathDate (YYYY-MM-01 - with precision to month, this will always be the first of the month)

--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2020-02-01';

--> EXECUTE query-cancer-cohort-matching.sql
-- OUTPUT:, #Patients


-- Following query has been copied in and adjusted to extract current smoking status on index date 
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

--> CODESET smoking-status-current:1 smoking-status-currently-not:1 smoking-status-ex:1 smoking-status-ex-trivial:1 smoking-status-never:1 smoking-status-passive:1 smoking-status-trivial:1
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
	WHERE (Severity >= 0 AND EventDate <= @StartDate)
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
--> EXECUTE query-get-covid-vaccines.sql

-- Get the first and second vaccine dates of our cohort. 
IF OBJECT_ID('tempdb..#COVIDVaccinations2') IS NOT NULL DROP TABLE #COVIDVaccinations2;
SELECT 
	FK_Patient_Link_ID,
	FirstVaccineDate = MAX(CASE WHEN VaccineDate IS NOT NULL AND DaysSinceFirstVaccine = 0 THEN VaccineDate ELSE NULL END), 
	SecondVaccineDate = MAX(CASE WHEN VaccineDate IS NOT NULL AND DaysSinceFirstVaccine != 0 THEN VaccineDate ELSE NULL END) 
INTO #COVIDVaccinations2
FROM #COVIDVaccinations
GROUP BY FK_Patient_Link_ID




--> CODESET bmi:2

-- Get BMI for all patients in the cohort on 1 month prior to index date - 1st Jan 2020
-- Uses the BMI codeset version 2 to get the BMI values
IF OBJECT_ID('tempdb..#PatientBMIValues') IS NOT NULL DROP TABLE #PatientBMIValues;
SELECT 
	FK_Patient_Link_ID,
	CAST(EventDate AS DATE) AS EventDate,
	[Value] AS BMIValue,
	Row_Number() OVER(PARTITION BY FK_Patient_Link_ID ORDER BY EventDate DESC) AS DateRowNumber
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
AND EventDate <= DATEADD(month, -1, @StartDate)
AND [Value] IS NOT NULL
AND [Value] != '0';

-- Get the latest BMI value before the index date 1st Jan 2020
IF OBJECT_ID('tempdb..#PatientLatestBMIValues') IS NOT NULL DROP TABLE #PatientLatestBMIValues;
SELECT
  FK_Patient_Link_ID,
  BMIValue,
  EventDate as BMILatestDate
INTO #PatientLatestBMIValues
FROM #PatientBMIValues
WHERE 
  DateRowNumber = 1;

-- Get  frailty information 
-- If patients have a tenancy id of 2 we take this as their most likely frailty
-- as this is the GP data feed and so most likely to be up to date
IF OBJECT_ID('tempdb..#PatientFrailty') IS NOT NULL DROP TABLE #PatientFrailty;
SELECT
  FK_Patient_Link_ID,
  FrailtyScore,
  FrailtyDeficits,
  FrailtyDeficitList,
  Row_Number() OVER(PARTITION BY FK_Patient_Link_ID ORDER BY FrailtyScore DESC) AS FrailtyRowNumber
INTO #PatientFrailty
FROM RLS.vw_Patient
WHERE 
  FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
  AND FK_Reference_Tenancy_ID = 2

-- De-duped to get the highest frailty score per patient. 
IF OBJECT_ID('tempdb..#PatientHighestFrailty') IS NOT NULL DROP TABLE #PatientHighestFrailty;
SELECT
  FK_Patient_Link_ID,
  FrailtyScore,
  FrailtyDeficits,
  FrailtyDeficitList
INTO #PatientHighestFrailty
FROM #PatientFrailty
WHERE 
  FrailtyRowNumber = 1;

-- Get additional demographics information for all the patients in the cohort.
SELECT 
  p.FK_Patient_Link_ID AS PatientId, 
  p.YearOfBirth, 
  p.Sex, 
  p.HasCancer,
  p.NumberOfMatches,
  sm.PassiveSmoker,
  sm.WorstSmokingStatus,
  sm.CurrentSmokingStatus,
  lsoa.LSOA_Code AS LSOA,
  imd.IMD2019Decile1IsMostDeprived10IsLeastDeprived As IndicesOfDeprivation,
  pl.EthnicCategoryDescription AS Ethnicity,
  bmi.BMIValue,
  bmi.BMILatestDate,
  pa.FrailtyScore,
  pa.FrailtyDeficits,
  pa.FrailtyDeficitList,
  cv.FirstVaccineDate,
  cv.SecondVaccineDate,
  pl.Deceased AS DeathStatus,
  pl.DeathDate
FROM #Patients p
LEFT OUTER JOIN #PatientSmokingStatus sm ON sm.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientLSOA lsoa ON lsoa.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientIMDDecile imd ON imd.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDVaccinations2 cv ON cv.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN RLS.vw_Patient_Link pl ON pl.PK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientLatestBMIValues bmi ON bmi.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientHighestFrailty pa ON pa.FK_Patient_Link_ID = p.FK_Patient_Link_ID;


