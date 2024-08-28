--┌──────────────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 14 - Whittaker - Trust level admissions │
--└──────────────────────────────────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK ---------
-- Richard Williams	2024-08-09	Review complete

USE PRESENTATION.LOCAL_FLOWS_VIRTUAL_WARDS;

-- Date range: 2018 to present

set(StudyStartDate) = to_date('2018-04-01');
set(StudyEndDate)   = to_date('2024-06-30');

-- CREATE A TABLE OF ADMISSIONS FROM GM TRUSTS
DROP TABLE IF EXISTS ManchesterTrusts;
CREATE TEMPORARY TABLE ManchesterTrusts AS 
SELECT *
FROM PRESENTATION.NATIONAL_FLOWS_APC."DS708_Apcs"
WHERE "ProviderDesc" IN    -- limit to trusts that have virtual ward data 
    ('Manchester University NHS Foundation Trust',
     --'Pennine Acute Hospitals NHS Trust',
     'Northern Care Alliance NHS Foundation Trust',
     'Wrightington, Wigan And Leigh NHS Foundation Trust',
     'Stockport NHS Foundation Trust',
     'Bolton NHS Foundation Trust',
     'Tameside And Glossop Integrated Care NHS Foundation Trust')
where TO_DATE("AdmissionDttm") between $StudyStartDate and $StudyEndDate
and "HospitalSpellDuration" != '*'; -- < 10 records have missing discharge date and spell duration, so exclude
  -- FILTER OUT ELECTIVE ??   
  
-- MONTHLY ADMISSION COUNTS AND AVG LENGTH OF STAY BY TRUST

    -- GROUP BY TRUST ONLY
DROP TABLE IF EXISTS {{project-schema}}."6a_TrustLevelAdmissions";
CREATE TABLE {{project-schema}}."6a_TrustLevelAdmissions" AS
select 
      YEAR("AdmissionDttm") AS "Year"
    , MONTH("AdmissionDttm") AS "Month"
    ,"ProviderDesc"
    , count(*) as Admissions  
    , AVG("HospitalSpellDuration") as "Avg_LengthOfStay" 
from ManchesterTrusts
group by YEAR("AdmissionDttm"), MONTH("AdmissionDttm"), "ProviderDesc"
order by YEAR("AdmissionDttm"), MONTH("AdmissionDttm"), "ProviderDesc";

    -- READMISSIONS ONLY
DROP TABLE IF EXISTS {{project-schema}}."6b_TrustLevelReadmissions";
CREATE TABLE {{project-schema}}."6b_TrustLevelReadmissions" AS
select 
      YEAR("AdmissionDttm") AS "Year"
    , MONTH("AdmissionDttm") AS "Month"
    ,"ProviderDesc"
    , count(*) as Readmissions  
    , AVG("HospitalSpellDuration") as "Avg_LengthOfStay" 
FROM ManchesterTrusts
and "IsReadmission" = 'TRUE'
group by YEAR("AdmissionDttm"), MONTH("AdmissionDttm"), "ProviderDesc"
order by YEAR("AdmissionDttm"), MONTH("AdmissionDttm"), "ProviderDesc";

    -- GROUP BY TRUST AND ICD CATEGORY 

DROP TABLE IF EXISTS {{project-schema}}."6c_TrustLevelAdmissions_icd";
CREATE TABLE {{project-schema}}."6c_TrustLevelAdmissions_icd" AS
select 
      YEAR("AdmissionDttm") AS "Year"
    , MONTH("AdmissionDttm") AS "Month"
    , "ProviderDesc" 
    , "DerPrimaryDiagnosisChapterCodeReportingEpisode" as PrimaryICDCategoryCode
    , "DerPrimaryDiagnosisChapterDescReportingEpisode" as PrimaryICDCategoryDesc
    , count(*) as Admissions  
    , AVG("HospitalSpellDuration") as "Avg_LengthOfStay" 
FROM ManchesterTrusts
group by   
      YEAR("AdmissionDttm") 
    , MONTH("AdmissionDttm") 
    , "ProviderDesc"
    , "DerPrimaryDiagnosisChapterCodeReportingEpisode" 
    , "DerPrimaryDiagnosisChapterDescReportingEpisode"
order by 
      YEAR("AdmissionDttm") 
    , MONTH("AdmissionDttm") 
    , "ProviderDesc"
    , "DerPrimaryDiagnosisChapterCodeReportingEpisode" 
    , "DerPrimaryDiagnosisChapterDescReportingEpisode";

    -- GROUP BY TRUST AND AGE BAND
DROP TABLE IF EXISTS {{project-schema}}."6d_TrustLevelAdmissions_age";
CREATE TABLE {{project-schema}}."6d_TrustLevelAdmissions_age" AS
select 
      YEAR("AdmissionDttm") AS "Year"
    , MONTH("AdmissionDttm") AS "Month"
    , "ProviderDesc" 
    , case when "AgeAtStartOfSpellSus" < 18 then '1. <18' 
         when "AgeAtStartOfSpellSus" between 18 and 30  then '2. 18-30'
         when "AgeAtStartOfSpellSus" between 31 and 50  then '3. 31-50' 
         when "AgeAtStartOfSpellSus" between 51 and 70  then '4. 51-70'
         when "AgeAtStartOfSpellSus" between 71 and 90  then '5. 71-90'
         when "AgeAtStartOfSpellSus" > 90  then '6. >90'
            else NULL end as AgeBand
    , count(*) as Admissions  
    , AVG("HospitalSpellDuration") as "Avg_LengthOfStay" 
from ManchesterTrusts
and "AgeAtStartOfSpellSus" between 0 and 120 -- REMOVE UNREALISTIC VALUES
group by 
      YEAR("AdmissionDttm")
    , MONTH("AdmissionDttm")
    , "ProviderDesc"  
    , case when "AgeAtStartOfSpellSus" < 18 then '1. <18' 
         when "AgeAtStartOfSpellSus" between 18 and 30  then '2. 18-30'
         when "AgeAtStartOfSpellSus" between 31 and 50  then '3. 31-50' 
         when "AgeAtStartOfSpellSus" between 51 and 70  then '4. 51-70'
         when "AgeAtStartOfSpellSus" between 71 and 90  then '5. 71-90'
         when "AgeAtStartOfSpellSus" > 90  then '6. >90'
            else end NULL
order by 
      YEAR("AdmissionDttm")
    , MONTH("AdmissionDttm")
    , "ProviderDesc"
    , case when "AgeAtStartOfSpellSus" < 18 then '1. <18' 
         when "AgeAtStartOfSpellSus" between 18 and 30  then '2. 18-30'
         when "AgeAtStartOfSpellSus" between 31 and 50  then '3. 31-50' 
         when "AgeAtStartOfSpellSus" between 51 and 70  then '4. 51-70'
         when "AgeAtStartOfSpellSus" between 71 and 90  then '5. 71-90'
         when "AgeAtStartOfSpellSus" > 90  then '6. >90'
            else end NULL;

-- Emergency department attendances: 
	-- Total
	-- by ICD   -- providing this is likely to have too many small numbers, as we could only do it using 'chief complaint snomed code'
	-- by ageband 

DROP TABLE IF EXISTS ManchesterTrustsAE;
CREATE TEMPORARY TABLE ManchesterTrustsAE AS 
SELECT *
FROM PRESENTATION.NATIONAL_FLOWS_ECDS."DS707_Ecds" E
WHERE "ProviderDesc" IN 
    ('Manchester University NHS Foundation Trust',
     'Pennine Acute Hospitals NHS Trust',
     'Northern Care Alliance NHS Foundation Trust',
     'Wrightington, Wigan And Leigh NHS Foundation Trust',
     'Stockport NHS Foundation Trust',
     'Bolton NHS Foundation Trust',
     'Tameside And Glossop Integrated Care NHS Foundation Trust')
AND  TO_DATE("ArrivalDate") between $StudyStartDate and $StudyEndDate

    
-- total
DROP TABLE IF EXISTS {{project-schema}}."6e_TrustLevelAEAdmissions";
CREATE TABLE {{project-schema}}."6e_TrustLevelAEAdmissions" AS
SELECT
	  YEAR("ArrivalDate") AS "Year"
    , MONTH("ArrivalDate") AS "Month"
	, "ProviderDesc"
    , count(*) as count 
FROM ManchesterTrustsAE
WHERE "IsAttendance" = 1 -- been advised to apply this filter to get A&E admissions
GROUP BY 
	  YEAR("ArrivalDate")
    , MONTH("ArrivalDate")
	, "ProviderDesc"
ORDER BY 
	  YEAR("ArrivalDate")
    , MONTH("ArrivalDate")
	, "ProviderDesc"

-- by Age band
DROP TABLE IF EXISTS {{project-schema}}."6f_TrustLevelAEAdmissions_age";
CREATE TABLE {{project-schema}}."6f_TrustLevelAEAdmissions_age" AS
SELECT
	  YEAR("ArrivalDate") AS "Year"
    , MONTH("ArrivalDate") AS "Month"
	, "ProviderDesc"
    , case when "AgeAtArrival" < 18 then '1. <18' 
         when "AgeAtArrival" between 18 and 30  then '2. 18-30'
         when "AgeAtArrival" between 31 and 50  then '3. 31-50' 
         when "AgeAtArrival" between 51 and 70  then '4. 51-70'
         when "AgeAtArrival" between 71 and 90  then '5. 71-90'
         when "AgeAtArrival" > 90  then '6. >90'
            else NULL end AS AgeBand
    , count(*) as count 
FROM ManchesterTrustsAE
GROUP BY 
	  YEAR("ArrivalDate")
    , MONTH("ArrivalDate")
	, "ProviderDesc"
    , case when "AgeAtArrival" < 18 then '1. <18' 
         when "AgeAtArrival" between 18 and 30  then '2. 18-30'
         when "AgeAtArrival" between 31 and 50  then '3. 31-50' 
         when "AgeAtArrival" between 51 and 70  then '4. 51-70'
         when "AgeAtArrival" between 71 and 90  then '5. 71-90'
         when "AgeAtArrival" > 90  then '6. >90'
            else NULL end
ORDER BY YEAR("ArrivalDate")
    , MONTH("ArrivalDate")
	, "ProviderDesc"
    , case when "AgeAtArrival" < 18 then '1. <18' 
         when "AgeAtArrival" between 18 and 30  then '2. 18-30'
         when "AgeAtArrival" between 31 and 50  then '3. 31-50' 
         when "AgeAtArrival" between 51 and 70  then '4. 51-70'
         when "AgeAtArrival" between 71 and 90  then '5. 71-90'
         when "AgeAtArrival" > 90  then '6. >90'
            else NULL end