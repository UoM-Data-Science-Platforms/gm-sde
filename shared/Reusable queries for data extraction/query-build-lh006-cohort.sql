--┌───────────────────────────────────────────────────────────────────┐
--│ Define Cohort for LH006: patients that had a dementia diagnosis   │
--└───────────────────────────────────────────────────────────────────┘

-- OBJECTIVE: To build the cohort of patients needed for LH006. This reduces duplication of code in the template scripts.

-- COHORT: Any adult patient with non-chronic cancer pain, who received more than two oral or transdermal opioid prescriptions
--          for 14 days within 90 days, between 2017 and 2023.
--          Excluding patients with a cancer diagnosis within 12 months from index date

-- INPUT: none
-- OUTPUT: Temp tables as follows:
-- #Cohort
-- #Patients (reduced to cohort only)

--> EXECUTE query-get-possible-patients.sql
--> EXECUTE query-patient-year-of-birth.sql

DECLARE @StudyStartDate datetime;
SET @StudyStartDate = '2017-01-01';


--> CODESET cancer:1

--> CODESET opioid-analgesics:1 nsaids:1 benzodiazepines:1


-- table of chronic pain coding events

IF OBJECT_ID('tempdb..#x') IS NOT NULL DROP #x;
SELECT FK_Patient_Link_ID AS PatientId, EventDate
INTO #x
FROM SharedCare.GP_Events
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'dementia' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'dementia' AND Version = 1)
)


-- table of patients that had a cancer code within 12m of index date - to exclude from cohort

IF OBJECT_ID('tempdb..#cancer') IS NOT NULL DROP #cancer;
SELECT FK_Patient_Link_ID 
INTO #cancer
FROM SharedCare.GP_Events
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'cancer' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'cancer' AND Version = 1)
)
GROUP BY FK_Patient_Link_ID, EventDate



-- create cohort of patients with a chronic pain diagnosis in the study period, excluding cancer patients

IF OBJECT_ID('tempdb..#Cohort') IS NOT NULL DROP #Cohort;
SELECT
	 p.FK_Patient_Link_ID
	,yob.YearOfBirth
	,p.EthnicGroupDescription
	,p.DeathDate
INTO #Cohort
FROM #Patients p
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE p.FK_Patient_Link_ID IN (SELECT DISTINCT FK_Patient_Link_ID FROM #x)
	AND p.FK_Patient_Link_ID NOT IN (SELECT DISTINCT FK_Patient_Link_ID FROM #cancer)
AND YEAR(@StartDate) - YearOfBirth > 18 -- over 18


---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
