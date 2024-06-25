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
set(StudyStartDate) = to_date('2017-01-01');
set(StudyEndDate)   = to_date('2023-12-31');

--> EXECUTE query-build-lh006-cohort.sql

-- codesets already added (from buid-lh006-cohort file): opioids:1 cancer:1 chronic-pain:1

-- CODESET nsaids:1 benzodiazepines:1 gabapentinoid:1

--  PATIENTS WITH RX OF SELECTED MEDS (2017 - 2023)

DROP TABLE IF EXISTS meds;
CREATE TEMPORARY TABLE AS
SELECT 
	 m."FK_Patient_ID",
		TO_DATE("MedicationDate") as PrescriptionDate,
		FullDescription,
		MedicationCategory = CASE WHEN vcs.Concept IS NOT NULL THEN vcs.Concept ELSE vs.Concept END
FROM INTERMEDIATE.GP_RECORD."GP_Medications_SecondaryUses" m
WHERE m."FK_Patient_ID" IN (SELECT FK_Patient_ID FROM Cohort)
LEFT JOIN VersionedSnomedSets vs ON vs.FK_Patient_ID = m."FK_Patient_ID" AND (Concept IN ('opioids','nsaids','benzodiazepines','gabapentinoid' ) AND [Version]=1)
LEFT JOIN VersionedCodeSets vcs ON vcs.FK_Patient_ID = m."FK_Patient_ID" AND (Concept IN ('opioids','nsaids','benzodiazepines','gabapentinoid' ) AND [Version]=1)
AND m."MedicationDate" BETWEEN $StudyStartDate and $StudyEndDate  


