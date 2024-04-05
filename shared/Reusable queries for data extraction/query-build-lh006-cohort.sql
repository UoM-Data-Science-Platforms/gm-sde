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


DECLARE @StudyStartDate datetime;
SET @StudyStartDate = '2017-01-01';

--> EXECUTE query-get-possible-patients.sql
--> EXECUTE query-patient-year-of-birth.sql

--> CODESET cancer:1 chronic-pain:1

--> CODESET opioid-analgesics:1      

-- need to exclude opioids that are commonly used to treat addiction (e.g. methadone)


-- table of chronic pain coding events

IF OBJECT_ID('tempdb..#chronic_pain') IS NOT NULL DROP TABLE #chronic_pain;
SELECT FK_Patient_Link_ID, EventDate
INTO #chronic_pain
FROM SharedCare.GP_Events
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'chronic-pain' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'chronic-pain' AND Version = 1)
)

-- table of cancer codes - to use for cohort exclusion (any cancer code within 12m from first chronic pain diagnosis)

IF OBJECT_ID('tempdb..#cancer') IS NOT NULL DROP tABLE #cancer;
SELECT FK_Patient_Link_ID, EventDate 
INTO #cancer
FROM SharedCare.GP_Events
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'cancer' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'cancer' AND Version = 1)
)
select * from #chronic_pain

-- find first chronic pain code in the period 
IF OBJECT_ID('tempdb..#first_pain') IS NOT NULL DROP tABLE #first_pain;
SELECT 
	FK_Patient_Link_ID, 
	FirstPainCode = MIN(EventDate)
INTO #first_pain
FROM #chronic_pain
WHERE MedicationDate BETWEEN '2017-01-01' and '2023-12-31'
GROUP BY FK_Patient_Link_ID


-- find patients in the chronic pain cohort who received more than 2 opioids
-- for 14 days, within a 90 day period, after their first chronic pain code, from 2017 to 2023 

-- first get all opioid prescriptions for the cohort

IF OBJECT_ID('tempdb..#OpioidPrescriptions') IS NOT NULL DROP TABLE #OpioidPrescriptions;
SELECT FK_Patient_Link_ID, MedicationDate, Dosage, Quantity, SuppliedCode
INTO #OpioidPrescriptions
FROM SharedCare.GP_Medications 
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'opioid-analgesics' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'opioid-analgesics' AND Version = 1)
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #chronic_pain)
AND FK_Patient_Link_ID NOT IN (SELECT FK_Patient_Link_ID FROM #cancer)
AND MedicationDate BETWEEN '2017-01-01' and '2023-12-31'


select FK_Patient_Link_ID, Lag(MedicationDate, 1) OVER (ORDER BY MedicationDate ASC) AS PreviousOpioidDate
from #OpioidPrescriptions

-- create cohort of patients with a chronic pain diagnosis in the study period, excluding cancer patients

IF OBJECT_ID('tempdb..#Cohort') IS NOT NULL DROP #Cohort;
SELECT
	 p.FK_Patient_Link_ID
	,yob.YearOfBirth
	,p.EthnicGroupDescription
	,FORMAT(p.DeathDate, 'yyyy-MM')
INTO #Cohort
FROM #Patients p
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE p.FK_Patient_Link_ID IN (SELECT DISTINCT FK_Patient_Link_ID FROM #x)
	AND p.FK_Patient_Link_ID NOT IN (SELECT DISTINCT FK_Patient_Link_ID FROM #cancer)
AND YEAR(@StartDate) - YearOfBirth > 18 -- over 18


---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
