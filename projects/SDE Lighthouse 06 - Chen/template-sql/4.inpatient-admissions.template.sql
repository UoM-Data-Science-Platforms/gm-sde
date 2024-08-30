--┌────────────────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 06 - Chen - Inpatient hospital admissions │
--└────────────────────────────────────────────────────────────────┘

set(StudyStartDate) = to_date('2017-01-01');
set(StudyEndDate)   = to_date('2023-12-31');

-- get all inpatient admissions

DROP TABLE IF EXISTS {{project-schema}}."4_InpatientAdmissions";
CREATE TABLE {{project-schema}}."4_InpatientAdmissions" AS
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
LEFT JOIN {{cohort-table}} c ON c."GmPseudo" = ap."GmPseudo"
WHERE 
-- FILTER OUT ELECTIVE ??   
TO_DATE("AdmissionDttm") BETWEEN $StudyStartDate AND $StudyEndDate
AND ap."GmPseudo" IN (SELECT "GmPseudo" FROM {{cohort-table}});

