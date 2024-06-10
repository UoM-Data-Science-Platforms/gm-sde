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
DECLARE @StudyEndDate datetime;
SET @StudyEndDate = '2023-12-31'

--> EXECUTE query-get-possible-patients.sql
--> EXECUTE query-patient-date-of-birth.sql

--> CODESET cancer:1 chronic-pain:1

--> CODESET opioid-analgesics:1      

-- need to exclude opioids that are commonly used to treat addiction (e.g. methadone)


-- table of chronic pain coding events

IF OBJECT_ID('tempdb..#chronic_pain') IS NOT NULL DROP TABLE #chronic_pain;
SELECT gp.FK_Patient_Link_ID, EventDate
INTO #chronic_pain
FROM SharedCare.GP_Events gp
LEFT OUTER JOIN #PatientDateOfBirth dob ON dob.FK_Patient_Link_ID = gp.FK_Patient_Link_ID
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'chronic-pain' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'chronic-pain' AND Version = 1)
) 
AND EventDate BETWEEN @StudyStartDate AND @StudyEndDate
AND DATEDIFF(Year, dob.DateOfBirthPID, EventDate) > 18  --adults only

-- find first chronic pain code in the study period 
IF OBJECT_ID('tempdb..#FirstPain') IS NOT NULL DROP TABLE #FirstPain;
SELECT 
	FK_Patient_Link_ID, 
	FirstPainCodeDate = MIN(CAST(EventDate AS DATE))
INTO #FirstPain
FROM #chronic_pain
GROUP BY FK_Patient_Link_ID

-- find patients with a cancer code within 12 months either side of first chronic pain code
-- to exclude in next step

IF OBJECT_ID('tempdb..#cancer') IS NOT NULL DROP TABLE #cancer;
SELECT gp.FK_Patient_Link_ID, EventDate 
INTO #cancer
FROM SharedCare.GP_Events gp
LEFT JOIN #FirstPain fp ON fp.FK_Patient_Link_ID = gp.FK_Patient_Link_ID 
				AND gp.EventDate BETWEEN DATEADD(year, 1, FirstPainCodeDate) AND DATEADD(year, -1, FirstPainCodeDate)
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'cancer' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'cancer' AND Version = 1)
)
AND gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #chronic_pain)

-- find patients in the chronic pain cohort who received more than 2 opioids
-- for 14 days, within a 90 day period, after their first chronic pain code
-- excluding those with cancer code close to first pain code 

-- first get all opioid prescriptions for the cohort

IF OBJECT_ID('tempdb..#OpioidPrescriptions') IS NOT NULL DROP TABLE #OpioidPrescriptions;
SELECT 
	gp.FK_Patient_Link_ID, 
	CAST(MedicationDate AS DATE) AS MedicationDate, 
	Dosage, 
	Quantity, 
	SuppliedCode,
	fp.FirstPainCodeDate,
	PreviousOpioidDate = Lag(MedicationDate, 1) OVER 
		(PARTITION BY gp.FK_Patient_Link_ID ORDER BY MedicationDate ASC) 
INTO #OpioidPrescriptions
FROM SharedCare.GP_Medications gp
INNER JOIN #FirstPain fp ON fp.FK_Patient_Link_ID = gp.FK_Patient_Link_ID 
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'opioid-analgesics' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'opioid-analgesics' AND Version = 1)
)
AND gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #chronic_pain)
AND gp.FK_Patient_Link_ID NOT IN (SELECT FK_Patient_Link_ID FROM #cancer)
AND MedicationDate BETWEEN @StudyStartDate and @StudyEndDate
AND gp.MedicationDate > fp.FirstPainCodeDate

-- find all patients that have had two prescriptions within 90 days, and calculate the index date as
-- the first prescription that meets the criteria

IF OBJECT_ID('tempdb..#IndexDates') IS NOT NULL DROP TABLE #IndexDates;
SELECT FK_Patient_Link_ID, 
	IndexDate = MIN(PreviousOpioidDate)
INTO #IndexDates
FROM #OpioidPrescriptions
WHERE DATEDIFF(dd, PreviousOpioidDate, MedicationDate) <= 90
GROUP BY FK_Patient_Link_ID


-- create cohort of patients

IF OBJECT_ID('tempdb..#Cohort') IS NOT NULL DROP TABLE #Cohort;
SELECT
	 i.FK_Patient_Link_ID,
	 EthnicMainGroup, 
	 EthnicGroupDescription, 
	 DeathDate, 		 -- REMEMBER TO MASK THIS IN THE FINAL FILES
	 dob.DateOfBirthPID, -- REMEMBER TO MASK THIS IN THE FINAL FILES
	 i.IndexDate
INTO #Cohort
FROM #IndexDates i
LEFT OUTER JOIN #Patients p ON p.FK_Patient_Link_ID = i.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDateOfBirth dob ON dob.FK_Patient_Link_ID = i.FK_Patient_Link_ID


---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
