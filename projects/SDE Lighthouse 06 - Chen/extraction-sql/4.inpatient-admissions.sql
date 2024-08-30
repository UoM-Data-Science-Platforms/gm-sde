USE SCHEMA SDE_REPOSITORY.SHARED_UTILITIES;

--┌────────────────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 06 - Chen - Inpatient hospital admissions │
--└────────────────────────────────────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK ------------
-- Richard Williams	2024-08-30	Review complete --
--------------------------------------------------

set(StudyStartDate) = to_date('2017-01-01');
set(StudyEndDate)   = to_date('2023-12-31');

-- get all inpatient admissions


-- First we create a table in an area only visible to the RDEs which contains
-- the GmPseudo or FK_Patient_IDs. These cannot be released to end users.
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."4_InpatientAdmissions_WITH_PSEUDO_IDS";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."4_InpatientAdmissions_WITH_PSEUDO_IDS" AS
SELECT 
    ap."GmPseudo"
    , TO_DATE("AdmissionDttm") AS "AdmissionDate"
    , TO_DATE("DischargeDttm") AS "DischargeDate"
	, "AdmissionMethodCode"
	, "AdmissionMethodDesc"
    , "HospitalSpellDuration" AS "LOS_days"
    , "DerPrimaryDiagnosisChapterDescReportingEpisode" AS "PrimaryDiagnosisChapter"
	, "DerPrimaryDiagnosisCodeReportingEpisode" AS "PrimaryDiagnosisCode" 
    , "DerPrimaryDiagnosisDescReportingEpisode" AS "PrimaryDiagnosisDesc"
FROM PRESENTATION.NATIONAL_FLOWS_APC."DS708_Apcs" ap
WHERE  TO_DATE("AdmissionDttm") BETWEEN $StudyStartDate AND $StudyEndDate
AND ap."GmPseudo" IN (SELECT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_06_Chen");

-- Then we select from that table, to populate the table for the end users
-- where the GmPseudo or FK_Patient_ID fields are redacted via a function
-- created in the 0.code-sets.sql
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."4_InpatientAdmissions";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."4_InpatientAdmissions" AS
SELECT SDE_REPOSITORY.SHARED_UTILITIES.gm_pseudo_hash_SDE_Lighthouse_06_Chen("GmPseudo") AS "PatientID", * EXCLUDE "GmPseudo"
FROM SDE_REPOSITORY.SHARED_UTILITIES."4_InpatientAdmissions_WITH_PSEUDO_IDS";

