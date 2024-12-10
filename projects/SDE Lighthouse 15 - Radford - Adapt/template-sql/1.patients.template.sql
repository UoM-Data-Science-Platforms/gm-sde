
--┌───────────────────────────────────────────────────────────────────────────────┐
--│ Define Cohort for LH015: patients from the ADAPT cohort and matched controls  │
--└───────────────────────────────────────────────────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK ------------

--------------------------------------------------


-- OBJECTIVE: To build the cohort of patients needed for LH015. This reduces duplication of code in the template scripts.

-- COHORT: Any adult patient that was enrolled on the ADAPT intervention, as well as a cohort of matched controls.
--         Excluding .....

-- INPUT: none
-- OUTPUT: Cohort table and patients table

set(StudyStartDate) = to_date('2015-03-01');
set(StudyEndDate)   = to_date('2022-03-31');


--> EXECUTE query-get-possible-patients.sql

DROP TABLE IF EXISTS PatientsToInclude;
CREATE TEMPORARY TABLE PatientsToInclude AS
SELECT *
FROM GPRegPatients 
WHERE ("DeathDate" IS NULL OR "DeathDate" > $StudyStartDate) -- alive on study start date
	AND 
	("leftGMDate" IS NULL OR "leftGMDate" > $StudyEndDate) -- don't include patients who left GM mid study (as we lose their data)
	AND DATEDIFF(YEAR, "DateOfBirth", $StudyStartDate) >= 18;   -- over 50 in 2016

--> CODESET diffuse-large-b-cell-lymphoma:1 hodgkin-lymphoma:1 malignant-lymphoma:1


-- table of ADAPT patients
DROP TABLE IF EXISTS AdaptPatients;
CREATE TEMPORARY TABLE AdaptPatients AS
SELECT DISTINCT "GmPseudo", "AdaptDate"
FROM INTERMEDIATE.LOCAL_FLOWS_GM_ADAPT."Adapt";
--

-- patients with a malignant lymphoma - to get lymphoma details for adapt cohort
drop table if exists "PatsWithML";
create temporary table "PatsWithML" as
SELECT e."FK_Patient_ID", MIN(TO_DATE("EventDate")) AS "FirstDiagnosisMalignantLymphoma" 
from INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" e
left join {{code-set-table}} cs on cs.code = e.sctid
where cs.concept = 'malignant-lymphoma'
group by 1;

-- patients with lymphoma evidence from APC data (this is to use for ADAPT 
-- patients that don't have evidence of hodgkin or dlbc lymphoma)
drop table if exists "PatsWithLymphomaAPC";
create temporary table "PatsWithLymphomaAPC" as
select "GmPseudo", MIN(TO_DATE("AdmissionDttm")) AS "FirstAdmissionLymphoma"
from presentation.national_flows_apc."DS708_Apcs"
where lower("DerDiagnosisAllAcrossAllEpisodes") like ('%c81%') or
    lower("DerDiagnosisAllAcrossAllEpisodes") like ('%c82%') or
    lower("DerDiagnosisAllAcrossAllEpisodes") like ('%c83%') or
    lower("DerDiagnosisAllAcrossAllEpisodes") like ('%c84%') or
    lower("DerDiagnosisAllAcrossAllEpisodes") like ('%c85%') or
    lower("DerDiagnosisAllAcrossAllEpisodes") like ('%c86%') 
group by 1; 


-----------------------------------
--- patients with lymphoma - for matched cohort
-----------------------------------

-- First let's find anyone from the HES APC data who has a diagnosis of Hodgkin lymphoma
drop table if exists "PatsWithHodgkinLymphoma";
create temporary table "PatsWithHodgkinLymphoma" as
select "GmPseudo", MIN(TO_DATE("AdmissionDttm")) AS "FirstAdmissionHodgkin"
from presentation.national_flows_apc."DS708_Apcs"
where lower("DerDiagnosisAllAcrossAllEpisodes") like ('%c81%')
group by 1; -- C81.* = Hodgkin lymphoma (ICD10 code)

-- However, we probably only want to include them it they also have a primary care record. ADAPT is about long-term management of the 
-- patients when they are discharged into primary care, so we should exclude people who don't have a GP record (because of living outside
-- GM or any other reason).
drop table if exists "PatsWithHodgkinLymphomaFromSUSWithGPRecord";
create temporary table "PatsWithHodgkinLymphomaFromSUSWithGPRecord" as
select distinct p."GmPseudo", p."FirstAdmissionHodgkin" from presentation.gp_record."DemographicsProtectedCharacteristics_SecondaryUses" d
inner join "PatsWithHodgkinLymphoma" p on p."GmPseudo" = d."GmPseudo";

-- Now we do the same as above but for patients with diffuse large B-cell lymphoma
drop table if exists "PatsWithDLBCL";
create temporary table "PatsWithDLBCL" as
select "GmPseudo", MIN(TO_DATE("AdmissionDttm")) AS "FirstAdmissionDLBCL"
from presentation.national_flows_apc."DS708_Apcs"
where lower("DerDiagnosisAllAcrossAllEpisodes") like ('%c833%')
group by 1; -- C83.3 Diffuse large B-cell lymphoma (ICD10 code)

-- And again filter to those with a primary care record
drop table if exists "PatsWithDLBCLFromSUSWithGPRecord";
create temporary table "PatsWithDLBCLFromSUSWithGPRecord" as
select distinct p."GmPseudo", p."FirstAdmissionDLBCL" from presentation.gp_record."DemographicsProtectedCharacteristics_SecondaryUses" d
inner join "PatsWithDLBCL" p on p."GmPseudo" = d."GmPseudo";

-- Now we join the two groups together to see how many people have either Hodgkin or diffuse large b-cell in HES data,
-- and a primary care record.
drop table if exists "PatsFromSUSWithGPRecord";
create temporary table "PatsFromSUSWithGPRecord" as
select "GmPseudo" from "PatsWithHodgkinLymphomaFromSUSWithGPRecord"
UNION
select "GmPseudo" from "PatsWithDLBCLFromSUSWithGPRecord";

-- Now let's look in the GP_Events table. 


drop table if exists "GPPatsWithDLBCL";
create temporary table "GPPatsWithDLBCL" as
select e."FK_Patient_ID", MIN(TO_DATE("EventDate")) AS "FirstDiagnosisDLBCL" 
from INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" e
left join {{code-set-table}} cs on cs.code = e.sctid
where cs.concept = 'diffuse-large-b-cell-lymphoma'
group by 1;

-- And for Hodgkin Lymphoma
drop table if exists "GPPatsWithHodgkinLymphoma";
create temporary table "GPPatsWithHodgkinLymphoma" as
select e."FK_Patient_ID", MIN(TO_DATE("EventDate")) AS "FirstDiagnosisHodgkin" 
from INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" e
left join {{code-set-table}} cs on cs.code = e.sctid
where cs.concept = 'hodgkin-lymphoma'
group by 1;

-- join GP tables together and get GmPseudo
drop table if exists "PatsFromGPRecord";
create temporary table "PatsFromGPRecord" as
select distinct "GmPseudo" from "GPPatsWithDLBCL" d
inner join presentation.gp_record."DemographicsProtectedCharacteristics_SecondaryUses" dpc on dpc."FK_Patient_ID" = d."FK_Patient_ID"
UNION
select distinct "GmPseudo" from "GPPatsWithHodgkinLymphoma" h
inner join presentation.gp_record."DemographicsProtectedCharacteristics_SecondaryUses" dpc on dpc."FK_Patient_ID" = h."FK_Patient_ID";

-- Now we find any patients with one or both, and link to demographics
-- table to get the GmPseudo
drop table if exists "LymphomaPatients" ;
CREATE TEMPORARY TABLE "LymphomaPatients" AS
select "GmPseudo"
from "PatsFromSUSWithGPRecord"
union 
select "GmPseudo"
from "PatsFromGPRecord";

-- find latest snapshot date so we can join to one record per patient

DROP TABLE IF EXISTS LatestSnapshotDate;
CREATE TEMPORARY TABLE LatestSnapshotDate AS
SELECT "GmPseudo", MAX("Snapshot") AS LatestSnapshot
FROM PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses"
WHERE "GmPseudo" IN (SELECT "GmPseudo" FROM adaptpatients)
GROUP BY 1;

DROP TABLE IF EXISTS MainCohort;
CREATE TEMPORARY TABLE MainCohort AS
SELECT DISTINCT
	 d."FK_Patient_ID",
	 Ad."GmPseudo",
     "Sex" as Sex,
     YEAR("DateOfBirth") AS YearOfBirth,
	 "EthnicityLatest_Category" AS EthnicCategory,
	  Ad."AdaptDate",
	 "Snapshot",
     CASE WHEN "FirstDiagnosisMalignantLymphoma" IS NOT NULL 
        AND ("FirstDiagnosisMalignantLymphoma" <=  "FirstAdmissionLymphoma" OR "FirstAdmissionLymphoma" IS NULL)
                                        THEN YEAR("FirstDiagnosisMalignantLymphoma")
          WHEN "FirstAdmissionLymphoma" IS NOT NULL 
        AND ("FirstAdmissionLymphoma" <=  "FirstDiagnosisMalignantLymphoma" OR "FirstDiagnosisMalignantLymphoma" IS NULL)
                                        THEN YEAR("FirstAdmissionLymphoma")
                ELSE NULL END AS DiagnosisYear,
	CASE WHEN ("FirstAdmissionHodgkin" IS NOT NULL OR "FirstDiagnosisHodgkin" IS NOT NULL)  THEN 'hodgkin'
		WHEN ("FirstAdmissionDLBCL" IS NOT NULL OR "FirstDiagnosisDLBCL" IS NOT NULL) 		THEN 'diffuse-large-b-cell'
			ELSE 'unknown' END AS Diagnosis,
	 HL."FirstAdmissionHodgkin", 
	 GPHL."FirstDiagnosisHodgkin", 
	 DLBCL."FirstAdmissionDLBCL", 
	 GPDLBCL."FirstDiagnosisDLBCL",
	 ML."FirstDiagnosisMalignantLymphoma",
     MLAPC."FirstAdmissionLymphoma"
FROM AdaptPatients Ad
LEFT OUTER JOIN LatestSnapshotDate lsd ON lsd."GmPseudo" = Ad."GmPseudo"
-- inner join demographics table to exclude (for now) ADAPT patients with no GP record (as we wouldn't be able to find matches for them)
INNER JOIN PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" d ON d."GmPseudo" = Ad."GmPseudo" AND d."Snapshot" = lsd.LatestSnapshot
LEFT OUTER JOIN "PatsWithHodgkinLymphoma" HL ON HL."GmPseudo" = Ad."GmPseudo"
LEFT OUTER JOIN "GPPatsWithHodgkinLymphoma" GPHL ON GPHL."FK_Patient_ID" = d."FK_Patient_ID"
LEFT OUTER JOIN "PatsWithDLBCL" DLBCL ON DLBCL."GmPseudo" = Ad."GmPseudo"
LEFT OUTER JOIN "GPPatsWithDLBCL" GPDLBCL ON GPDLBCL."FK_Patient_ID" = d."FK_Patient_ID"
LEFT OUTER JOIN "PatsWithML" ML ON ML."FK_Patient_ID" = d."FK_Patient_ID"
LEFT OUTER JOIN "PatsWithLymphomaAPC" MLAPC ON MLAPC."GmPseudo" = Ad."GmPseudo";

-- create table of potential patients to match to the main cohort
DROP TABLE IF EXISTS PotentialMatches;
CREATE TEMPORARY TABLE PotentialMatches AS
SELECT DISTINCT p."GmPseudo",
		p."FK_Patient_ID",
		p."Sex" as Sex,
		YEAR("DateOfBirth") AS YearOfBirth,
		CASE WHEN "FirstDiagnosisHodgkin" IS NOT NULL 
                    AND ("FirstDiagnosisHodgkin" <= "FirstAdmissionHodgkin" OR "FirstAdmissionHodgkin" IS NULL)
                    AND ("FirstDiagnosisHodgkin" <= "FirstAdmissionDLBCL" OR "FirstAdmissionDLBCL" IS NULL)
                    AND ("FirstDiagnosisHodgkin" <= "FirstDiagnosisDLBCL" OR "FirstDiagnosisDLBCL" IS NULL)
                                              THEN YEAR("FirstDiagnosisHodgkin")  
             WHEN "FirstAdmissionHodgkin" IS NOT NULL 
                    AND ("FirstAdmissionHodgkin" <= "FirstDiagnosisHodgkin" OR "FirstDiagnosisHodgkin" IS NULL)
                    AND ("FirstAdmissionHodgkin" <= "FirstAdmissionDLBCL" OR "FirstAdmissionDLBCL" IS NULL)
                    AND ("FirstAdmissionHodgkin" <= "FirstDiagnosisDLBCL" OR "FirstDiagnosisDLBCL" IS NULL)
                                              THEN YEAR("FirstAdmissionHodgkin")  
             WHEN "FirstDiagnosisDLBCL" IS NOT NULL 
                    AND ("FirstDiagnosisDLBCL" <= "FirstAdmissionHodgkin"  OR "FirstAdmissionHodgkin" IS NULL)
                    AND ("FirstDiagnosisDLBCL" <= "FirstAdmissionDLBCL" OR "FirstAdmissionDLBCL" IS NULL)
                    AND ("FirstDiagnosisDLBCL" <= "FirstDiagnosisHodgkin" OR "FirstDiagnosisHodgkin" IS NULL)
                                              THEN YEAR("FirstDiagnosisDLBCL")  
             WHEN "FirstAdmissionDLBCL" IS NOT NULL 
                    AND ("FirstAdmissionDLBCL" <= "FirstAdmissionHodgkin"  OR "FirstAdmissionHodgkin" IS NULL)
                    AND ("FirstAdmissionDLBCL" <= "FirstDiagnosisDLBCL" OR "FirstDiagnosisDLBCL" IS NULL)
                    AND ("FirstAdmissionDLBCL" <= "FirstDiagnosisHodgkin" OR "FirstDiagnosisHodgkin" IS NULL)
                                              THEN YEAR("FirstAdmissionDLBCL") 
                                                        ELSE NULL END AS DiagnosisYear,
		CASE WHEN ("FirstAdmissionHodgkin" IS NOT NULL OR "FirstDiagnosisHodgkin" IS NOT NULL)  THEN 'hodgkin'
		WHEN ("FirstAdmissionDLBCL" IS NOT NULL OR "FirstDiagnosisDLBCL" IS NOT NULL) 			THEN 'diffuse-large-b-cell'
			ELSE 'unknown' END AS Diagnosis,
		HL."FirstAdmissionHodgkin", 
		GPHL."FirstDiagnosisHodgkin", 
		DLBCL."FirstAdmissionDLBCL", 
		GPDLBCL."FirstDiagnosisDLBCL",
		ML."FirstDiagnosisMalignantLymphoma",
        MLAPC."FirstAdmissionLymphoma"
FROM PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" p
LEFT OUTER JOIN "PatsWithHodgkinLymphoma" HL ON HL."GmPseudo" = p."GmPseudo"
LEFT OUTER JOIN "GPPatsWithHodgkinLymphoma" GPHL ON GPHL."FK_Patient_ID" = p."FK_Patient_ID"
LEFT OUTER JOIN "PatsWithDLBCL" DLBCL ON DLBCL."GmPseudo" = p."GmPseudo"
LEFT OUTER JOIN "GPPatsWithDLBCL" GPDLBCL ON GPDLBCL."FK_Patient_ID" = p."FK_Patient_ID"
LEFT OUTER JOIN "PatsWithML" ML ON ML."FK_Patient_ID" = p."FK_Patient_ID"
LEFT OUTER JOIN "PatsWithLymphomaAPC" MLAPC ON MLAPC."GmPseudo" = p."GmPseudo"
WHERE p."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM PatientsToInclude)
	AND p."GmPseudo" NOT IN (SELECT "GmPseudo" FROM MainCohort)
	AND p."GmPseudo" IN (SELECT "GmPseudo" FROM "LymphomaPatients")
QUALIFY row_number() OVER (PARTITION BY p."GmPseudo" ORDER BY "Snapshot" DESC) = 1; -- this brings back the values from the most recent snapshot

-- run matching script with parameters filled in

--> EXECUTE query-cohort-matching-yob-sex-diagnosisyear-replacement.sql yob-flex:2 num-matches:3 diagyear-flex:5


-- Get the matched cohort detail - same as main cohort
DROP TABLE IF EXISTS MatchedCohort;
CREATE TEMPORARY TABLE MatchedCohort AS
SELECT 
  c.MatchingPatientId AS "GmPseudo",
  c.YearOfBirth,
  c.Sex,
  c.MatchingYearOfBirth,
  c.PatientId AS PatientWhoIsMatched,
  pm."FK_Patient_ID",
  pm."FirstAdmissionHodgkin", 
  pm."FirstDiagnosisHodgkin", 
  pm."FirstAdmissionDLBCL", 
  pm."FirstDiagnosisDLBCL",
  pm."FirstDiagnosisMalignantLymphoma",
  pm."FirstAdmissionLymphoma",
  pm.Diagnosis
FROM CohortStore c
LEFT OUTER JOIN PotentialMatches pm ON pm."GmPseudo" = c.MatchingPatientId;


-- create final cohort table by combining main and matched cohort

{{create-output-table-matched-cohort::"LH015-1_Patients"}}
SELECT 
	 m."GmPseudo",
	 D."Snapshot",
     NULL AS "MainCohortMatchedGmPseudo",
     m.Sex AS "Sex",
	 m.Diagnosis,
     D."DateOfBirth" AS "YearAndMonthOfBirth",
	 m.EthnicCategory AS "EthnicCategory",
	 LSOA11 AS "LSOA11", 
	"IMD_Decile", 
	"PracticeCode", 
	"Frailty",
	 m."AdaptDate",
	 DATE_TRUNC(month, dth.DeathDate) AS "DeathYearAndMonth",
	"DiagnosisOriginalMentionCode" AS "CauseOfDeathCode",
	"DiagnosisOriginalMentionDesc" AS "CauseOfDeathDesc",
	"DiagnosisOriginalMentionChapterCode" AS "CauseOfDeathChapterCode",
    "DiagnosisOriginalMentionChapterDesc" AS "CauseOfDeathChapterDesc",
    "DiagnosisOriginalMentionCategory1Code" AS "CauseOfDeathCategoryCode",
    "DiagnosisOriginalMentionCategory1Desc" AS "CauseOfDeathCategoryDesc",
    m."FirstAdmissionHodgkin", 
    m."FirstDiagnosisHodgkin", 
    m."FirstAdmissionDLBCL", 
    m."FirstDiagnosisDLBCL",
	m."FirstDiagnosisMalignantLymphoma",
    m."FirstAdmissionLymphoma"
FROM MainCohort m
LEFT OUTER JOIN Death dth ON dth."GmPseudo" = m."GmPseudo"
LEFT OUTER JOIN PatientsToInclude D on D."GmPseudo" = m."GmPseudo"
QUALIFY row_number() OVER (PARTITION BY D."GmPseudo" ORDER BY D."Snapshot" DESC) = 1 -- this brings back the values from the most recent snapshot
UNION
SELECT
 	 m."GmPseudo",
	 D."Snapshot",
	 PatientWhoIsMatched AS "MainCohortMatchedGmPseudo", 
     m.Sex AS "Sex",
	 m.Diagnosis,
     D."DateOfBirth" AS "YearAndMonthOfBirth",
	 D."EthnicityLatest_Category" AS "EthnicCategory",
	 LSOA11 AS "LSOA11", 
	"IMD_Decile", 
	"PracticeCode", 
	"Frailty",
     NULL AS "AdaptDate",
	 DATE_TRUNC(month, dth.DeathDate) AS "DeathYearAndMonth",
	"DiagnosisOriginalMentionCode" AS "CauseOfDeathCode",
	"DiagnosisOriginalMentionDesc" AS "CauseOfDeathDesc",
	"DiagnosisOriginalMentionChapterCode" AS "CauseOfDeathChapterCode",
    "DiagnosisOriginalMentionChapterDesc" AS "CauseOfDeathChapterDesc",
    "DiagnosisOriginalMentionCategory1Code" AS "CauseOfDeathCategoryCode",
    "DiagnosisOriginalMentionCategory1Desc" AS "CauseOfDeathCategoryDesc",
     m."FirstAdmissionHodgkin", 
     m."FirstDiagnosisHodgkin", 
     m."FirstAdmissionDLBCL", 
     m."FirstDiagnosisDLBCL",
	 m."FirstDiagnosisMalignantLymphoma",
     m."FirstAdmissionLymphoma"
FROM MatchedCohort m
LEFT OUTER JOIN Death dth ON dth."GmPseudo" = m."GmPseudo"
LEFT OUTER JOIN PatientsToInclude D on D."GmPseudo" = m."GmPseudo"
QUALIFY row_number() OVER (PARTITION BY D."GmPseudo" ORDER BY D."Snapshot" DESC) = 1 -- this brings back the values from the most recent snapshot
;

-- create simpler version of the above table to be the cohort table that other files pull from
-- combine the main cohort, matched cohort, and any ADAPT patients that didn't have demographic
-- info so we couldn't match them

DROP TABLE IF EXISTS {{cohort-table}};
CREATE TABLE {{cohort-table}} AS 
SELECT 
	 m."GmPseudo"
FROM MainCohort m
UNION
SELECT
 	 m."GmPseudo"
FROM MatchedCohort m
UNION 
SELECT "GmPseudo"
FROM SDE_REPOSITORY.SHARED_UTILITIES."LH015-0_AdaptPatients_WITH_IDENTIFIER";