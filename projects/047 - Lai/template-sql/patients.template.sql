--┌────────────────────────────────────┐
--│ Patient demographics               │
--└────────────────────────────────────┘

-- OUTPUT: Data with the following fields
-- 	- PatientId (int)
--  - YOB (year of birth - YYYY)
--  - Sex (M/F)
--  - Ethnicity
--  - HasCancer (Y/N)  ????
--  - IMD2019Decile1IsMostDeprived10IsLeastDeprived (IMD 2019: number 1 to 10 inclusive) Individual index of multiple deprivation quintile score
--  - LSOA (Geographical location)

--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2018-01-01';


-- Get patients with a diagnosis for skin cancer from Jan 2018.
IF OBJECT_ID('tempdb..#SkinCancerPatients') IS NOT NULL DROP TABLE #SkinCancerPatients;
SELECT 
  FK_Patient_Link_ID,
  CAST(EventDate AS DATE) AS DiagnosisDate
INTO #SkinCancerPatients
FROM RLS.vw_GP_Events
WHERE (
  FK_Reference_SnomedCT_ID IN (
      SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('cancer') AND [Version]=3
  ) OR
  FK_Reference_Coding_ID IN (
      SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('cancer') AND [Version]=3
  )  
) 
AND DiagnosisDate >= @StartDate
GROUP BY FK_Patient_Link_ID;


-- Get patients with a diagnosis for gynae cancer from Jan 2018.
IF OBJECT_ID('tempdb..#GynaeCancerPatients') IS NOT NULL DROP TABLE #GynaeCancerPatients;
SELECT 
  FK_Patient_Link_ID,
  CAST(EventDate AS DATE) AS DiagnosisDate
INTO #GynaeCancerPatients
FROM RLS.vw_GP_Events
WHERE (
  FK_Reference_SnomedCT_ID IN (
      SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('cancer') AND [Version]=4
  ) OR
  FK_Reference_Coding_ID IN (
      SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('cancer') AND [Version]=4
  ) 
)
AND DiagnosisDate >= @StartDate
GROUP BY FK_Patient_Link_ID;

-- Get unique patients with a skin or/and gynae cancer diagnosis within the time period.
-- `UNION` will exclude duplicates
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT 
  FK_Patient_Link_ID
INTO #Patients 
FROM #SkinCancerPatients
UNION
SELECT 
  FK_Patient_Link_ID
FROM #GynaeCancerPatients;

--> EXECUTE query-patient-year-of-birth.sql
--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-lsoa.sql
--> EXECUTE query-patient-imd.sql

IF OBJECT_ID('tempdb..#PatientsDemographics') IS NOT NULL DROP TABLE #PatientsDemographics;
SELECT
  FK_Patient_Link_ID AS PatientId,
  YearOfBirth,
  Sex,
  pl.NHS_EthnicCategory AS Ethnicity,
  IMD2019Decile1IsMostDeprived10IsLeastDeprived,
  LSOA_Code AS LSOA
FROM #Patients p
LEFT JOIN #PatientYearOfBirth pyob ON p.FK_Patient_Link_ID = pyob.FK_Patient_Link_ID
LEFT JOIN #PatientSex ps ON p.FK_Patient_Link_ID = ps.FK_Patient_Link_ID
LEFT OUTER JOIN RLS.vw_Patient_Link pl ON pl.PK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT JOIN #PatientIMDDecile pimd ON pimd.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT JOIN #PatientLSOA plsoa ON plsoa.FK_Patient_Link_ID = p.FK_Patient_Link_ID;


