--┌──────────────────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 01 - Newman - Inpatient hospital admissions │
--└──────────────────────────────────────────────────────────────────┘

set(StudyStartDate) = to_date('2020-01-01');
set(StudyEndDate)   = to_date('2023-12-31');

-- get all inpatient admissions
{{create-output-table::"LH001-5_InpatientAdmissions"}}
SELECT 
    "GmPseudo"
    , TO_DATE("AdmissionDttm") AS "AdmissionDate"
    , TO_DATE("DischargeDttm") AS "DischargeDate"
	, "AdmissionMethodCode"
	, "AdmissionMethodDesc"
    , "HospitalSpellDuration" AS "LOS_days"
    , "DerPrimaryDiagnosisChapterDescReportingEpisode" AS "PrimaryDiagnosisChapter"
	, "DerPrimaryDiagnosisCodeReportingEpisode" AS "PrimaryDiagnosisCode" 
    , "DerPrimaryDiagnosisDescReportingEpisode" AS "PrimaryDiagnosisDesc"
FROM PRESENTATION.NATIONAL_FLOWS_APC."DS708_Apcs"
WHERE TO_DATE("AdmissionDttm") BETWEEN $StudyStartDate AND $StudyEndDate
	AND "GmPseudo" IN (SELECT "GmPseudo" FROM {{cohort-table}});