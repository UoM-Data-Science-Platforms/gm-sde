USE SCHEMA SDE_REPOSITORY.SHARED_UTILITIES;

--┌──────────────────────────────────────────────┐
--│ SDE Lighthouse study 15 - Patients           │
--└──────────────────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK ------------

--------------------------------------------------

--┌───────────────────────────────────────────────────────────────────────────────┐
--│ Define Cohort for LH015: patients from the ADAPT cohort and matched controls  │
--└───────────────────────────────────────────────────────────────────────────────┘

-- OBJECTIVE: To build the cohort of patients needed for LH015. This reduces duplication of code in the template scripts.

-- COHORT: Any adult patient that was enrolled on the ADAPT intervention, as well as a cohort of matched controls.
--         Excluding .....

-- INPUT: none
-- OUTPUT: Cohort table and patients table

set(StudyStartDate) = to_date('2015-03-01');
set(StudyEndDate)   = to_date('2022-03-31');


--┌─────────────────────────────────────────────────────────────────┐
--│ Create table of patients who were alive at the study start date │
--└─────────────────────────────────────────────────────────────────┘

-- ** any patients opted out of sharing GP data would not appear in the final table

-- this script requires an input of StudyStartDate

-- takes one parameter: 
-- minimum-age : integer - The minimum age of the group of patients. Typically this would be 0 (all patients) or 18 (all adults)

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
	WHERE DATEDIFF(YEAR, TO_DATE("DateOfBirth"), $StudyStartDate) >= 18 -- adults only
    GROUP BY "GmPseudo"
    ) t2
ON t2."GmPseudo" = p."GmPseudo" AND t2.LatestSnapshot = p."Snapshot";

-- FIND ALL ADULT PATIENTS ALIVE AT STUDY START DATE

DROP TABLE IF EXISTS AlivePatientsAtStart;
CREATE TEMPORARY TABLE AlivePatientsAtStart AS 
SELECT  
    dem.*, 
    Death.DeathDate
FROM LatestSnapshot dem
LEFT JOIN Death ON Death."GmPseudo" = dem."GmPseudo"
WHERE 
    (DeathDate IS NULL OR DeathDate > $StudyStartDate); -- alive on study start date


-- >>> Codesets required... Inserting the code set code
-- >>> Codesets extracted into 0.code-sets.sql
-- >>> Following code sets injected: diffuse-large-b-cell-lymphoma v1/hodgkin-lymphoma v1


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
left join SDE_REPOSITORY.SHARED_UTILITIES."Code_Sets_SDE_Lighthouse_15_Radford_Adapt" cs on cs.code = e."SuppliedCode"
where cs.concept = 'diffuse-large-b-cell-lymphoma';

-- And for Hodgkin Lymphoma
drop table if exists "GPPatsWithHodgkinLymphoma";
create temporary table "GPPatsWithHodgkinLymphoma" as
select distinct "FK_Patient_ID" 
from INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" e
left join SDE_REPOSITORY.SHARED_UTILITIES."Code_Sets_SDE_Lighthouse_15_Radford_Adapt" cs on cs.code = e."SuppliedCode"
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

--┌────────────────────────────────────────────────────┐
--│ Cohort matching on year of birth / sex 					   │
--└────────────────────────────────────────────────────┘

-- OBJECTIVE: To take a primary cohort and find a 1:n matched cohort based on year of birth and sex.

-- INPUT: Takes two parameters
--  - yob-flex: integer - number of years each way that still allow a year of birth match
--  - num-matches: integer - number of matches for each patient in the cohort
-- Requires two temp tables to exist as follows:
-- MainCohort (FK_Patient_Link_ID, Sex, YearOfBirth)
-- 	- FK_Patient_Link_ID - unique patient id
--	- Sex - M/F
--	- YearOfBirth - Integer
-- PotentialMatches (FK_Patient_Link_ID, Sex, YearOfBirth)
-- 	- FK_Patient_Link_ID - unique patient id
--	- Sex - M/F
--	- YearOfBirth - Integer

-- OUTPUT: A temp table as follows:
-- #CohortStore (FK_Patient_Link_ID, YearOfBirth, Sex, MatchingPatientId, MatchingYearOfBirth)
--  - FK_Patient_Link_ID - unique patient id for primary cohort patient
--  - YearOfBirth - of the primary cohort patient
--  - Sex - of the primary cohort patient
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
SELECT "FK_Patient_ID" AS PatientId, 
	YearOfBirth, 
	Sex, 
	Row_Number() OVER(PARTITION BY YearOfBirth, Sex ORDER BY "FK_Patient_ID") AS CaseRowNumber
FROM MainCohort;

-- Then we do the same with the PotentialMatches table
DROP TABLE IF EXISTS Matches;
CREATE TEMPORARY TABLE Matches AS
SELECT "FK_Patient_ID" AS PatientId, 
	YearOfBirth, 
	Sex, 
	Row_Number() OVER(PARTITION BY YearOfBirth, Sex ORDER BY "FK_Patient_ID") AS AssignedPersonNumber
FROM PotentialMatches;

-- Find the number of people with each characteristic in the main cohort
DROP TABLE IF EXISTS CharacteristicCount;
CREATE TEMPORARY TABLE CharacteristicCount AS
SELECT YearOfBirth, Sex, COUNT(*) AS "Count" 
FROM Cases 
GROUP BY YearOfBirth, Sex;

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
  MatchingPatientId BIGINT,
  MatchingYearOfBirth INT
);

--1. First match try to match people exactly. We do this as follows:
--    - For each YOB/Sex combination we find all potential matches. E.g. all patients
--      in the potential matches with sex='F' and yob=1957
--    - We then try to assign a single match to all cohort members with sex='F' and yob=1957
--    - If there are still matches unused, we then assign a second match to all cohort members
--    - This continues until we either run out of matches, or successfully match everyone with
--      the desired number of matches.

DECLARE 
    counter INT;

BEGIN 
    counter := 1; 
    
    WHILE (counter <= 5) DO 
    
        INSERT INTO CohortStore
          SELECT c.PatientId, c.YearOfBirth, c.Sex, p.PatientId AS MatchedPatientId, c.YearOfBirth
          FROM Cases c
            INNER JOIN CharacteristicCount cc on cc.YearOfBirth = c.YearOfBirth and cc.Sex = c.Sex
            INNER JOIN Matches p 
              ON p.Sex = c.Sex 
              AND p.YearOfBirth = c.YearOfBirth 
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
		SELECT sub.PatientId, sub.YearOfBirth, sub.Sex, MatchedPatientId, MAX(m.YearOfBirth) FROM (
		SELECT c.PatientId, c.YearOfBirth, c.Sex, MAX(p.PatientId) AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(p.PatientId) ORDER BY p.PatientId) AS AssignedPersonNumber
		FROM Cases c
		INNER JOIN Matches p 
			ON p.Sex = c.Sex 
			AND p.YearOfBirth >= c.YearOfBirth - 5
			AND p.YearOfBirth <= c.YearOfBirth + 5
		WHERE c.PatientId in (
			-- find patients who aren't currently matched
			select PatientId from Cases except select PatientId from CohortStore
		)
		GROUP BY c.PatientId, c.YearOfBirth, c.Sex, p.PatientId) sub
		INNER JOIN Matches m 
			ON m.Sex = sub.Sex 
			AND m.PatientId = sub.MatchedPatientId
			AND m.YearOfBirth >= sub.YearOfBirth - 5
			AND m.YearOfBirth <= sub.YearOfBirth + 5
		WHERE sub.AssignedPersonNumber = 1
		GROUP BY sub.PatientId, sub.YearOfBirth, sub.Sex, MatchedPatientId;

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

    WHILE (Counter2 < 5) DO
            LastRowInsert:= 1;
            
            WHILE (LastRowInsert > 0) DO
            CohortStoreRowsAtStart := (SELECT COUNT(*) FROM CohortStore);

                DROP TABLE IF EXISTS CohortPatientForEachMatchingPatient;
                CREATE TEMPORARY TABLE CohortPatientForEachMatchingPatient AS
                SELECT p.PatientId AS MatchedPatientId, c.PatientId, Row_Number() OVER(PARTITION BY p.PatientId ORDER BY p.PatientId) AS MatchedPatientNumber
                FROM Matches p
                INNER JOIN Cases c
                  ON p.Sex = c.Sex 
                  AND p.YearOfBirth >= c.YearOfBirth - 5
                  AND p.YearOfBirth <= c.YearOfBirth + 5
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
                SELECT s.PatientId, c.YearOfBirth, c.Sex, MatchedPatientId, m.YearOfBirth FROM CohortPatientForEachMatchingPatientWithCohortNumbered s
                LEFT OUTER JOIN Cases c ON c.PatientId = s.PatientId
                LEFT OUTER JOIN Matches m ON m.PatientId = MatchedPatientId
                WHERE PatientNumber = 1;
            
                lastrowinsert := CohortStoreRowsAtStart - (SELECT COUNT(*) FROM CohortStore);
            
                DELETE FROM Matches WHERE PatientId IN (SELECT MatchingPatientId FROM CohortStore);
                
            END WHILE;
  
    Counter2 := Counter2  + 1;
    END WHILE;
END;



-- Get the matched cohort detail - same as main cohort
DROP TABLE IF EXISTS MatchedCohort;
CREATE TEMPORARY TABLE MatchedCohort AS
SELECT 
  c.MatchingPatientId AS "GmPseudo",
  c.YearOfBirth,
  c.Sex,
  c.MatchingYearOfBirth,
  c.PatientId AS PatientWhoIsMatched,
select * FROM CohortStore c;

-- No output table required for this script