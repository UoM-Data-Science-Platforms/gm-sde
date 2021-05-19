--┌─────────────────────────────────┐
--│ Patients demographics           │
--└─────────────────────────────────┘

-- OUTPUT: Data with the following fields
--  •	PatientID (int)
--  •	YearOfBirth (int in this format YYYY)
--  •	Sex (M/F/U)
--  •	Location (LSOA residence)
--  •	IndicesOfDeprivation (IMD 2019)
--  •	BMI (for anyone over the age of 16 as at 1st February 2020 or within 1 month prior to index date)
--  •	SmokingStatus (as of 1st February 2020)
--  •	Ethnicity (TODO)
--  •	FrailtyScore (as captured in GP records)
--  •	FrailtyDeficits 
--  •	FrailtyDeficitList 
--  •	DeathStatus (Alive/Dead)
--  •	DateOfDeath (YYYY-MM-01 - with precision to month, this will always be the first of the month)

--Just want the output, not the messages
SET NOCOUNT ON;


-- Define the main cohort that will be matched based on: 
--	Cancer diagnosis between 1st February 2015 and 1st February 2020
--	>= 18 year old 
--	Alive on 1st Feb 2020 



--> CODESET cancer
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT 
  FK_Patient_Link_ID
INTO #Patients
FROM RLS.vw_GP_Events
WHERE (
  FK_Reference_SnomedCT_ID IN (
      SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('cancer') AND [Version]=1
  ) OR
  FK_Reference_Coding_ID IN (
      SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('cancer') AND [Version]=1
  ) AND (
      CAST(EventDate AS DATE) BETWEEN '2015-02-01' AND '2020-02-01'
  )
)
GROUP BY FK_Patient_Link_ID;


--> EXECUTE query-patient-year-of-birth.sql
--> EXECUTE query-patient-sex.sql

-- Get adult cancer patients for the main cohort.
IF OBJECT_ID('tempdb..#AdultCancerCohort') IS NOT NULL DROP TABLE #AdultCancerCohort;
SELECT 
  p.FK_Patient_Link_ID,
  sex.Sex,
  yob.YearOfBirth
INTO #AdultCancerCohort
FROM #Patients p
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE 
  YearOfBirth <= '2002-02-01';


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
  (pl.DeathDate is not null and (pl.DeathDate >= '2020-02-01'));



-- Define the population of potential matches for the cohort
--	Alive on 1st February 2020 
--	no current or history of cancer diagnosis (Christie registered or in ICDR record).


SELECT 
  PatientID,
  YearOfBirth,
  Sex,
  Location,
  IndicesOfDeprivation,
  BMI,
  SmokingStatus,
  Ethnicity,
  FrailtyScore,
  FrailtyDeficits,
  FrailtyDeficitList,
  DeathStatus,
  DateOfDeath
FROM TODO