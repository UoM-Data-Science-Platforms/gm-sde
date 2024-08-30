USE SCHEMA SDE_REPOSITORY.SHARED_UTILITIES;

--┌────────────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 14 - Whittaker - Inpatient admissions │
--└────────────────────────────────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK ---------
-- Richard Williams	2024-08-09	Review complete

-- Date range: 2018 to present

set(StudyStartDate) = to_date('2018-01-01');
set(StudyEndDate)   = to_date('2024-05-31');

-- get all inpatient admissions
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."5_InpatientAdmissions";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."5_InpatientAdmissions" AS
SELECT 
    "GmPseudo" -- NEEDS PSEUDONYMISING
    , TO_DATE("AdmissionDttm") AS "AdmissionDate"
    , TO_DATE("DischargeDttm") AS "DischargeDate"
	, "AdmissionMethodCode"
	, "AdmissionMethodDesc"
    , "HospitalSpellDuration" AS "LOS_days"
    , "DerPrimaryDiagnosisChapterDescReportingEpisode" AS PrimaryDiagnosisChapter
	, "DerPrimaryDiagnosisCodeReportingEpisode" AS PrimaryDiagnosisCode 
    , "DerPrimaryDiagnosisDescReportingEpisode" AS PrimaryDiagnosisDesc
FROM PRESENTATION.NATIONAL_FLOWS_APC."DS708_Apcs"
WHERE TO_DATE("AdmissionDttm") BETWEEN $StudyStartDate AND $StudyEndDate
	AND "GmPseudo" IN (select "GmPseudo" from SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_14_Whittaker");

