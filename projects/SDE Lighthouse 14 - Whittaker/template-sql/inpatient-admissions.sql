--┌────────────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 14 - Whittaker - Inpatient admissions │
--└────────────────────────────────────────────────────────────┘

-- Date range: 2018 to present

---- find the latest snapshot for each spell, to get all virtual ward patients
drop table if exists virtualWards;
create temporary table virtualWards as
select  
	distinct SUBSTRING(vw."Pseudo NHS Number", 2)::INT as "GmPseudo"
from PRESENTATION.LOCAL_FLOWS_VIRTUAL_WARDS.VIRTUAL_WARD_OCCUPANCY vw;

-- find all inpatient admissions for greater manchester trusts

DROP TABLE IF EXISTS ManchesterTrusts;
CREATE TEMPORARY TABLE ManchesterTrusts AS 
SELECT top 1000 *
FROM PRESENTATION.NATIONAL_FLOWS_APC."DS708_Apcs"
WHERE "ProviderDesc" IN 
    ('Manchester University NHS Foundation Trust',
     'Pennine Acute Hospitals NHS Trust',
     'Northern Care Alliance NHS Foundation Trust',
     'Wrightington, Wigan And Leigh NHS Foundation Trust',
     'Stockport NHS Foundation Trust',
     'Bolton NHS Foundation Trust',
     'Tameside And Glossop Integrated Care NHS Foundation Trust',
     'The Christie NHS Foundation Trust')
  -- FILTER OUT ELECTIVE ??   
AND TO_DATE("AdmissionDttm") BETWEEN $StudyStartDate and $StudyEndDate
     ;

-- final table

SELECT
    "GmPseudo"
    , TO_DATE("AdmissionDttm") AS "AdmissionDate"
    , TO_DATE("DischargeDttm") AS "DischargeDate"
    , "ProviderDesc"
    , "HospitalSpellDuration" AS "LOS_days"
    , "DerPrimaryDiagnosisChapterDescReportingEpisode" AS PrimaryDiagnosisChapter
	, "DerPrimaryDiagnosisCodeReportingEpisode" AS PrimaryDiagnosisCode 
    , "DerPrimaryDiagnosisDescReportingEpisode" AS PrimaryDiagnosisDesc
FROM ManchesterTrusts