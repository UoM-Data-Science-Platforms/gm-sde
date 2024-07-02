--┌───────────────────────────────────────────────────────────────┐
--│ Define Cohort for LH004: patients that had an SLE diagnosis   │
--└───────────────────────────────────────────────────────────────┘

-- OBJECTIVE: To build the cohort of patients needed for LH004. This reduces duplication of code in the template scripts.

-- COHORT: Any patient with a SLE diagnosis between start and end date.

-- INPUT: None

-- OUTPUT: Temp tables as follows:
-- #Cohort

DECLARE @StudyStartDate datetime;
SET @StudyStartDate = '2020-01-01'; 

--> EXECUTE query-get-possible-patients.sql
--> EXECUTE query-patient-year-of-birth.sql

--> CODESET sle:1 

------- EXCLUSIONS: PI wants to exclude the following: lupus pernio, neonatal lupus, drug-induced lupus, tuberculosis, cutaneous lupus without a corresponding 
------- systemic diagnosis, codes relating to a diagnostic test

------- lupus pernio, drug-induced lupus, and neonatal lupus code sets have been created - but prevalence suggests they are unused


--> CODESET tuberculosis:1 

-- table of sle coding events

IF OBJECT_ID('tempdb..#SLECodes') IS NOT NULL DROP TABLE #SLECodes;
SELECT FK_Patient_Link_ID, EventDate
INTO #SLECodes
FROM SharedCare.[GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'sle' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'sle' AND Version = 1)
)
GROUP BY FK_Patient_Link_ID, EventDate

-- table of patients that meet the exclusion criteria: turberculosis, lupus pernio, drug-induced lupus, neonatal lupus

IF OBJECT_ID('tempdb..#Exclusions') IS NOT NULL DROP TABLE #Exclusions;
SELECT FK_Patient_Link_ID AS PatientId, EventDate
INTO #Exclusions
FROM SharedCare.[GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'tuberculosis' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'tuberculosis' AND Version = 1)
)
GROUP BY FK_Patient_Link_ID, EventDate


-- create cohort of patients with an SLE diagnosis in the study period

IF OBJECT_ID('tempdb..#Cohort') IS NOT NULL DROP TABLE #Cohort;
SELECT
	 p.FK_Patient_Link_ID
	,yob.YearOfBirth
	,p.EthnicGroupDescription
	,p.DeathDate
INTO #Cohort
FROM #Patients p
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE 
	p.FK_Patient_Link_ID IN (SELECT DISTINCT FK_Patient_Link_ID FROM #SLECodes)
	AND p.FK_Patient_Link_ID NOT IN (SELECT DISTINCT FK_Patient_Link_ID FROM #Exclusions)
AND 2020 - YearOfBirth > 18

---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
