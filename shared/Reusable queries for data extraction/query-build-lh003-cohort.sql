--┌───────────────────────────────────────────────────────────────────┐
--│ Define Cohort for LH003: patients that had a dementia diagnosis   │
--└───────────────────────────────────────────────────────────────────┘

-- OBJECTIVE: To build the cohort of patients needed for LH003. This reduces duplication of code in the template scripts.

-- COHORT: Any patient with a dementia diagnosis between start and end date.

-- INPUT: assumes there exists one temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: Temp tables as follows:
-- #Cohort

--> EXECUTE query-get-possible-patients.sql
--> EXECUTE query-patient-year-of-birth.sql
--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-lsoa.sql
--> EXECUTE query-patient-imd.sql

--> CODESET dementia:1 

-- table of dementia coding events

IF OBJECT_ID('tempdb..#DementiaCodes') IS NOT NULL DROP #DementiaCodes;
SELECT FK_Patient_Link_ID AS PatientId, EventDate, COUNT(*) AS NumberOfDementiaCodes
INTO #DementiaCodes
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'dementia' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'dementia' AND Version = 1)
)
GROUP BY FK_Patient_Link_ID, EventDate

-- create cohort of patients with a dementia diagnosis in the study period

IF OBJECT_ID('tempdb..#Cohort') IS NOT NULL DROP #Cohort;
SELECT
	 p.FK_Patient_Link_ID
	,yob.YearOfBirth
	,sex.Sex
	,lsoa.LSOA_Code
	,p.EthnicMainGroup ----- CHANGE TO MORE SPECIFIC ETHNICITY ?
	,imd.IMD2019Decile1IsMostDeprived10IsLeastDeprived
	,p.DeathDate
INTO #Cohort
FROM #Patients p
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientLSOA lsoa ON lsoa.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientIMDDecile imd ON imd.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE p.FK_Patient_Link_ID IN 
	(SELECT DISTINCT FK_Patient_Link_ID
	 FROM #DementiaCodes
	 WHERE NumberOfDementiaCodes >= 1)
AND YEAR(@StartDate) - YearOfBirth > 18


---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
