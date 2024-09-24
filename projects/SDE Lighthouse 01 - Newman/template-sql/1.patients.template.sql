--┌────────────────────────────────────┐
--│ LH001 Patient file                 │
--└────────────────────────────────────┘

-- COHORT: Any patient with a pharmacogenetic test, or a matched control.

set(StudyStartDate) = to_date('2023-06-01');
set(StudyEndDate)   = to_date('2024-06-30');

--> EXECUTE query-get-possible-patientsSDE.sql

-- table of pharmacogenetic test patients

------


--- table of new prescriptions to use for potential matches

DROP TABLE IF EXISTS prescriptions;
CREATE TEMPORARY TABLE prescriptions AS
SELECT 
    ec."FK_Patient_ID"
	, c."GmPseudo"
    , TO_DATE(ec."MedicationDate") AS "MedicationDate"
    , ec."SCTID" AS "SnomedCode"
	, ec."Quantity"
    , ec."Dosage_GP_Medications" AS "Dosage" 
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
FROM INTERMEDIATE.GP_RECORD."MedicationsClusters" ec
INNER JOIN {{cohort-table}} c ON c."FK_Patient_ID" = ec."FK_Patient_ID"
WHERE 
	-- Statins
	("Field_ID" = 'Statin') OR 
	-- SSRIs
	("Field_ID" = 'ANTIDEPDRUG_COD' AND (LOWER("MedicationDescription") LIKE '%citalopram%' OR LOWER("MedicationDescription") LIKE '%escitalopram%' OR LOWER("MedicationDescription") LIKE '%fluvoxamine%' OR LOWER("MedicationDescription") LIKE '%paroxetine%' OR LOWER("MedicationDescription") LIKE '%sertraline%' OR LOWER("MedicationDescription") LIKE '%venlafaxine%')) OR
	-- tricyclic antidepressants
	("Field_ID" = 'ANTIDEPDRUG_COD' AND (LOWER("MedicationDescription") LIKE '%amitriptyline%' OR LOWER("MedicationDescription") LIKE '%clomipramine%' OR LOWER("MedicationDescription") LIKE '%doxepin%' OR LOWER("MedicationDescription") LIKE '%imipramine%' OR LOWER("MedicationDescription") LIKE '%nortriptyline%' OR LOWER("MedicationDescription") LIKE '%trimipramine%')) OR
	-- proton pump inhibitors
	( "Field_ID" = 'ULCERHEALDRUG_COD' AND (LOWER("MedicationDescription") LIKE '%esomeprazole%' OR LOWER("MedicationDescription") LIKE '%lansoprazole%' OR LOWER("MedicationDescription") LIKE '%omeprazole%' OR LOWER("MedicationDescription") LIKE '%pantoprazole%' OR LOWER("MedicationDescription") LIKE '%rabeprazole%' )) OR 

AND TO_DATE(ec."MedicationDate") BETWEEN $StartDate and $EndDate;



-- create main cohort
-- use the latest snapshot before the start of the PROGRESS study

DROP TABLE IF EXISTS MainCohort;
CREATE TEMPORARY TABLE MainCohort AS
SELECT DISTINCT
	 "FK_Patient_ID",
	 "GmPseudo",
     "Sex" as Sex,
     YEAR("DateOfBirth") AS YearOfBirth,
	 "EthnicityLatest_Category" AS EthnicCategory,
	 --IndexDate : DATE OF STUDY START : IPTIP OR PROGRESS -- SET AS PROGRESS FOR NOW TO TEST
	 '2022-07-01' AS IndexDate,
	 "Snapshot"
FROM PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" p
WHERE "FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM AlivePatientsAtStart)
 	--AND "FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM PharmacogeneticTable)
    AND "Snapshot" <= '2022-07-01'
QUALIFY row_number() OVER (PARTITION BY p."GmPseudo" ORDER BY "Snapshot" DESC) = 1; -- this brings back the values from the most recent snapshot

-- create table of potential patients to match to the main cohort

DROP TABLE IF EXISTS PotentialMatches;
CREATE TEMPORARY TABLE PotentialMatches AS
SELECT DISTINCT "GmPseudo", 
		"Sex" as Sex,
		YEAR("DateOfBirth") AS YearOfBirth,
		"EthnicityLatest_Category" AS EthnicCategory
FROM PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" p
WHERE 
"GmPseudo" NOT IN (SELECT "GmPseudo" FROM MainCohort)
	AND "Snapshot" <= '2022-07-01'
QUALIFY row_number() OVER (PARTITION BY p."GmPseudo" ORDER BY "Snapshot" DESC) = 1; -- this brings back the values from the most recent snapshot


-- TO DO: 
 -- LIMIT THE POTENTIAL MATCHES TO PATIENTS THAT HAD A NEW PRESCRIPTION OF SSRI,TCA,PPI OR STATIN)


-- run matching script with parameters filled in

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

{{create-output-table::"1_Patients"}}
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
	"Frailty", -- 92% missingness
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
LEFT OUTER JOIN PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" D on D."GmPseudo" = m."GmPseudo"
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
	"Frailty", -- 92% missingness
	 dth.DeathDate AS "DeathDate",
	"DiagnosisOriginalMentionCode" AS "CauseOfDeathCode",
	"DiagnosisOriginalMentionDesc" AS "CauseOfDeathDesc",
	"DiagnosisOriginalMentionChapterCode" AS "CauseOfDeathChapterCode",
    "DiagnosisOriginalMentionChapterDesc" AS "CauseOfDeathChapterDesc",
    "DiagnosisOriginalMentionCategory1Code" AS "CauseOfDeathCategoryCode",
    "DiagnosisOriginalMentionCategory1Desc" AS "CauseOfDeathCategoryDesc",
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
     NULL AS "MainCohortMatchedPatientId"
FROM MainCohort m
UNION
SELECT
 	 m."GmPseudo",
	 PatientWhoIsMatched AS "MainCohortMatchedPatientId", 
FROM MatchedCohort m;