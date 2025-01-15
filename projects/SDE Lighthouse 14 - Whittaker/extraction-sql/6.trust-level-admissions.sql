USE SCHEMA SDE_REPOSITORY.SHARED_UTILITIES;

--┌──────────────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 14 - Whittaker - Trust level admissions │
--└──────────────────────────────────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK ---------
-- Richard Williams	2024-08-09	Review complete

-- Date range: 2018 to present

-- FOR EACH TRUST: 
-- monthly inpatient admissions
-- monthly inpatient readmissions (unsure on definition)
-- monthly inpatient admissions broken down by age band
-- monthly inpatient admissions broken down by ICD10 category
-- monthly A&E attendances total
-- monthly A&E attendances broekn down by age band

set(StudyStartDate) = to_date('2018-04-01');
set(StudyEndDate)   = to_date('2024-10-31');

-- CREATE A TABLE OF ADMISSIONS (inpatient) FROM GM TRUSTS
DROP TABLE IF EXISTS ManchesterTrusts;
CREATE TEMPORARY TABLE ManchesterTrusts AS 
SELECT *
FROM PRESENTATION.NATIONAL_FLOWS_APC."DS708_Apcs"
WHERE "ProviderDesc" IN    -- limit to trusts that have virtual ward data 
    ('Manchester University NHS Foundation Trust',
     'Northern Care Alliance NHS Foundation Trust',
     'Wrightington, Wigan And Leigh NHS Foundation Trust',
     'Stockport NHS Foundation Trust',
     'Bolton NHS Foundation Trust',
     'Tameside And Glossop Integrated Care NHS Foundation Trust')
	AND TO_DATE("AdmissionDttm") between $StudyStartDate and $StudyEndDate
	AND "HospitalSpellDuration" != '*' -- < 10 records have missing discharge date and spell duration, so exclude
	AND "GmPseudo" IN (SELECT "GmPseudo" FROM PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses"); -- ensure opt-out applied
  
-- MONTHLY ADMISSION COUNTS AND AVG LENGTH OF STAY BY TRUST

    -- GROUP BY TRUST ONLY

-- There are no patient ids ("GmPseudo") so we don't need to 
-- obfuscate them. Instead we just create a table, readable by the analysts
-- where we put the data.
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH014-6a_TrustLevelAdmissions";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH014-6a_TrustLevelAdmissions" AS
select 
      YEAR("AdmissionDttm") AS "Year"
    , MONTH("AdmissionDttm") AS "Month"
    ,"ProviderDesc"
    , count(*) as Admissions  
    , AVG("HospitalSpellDuration") as "Avg_LengthOfStayDays" 
from ManchesterTrusts
group by YEAR("AdmissionDttm"), MONTH("AdmissionDttm"), "ProviderDesc"
order by YEAR("AdmissionDttm"), MONTH("AdmissionDttm"), "ProviderDesc";

   -- READMISSIONS ONLY (might be able to work out definition from snowflake)


-- There are no patient ids ("GmPseudo") so we don't need to 
-- obfuscate them. Instead we just create a table, readable by the analysts
-- where we put the data.
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH014-6b_TrustLevelReadmissions";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH014-6b_TrustLevelReadmissions" AS
select 
      YEAR("AdmissionDttm") AS "Year"
    , MONTH("AdmissionDttm") AS "Month"
    ,"ProviderDesc"
    , count(*) as Readmissions  
    , AVG("HospitalSpellDuration") as "Avg_LengthOfStayDays" 
FROM ManchesterTrusts
WHERE "IsReadmission" = 'TRUE'
group by YEAR("AdmissionDttm"), MONTH("AdmissionDttm"), "ProviderDesc"
order by YEAR("AdmissionDttm"), MONTH("AdmissionDttm"), "ProviderDesc";

    -- GROUP BY TRUST AND ICD CATEGORY 

	-- ** warn researcher about small numbers. Ensure they will aggregate before exporting.


-- There are no patient ids ("GmPseudo") so we don't need to 
-- obfuscate them. Instead we just create a table, readable by the analysts
-- where we put the data.
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH014-6c_TrustLevelAdmissions_icd";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH014-6c_TrustLevelAdmissions_icd" AS
select 
      YEAR("AdmissionDttm") AS "Year"
    , MONTH("AdmissionDttm") AS "Month"
    , "ProviderDesc" 
    , "DerPrimaryDiagnosisChapterCodeReportingEpisode" as PrimaryICDCategoryCode
    , "DerPrimaryDiagnosisChapterDescReportingEpisode" as PrimaryICDCategoryDesc
    , count(*) as Admissions  
    , AVG("HospitalSpellDuration") as "Avg_LengthOfStayDays" 
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


-- There are no patient ids ("GmPseudo") so we don't need to 
-- obfuscate them. Instead we just create a table, readable by the analysts
-- where we put the data.
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH014-6d_TrustLevelAdmissions_age";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH014-6d_TrustLevelAdmissions_age" AS
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
    , AVG("HospitalSpellDuration") as "Avg_LengthOfStayDays" 
from ManchesterTrusts
WHERE "AgeAtStartOfSpellSus" between 0 and 120 -- REMOVE UNREALISTIC VALUES
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

-- Emergency (A&E) department attendances: 
	-- Total
	-- by ICD   -- providing this is likely to have too many small numbers, as we could only do it using 'chief complaint snomed code'
	-- by ageband 

DROP TABLE IF EXISTS ManchesterTrustsAE;
CREATE TEMPORARY TABLE ManchesterTrustsAE AS 
SELECT *
FROM PRESENTATION.NATIONAL_FLOWS_ECDS."DS707_Ecds" E
WHERE "ProviderDesc" IN 
    ('Manchester University NHS Foundation Trust',
     'Northern Care Alliance NHS Foundation Trust',
     'Wrightington, Wigan And Leigh NHS Foundation Trust',
     'Stockport NHS Foundation Trust',
     'Bolton NHS Foundation Trust',
     'Tameside And Glossop Integrated Care NHS Foundation Trust')
AND TO_DATE("ArrivalDate") between $StudyStartDate and $StudyEndDate
AND "GmPseudo" IN (SELECT "GmPseudo" FROM PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses"); -- apply opt-out

    
-- total

-- There are no patient ids ("GmPseudo") so we don't need to 
-- obfuscate them. Instead we just create a table, readable by the analysts
-- where we put the data.
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH014-6e_TrustLevelAEAdmissions";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH014-6e_TrustLevelAEAdmissions" AS
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
	, "ProviderDesc";

-- by Age band

-- There are no patient ids ("GmPseudo") so we don't need to 
-- obfuscate them. Instead we just create a table, readable by the analysts
-- where we put the data.
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH014-6f_TrustLevelAEAdmissions_age";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH014-6f_TrustLevelAEAdmissions_age" AS
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
            else NULL end;

