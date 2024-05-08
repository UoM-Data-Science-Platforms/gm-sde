--┌──────────────────────────────┐
--│ Medications for LH006 cohort │
--└──────────────────────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------
-- 
------------------------------------------------------

-- All prescriptions of: antipsychotic medication.

-- OUTPUT: Data with the following fields
-- 	-   PatientId (int)
--	-	MedicationCategory
--  -   MedicationName
--  -   Quantity
--  -   Dosage

--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2017-01-01';
SET @EndDate = '2023-12-31';

--> EXECUTE query-build-lh006-cohort.sql

-- codesets already added (from buid-lh006-cohort file): opioids-analgesics:1,  

-- CODESET nsaids:1 benzodiazepines:1 gabapentinoid:1

--  PATIENTS WITH RX OF SELECTED MEDS (2017 - 2023)

IF OBJECT_ID('tempdb..#meds') IS NOT NULL DROP TABLE #meds;
SELECT 
	 m.FK_Patient_Link_ID,
		CAST(MedicationDate AS DATE) as PrescriptionDate,
		FullDescription,
		MedicationCategory = CASE WHEN vcs.Concept IS NOT NULL THEN vcs.Concept ELSE vs.Concept END
INTO #meds
FROM SharedCare.GP_Medications m
WHERE m.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort)
LEFT JOIN #VersionedSnomedSets vs ON vs.FK_Patient_Link_ID = m.FK_Patient_Link_ID AND (Concept IN ('opioids-analgesics','nsaids','benzodiazepines','gabapentinoid' ) AND [Version]=1)
LEFT JOIN #VersionedCodeSets vcs ON vcs.FK_Patient_Link_ID = m.FK_Patient_Link_ID AND (Concept IN ('opioids-analgesics','nsaids','benzodiazepines','gabapentinoid' ) AND [Version]=1)
AND m.MedicationDate BETWEEN @StartDate AND @EndDate


