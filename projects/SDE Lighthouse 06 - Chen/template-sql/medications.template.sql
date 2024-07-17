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
DROP TABLE IF EXISTS Prescriptions;
CREATE TEMPORARY TABLE Prescriptions AS
SELECT 
	gp."FK_Patient_ID", 
	TO_DATE("MedicationDate") AS "MedicationDate", 
	"Dosage", 
	"Quantity", 
	"SuppliedCode",
    "MedicationDescription"
FROM INTERMEDIATE.GP_RECORD."GP_Medications_SecondaryUses" gp
INNER JOIN VersionedCodeSets vcs ON vcs.FK_Reference_Coding_ID = gp."FK_Reference_Coding_ID" AND vcs.Version =1
INNER JOIN VersionedSnomedSets vss ON vss.FK_Reference_SnomedCT_ID = gp."FK_Reference_SnomedCT_ID" AND vss.Version =1
WHERE 
 gp."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM AlivePatientsAtStart) AND
 vcs.Concept not in ('chronic-pain', 'opioids', 'cancer') AND
 vss.Concept not in ('chronic-pain', 'opioids', 'cancer') AND
 gp."MedicationDate" BETWEEN $StudyStartDate and $StudyEndDate;    -- only looking at prescriptions in the study period



