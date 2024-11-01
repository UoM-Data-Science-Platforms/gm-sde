
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

--> EXECUTE query-get-possible-patients.sql minimum-age:18

--> CODESET diffuse-large-b-cell-lymphoma:1 hodgkin-lymphoma:1


-- table of ADAPT patients
--

-----------------------------------
--- patients with lymphoma - for matched cohort
-----------------------------------

-- First let's find anyone from the HES APC data who has a diagnosis of Hodgkin lymphoma
drop table if exists "PatsWithHodgkinLymphoma";
create temporary table "PatsWithHodgkinLymphoma" as
select distinct "GmPseudo"
from presentation.national_flows_apc."DS708_Apcs"
where lower("DerDiagnosisAllAcrossAllEpisodes") like ('%c81%'); -- C81.* = Hodgkin lymphoma (ICD10 code)

-- However, we probably only want to include them it they also have a primary care record. ADAPT is about long-term management of the 
-- patients when they are discharged into primary care, so we should exclude people who don't have a GP record (because of living outside
-- GM or any other reason).
drop table if exists "PatsWithHodgkinLymphomaFromSUSWithGPRecord";
create temporary table "PatsWithHodgkinLymphomaFromSUSWithGPRecord" as
select distinct p."GmPseudo" from presentation.gp_record."DemographicsProtectedCharacteristics_SecondaryUses" d
inner join "PatsWithHodgkinLymphoma" p on p."GmPseudo" = d."GmPseudo";

-- Now we do the same as above but for patients with diffuse large B-cell lymphoma
drop table if exists "PatsWithDLBCL";
create temporary table "PatsWithDLBCL" as
select distinct "GmPseudo"
from presentation.national_flows_apc."DS708_Apcs"
where lower("DerDiagnosisAllAcrossAllEpisodes")like ('%c833%'); -- C83.3 Diffuse large B-cell lymphoma (ICD10 code)

-- And again filter to those with a primary care record
drop table if exists "PatsWithDLBCLFromSUSWithGPRecord";
create temporary table "PatsWithDLBCLFromSUSWithGPRecord" as
select distinct p."GmPseudo" from presentation.gp_record."DemographicsProtectedCharacteristics_SecondaryUses" d
inner join "PatsWithDLBCL" p on p."GmPseudo" = d."GmPseudo";

-- Now we join the two groups together to see how many people have either Hodgkin or diffuse large b-cell in HES data,
-- and a primary care record.
drop table if exists "PatsFromSUSWithGPRecord";
create temporary table "PatsFromSUSWithGPRecord" as
select * from "PatsWithHodgkinLymphomaFromSUSWithGPRecord"
UNION
select * from "PatsWithDLBCLFromSUSWithGPRecord";

-- Now let's look in the GP_Events table. 

drop table if exists "GPPatsWithDLBCL";
create temporary table "GPPatsWithDLBCL" as
select distinct e."FK_Patient_ID" 
from INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" e
left join {{code-set-table}} cs on cs.code = e."SuppliedCode"
where cs.concept = 'diffuse-large-b-cell-lymphoma';

-- And for Hodgkin Lymphoma
drop table if exists "GPPatsWithHodgkinLymphoma";
create temporary table "GPPatsWithHodgkinLymphoma" as
select distinct "FK_Patient_ID" 
from INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" e
left join {{code-set-table}} cs on cs.code = e."SuppliedCode"
where cs.concept = 'hodgkin-lymphoma';

-- join GP tables together and get GmPseudo
drop table if exists "PatsFromGPRecord";
create temporary table "PatsFromGPRecord" as
select "GmPseudo" from "GPPatsWithDLBCL" d
inner join presentation.gp_record."DemographicsProtectedCharacteristics_SecondaryUses" dpc on dpc."FK_Patient_ID" = d."FK_Patient_ID"
UNION
select "GmPseudo" from "GPPatsWithHodgkinLymphoma" h
inner join presentation.gp_record."DemographicsProtectedCharacteristics_SecondaryUses" dpc on dpc."FK_Patient_ID" = h."FK_Patient_ID";

-- Now we find any patients with one or both, and link to demographics
-- table to get the GmPseudo

drop table if exists "LymphomaPatients" ;
CREATE TEMPORARY TABLE "LymphomaPatients" AS
select distinct "GmPseudo" 
from 
	(select * 
	from "PatsFromSUSWithGPRecord"
	union 
	select * 
	from "PatsFromGPRecord"
);



-------------------



DROP TABLE IF EXISTS MainCohort;
CREATE TEMPORARY TABLE MainCohort AS
SELECT top 1000 DISTINCT
	 "FK_Patient_ID",
	 "GmPseudo",
     "Sex" as Sex,
     YEAR("DateOfBirth") AS YearOfBirth,
	 "EthnicityLatest_Category" AS EthnicCategory,
	 --'2022-07-01' AS IndexDate,
	 "Snapshot"
FROM PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" p
WHERE "FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM AlivePatientsAtStart)
 	--AND "FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM ADAPT)
    AND "Snapshot" <= $StudyStartDate
QUALIFY row_number() OVER (PARTITION BY p."GmPseudo" ORDER BY "Snapshot" DESC) = 1; -- this brings back the values from the most recent snapshot

-- create table of potential patients to match to the main cohort

DROP TABLE IF EXISTS PotentialMatches;
CREATE TEMPORARY TABLE PotentialMatches AS
SELECT DISTINCT p."GmPseudo", 
		p."Sex" as Sex,
		YEAR("DateOfBirth") AS YearOfBirth,
		p."EthnicityLatest_Category" AS EthnicCategory
FROM PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" p
WHERE p."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM AlivePatientsAtStart)
	AND p."GmPseudo" NOT IN (SELECT "GmPseudo" FROM MainCohort)
	AND p."GmPseudo" IN (SELECT "GmPseudo" FROM "LymphomaPatients")
	AND "Snapshot" <= $StudyStartDate -- demographic information at closest date to the start of the trial
QUALIFY row_number() OVER (PARTITION BY p."GmPseudo" ORDER BY "Snapshot" DESC) = 1; -- this brings back the values from the most recent snapshot


-- run matching script with parameters filled in

--> EXECUTE query-cohort-matching-yob-sex.sql yob-flex:5 num-matches:5


-- Get the matched cohort detail - same as main cohort
DROP TABLE IF EXISTS MatchedCohort;
CREATE TEMPORARY TABLE MatchedCohort AS
SELECT 
  c.MatchingPatientId AS "GmPseudo",
  c.YearOfBirth,
  c.Sex,
  c.MatchingYearOfBirth,
  c.PatientId AS PatientWhoIsMatched,
FROM CohortStore c;


-- create final cohort table by combining main and matched cohort

{{create-output-table-matched-cohort::"LH015-1_Patients"}}
SELECT 
	 m."GmPseudo",
	 D."Snapshot",
     NULL AS "MainCohortMatchedGmPseudo",
     m.Sex AS "Sex",
     D."DateOfBirth" AS "YearAndMonthOfBirth",
	 EthnicCategory AS "EthnicCategory",
	 LSOA11 AS "LSOA11", 
	"IMD_Decile", 
	"PracticeCode", 
	"Frailty",
	 --IndexDate,
	 dth.DeathDate AS "DeathDate",
	"DiagnosisOriginalMentionCode" AS "CauseOfDeathCode",
	"DiagnosisOriginalMentionDesc" AS "CauseOfDeathDesc",
	"DiagnosisOriginalMentionChapterCode" AS "CauseOfDeathChapterCode",
    "DiagnosisOriginalMentionChapterDesc" AS "CauseOfDeathChapterDesc",
    "DiagnosisOriginalMentionCategory1Code" AS "CauseOfDeathCategoryCode",
    "DiagnosisOriginalMentionCategory1Desc" AS "CauseOfDeathCategoryDesc",
FROM MainCohort m
LEFT OUTER JOIN Death dth ON dth."GmPseudo" = m."GmPseudo"
LEFT OUTER JOIN AlivePatientsAtStart D on D."GmPseudo" = m."GmPseudo"
WHERE D."Snapshot" <= '2022-07-01'
QUALIFY row_number() OVER (PARTITION BY D."GmPseudo" ORDER BY D."Snapshot" DESC) = 1 -- this brings back the values from the most recent snapshot
UNION
SELECT
 	 m."GmPseudo",
	 D."Snapshot",
	 PatientWhoIsMatched AS "MainCohortMatchedGmPseudo", 
     m.Sex AS "Sex",
     D."DateOfBirth" AS "YearAndMonthOfBirth",
	 EthnicCategory AS "EthnicCategory",
	 LSOA11 AS "LSOA11", 
	"IMD_Decile", 
	"PracticeCode", 
	"Frailty",
	 dth.DeathDate AS "DeathDate",
	"DiagnosisOriginalMentionCode" AS "CauseOfDeathCode",
	"DiagnosisOriginalMentionDesc" AS "CauseOfDeathDesc",
	"DiagnosisOriginalMentionChapterCode" AS "CauseOfDeathChapterCode",
    "DiagnosisOriginalMentionChapterDesc" AS "CauseOfDeathChapterDesc",
    "DiagnosisOriginalMentionCategory1Code" AS "CauseOfDeathCategoryCode",
    "DiagnosisOriginalMentionCategory1Desc" AS "CauseOfDeathCategoryDesc",
FROM MatchedCohort m
LEFT JOIN Death dth ON dth."GmPseudo" = m."GmPseudo"
LEFT OUTER JOIN AlivePatientsAtStart D on D."GmPseudo" = m."GmPseudo"
WHERE D."Snapshot" <= '2022-07-01'
QUALIFY row_number() OVER (PARTITION BY D."GmPseudo" ORDER BY D."Snapshot" DESC) = 1 -- this brings back the values from the most recent snapshot
;

-- create simpler version of the above table to be the cohort table that other files pull from

DROP TABLE IF EXISTS {{cohort-table}};
CREATE TABLE {{cohort-table}} AS 
SELECT 
	 m."GmPseudo",
     NULL AS "MainCohortMatchedPatientId"
FROM MainCohort m
UNION
SELECT
 	 m."GmPseudo",
	 PatientWhoIsMatched AS "MainCohortMatchedPatientId", 
FROM MatchedCohort m;