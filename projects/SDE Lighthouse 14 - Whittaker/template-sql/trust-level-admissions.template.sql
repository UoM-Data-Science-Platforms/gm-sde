--┌──────────────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 14 - Whittaker - Trust level admissions │
--└──────────────────────────────────────────────────────────────┘

-- Date range: 2018 to present


-- Emergency department attendances: 
	-- Total
	-- by ICD
	-- by ageband 

-- Average emergency department door to provider time - UNLIKELY

-- Average emergency department onboarding time - UNLIKELY

-- Average bed request to assign time - UNLIKELY



-- CREATE A TABLE OF ADMISSIONS FROM GM TRUSTS

DROP TABLE IF EXISTS ManchesterTrusts;
CREATE TEMPORARY TABLE ManchesterTrusts AS 
SELECT *
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
     ;

-- MONTHLY ADMISSION COUNTS AND AVG LENGTH OF STAY BY TRUST

    -- GROUP BY TRUST ONLY
CREATE TEMPORARY TABLE MonthlyAdmissionsByTrust AS 
select 
      YEAR("AdmissionDttm") AS "Year"
    , MONTH("AdmissionDttm") AS "Month"
    ,"ProviderDesc"
    , COUNT(*)  AS "Admissions"
    , AVG("HospitalSpellDuration") as "Avg_LengthOfStay"
from ManchesterTrusts
where TO_DATE("AdmissionDttm") between '2020-01-01' and '2024-05-31'
--and "IsReadmission" = 1
group by   YEAR("AdmissionDttm"), MONTH("AdmissionDttm"), "ProviderDesc"
having count(*) > 5 -- exclude small counts 
order by YEAR("AdmissionDttm"), MONTH("AdmissionDttm"), "ProviderDesc";

    -- GROUP BY TRUST AND ICD CATEGORY 

CREATE TEMPORARY TABLE MonthlyAdmissionsByTrustAndICDChapter AS 
select 
      YEAR("AdmissionDttm") AS "Year"
    , MONTH("AdmissionDttm") AS "Month"
    , "ProviderDesc"
    , "DerPrimaryDiagnosisChapterDescReportingEpisode"
    , COUNT(*)  AS "Admissions"
    , AVG("HospitalSpellDuration") as "Avg_LengthOfStay"
from ManchesterTrusts
where TO_DATE("AdmissionDttm") between '2020-01-01' and '2024-05-31'
--and "IsReadmission" = 1
group by   
      YEAR("AdmissionDttm") 
    , MONTH("AdmissionDttm") 
    , "ProviderDesc"
    , "DerPrimaryDiagnosisChapterDescReportingEpisode"
having count(*) > 5 -- exclude small counts 
order by 
      YEAR("AdmissionDttm") 
    , MONTH("AdmissionDttm") 
    , "ProviderDesc"
    , "DerPrimaryDiagnosisChapterDescReportingEpisode";

    -- GROUP BY TRUST AND AGE BAND

CREATE TEMPORARY TABLE MonthlyAdmissionsByTrustAndAgeBand AS 
select 
      YEAR("AdmissionDttm") AS "Year"
    , MONTH("AdmissionDttm") AS "Month"
    , "ProviderDesc", 
    case when "AgeAtStartOfSpellSus" < 18 then '1. <18' 
         when "AgeAtStartOfSpellSus" between 18 and 30  then '2. 18-30'
         when "AgeAtStartOfSpellSus" between 31 and 50  then '3. 31-50' 
         when "AgeAtStartOfSpellSus" between 51 and 70  then '4. 51-70'
         when "AgeAtStartOfSpellSus" between 71 and 90  then '5. 71-90'
         when "AgeAtStartOfSpellSus" > 90  then '6. >90'
            else NULL end as AgeBand, 
    count(*) AS Admissions,
    AVG("HospitalSpellDuration") as "Avg_LengthOfStay"
from ManchesterTrusts
where TO_DATE("AdmissionDttm") between '2020-01-01' and '2024-05-31'
and "AgeAtStartOfSpellSus" between 0 and 120 -- REMOVE UNREALISTIC VALUES
--and "IsReadmission" = 1
group by 
      YEAR("AdmissionDttm")
    , MONTH("AdmissionDttm")
    , "ProviderDesc",  case when "AgeAtStartOfSpellSus" < 18 then '1. <18' 
         when "AgeAtStartOfSpellSus" between 18 and 30  then '2. 18-30'
         when "AgeAtStartOfSpellSus" between 31 and 50  then '3. 31-50' 
         when "AgeAtStartOfSpellSus" between 51 and 70  then '4. 51-70'
         when "AgeAtStartOfSpellSus" between 71 and 90  then '5. 71-90'
         when "AgeAtStartOfSpellSus" > 90  then '6. >90'
            else NULL end
having count(*) > 5 -- exclude small counts 
order by 
      YEAR("AdmissionDttm")
    , MONTH("AdmissionDttm")
    , "ProviderDesc", case when "AgeAtStartOfSpellSus" < 18 then '1. <18' 
         when "AgeAtStartOfSpellSus" between 18 and 30  then '2. 18-30'
         when "AgeAtStartOfSpellSus" between 31 and 50  then '3. 31-50' 
         when "AgeAtStartOfSpellSus" between 51 and 70  then '4. 51-70'
         when "AgeAtStartOfSpellSus" between 71 and 90  then '5. 71-90'
         when "AgeAtStartOfSpellSus" > 90  then '6. >90'
            else NULL end;


