--┌────────────────────────────────────┐
--│ LH001 Patient file                 │
--└────────────────────────────────────┘

-- COHORT: Any patient with a pharmacogenetic test, or a matched control.

set(StudyStartDate) = to_date('2022-07-01');
set(StudyEndDate)   = to_date('2024-10-31');


-- The cohort matching for this project currently uses: Sex, YearOfBirth, Ethnicity, and only involves patients 
-- that have had a new prescription of SSRI, TCA, PPI or Statin)

--> EXECUTE query-get-possible-patients.sql

DROP TABLE IF EXISTS PatientsToInclude;
CREATE TEMPORARY TABLE PatientsToInclude AS
SELECT 
FROM GPRegPatients 
WHERE ("DeathDate" IS NULL OR "DeathDate" > $StudyStartDate) -- alive on study start date
	AND 
	("leftGMDate" IS NULL OR "leftGMDate" > $StudyEndDate) -- don't include patients who left GM mid study (as we lose their data)
	AND DATEDIFF(YEAR, "DateOfBirth", $StudyStartDate) >= 18; -- OVER 18s ONLY

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
WHERE p."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM PatientsToInclude)
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

--> EXECUTE query-cohort-matching-yob-sex-ethnicity.sql yob-flex:2 num-matches:5

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

{{create-output-table-matched-cohort::"LH001-1_Patients"}}
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

-- create simpler version of the above table to be the cohort table that other files pull from

DROP TABLE IF EXISTS {{cohort-table}};
CREATE TABLE {{cohort-table}} AS 
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