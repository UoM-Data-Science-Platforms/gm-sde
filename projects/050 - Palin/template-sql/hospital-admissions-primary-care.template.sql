--┌──────────────────────────────────────────────────────────────────────────────────┐
--│ Hospital inpatient episodes for pregnancy cohort - identified from primary care  │
--└──────────────────────────────────────────────────────────────────────────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------

-- OUTPUT: Data with the following fields
-- Patient Id
-- AdmissionDate (DD-MM-YYYY)

-- Set the start date
DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2012-01-01';
SET @EndDate = '2023-08-31';

--Just want the output, not the messages
SET NOCOUNT ON;

----------------------------------------
--> EXECUTE query-build-rq050-cohort.sql
----------------------------------------

-- Find all indications of a hospital encounter in the GP record 

-- add ReadCodes
SELECT 'Hospital' AS EncounterType, PK_Reference_Coding_ID, FK_Reference_SnomedCT_ID
INTO #CodingClassifier
FROM SharedCare.Reference_Coding
WHERE CodingType='ReadCodeV2'
AND (
	MainCode like '7%'
	or MainCode like '8H[1-3]%'
	or MainCode like '9N%' 
);

-- Add the equivalent CTV3 codes
INSERT INTO #CodingClassifier
SELECT 'Hospital', PK_Reference_Coding_ID, FK_Reference_SnomedCT_ID FROM SharedCare.Reference_Coding
WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #CodingClassifier WHERE EncounterType='Hospital' AND FK_Reference_SnomedCT_ID != -1)
AND CodingType='CTV3';

-- Add the equivalent EMIS codes
INSERT INTO #CodingClassifier
SELECT 'Hospital', FK_Reference_Coding_ID, FK_Reference_SnomedCT_ID FROM SharedCare.Reference_Local_Code
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #CodingClassifier WHERE EncounterType='Hospital' AND FK_Reference_SnomedCT_ID != -1) OR
	FK_Reference_Coding_ID IN (SELECT PK_Reference_Coding_ID FROM #CodingClassifier WHERE EncounterType='Hospital' AND PK_Reference_Coding_ID != -1)
);

--FIND ALL EVENTS IN GP RECORD INDICATING A HOSPITAL ENCOUNTER
IF OBJECT_ID('tempdb..#HospitalEncounters') IS NOT NULL DROP TABLE #HospitalEncounters;
SELECT DISTINCT FK_Patient_Link_ID, CAST(EventDate AS DATE) AS EntryDate
INTO #HospitalEncounters
FROM #PatientEventData
WHERE FK_Reference_Coding_ID IN (SELECT PK_Reference_Coding_ID FROM #CodingClassifier)
AND EventDate BETWEEN @StartDate and @EndDate;

--bring together for final output
SELECT 
	PatientId = FK_Patient_Link_ID,
	AdmissionDate = EntryDate
FROM #HospitalEncounters
