--┌──────────────────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 01 - Newman - Inpatient hospital admissions │
--└──────────────────────────────────────────────────────────────────┘

set(StudyStartDate) = to_date('2020-01-01');
set(StudyEndDate)   = to_date('2023-12-31');

--> EXECUTE query-build-lh001-cohort.sql

-- get all inpatient admissions
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
-- "ProviderDesc" IN ('Manchester University NHS Foundation Trust', 'Pennine Acute Hospitals NHS Trust', 'Northern Care Alliance NHS Foundation Trust', 'Wrightington, Wigan And Leigh NHS Foundation Trust', 'Stockport NHS Foundation Trust', 'Bolton NHS Foundation Trust', 'Tameside And Glossop Integrated Care NHS Foundation Trust', 'The Christie NHS Foundation Trust') AND
-- FILTER OUT ELECTIVE ??   
TO_DATE("AdmissionDttm") BETWEEN $StudyStartDate AND $StudyEndDate
AND "GmPseudo" IN (SELECT "GmPseudo" FROM cOHORT);

