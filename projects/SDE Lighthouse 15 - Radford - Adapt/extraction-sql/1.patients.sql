USE SCHEMA SDE_REPOSITORY.SHARED_UTILITIES;


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



--┌───────────────────────────┐
--│ Create table of patients  │
--└───────────────────────────┘

-- ** any patients opted out of sharing GP data would not appear in the final table

-- this script requires an input of StudyStartDate

--ALL DEATHS 

DROP TABLE IF EXISTS Death;
CREATE TEMPORARY TABLE Death AS
SELECT 
    DEATH."GmPseudo",
    TO_DATE(DEATH."RegisteredDateOfDeath") AS DeathDate,
	OM."DiagnosisOriginalMentionCode",
    OM."DiagnosisOriginalMentionDesc",
    OM."DiagnosisOriginalMentionChapterCode",
    OM."DiagnosisOriginalMentionChapterDesc",
    OM."DiagnosisOriginalMentionCategory1Code",
    OM."DiagnosisOriginalMentionCategory1Desc"
FROM PRESENTATION.NATIONAL_FLOWS_PCMD."DS1804_Pcmd" DEATH
LEFT JOIN PRESENTATION.NATIONAL_FLOWS_PCMD."DS1804_PcmdDiagnosisOriginalMentions" OM 
        ON OM."XSeqNo" = DEATH."XSeqNo" AND OM."DiagnosisOriginalMentionNumber" = 1;

-- GET LATEST SNAPSHOT OF DEMOGRAPHICS TABLE

DROP TABLE IF EXISTS LatestSnapshot;
CREATE TEMPORARY TABLE LatestSnapshot AS
SELECT 
    p.*
FROM PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" p 
INNER JOIN (
    SELECT "GmPseudo", MAX("Snapshot") AS LatestSnapshot
    FROM PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" p 
    GROUP BY "GmPseudo"
    ) t2
ON t2."GmPseudo" = p."GmPseudo" AND t2.LatestSnapshot = p."Snapshot";

-- CREATE A PATIENT SUMMARY TABLE TO WORK OUT WHICH PATIENTS HAVE LEFT GM 
-- AND THEREFORE THEIR DATA FEED STOPPED 

drop table if exists PatientSummary;
create temporary table PatientSummary as
select dem."GmPseudo", 
        min("Snapshot") as "min", 
        max("Snapshot") as "max", 
        max(DeathDate) as DeathDate
from PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" dem
LEFT JOIN Death ON Death."GmPseudo" = dem."GmPseudo"
group by dem."GmPseudo";

-- FIND THE DATE THAT PATIENT LEFT GM

drop table if exists leftGMDate;
create temporary table leftGMDate as 
select *,
    case when DeathDate is null and "max" < (select max("max") from PatientSummary) then "max" else null end as "leftGMDate"
from PatientSummary;

-- FIND ALL ADULT PATIENTS ALIVE AT STUDY START DATE

DROP TABLE IF EXISTS GPRegPatients;
CREATE TEMPORARY TABLE GPRegPatients AS 
SELECT  
    dem.*, 
    Death."DEATHDATE" AS "DeathDate",
	l."leftGMDate"
FROM LatestSnapshot dem
LEFT JOIN Death ON Death."GmPseudo" = dem."GmPseudo"
LEFT JOIN leftGMDate l ON l."GmPseudo" = dem."GmPseudo";

 -- study teams can be provided with 'leftGMDate' to deal with themselves, or we can filter out
 -- those that left within the study period, by applying the filter in the patient file

 -- study teams can be provided with 'DeathDate' to deal with themselves, or we can filter out
 -- those that died before the study started, by applying the filter in the patient file


DROP TABLE IF EXISTS PatientsToInclude;
CREATE TEMPORARY TABLE PatientsToInclude AS
SELECT *
FROM GPRegPatients 
WHERE ("DeathDate" IS NULL OR "DeathDate" > $StudyStartDate) -- alive on study start date
	AND 
	("leftGMDate" IS NULL OR "leftGMDate" > $StudyEndDate) -- don't include patients who left GM mid study (as we lose their data)
	AND DATEDIFF(YEAR, "DateOfBirth", $StudyStartDate) >= 18;   -- over 50 in 2016

-- >>> Codesets required... Inserting the code set code
-- >>> Codesets extracted into 0.code-sets.sql
-- >>> Following code sets injected: diffuse-large-b-cell-lymphoma v1/hodgkin-lymphoma v1/malignant-lymphoma v1


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
left join SDE_REPOSITORY.SHARED_UTILITIES."Code_Sets_SDE_Lighthouse_15_Radford_Adapt" cs on cs.code = e.sctid
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
left join SDE_REPOSITORY.SHARED_UTILITIES."Code_Sets_SDE_Lighthouse_15_Radford_Adapt" cs on cs.code = e.sctid
where cs.concept = 'diffuse-large-b-cell-lymphoma'
group by 1;

-- And for Hodgkin Lymphoma
drop table if exists "GPPatsWithHodgkinLymphoma";
create temporary table "GPPatsWithHodgkinLymphoma" as
select e."FK_Patient_ID", MIN(TO_DATE("EventDate")) AS "FirstDiagnosisHodgkin" 
from INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" e
left join SDE_REPOSITORY.SHARED_UTILITIES."Code_Sets_SDE_Lighthouse_15_Radford_Adapt" cs on cs.code = e.sctid
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

--┌────────────────────────────────────────────────────┐
--│ Cohort matching on year of birth / sex / diagnosis │
--└────────────────────────────────────────────────────┘

-- OBJECTIVE: To take a primary cohort and find a 1:n matched cohort based on year of birth, sex and diagnosis.

-- INPUT: Takes two parameters
--  - yob-flex: integer - number of years each way that still allow a year of birth match
--  - num-matches: integer - number of matches for each patient in the cohort
-- Requires two temp tables to exist as follows:
-- MainCohort (FK_Patient_Link_ID, Sex, YearOfBirth)
-- 	- FK_Patient_Link_ID - unique patient id
--	- Sex - M/F
--	- YearOfBirth - Integer
--  - Diagnosis - varchar
-- PotentialMatches (FK_Patient_Link_ID, Sex, YearOfBirth)
-- 	- FK_Patient_Link_ID - unique patient id
--	- Sex - M/F
--	- YearOfBirth - Integer
--  - Diagnosis - varchar

-- OUTPUT: A temp table as follows:
-- #CohortStore (FK_Patient_Link_ID, YearOfBirth, Sex, MatchingPatientId, MatchingYearOfBirth)
--  - FK_Patient_Link_ID - unique patient id for primary cohort patient
--  - YearOfBirth - of the primary cohort patient
--  - Sex - of the primary cohort patient
--  - Diagnosis - diagnosis of patient
--  - MatchingPatientId - id of the matched patient
--  - MatchingYearOfBirth - year of birth of the matched patient

-- TODO 
-- A few things to consider when doing matching:
--  - Consider removing "ghost patients" e.g. people without a primary care record
--  - Consider matching on practice. Patients in different locations might have different outcomes. Also
--    for primary care based diagnosing, practices might have different thoughts on severity, timing etc.
--  - For instances where lots of cases have no matches, consider allowing matching to occur with replacement.
--    I.e. a patient can match more than one person in the main cohort.

-- First we extend the PrimaryCohort table to give each age-sex combo a unique number
-- and to avoid polluting the MainCohort table

DROP TABLE IF EXISTS Cases;
CREATE TEMPORARY TABLE Cases AS
SELECT "GmPseudo" AS PatientId, 
	YearOfBirth, 
	Sex, 
	Diagnosis,
		Row_Number() OVER(PARTITION BY YearOfBirth, Sex, Diagnosis ORDER BY "GmPseudo") AS CaseRowNumber
FROM MainCohort;


-- Then we do the same with the PotentialMatches table
DROP TABLE IF EXISTS Matches;
CREATE TEMPORARY TABLE Matches AS
SELECT "GmPseudo" AS PatientId, 
	YearOfBirth, 
	Sex, 
	Diagnosis,
	Row_Number() OVER(PARTITION BY YearOfBirth, Sex, Diagnosis ORDER BY "GmPseudo") AS AssignedPersonNumber
FROM PotentialMatches;

-- Find the number of people with each characteristic in the main cohort
DROP TABLE IF EXISTS CharacteristicCount;
CREATE TEMPORARY TABLE CharacteristicCount AS
SELECT YearOfBirth, Sex, Diagnosis, COUNT(*) AS "Count" 
FROM Cases 
GROUP BY YearOfBirth, Sex, Diagnosis;

-- Find the number of potential matches for each Age/Sex combination
-- The output of this is useful for seeing how many matches you can get
-- SELECT A.YearOfBirth, A.Sex, B.Count / A.Count AS NumberOfPotentialMatchesPerCohortPatient FROM (SELECT * FROM #CharacteristicCount) A LEFT OUTER JOIN (SELECT YearOfBirth, Sex, COUNT(*) AS [Count] FROM #Matches GROUP BY YearOfBirth, Sex) B ON B.YearOfBirth = A.YearOfBirth AND B.Sex = A.Sex ORDER BY NumberOfPotentialMatches,A.YearOfBirth,A.Sex;

-- The final table contains a row for each match, so e.g. if patient 1 has 4
-- matches then there will be 4 rows in the table for this.
DROP TABLE IF EXISTS CohortStore;
CREATE TEMPORARY TABLE CohortStore ( 
  PatientId BIGINT, 
  YearOfBirth INT, 
  Sex nchar(1), 
  Diagnosis varchar(50),
  MatchingPatientId BIGINT,
  MatchingYearOfBirth INT
);

--1. First match try to match people exactly. We do this as follows:
--    - For each YOB/Sex/Diagnosis combination we find all potential matches. E.g. all patients
--    - in the potential matches with sex='F' and yob=1957 and Diagnosis = 'White British'
--    - We then try to assign a single match to all cohort members with sex='F' and yob=1957 and
--    - Diagnosis = 'White British'. If there are still matches unused, we then assign
--    - a second match to all cohort members. This continues until we either run out of matches,
--    - or successfully match everyone with the desired number of matches.

DECLARE 
    counter INT;

BEGIN 
    counter := 1; 
    
    WHILE (counter <= 3) DO 
    
        INSERT INTO CohortStore
          SELECT c.PatientId, c.YearOfBirth, c.Sex, c.Diagnosis, p.PatientId AS MatchedPatientId, c.YearOfBirth
          FROM Cases c
            INNER JOIN CharacteristicCount cc on cc.YearOfBirth = c.YearOfBirth and cc.Sex = c.Sex and cc.Diagnosis = c.Diagnosis
            INNER JOIN Matches p 
              ON p.Sex = c.Sex 
              AND p.YearOfBirth = c.YearOfBirth 
			  AND p.Diagnosis = c.Diagnosis
              -- This next line is the trick to only matching each person once
              AND p.AssignedPersonNumber = CaseRowNumber + (:counter - 1) * cc."Count";
              
           -- We might not need this, but to be extra sure let's delete any patients who 
           -- we're already using to match people
           DELETE FROM Matches WHERE PatientId IN (SELECT MatchingPatientId FROM CohortStore);
        
        counter := counter + 1; 
        
    END WHILE; 

END; 

--2. Now relax the yob restriction to get extra matches for people with no matches

DECLARE 
    lastrowinsert1 INT;
    CohortStoreRowsAtStart1 INT;

BEGIN 
    lastrowinsert1 := 1; 
    
    WHILE (lastrowinsert1 > 0) DO 
    CohortStoreRowsAtStart1 := (SELECT COUNT(*) FROM CohortStore);
    
		INSERT INTO CohortStore
		SELECT sub.PatientId, sub.YearOfBirth, sub.Sex, sub.Diagnosis, MatchedPatientId, MAX(m.YearOfBirth) FROM (
		SELECT c.PatientId, c.YearOfBirth, c.Sex, c.Diagnosis, MAX(p.PatientId) AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(p.PatientId) ORDER BY p.PatientId) AS AssignedPersonNumber
		FROM Cases c
		INNER JOIN Matches p 
			ON p.Sex = c.Sex 
			AND p.Diagnosis = c.Diagnosis 
			AND p.YearOfBirth >= c.YearOfBirth - 2
			AND p.YearOfBirth <= c.YearOfBirth + 2
		WHERE c.PatientId in (
			-- find patients who aren't currently matched
			select PatientId from Cases except select PatientId from CohortStore
		)
		GROUP BY c.PatientId, c.YearOfBirth, c.Sex, c.Diagnosis, p.PatientId) sub
		INNER JOIN Matches m 
			ON m.Sex = sub.Sex 
			AND m.Diagnosis = sub.Diagnosis 
			AND m.PatientId = sub.MatchedPatientId
			AND m.YearOfBirth >= sub.YearOfBirth - 2
			AND m.YearOfBirth <= sub.YearOfBirth + 2
		WHERE sub.AssignedPersonNumber = 1
		GROUP BY sub.PatientId, sub.YearOfBirth, sub.Sex, sub.Diagnosis, MatchedPatientId;

        lastrowinsert1 := CohortStoreRowsAtStart1 - (SELECT COUNT(*) FROM CohortStore);

		DELETE FROM Matches WHERE PatientId IN (SELECT MatchingPatientId FROM CohortStore);

	END WHILE;

END;

--3. Now relax the yob restriction to get extra matches for people with only 1, 2, 3, ... n-1 matches

DECLARE
    Counter2 INT;
    CohortStoreRowsAtStart INT;
    LastRowInsert INT;

BEGIN
    Counter2 := 1;

    WHILE (Counter2 < 3) DO
            LastRowInsert:= 1;
            
            WHILE (LastRowInsert > 0) DO
            CohortStoreRowsAtStart := (SELECT COUNT(*) FROM CohortStore);

                DROP TABLE IF EXISTS CohortPatientForEachMatchingPatient;
                CREATE TEMPORARY TABLE CohortPatientForEachMatchingPatient AS
                SELECT p.PatientId AS MatchedPatientId, c.PatientId, Row_Number() OVER(PARTITION BY p.PatientId ORDER BY p.PatientId) AS MatchedPatientNumber
                FROM Matches p
                INNER JOIN Cases c
                  ON p.Sex = c.Sex 
				  AND p.Diagnosis = c.Diagnosis 
                  AND p.YearOfBirth >= c.YearOfBirth - 2
                  AND p.YearOfBirth <= c.YearOfBirth + 2
                WHERE c.PatientId IN (
                  -- find patients who only have @Counter2 matches
                  SELECT PatientId FROM CohortStore GROUP BY PatientId HAVING count(*) = :Counter2
                );
            
                DROP TABLE IF EXISTS CohortPatientForEachMatchingPatientWithCohortNumbered;
                CREATE TEMPORARY TABLE CohortPatientForEachMatchingPatientWithCohortNumbered AS
                SELECT PatientId, MatchedPatientId, Row_Number() OVER(PARTITION BY PatientId ORDER BY MatchedPatientId) AS PatientNumber
                FROM CohortPatientForEachMatchingPatient
                WHERE MatchedPatientNumber = 1;
                
                INSERT INTO CohortStore
                SELECT s.PatientId, c.YearOfBirth, c.Sex, c.Diagnosis, MatchedPatientId, m.YearOfBirth FROM CohortPatientForEachMatchingPatientWithCohortNumbered s
                LEFT OUTER JOIN Cases c ON c.PatientId = s.PatientId
                LEFT OUTER JOIN Matches m ON m.PatientId = MatchedPatientId
                WHERE PatientNumber = 1;
            
                lastrowinsert := CohortStoreRowsAtStart - (SELECT COUNT(*) FROM CohortStore);
            
                DELETE FROM Matches WHERE PatientId IN (SELECT MatchingPatientId FROM CohortStore);
                
            END WHILE;
  
    Counter2 := Counter2  + 1;
    END WHILE;
END;

-- 4. Now attempt to match any patients with 'unknown' diagnosis


DECLARE 
    lastrowinsert3 INT;
    CohortStoreRowsAtStart3 INT;

BEGIN 
    lastrowinsert3 := 1; 
    
    WHILE (lastrowinsert3 > 0) DO 
    CohortStoreRowsAtStart3 := (SELECT COUNT(*) FROM CohortStore);
    
		INSERT INTO CohortStore
		SELECT sub.PatientId, sub.YearOfBirth, sub.Sex, sub.Diagnosis, MatchedPatientId, MAX(m.YearOfBirth) FROM (
		SELECT c.PatientId, c.YearOfBirth, c.Sex, c.Diagnosis, MAX(p.PatientId) AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(p.PatientId) ORDER BY p.PatientId) AS AssignedPersonNumber
		FROM Cases c
		INNER JOIN Matches p 
			ON p.Sex = c.Sex 
			AND c.Diagnosis = 'unknown' -- match those with unknown diag to any patient with similar YOB/Sex
			AND p.YearOfBirth >= c.YearOfBirth - 2
			AND p.YearOfBirth <= c.YearOfBirth + 2
		WHERE c.PatientId in (
			-- find patients who aren't currently matched
			select PatientId from Cases except select PatientId from CohortStore
		)
		GROUP BY c.PatientId, c.YearOfBirth, c.Sex, c.Diagnosis, p.PatientId) sub
		INNER JOIN Matches m 
			ON m.Sex = sub.Sex 
			AND sub.Diagnosis = 'unknown' -- match those with unknown diag to any patient with similar YOB/Sex			AND m.PatientId = sub.MatchedPatientId
			AND m.YearOfBirth >= sub.YearOfBirth - 2
			AND m.YearOfBirth <= sub.YearOfBirth + 2
		WHERE sub.AssignedPersonNumber = 1
		GROUP BY sub.PatientId, sub.YearOfBirth, sub.Sex, sub.Diagnosis, MatchedPatientId;

        lastrowinsert3 := CohortStoreRowsAtStart3 - (SELECT COUNT(*) FROM CohortStore);

		DELETE FROM Matches WHERE PatientId IN (SELECT MatchingPatientId FROM CohortStore);

	END WHILE;

END;


-- Get the matched cohort detail - same as main cohort
DROP TABLE IF EXISTS MatchedCohort;
CREATE TEMPORARY TABLE MatchedCohort AS
SELECT 
  c.MatchingPatientId AS "GmPseudo",
  c.YearOfBirth,
  c.Sex,
  pm.Diagnosis,
  c.MatchingYearOfBirth,
  c.PatientId AS PatientWhoIsMatched,
  c.Diagnosis AS MatchingDiagnosis,
  pm."FK_Patient_ID",
  pm."FirstAdmissionHodgkin", 
  pm."FirstDiagnosisHodgkin", 
  pm."FirstAdmissionDLBCL", 
  pm."FirstDiagnosisDLBCL",
  pm."FirstDiagnosisMalignantLymphoma",
  pm."FirstAdmissionLymphoma",
  --row_number() over (partition by c.PatientId order by square(c.YearOfBirth - c.MatchingYearOfBirth)) as matchingPriority
FROM CohortStore c
LEFT OUTER JOIN PotentialMatches pm ON pm."GmPseudo" = c.MatchingPatientId;
QUALIFY row_number() over 																		--for the cases where there are more than 3 matches
		(partition by c.PatientId order by square(c.YearOfBirth - c.MatchingYearOfBirth)) <= 3; --limit it to 3, based on closest YOB match



-- create final cohort table by combining main and matched cohort


-- ... processing [[create-output-table-matched-cohort::"LH015-1_Patients"]] ... 
-- ... Need to create an output table called "LH015-1_Patients" and replace 
-- ... the GmPseudo column with a study-specific random patient id.

-- First we create a table in an area only visible to the RDEs which contains
-- the GmPseudos. THESE CANNOT BE RELEASED TO END USERS.
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH015-1_Patients_WITH_IDENTIFIER";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH015-1_Patients_WITH_IDENTIFIER" AS
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

-- Then we check to see if there are any new GmPseudo ids. We do this by making a temp table 
-- of all "new" GmPseudo ids from either the main column or the matched column. I.e. any GmPseudo ids that 
-- we've already got a unique id for for this study are excluded

DROP TABLE IF EXISTS "AllPseudos_SDE_Lighthouse_15_Radford_Adapt";
CREATE TEMPORARY TABLE "AllPseudos_SDE_Lighthouse_15_Radford_Adapt" AS
(
SELECT DISTINCT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."LH015-1_Patients_WITH_IDENTIFIER"
UNION 
SELECT DISTINCT "MainCohortMatchedGmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."LH015-1_Patients_WITH_IDENTIFIER"
)
EXCEPT
SELECT "GmPseudo" FROM "Patient_ID_Mapping_SDE_Lighthouse_15_Radford_Adapt";

-- Find the highest currently assigned id. Ids are given incrementally, so now ones
-- need to start at +1 of the current highest
SET highestPatientId = (
    SELECT IFNULL(MAX("StudyPatientPseudoId"),0) FROM "Patient_ID_Mapping_SDE_Lighthouse_15_Radford_Adapt"
);

-- Make a study specific hash for each new GmPseudo and insert it
-- into the patient lookup table
INSERT INTO "Patient_ID_Mapping_SDE_Lighthouse_15_Radford_Adapt"
SELECT
    "GmPseudo", -- the GM SDE patient ids for patients in this cohort
    SHA2(CONCAT('SDE_Lighthouse_15_Radford_Adapt', "GmPseudo")) AS "Hash", -- used to provide a random (study-specific) ordering for the patient ids we provide
    $highestPatientId + ROW_NUMBER() OVER (ORDER BY "Hash") -- the patient id that we provide to the analysts
FROM "AllPseudos_SDE_Lighthouse_15_Radford_Adapt";

-- Finally, we select from the output table which includes the GmPseudos, in order
-- to populate the table for the end users where the GmPseudo fields are redacted via a function
-- created in the 0.code-sets.sql file
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH015-1_Patients";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH015-1_Patients" AS
SELECT SDE_REPOSITORY.SHARED_UTILITIES.gm_pseudo_hash_SDE_Lighthouse_15_Radford_Adapt("GmPseudo") AS "PatientID",
	SDE_REPOSITORY.SHARED_UTILITIES.gm_pseudo_hash_SDE_Lighthouse_15_Radford_Adapt("MainCohortMatchedGmPseudo") AS "MainCohortMatchedPatientID",
	* EXCLUDE ("GmPseudo", "MainCohortMatchedGmPseudo")
FROM SDE_REPOSITORY.SHARED_UTILITIES."LH015-1_Patients_WITH_IDENTIFIER";

-- create simpler version of the above table to be the cohort table that other files pull from
-- combine the main cohort, matched cohort, and any ADAPT patients that didn't have demographic
-- info so we couldn't match them


DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_15_Radford_Adapt";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_15_Radford_Adapt" AS 
SELECT 
	 m."GmPseudo",
     D."FK_Patient_ID"
FROM MainCohort m
-- 378 ADAPT patients with GP record so we can match 
LEFT OUTER JOIN PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" D on D."GmPseudo" = m."GmPseudo"
UNION
SELECT
 	 m."GmPseudo",
     D."FK_Patient_ID"
FROM MatchedCohort m
LEFT OUTER JOIN PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" D on D."GmPseudo" = m."GmPseudo"
-- around 1,100 matched patients
UNION 
SELECT 
     m."GmPseudo",
     D."FK_Patient_ID"
FROM SDE_REPOSITORY.SHARED_UTILITIES."LH015-0_AdaptPatients_WITH_IDENTIFIER" m
LEFT OUTER JOIN PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" D on D."GmPseudo" = m."GmPseudo";
-- around 300 patients with no GP record