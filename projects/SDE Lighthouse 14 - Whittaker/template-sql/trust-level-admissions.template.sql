--┌──────────────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 14 - Whittaker - Trust level admissions │
--└──────────────────────────────────────────────────────────────┘

-- Average emergency department door to provider time - UNLIKELY
-- Average emergency department onboarding time - UNLIKELY
-- Average bed request to assign time - UNLIKELY

USE PRESENTATION.LOCAL_FLOWS_VIRTUAL_WARDS;

-- Date range: 2018 to present

set(StudyStartDate) = to_date('2018-01-01');
set(StudyEndDate)   = to_date('2024-06-30');

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
and "HospitalSpellDuration" != '*'; -- < 10 records have missing discharge date and spell duration, so exclude
  -- FILTER OUT ELECTIVE ??   

-- MONTHLY ADMISSION COUNTS AND AVG LENGTH OF STAY BY TRUST

    -- GROUP BY TRUST ONLY

select 
      YEAR("AdmissionDttm") AS "Year"
    , MONTH("AdmissionDttm") AS "Month"
    ,"ProviderDesc"
    , case when count(*) < 5 then 5 else count(*) end as Admissions  --mask small values
    , case when count(*)  5  then NULL else AVG("HospitalSpellDuration") end as "Avg_LengthOfStay" --mask potentially identifiable values
from ManchesterTrusts
where TO_DATE("AdmissionDttm") between $StudyStartDate and $StudyEndDate
group by   YEAR("AdmissionDttm"), MONTH("AdmissionDttm"), "ProviderDesc"
order by YEAR("AdmissionDttm"), MONTH("AdmissionDttm"), "ProviderDesc";

    -- GROUP BY TRUST ONLY
    -- READMISSIONS ONLY

select 
      YEAR("AdmissionDttm") AS "Year"
    , MONTH("AdmissionDttm") AS "Month"
    ,"ProviderDesc"
    , case when count(*) < 5 then 5 else count(*) end as Readmissions  --mask small values
    , case when count(*)  5  then NULL else AVG("HospitalSpellDuration") end as "Avg_LengthOfStay" --mask potentially identifiable values
from ManchesterTrusts
where TO_DATE("AdmissionDttm") between $StudyStartDate and $StudyEndDate
and "IsReadmission" = 1
group by   YEAR("AdmissionDttm"), MONTH("AdmissionDttm"), "ProviderDesc"
order by YEAR("AdmissionDttm"), MONTH("AdmissionDttm"), "ProviderDesc";

    -- GROUP BY TRUST AND ICD CATEGORY 

select 
      YEAR("AdmissionDttm") AS "Year"
    , MONTH("AdmissionDttm") AS "Month"
    , "ProviderDesc" 
    , "DerPrimaryDiagnosisChapterDescReportingEpisode" as PrimaryICDCategory
    , case when count(*) < 5 then 5 else count(*) end as Admissions  --mask small values
    , case when count(*) <= 5  then NULL else AVG("HospitalSpellDuration") end as "Avg_LengthOfStay" --mask potentially identifiable values
from ManchesterTrusts
where TO_DATE("AdmissionDttm") between $StudyStartDate and $StudyEndDate
group by   
      YEAR("AdmissionDttm") 
    , MONTH("AdmissionDttm") 
    , "ProviderDesc"
    , "DerPrimaryDiagnosisChapterDescReportingEpisode"
order by 
      YEAR("AdmissionDttm") 
    , MONTH("AdmissionDttm") 
    , "ProviderDesc"
    , "DerPrimaryDiagnosisChapterDescReportingEpisode";

    -- GROUP BY TRUST AND AGE BAND
 
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
    , case when count(*) < 5 then 5 else count(*) end as Admissions  --mask small values
    , case when count(*) <= 5  then NULL else AVG("HospitalSpellDuration") end as "Avg_LengthOfStay" --mask potentially identifiable values
from ManchesterTrusts
where TO_DATE("AdmissionDttm") between $StudyStartDate and $StudyEndDate
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
            else NULL end
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
            else NULL end;

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
     'Tameside And Glossop Integrated Care NHS Foundation Trust',
     'The Christie NHS Foundation Trust')
AND  TO_DATE("ArrivalDate") between $StudyStartDate and $StudyEndDate

    
-- total
 
SELECT
	  YEAR("ArrivalDate") AS "Year"
    , MONTH("ArrivalDate") AS "Month"
	, "ProviderDesc"
    , case when count(*) <= 5 then 5 else count(*) end as count --mask small values
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
    , case when count(*) <= 5 then 5 else count(*) end as count --mask small values
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