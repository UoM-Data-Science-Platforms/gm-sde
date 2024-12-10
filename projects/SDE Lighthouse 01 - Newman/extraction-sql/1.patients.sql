USE SCHEMA SDE_REPOSITORY.SHARED_UTILITIES;

--┌────────────────────────────────────┐
--│ LH001 Patient file                 │
--└────────────────────────────────────┘

-- COHORT: Any patient with a pharmacogenetic test, or a matched control.

set(StudyStartDate) = to_date('2022-07-01');
set(StudyEndDate)   = to_date('2024-10-31');



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
LEFT JOIN leftGMDate l ON l."GmPseudo" = dem."GmPseudo"

 -- study teams can be provided with 'leftGMDate' to deal with themselves, or we can filter out
 -- those that left within the study period, by applying the filter in the patient file

 -- study teams can be provided with 'DeathDate' to deal with themselves, or we can filter out
 -- those that died before the study started, by applying the filter in the patient file


DROP TABLE IF EXISTS PatientsToInclude;
CREATE TEMPORARY TABLE PatientsToInclude AS
SELECT 
FROM GPRegPatients 
WHERE ("DeathDate" IS NULL OR "DeathDate" > $StudyStartDate) -- alive on study start date
	AND 
	("leftGMDate" IS NULL OR "leftGMDate" > $StudyEndDate); -- don't include patients who left GM mid study (as we lose their data)
	AND DATEDIFF(YEAR, "DateOfBirth", $StudyStartDate) >= 18 -- OVER 18s ONLY

-- table of pharmacogenetic test patients

-- for now, create a test table to imitate the pharmacogenetic data
DROP TABLE IF EXISTS PharmacogeneticTable;
CREATE TEMPORARY TABLE PharmacogeneticTable AS
(SELECT DISTINCT
    ec."FK_Patient_ID"
	, ec."GmPseudo"
    , 'IPTIP' as "Cohort"
FROM INTERMEDIATE.GP_RECORD."Combined_EventsMedications_Clusters_SecondaryUses" ec
LIMIT 500)
UNION
(SELECT DISTINCT
    ec."FK_Patient_ID"
	, ec."GmPseudo"
    , 'PROGRESS' as "Cohort"
FROM INTERMEDIATE.GP_RECORD."Combined_EventsMedications_Clusters_SecondaryUses" ec
LIMIT 500);
    
------

--- the study team want to find patients that recently started on a new medication, to match to the main cohort
--- so we build two tables, one for old prescriptions, and one for new

-- build table of new prescriptions 

DROP TABLE IF EXISTS new_prescriptions;
CREATE TEMPORARY TABLE new_prescriptions AS
SELECT 
    ec."FK_Patient_ID"
	, ec."GmPseudo"
    , TO_DATE(ec."Date") AS "Date"
    , ec."SCTID" AS "SnomedCode"
    , CASE WHEN ec."Field_ID" = 'Statin' THEN "FoundValue" -- statin
			-- SSRIs
	       WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("MedicationDescription") LIKE '%citalopram%')    THEN 'citalopram'
		   WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("MedicationDescription") LIKE '%escitalopram%')  THEN 'escitalopram'
	       WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("MedicationDescription") LIKE '%fluvoxamine%')   THEN 'fluvoxamine'
	       WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("MedicationDescription") LIKE '%paroxetine%')    THEN 'paroxetine'
		   WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("MedicationDescription") LIKE '%sertraline%')    THEN 'sertraline'
	       WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("MedicationDescription") LIKE '%venlafaxine%')   THEN 'venlafaxine'
		   -- tricyclic antidepressants
		   WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("MedicationDescription") LIKE '%amitriptyline%') THEN 'amitriptyline'
           WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("MedicationDescription") LIKE '%clomipramine%')  THEN 'clomipramine'
		   WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("MedicationDescription") LIKE '%doxepin%')       THEN 'doxepin'
		   WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("MedicationDescription") LIKE '%imipramine%')    THEN 'imipramine'
		   WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("MedicationDescription") LIKE '%nortriptyline%') THEN 'nortiptyline'
		   WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("MedicationDescription") LIKE '%trimipramine%')  THEN 'trimipramine'
			-- proton pump inhibitors
		   WHEN ("Cluster_ID" = 'ULCERHEALDRUG_COD') AND (LOWER("MedicationDescription") LIKE '%esomeprazole%') THEN 'esomeprazole'
		   WHEN ("Cluster_ID" = 'ULCERHEALDRUG_COD') AND (LOWER("MedicationDescription") LIKE '%lansoprazole%') THEN 'lansoprazole'
		   WHEN ("Cluster_ID" = 'ULCERHEALDRUG_COD') AND (LOWER("MedicationDescription") LIKE '%omeprazole%')   THEN 'omeprazole'
		   WHEN ("Cluster_ID" = 'ULCERHEALDRUG_COD') AND (LOWER("MedicationDescription") LIKE '%pantoprazole%') THEN 'pantoprazole'
		   WHEN ("Cluster_ID" = 'ULCERHEALDRUG_COD') AND (LOWER("MedicationDescription") LIKE '%rabeprazole%')  THEN 'rabeprazole'
		   ELSE 'other' END AS "Concept"
    , ec."MedicationDescription" AS "Description"
FROM INTERMEDIATE.GP_RECORD."Combined_EventsMedications_Clusters_SecondaryUses" ec
WHERE 
	ec."GmPseudo" NOT IN (SELECT "GmPseudo" FROM PharmacogeneticTable)
	AND
	-- Statins
	(("Field_ID" = 'Statin') OR 
	-- SSRIs
	("Field_ID" = 'ANTIDEPDRUG_COD' AND (LOWER("MedicationDescription") LIKE '%citalopram%' OR LOWER("MedicationDescription") LIKE '%escitalopram%' OR LOWER("MedicationDescription") LIKE '%fluvoxamine%' OR LOWER("MedicationDescription") LIKE '%paroxetine%' OR LOWER("MedicationDescription") LIKE '%sertraline%' OR LOWER("MedicationDescription") LIKE '%venlafaxine%')) OR
	-- tricyclic antidepressants
	("Field_ID" = 'ANTIDEPDRUG_COD' AND (LOWER("MedicationDescription") LIKE '%amitriptyline%' OR LOWER("MedicationDescription") LIKE '%clomipramine%' OR LOWER("MedicationDescription") LIKE '%doxepin%' OR LOWER("MedicationDescription") LIKE '%imipramine%' OR LOWER("MedicationDescription") LIKE '%nortriptyline%' OR LOWER("MedicationDescription") LIKE '%trimipramine%')) OR
	-- proton pump inhibitors
	( "Field_ID" = 'ULCERHEALDRUG_COD' AND (LOWER("MedicationDescription") LIKE '%esomeprazole%' OR LOWER("MedicationDescription") LIKE '%lansoprazole%' OR LOWER("MedicationDescription") LIKE '%omeprazole%' OR LOWER("MedicationDescription") LIKE '%pantoprazole%' OR LOWER("MedicationDescription") LIKE '%rabeprazole%' )) )
AND TO_DATE(ec."Date") BETWEEN '2023-06-01' and '2025-06-01';

-- table of old prescriptions 
--	(we will use this to find patients that weren't prescribed the medication before,but have been prescribed it more recently)

DROP TABLE IF EXISTS new_prescriptions;
CREATE TEMPORARY TABLE new_prescriptions AS
SELECT 
    ec."FK_Patient_ID"
	, ec."GmPseudo"
    , TO_DATE(ec."Date") AS "Date"
    , ec."SCTID" AS "SnomedCode"
    , CASE WHEN ec."Field_ID" = 'Statin' THEN "FoundValue" -- statin
			-- SSRIs
	       WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("Term") LIKE '%citalopram%')    THEN 'citalopram'
		   WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("Term") LIKE '%escitalopram%')  THEN 'escitalopram'
	       WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("Term") LIKE '%fluvoxamine%')   THEN 'fluvoxamine'
	       WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("Term") LIKE '%paroxetine%')    THEN 'paroxetine'
		   WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("Term") LIKE '%sertraline%')    THEN 'sertraline'
	       WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("Term") LIKE '%venlafaxine%')   THEN 'venlafaxine'
		   -- tricyclic antidepressants
		   WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("Term") LIKE '%amitriptyline%') THEN 'amitriptyline'
           WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("Term") LIKE '%clomipramine%')  THEN 'clomipramine'
		   WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("Term") LIKE '%doxepin%')       THEN 'doxepin'
		   WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("Term") LIKE '%imipramine%')    THEN 'imipramine'
		   WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("Term") LIKE '%nortriptyline%') THEN 'nortiptyline'
		   WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("Term") LIKE '%trimipramine%')  THEN 'trimipramine'
			-- proton pump inhibitors
		   WHEN ("Cluster_ID" = 'ULCERHEALDRUG_COD') AND (LOWER("Term") LIKE '%esomeprazole%') THEN 'esomeprazole'
		   WHEN ("Cluster_ID" = 'ULCERHEALDRUG_COD') AND (LOWER("Term") LIKE '%lansoprazole%') THEN 'lansoprazole'
		   WHEN ("Cluster_ID" = 'ULCERHEALDRUG_COD') AND (LOWER("Term") LIKE '%omeprazole%')   THEN 'omeprazole'
		   WHEN ("Cluster_ID" = 'ULCERHEALDRUG_COD') AND (LOWER("Term") LIKE '%pantoprazole%') THEN 'pantoprazole'
		   WHEN ("Cluster_ID" = 'ULCERHEALDRUG_COD') AND (LOWER("Term") LIKE '%rabeprazole%')  THEN 'rabeprazole'
		   ELSE 'other' END AS "Concept"
    , ec."Term" AS "Description"
FROM INTERMEDIATE.GP_RECORD."Combined_EventsMedications_Clusters_SecondaryUses" ec
WHERE 
	ec."GmPseudo" NOT IN (SELECT "GmPseudo" FROM PharmacogeneticTable)
	AND
	-- Statins
	(("Field_ID" = 'Statin') OR 
	-- SSRIs
	("Field_ID" = 'ANTIDEPDRUG_COD' AND (LOWER("Term") LIKE '%citalopram%' OR LOWER("Term") LIKE '%escitalopram%' OR LOWER("Term") LIKE '%fluvoxamine%' OR LOWER("Term") LIKE '%paroxetine%' OR LOWER("Term") LIKE '%sertraline%' OR LOWER("Term") LIKE '%venlafaxine%')) OR
	-- tricyclic antidepressants
	("Field_ID" = 'ANTIDEPDRUG_COD' AND (LOWER("Term") LIKE '%amitriptyline%' OR LOWER("Term") LIKE '%clomipramine%' OR LOWER("Term") LIKE '%doxepin%' OR LOWER("Term") LIKE '%imipramine%' OR LOWER("Term") LIKE '%nortriptyline%' OR LOWER("Term") LIKE '%trimipramine%')) OR
	-- proton pump inhibitors
	( "Field_ID" = 'ULCERHEALDRUG_COD' AND (LOWER("Term") LIKE '%esomeprazole%' OR LOWER("Term") LIKE '%lansoprazole%' OR LOWER("Term") LIKE '%omeprazole%' OR LOWER("Term") LIKE '%pantoprazole%' OR LOWER("Term") LIKE '%rabeprazole%' )) )
AND TO_DATE(ec."Date") BETWEEN '2023-06-01' and '2025-06-01';

-- table of old prescriptions 
--	(we will use this to find patients that weren't prescribed the medication before,but have been prescribed it more recently)

DROP TABLE IF EXISTS old_prescriptions;
CREATE TEMPORARY TABLE old_prescriptions AS
SELECT 
    ec."FK_Patient_ID"
    , ec."GmPseudo"
    , TO_DATE(ec."Date") AS "Date"
    , ec."SCTID" AS "SnomedCode"
    , CASE WHEN ec."Field_ID" = 'Statin' THEN "FoundValue" -- statin
			-- SSRIs
	       WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("Term") LIKE '%citalopram%')    THEN 'citalopram'
		   WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("Term") LIKE '%escitalopram%')  THEN 'escitalopram'
	       WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("Term") LIKE '%fluvoxamine%')   THEN 'fluvoxamine'
	       WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("Term") LIKE '%paroxetine%')    THEN 'paroxetine'
		   WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("Term") LIKE '%sertraline%')    THEN 'sertraline'
	       WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("Term") LIKE '%venlafaxine%')   THEN 'venlafaxine'
		   -- tricyclic antidepressants
		   WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("Term") LIKE '%amitriptyline%') THEN 'amitriptyline'
           WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("Term") LIKE '%clomipramine%')  THEN 'clomipramine'
		   WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("Term") LIKE '%doxepin%')       THEN 'doxepin'
		   WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("Term") LIKE '%imipramine%')    THEN 'imipramine'
		   WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("Term") LIKE '%nortriptyline%') THEN 'nortiptyline'
		   WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("Term") LIKE '%trimipramine%')  THEN 'trimipramine'
			-- proton pump inhibitors
		   WHEN ("Cluster_ID" = 'ULCERHEALDRUG_COD') AND (LOWER("Term") LIKE '%esomeprazole%') THEN 'esomeprazole'
		   WHEN ("Cluster_ID" = 'ULCERHEALDRUG_COD') AND (LOWER("Term") LIKE '%lansoprazole%') THEN 'lansoprazole'
		   WHEN ("Cluster_ID" = 'ULCERHEALDRUG_COD') AND (LOWER("Term") LIKE '%omeprazole%')   THEN 'omeprazole'
		   WHEN ("Cluster_ID" = 'ULCERHEALDRUG_COD') AND (LOWER("Term") LIKE '%pantoprazole%') THEN 'pantoprazole'
		   WHEN ("Cluster_ID" = 'ULCERHEALDRUG_COD') AND (LOWER("Term") LIKE '%rabeprazole%')  THEN 'rabeprazole'
		   ELSE 'other' END AS "Concept"
    , ec."Term" AS "Description"
FROM INTERMEDIATE.GP_RECORD."Combined_EventsMedications_Clusters_SecondaryUses" ec
WHERE 
	"GmPseudo" NOT IN (SELECT "GmPseudo" FROM PharmacogeneticTable)
	AND
	-- Statins
	(("Field_ID" = 'Statin') OR 
	-- SSRIs
	("Field_ID" = 'ANTIDEPDRUG_COD' AND (LOWER("Term") LIKE '%citalopram%' OR LOWER("Term") LIKE '%escitalopram%' OR LOWER("Term") LIKE '%fluvoxamine%' OR LOWER("Term") LIKE '%paroxetine%' OR LOWER("Term") LIKE '%sertraline%' OR LOWER("Term") LIKE '%venlafaxine%')) OR
	-- tricyclic antidepressants
	("Field_ID" = 'ANTIDEPDRUG_COD' AND (LOWER("Term") LIKE '%amitriptyline%' OR LOWER("Term") LIKE '%clomipramine%' OR LOWER("Term") LIKE '%doxepin%' OR LOWER("Term") LIKE '%imipramine%' OR LOWER("Term") LIKE '%nortriptyline%' OR LOWER("Term") LIKE '%trimipramine%')) OR
	-- proton pump inhibitors
	( "Field_ID" = 'ULCERHEALDRUG_COD' AND (LOWER("Term") LIKE '%esomeprazole%' OR LOWER("Term") LIKE '%lansoprazole%' OR LOWER("Term") LIKE '%omeprazole%' OR LOWER("Term") LIKE '%pantoprazole%' OR LOWER("Term") LIKE '%rabeprazole%' )))
AND TO_DATE(ec."Date") < '2023-06-01';

-- binary columns for each med type, indicating whether patient was ever prescribed it before June 2023

DROP TABLE IF EXISTS OldPrescriptionsSummary;
CREATE TEMPORARY TABLE OldPrescriptionsSummary AS
SELECT "FK_Patient_ID",
    CASE WHEN PPI >= 1 THEN 1 ELSE 0 END AS PPI,
    CASE WHEN TCA >= 1 THEN 1 ELSE 0 END AS TCA,
    CASE WHEN SSRI >= 1 THEN 1 ELSE 0 END AS SSRI,
    CASE WHEN STATIN >= 1 THEN 1 ELSE 0 END AS STATIN
FROM (
SELECT "FK_Patient_ID", 
	SUM(CASE WHEN "Concept" in ('esomeprazole','lansoprazole', 'omeprazole', 'pantoprazole', 'rabeprazole') THEN 1 ELSE 0 END) 				AS PPI,
	SUM(CASE WHEN "Concept" in ('amitriptyline','clomipramine', 'doxepin', 'imipramine', 'nortiptyline', 'trimipramine') THEN 1 ELSE 0 END) AS TCA,
	SUM(CASE WHEN "Concept" in ('citalopram','escitalopram', 'fluvoxamine', 'paroxetine', 'sertraline', 'venlafaxine') THEN 1 ELSE 0 END) 	AS SSRI,
	SUM(CASE WHEN "Concept" like '%statin%' THEN 1 ELSE 0 END) 																				AS STATIN
FROM old_prescriptions
GROUP BY "FK_Patient_ID") SUB;

-- same table but for new prescriptions 

DROP TABLE IF EXISTS NewPrescriptionsSummary;
CREATE TEMPORARY TABLE NewPrescriptionsSummary AS
SELECT "FK_Patient_ID",
    CASE WHEN PPI >= 1 THEN 1 ELSE 0 END AS PPI,
    CASE WHEN TCA >= 1 THEN 1 ELSE 0 END AS TCA,
    CASE WHEN SSRI >= 1 THEN 1 ELSE 0 END AS SSRI,
    CASE WHEN STATIN >= 1 THEN 1 ELSE 0 END AS STATIN
FROM (
SELECT "FK_Patient_ID", 
	SUM(CASE WHEN "Concept" in ('esomeprazole','lansoprazole', 'omeprazole', 'pantoprazole', 'rabeprazole') THEN 1 ELSE 0 END) 				AS PPI,
	SUM(CASE WHEN "Concept" in ('amitriptyline','clomipramine', 'doxepin', 'imipramine', 'nortiptyline', 'trimipramine') THEN 1 ELSE 0 END) AS TCA,
	SUM(CASE WHEN "Concept" in ('citalopram','escitalopram', 'fluvoxamine', 'paroxetine', 'sertraline', 'venlafaxine') THEN 1 ELSE 0 END) 	AS SSRI,
	SUM(CASE WHEN "Concept" like '%statin%' THEN 1 ELSE 0 END) 																				AS STATIN
FROM new_prescriptions
GROUP BY "FK_Patient_ID") SUB;


-- create main cohort
-- use the latest snapshot before the start of the PROGRESS study
DROP TABLE IF EXISTS MainCohort;
CREATE TEMPORARY TABLE MainCohort AS
SELECT DISTINCT
	 p."FK_Patient_ID",
	 p."GmPseudo",
     "Sex" as Sex,
     YEAR("DateOfBirth") AS YearOfBirth,
	 "EthnicityLatest_Category" AS EthnicCategory,
     ph."Cohort",
     CASE WHEN ph."Cohort" = 'PROGRESS' THEN '2023-06-01' WHEN ph."Cohort" = 'IPTIP' THEN '2022-07-01'
        ELSE NULL END AS IndexDate,
	 "Snapshot"
FROM PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" p
INNER JOIN PharmacogeneticTable ph ON ph."GmPseudo" = p."GmPseudo" 
WHERE p."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM PharmacogeneticTable)
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
LEFT OUTER JOIN NewPrescriptionsSummary nps ON nps."FK_Patient_ID" = p."FK_Patient_ID"
LEFT OUTER JOIN OldPrescriptionsSummary ops ON ops."FK_Patient_ID" = p."FK_Patient_ID"
WHERE p."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM AlivePatientsAtStart)
	AND p."GmPseudo" NOT IN (SELECT "GmPseudo" FROM MainCohort)
	AND "Snapshot" <= '2022-07-01' -- demographic information at closest date to the start of the trial
	AND ( -- if a patient had no old prescriptions of a med type, but at least one new prescription, then include them
		(nps.PPI = 1 AND ops.PPI = 0) OR
		(nps.SSRI = 1 AND ops.SSRI = 0) OR
		(nps.TCA = 1 AND ops.TCA = 0) OR
		(nps.STATIN = 1 AND ops.STATIN = 0)
		)
QUALIFY row_number() OVER (PARTITION BY p."GmPseudo" ORDER BY "Snapshot" DESC) = 1; -- this brings back the values from the most recent snapshot



-- TODO : create a replica of the above table but with a diff snapshot date based on 

-- run matching script with parameters filled in
-- this will match the main cohort patients with up to 5 similar patients, with 2 years of flexibility around year of birth

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
SELECT "GmPseudo" AS PatientId, 
	YearOfBirth, 
	Sex, 
	EthnicCategory,
		Row_Number() OVER(PARTITION BY YearOfBirth, Sex, EthnicCategory ORDER BY "GmPseudo") AS CaseRowNumber
FROM MainCohort;


-- Then we do the same with the PotentialMatches table
DROP TABLE IF EXISTS Matches;
CREATE TEMPORARY TABLE Matches AS
SELECT "GmPseudo" AS PatientId, 
	YearOfBirth, 
	Sex, 
	EthnicCategory,
	Row_Number() OVER(PARTITION BY YearOfBirth, Sex, EthnicCategory ORDER BY "GmPseudo") AS AssignedPersonNumber
FROM PotentialMatches;

-- Find the number of people with each characteristic in the main cohort
DROP TABLE IF EXISTS CharacteristicCount;
CREATE TEMPORARY TABLE CharacteristicCount AS
SELECT YearOfBirth, Sex, EthnicCategory, COUNT(*) AS "Count" 
FROM Cases 
GROUP BY YearOfBirth, Sex, EthnicCategory;

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
  EthnicCategory varchar(50),
  MatchingPatientId BIGINT,
  MatchingYearOfBirth INT
);

--1. First match try to match people exactly. We do this as follows:
--    - For each YOB/Sex/EthnicCategory combination we find all potential matches. E.g. all patients
--    - in the potential matches with sex='F' and yob=1957 and EthnicCategory = 'White British'
--    - We then try to assign a single match to all cohort members with sex='F' and yob=1957 and
--    - EthnicCategory = 'White British'. If there are still matches unused, we then assign
--    - a second match to all cohort members. This continues until we either run out of matches,
--    - or successfully match everyone with the desired number of matches.

DECLARE 
    counter INT;

BEGIN 
    counter := 1; 
    
    WHILE (counter <= 5) DO 
    
        INSERT INTO CohortStore
          SELECT c.PatientId, c.YearOfBirth, c.Sex, c.EthnicCategory, p.PatientId AS MatchedPatientId, c.YearOfBirth
          FROM Cases c
            INNER JOIN CharacteristicCount cc on cc.YearOfBirth = c.YearOfBirth and cc.Sex = c.Sex and cc.EthnicCategory = c.EthnicCategory
            INNER JOIN Matches p 
              ON p.Sex = c.Sex 
              AND p.YearOfBirth = c.YearOfBirth 
			  AND p.EthnicCategory = c.EthnicCategory
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
		SELECT sub.PatientId, sub.YearOfBirth, sub.Sex, sub.EthnicCategory, MatchedPatientId, MAX(m.YearOfBirth) FROM (
		SELECT c.PatientId, c.YearOfBirth, c.Sex, c.EthnicCategory, MAX(p.PatientId) AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(p.PatientId) ORDER BY p.PatientId) AS AssignedPersonNumber
		FROM Cases c
		INNER JOIN Matches p 
			ON p.Sex = c.Sex 
			AND p.EthnicCategory = c.EthnicCategory
			AND p.YearOfBirth >= c.YearOfBirth - 2
			AND p.YearOfBirth <= c.YearOfBirth + 2
		WHERE c.PatientId in (
			-- find patients who aren't currently matched
			select PatientId from Cases except select PatientId from CohortStore
		)
		GROUP BY c.PatientId, c.YearOfBirth, c.Sex, c.EthnicCategory, p.PatientId) sub
		INNER JOIN Matches m 
			ON m.Sex = sub.Sex 
			AND m.EthnicCategory = sub.EthnicCategory
			AND m.PatientId = sub.MatchedPatientId
			AND m.YearOfBirth >= sub.YearOfBirth - 2
			AND m.YearOfBirth <= sub.YearOfBirth + 2
		WHERE sub.AssignedPersonNumber = 1
		GROUP BY sub.PatientId, sub.YearOfBirth, sub.Sex, sub.EthnicCategory, MatchedPatientId;

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
				  AND p.EthnicCategory = c.EthnicCategory
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
                SELECT s.PatientId, c.YearOfBirth, c.Sex, c.EthnicCategory, MatchedPatientId, m.YearOfBirth FROM CohortPatientForEachMatchingPatientWithCohortNumbered s
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
  c.Sex,
  c.MatchingYearOfBirth,
  c.EthnicCategory,
  c.PatientId AS PatientWhoIsMatched,
FROM CohortStore c;

-- bring main and matched cohort together for final output


-- ... processing [[create-output-table-matched-cohort::"LH001-1_Patients"]] ... 
-- ... Need to create an output table called "LH001-1_Patients" and replace 
-- ... the GmPseudo column with a study-specific random patient id.

-- First we create a table in an area only visible to the RDEs which contains
-- the GmPseudos. THESE CANNOT BE RELEASED TO END USERS.
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH001-1_Patients_WITH_IDENTIFIER";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH001-1_Patients_WITH_IDENTIFIER" AS
SELECT 
	 m."GmPseudo",
	 D."Snapshot",
     NULL AS "MainCohortMatchedGmPseudo",
     m."Cohort",
     m.IndexDate AS "IndexDate",
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
    "DiagnosisOriginalMentionCategory1Desc" AS "CauseOfDeathCategoryDesc"
FROM MainCohort m
LEFT OUTER JOIN Death dth ON dth."GmPseudo" = m."GmPseudo"
LEFT OUTER JOIN PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" D on D."GmPseudo" = m."GmPseudo"
WHERE D."Snapshot" <= '2022-07-01'
QUALIFY row_number() OVER (PARTITION BY D."GmPseudo" ORDER BY D."Snapshot" DESC) = 1 -- this brings back the values from the most recent snapshot
UNION
SELECT
 	 m."GmPseudo",
	 D."Snapshot",
	 PatientWhoIsMatched AS "MainCohortMatchedGmPseudo", 
     'MATCHED' AS "Cohort",
     NULL AS "IndexDate",
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
    "DiagnosisOriginalMentionCategory1Desc" AS "CauseOfDeathCategoryDesc"
FROM MatchedCohort m
LEFT JOIN Death dth ON dth."GmPseudo" = m."GmPseudo"
LEFT OUTER JOIN PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" D on D."GmPseudo" = m."GmPseudo"
WHERE D."Snapshot" <= '2022-07-01'
QUALIFY row_number() OVER (PARTITION BY D."GmPseudo" ORDER BY D."Snapshot" DESC) = 1 -- this brings back the values from the most recent snapshot
;

-- Then we check to see if there are any new GmPseudo ids. We do this by making a temp table 
-- of all "new" GmPseudo ids from either the main column or the matched column. I.e. any GmPseudo ids that 
-- we've already got a unique id for for this study are excluded

DROP TABLE IF EXISTS "AllPseudos_SDE_Lighthouse_01_Newman";
CREATE TEMPORARY TABLE "AllPseudos_SDE_Lighthouse_01_Newman" AS
(
SELECT DISTINCT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."LH001-1_Patients_WITH_IDENTIFIER"
UNION 
SELECT DISTINCT "MainCohortMatchedGmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."LH001-1_Patients_WITH_IDENTIFIER"
)
EXCEPT
SELECT "GmPseudo" FROM "Patient_ID_Mapping_SDE_Lighthouse_01_Newman";

-- Find the highest currently assigned id. Ids are given incrementally, so now ones
-- need to start at +1 of the current highest
SET highestPatientId = (
    SELECT IFNULL(MAX("StudyPatientPseudoId"),0) FROM "Patient_ID_Mapping_SDE_Lighthouse_01_Newman"
);

-- Make a study specific hash for each new GmPseudo and insert it
-- into the patient lookup table
INSERT INTO "Patient_ID_Mapping_SDE_Lighthouse_01_Newman"
SELECT
    "GmPseudo", -- the GM SDE patient ids for patients in this cohort
    SHA2(CONCAT('SDE_Lighthouse_01_Newman', "GmPseudo")) AS "Hash", -- used to provide a random (study-specific) ordering for the patient ids we provide
    $highestPatientId + ROW_NUMBER() OVER (ORDER BY "Hash") -- the patient id that we provide to the analysts
FROM "AllPseudos_SDE_Lighthouse_01_Newman";

-- Finally, we select from the output table which includes the GmPseudos, in order
-- to populate the table for the end users where the GmPseudo fields are redacted via a function
-- created in the 0.code-sets.sql file
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH001-1_Patients";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH001-1_Patients" AS
SELECT SDE_REPOSITORY.SHARED_UTILITIES.gm_pseudo_hash_SDE_Lighthouse_01_Newman("GmPseudo") AS "PatientID",
	SDE_REPOSITORY.SHARED_UTILITIES.gm_pseudo_hash_SDE_Lighthouse_01_Newman("MainCohortMatchedGmPseudo") AS "MainCohortMatchedPatientID",
	* EXCLUDE ("GmPseudo", "MainCohortMatchedGmPseudo")
FROM SDE_REPOSITORY.SHARED_UTILITIES."LH001-1_Patients_WITH_IDENTIFIER";

-- create simpler version of the above table to be the cohort table that other files pull from

DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_01_Newman";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_01_Newman" AS 
SELECT 
	 m."GmPseudo",
	 D."FK_Patient_ID",
     NULL AS "MainCohortMatchedPatientId"
FROM MainCohort m
LEFT OUTER JOIN PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" D on D."GmPseudo" = m."GmPseudo"
UNION
SELECT
 	 m."GmPseudo",
	 D."FK_Patient_ID",
	 PatientWhoIsMatched AS "MainCohortMatchedPatientId", 
FROM MatchedCohort m
LEFT OUTER JOIN PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" D on D."GmPseudo" = m."GmPseudo";