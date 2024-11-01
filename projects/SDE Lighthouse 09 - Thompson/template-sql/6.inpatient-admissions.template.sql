--┌───────────────────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 09 - Thompson - Inpatient hospital admissions │
--└───────────────────────────────────────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK ------------

--------------------------------------------------

set(StudyStartDate) = to_date('2020-01-01');
set(StudyEndDate)   = to_date('2024-09-30');

-- get all inpatient admissions

{{create-output-table::"LH009-6_InpatientAdmissions"}}
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
AND ap."GmPseudo" IN (SELECT "GmPseudo" FROM {{cohort-table}});

