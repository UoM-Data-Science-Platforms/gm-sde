USE SCHEMA SDE_REPOSITORY.SHARED_UTILITIES;

--┌────────────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 09 - diagnoses and symptoms           │
--└────────────────────────────────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK ---------------
-----------------------------------------------------

set(StudyStartDate) = to_date('2020-01-01');
set(StudyEndDate)   = to_date('2024-10-31');

-- >>> Codesets required... Inserting the code set code
-- >>> Codesets extracted into 0.code-sets.sql
-- >>> Following code sets injected: cognitive-impairment v1/hot-flash v1/irregular-periods v1/musculoskeletal-pain v1
-- >>> Following code sets injected: spondyloarthropathy v1

-- TO DO : find out what neurological conditions the PI wants, as well as any skin 
-- conditions other than psoriasis.

--- create a table combining diagnoses from SDE clusters with diagnoses from GMCR code sets

-- find diagnosis codes that exist in the clusters tables
DROP TABLE IF EXISTS diagnoses;
CREATE TEMPORARY TABLE diagnoses AS
SELECT 
    cohort."GmPseudo"
    , TO_DATE(ec."Date") AS "Date"
    , ec."SCTID" AS "SnomedCode"
    , CASE --diagnoses
		   WHEN ("Cluster_ID" = 'SLUPUS_COD')   					THEN 'systemic-lupus-erythematosus' 
		   WHEN ("Cluster_ID" = 'RARTH_COD')    					THEN 'rheumatoid-arthritis' 
		   WHEN ("Cluster_ID" = 'eFI2_InflammatoryBowelDisease')    THEN 'inflammatory-bowel-disease' 
		   WHEN ("Cluster_ID" = 'PSORIASIS_COD')    				THEN 'psoriasis' 
		   WHEN ("Cluster_ID" = 'AST_COD')    						THEN 'asthma' 
		   WHEN ("Cluster_ID" = 'C19PREG_COD')    					THEN 'pregnancy' 
		   WHEN ("Cluster_ID" = 'eFI2_Anxiety')    					THEN 'anxiety' 
		   WHEN ("Cluster_ID" = 'eFI2_InflammatoryBowelDisease')    THEN 'inflammatory-bowel-disease' 
		   -- symptoms
		   WHEN "SCTID" = '42984000' 								THEN 'night-sweats'
		   WHEN "SCTID" = '31908003' 								THEN 'vaginal-dryness'
		   WHEN "SCTID" = '339341000000102'							THEN 'contraceptive-implant-removal'
		   WHEN "SCTID" IN ('169553002', '698972004', '301806003',
		   					 '755621000000101', '384201000000103') 	THEN 'contraceptive-implant-fitting'
           ELSE 'other' END AS "Concept"
    , ec."Term" AS "Description"
FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_09_Thompson" cohort
LEFT OUTER JOIN INTERMEDIATE.GP_RECORD."Combined_EventsMedications_Clusters_SecondaryUses" ec ON ec."FK_Patient_ID" = cohort."FK_Patient_ID"
WHERE (
		"Cluster_ID" IN ('SLUPUS_COD', 'RARTH_COD', 'eFI2_InflammatoryBowelDisease', 'PSORIASIS_COD',
					  'AST_COD', 'C19PREG_COD', 'eFI2_Anxiety','eFI2_InflammatoryBowelDisease')
		OR "SCTID" IN ('42984000','31908003','339341000000102','169553002', 
					   '698972004', '301806003','755621000000101', '384201000000103') 
	  )
AND TO_DATE(ec."Date") BETWEEN $StudyStartDate and $StudyEndDate
AND ec."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_09_Thompson")
UNION
-- find diagnoses codes that don't exist in a cluster
SELECT 
	cohort."GmPseudo"
	, to_date("EventDate") AS "Date"
	, events."SCTID" AS "SnomedCode"
	, cs.concept AS "Concept"
	, events."Term" AS "Description"
FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_09_Thompson" cohort
LEFT OUTER JOIN INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" events ON events."FK_Patient_ID" = cohort."FK_Patient_ID"
LEFT OUTER JOIN SDE_REPOSITORY.SHARED_UTILITIES."Code_Sets_SDE_Lighthouse_09_Thompson" cs ON cs.code = events."SuppliedCode" 
WHERE cs.concept IN ('spondyloarthropathy', 'cognitive-impairment', 'hot-flash', 'irregular-periods', 
						'musculoskeletal-pain')
	AND events."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_09_Thompson")
	AND TO_DATE("EventDate") BETWEEN $StudyStartDate AND $StudyEndDate;


-- final table
-- some codes appear in multiple code sets (e.g. back pain appearing in the more speciifc 'back-pain' and the more broad 'chronic-pain'), 
-- so we're using sum case when statements to reduce the number of rows but indicate which code sets each code belongs to.


-- ... processing [[create-output-table::"LH009-3_Diagnoses"]] ... 
-- ... Need to create an output table called "LH009-3_Diagnoses" and replace 
-- ... the GmPseudo column with a study-specific random patient id.

-- First we create a table in an area only visible to the RDEs which contains
-- the GmPseudos. THESE CANNOT BE RELEASED TO END USERS.
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH009-3_Diagnoses_WITH_PSEUDO_IDS";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH009-3_Diagnoses_WITH_PSEUDO_IDS" AS
SELECT * from diagnoses;

-- Then we check to see if there are any new GmPseudo ids. We do this by making a temp table 
-- of all "new" GmPseudo ids. I.e. any GmPseudo ids that we've already got a unique id for
-- for this study are excluded
DROP TABLE IF EXISTS "AllPseudos_SDE_Lighthouse_09_Thompson";
CREATE TEMPORARY TABLE "AllPseudos_SDE_Lighthouse_09_Thompson" AS
SELECT DISTINCT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."LH009-3_Diagnoses_WITH_PSEUDO_IDS"
EXCEPT
SELECT "GmPseudo" FROM "Patient_ID_Mapping_SDE_Lighthouse_09_Thompson";

-- Find the highest currently assigned id. Ids are given incrementally, so now ones
-- need to start at +1 of the current highest
SET highestPatientId = (
    SELECT IFNULL(MAX("StudyPatientPseudoId"),0) FROM "Patient_ID_Mapping_SDE_Lighthouse_09_Thompson"
);

-- Make a study specific hash for each new GmPseudo and insert it
-- into the patient lookup table
INSERT INTO "Patient_ID_Mapping_SDE_Lighthouse_09_Thompson"
SELECT
    "GmPseudo", -- the GM SDE patient ids for patients in this cohort
    SHA2(CONCAT('SDE_Lighthouse_09_Thompson', "GmPseudo")) AS "Hash", -- used to provide a random (study-specific) ordering for the patient ids we provide
    $highestPatientId + ROW_NUMBER() OVER (ORDER BY "Hash") -- the patient id that we provide to the analysts
FROM "AllPseudos_SDE_Lighthouse_09_Thompson";

-- Finally, we select from the output table which includes the GmPseudos, in order
-- to populate the table for the end users where the GmPseudo fields are redacted via a function
-- created in the 0.code-sets.sql file
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH009-3_Diagnoses";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH009-3_Diagnoses" AS
SELECT SDE_REPOSITORY.SHARED_UTILITIES.gm_pseudo_hash_SDE_Lighthouse_09_Thompson("GmPseudo") AS "PatientID",
	* EXCLUDE "GmPseudo"
FROM SDE_REPOSITORY.SHARED_UTILITIES."LH009-3_Diagnoses_WITH_PSEUDO_IDS";