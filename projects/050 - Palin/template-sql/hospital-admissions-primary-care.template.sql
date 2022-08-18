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
SET @EndDate = '2022-01-01';

--Just want the output, not the messages
SET NOCOUNT ON;

-- Find all patients alive at start date
IF OBJECT_ID('tempdb..#PossiblePatients') IS NOT NULL DROP TABLE #PossiblePatients;
SELECT PK_Patient_Link_ID as FK_Patient_Link_ID, EthnicMainGroup, DeathDate INTO #PossiblePatients FROM [RLS].vw_Patient_Link
WHERE (DeathDate IS NULL OR DeathDate >= @StartDate);

-- Find all patients registered with a GP
IF OBJECT_ID('tempdb..#PatientsWithGP') IS NOT NULL DROP TABLE #PatientsWithGP;
SELECT DISTINCT FK_Patient_Link_ID INTO #PatientsWithGP FROM [RLS].vw_Patient
where FK_Reference_Tenancy_ID = 2;

-- Make cohort from patients alive at start date and registered with a GP
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT pp.* INTO #Patients FROM #PossiblePatients pp
INNER JOIN #PatientsWithGP gp on gp.FK_Patient_Link_ID = pp.FK_Patient_Link_ID;

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
