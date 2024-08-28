USE SCHEMA SDE_REPOSITORY.SHARED_UTILITIES;

--┌────────────────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 06 - Chen - Inpatient hospital admissions │
--└────────────────────────────────────────────────────────────────┘

USE PRESENTATION.NATIONAL_FLOWS_APC;

set(StudyStartDate) = to_date('2017-01-01');
set(StudyEndDate)   = to_date('2023-12-31');

-- get all inpatient admissions

DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."4_InpatientAdmissions";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."4_InpatientAdmissions" AS
SELECT 
    "GmPseudo"
    , TO_DATE("AdmissionDttm") AS "AdmissionDate"
    , TO_DATE("DischargeDttm") AS "DischargeDate"
	, "AdmissionMethodCode"
	, "AdmissionMethodDesc"
    , "HospitalSpellDuration" AS "LOS_days"
    , "DerPrimaryDiagnosisChapterDescReportingEpisode" AS PrimaryDiagnosisChapter
	, "DerPrimaryDiagnosisCodeReportingEpisode" AS PrimaryDiagnosisCode 
    , "DerPrimaryDiagnosisDescReportingEpisode" AS PrimaryDiagnosisDesc
FROM PRESENTATION.NATIONAL_FLOWS_APC."DS708_Apcs"
WHERE 
-- FILTER OUT ELECTIVE ??   
TO_DATE("AdmissionDttm") BETWEEN $StudyStartDate AND $StudyEndDate
AND "GmPseudo" IN (SELECT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_06_Chen");

