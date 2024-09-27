USE SCHEMA SDE_REPOSITORY.SHARED_UTILITIES;

--┌────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 06 - pain diagnoses           │
--└────────────────────────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK ---------------
-- Richard Williams	2024-08-30	Review in progress --
--   Suggest diabetic neuropathy has separate      --
--   code set                                      --
-----------------------------------------------------

set(StudyStartDate) = to_date('2017-01-01');
set(StudyEndDate)   = to_date('2023-12-31');

-- >>> Codesets required... Inserting the code set code
-- >>> Codesets extracted into 0.code-sets.sql
-- >>> Following code sets injected: chronic-pain v1/neck-problems v1/neuropathic-pain v1/chest-pain v1/post-herpetic-neuralgia v1/ankylosing-spondylitis v1
-- >>> Following code sets injected: psoriatic-arthritis v1/fibromyalgia v1/temporomandibular-pain v1/phantom-limb-pain v1/chronic-pancreatitis v1

--- create a table combining diagnoses from SDE clusters with diagnoses from GMCR code sets

-- find diagnosis codes that exist in the clusters tables
DROP TABLE IF EXISTS diagnoses;
CREATE TEMPORARY TABLE diagnoses AS
SELECT 
    cohort."GmPseudo"
    , TO_DATE(ec."EventDate") AS "DiagnosisDate"
    , ec."SCTID" AS "SnomedCode"
    , CASE WHEN ("Cluster_ID" = 'eFI2_PeripheralNeuropathy')    THEN 'peripheral-neuropathy' 
		   WHEN ("Cluster_ID" = 'RARTH_COD') 					THEN 'rheumatoid-arthritis'
		   WHEN ("Cluster_ID" = 'eFI2_Osteoarthritis') 			THEN 'osteoarthritis'
		   WHEN	("Cluster_ID" = 'eFI2_BackPainTimeSensitive') 	THEN 'back-pain' -- in last 5 years
           ELSE 'other' END AS "Concept"
    , ec."Term" AS "Description"
FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_06_Chen" cohort
LEFT OUTER JOIN INTERMEDIATE.GP_RECORD."EventsClusters" ec ON ec."FK_Patient_ID" = cohort."FK_Patient_ID"
WHERE 
	(
	("Cluster_ID" = 'eFI2_PeripheralNeuropathy') OR -- peripheral neuropathy
	("Cluster_ID" = 'RARTH_COD') OR -- rheumatoid arthritis diagnosis codes
	("Cluster_ID" = 'eFI2_Osteoarthritis') OR -- osteoarthritis
	("Cluster_ID" = 'eFI2_BackPainTimeSensitive') -- back pain in last 5 years
	)
AND TO_DATE(ec."EventDate") BETWEEN $StudyStartDate and $StudyEndDate
AND ec."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_06_Chen")
UNION
-- find diagnoses codes that don't exist in a cluster
SELECT 
	cohort."GmPseudo"
	, to_date("EventDate") AS "DiagnosisDate"
	, events."SCTID" AS "SnomedCode"
	, cs.concept AS "Concept"
	, events."Term" AS "Description"
FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_06_Chen" cohort
LEFT OUTER JOIN INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" events ON events."FK_Patient_ID" = cohort."FK_Patient_ID"
LEFT OUTER JOIN SDE_REPOSITORY.SHARED_UTILITIES."Code_Sets_SDE_Lighthouse_06_Chen" cs ON cs.code = events."SuppliedCode" 
WHERE cs.concept IN ('diabetic-neuropathy','chronic-pain', 'neck-problems','neuropathic-pain', 'chest-pain','post-herpetic-neuralgia', 'ankylosing-spondylitis',
				'psoriatic-arthritis', 'fibromyalgia', 'temporomandibular-pain', 'phantom-limb-pain', 'chronic-pancreatitis' )
	AND events."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_06_Chen")
	AND TO_DATE("EventDate") BETWEEN $StudyStartDate AND $StudyEndDate;


-- final table
-- some codes appear in multiple code sets (e.g. back pain appearing in the more speciifc 'back-pain' and the more broad 'chronic-pain'), 
-- so we're using sum case when statements to reduce the number of rows but indicate which code sets each code belongs to.


-- ... processing [[create-output-table::"5_PainDiagnoses"]] ... 
-- ... Need to create an output table called "5_PainDiagnoses" and replace 
-- ... the GmPseudo column with a study-specific random patient id.

-- First we create a table in an area only visible to the RDEs which contains
-- the GmPseudos. THESE CANNOT BE RELEASED TO END USERS.
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."5_PainDiagnoses_WITH_PSEUDO_IDS";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."5_PainDiagnoses_WITH_PSEUDO_IDS" AS
SELECT 
	"GmPseudo", -- NEEDS PSEUDONYMISING 
	"DiagnosisDate", 
	"SnomedCode", 
	"Description", 
	SUM(CASE WHEN "Concept" = 'chronic-pain' THEN 1 ELSE 0 END) AS "ChronicPain",
    SUM(CASE WHEN "Concept" = 'diabetic-neuropathy' THEN 1 ELSE 0 END) AS "DiabeticNeuropathy",
    SUM(CASE WHEN "Concept" = 'peripheral-neuropathy' THEN 1 ELSE 0 END) AS "PeripheralNeuropathy",
    SUM(CASE WHEN "Concept" = 'rheumatoid-arthritis' THEN 1 ELSE 0 END) AS "RheumatoidArthritis",
    SUM(CASE WHEN "Concept" = 'osteoarthritis' THEN 1 ELSE 0 END) AS "Osteoarthritis",
    SUM(CASE WHEN "Concept" = 'back-pain' THEN 1 ELSE 0 END) AS "BackPain",
    SUM(CASE WHEN "Concept" = 'neck-problems' THEN 1 ELSE 0 END) AS "NeckProblems",
    SUM(CASE WHEN "Concept" = 'neuropathic-pain' THEN 1 ELSE 0 END) AS "NeuropathicPain",
    SUM(CASE WHEN "Concept" = 'chest-pain' THEN 1 ELSE 0 END) AS "ChestPain",
    SUM(CASE WHEN "Concept" = 'post-herpetic-neuralgia' THEN 1 ELSE 0 END) AS "PostHerpeticNeuralgia",
    SUM(CASE WHEN "Concept" = 'ankylosing-spondylitis' THEN 1 ELSE 0 END) AS "AnkylosingSpondylitis",
    SUM(CASE WHEN "Concept" = 'psoriatic-arthritis' THEN 1 ELSE 0 END) AS "PsoriaticArthritis",
    SUM(CASE WHEN "Concept" = 'fibromyalgia' THEN 1 ELSE 0 END) AS "Fibromyalgia",
    SUM(CASE WHEN "Concept" = 'temporomandibular-pain' THEN 1 ELSE 0 END) AS "TemporomandibularPain",
    SUM(CASE WHEN "Concept" = 'phantom-limb-pain' THEN 1 ELSE 0 END) AS "PhantomLimbPain",
    SUM(CASE WHEN "Concept" = 'chronic-pancreatitis' THEN 1 ELSE 0 END) AS "ChronicPancreatitis"
FROM diagnoses
GROUP BY "GmPseudo", "DiagnosisDate", "SnomedCode", "Description";

-- Then we check to see if there are any new GmPseudo ids. We do this by making a temp table 
-- of all "new" GmPseudo ids. I.e. any GmPseudo ids that we've already got a unique id for
-- for this study are excluded
DROP TABLE IF EXISTS "AllPseudos_SDE_Lighthouse_06_Chen";
CREATE TEMPORARY TABLE "AllPseudos_SDE_Lighthouse_06_Chen" AS
SELECT DISTINCT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."5_PainDiagnoses_WITH_PSEUDO_IDS"
EXCEPT
SELECT "GmPseudo" FROM "Patient_ID_Mapping_SDE_Lighthouse_06_Chen";

-- Find the highest currently assigned id. Ids are given incrementally, so now ones
-- need to start at +1 of the current highest
SET highestPatientId = (
    SELECT IFNULL(MAX("StudyPatientPseudoId"),0) FROM "Patient_ID_Mapping_SDE_Lighthouse_06_Chen"
);

-- Make a study specific hash for each new GmPseudo and insert it
-- into the patient lookup table
INSERT INTO "Patient_ID_Mapping_SDE_Lighthouse_06_Chen"
SELECT
    "GmPseudo", -- the GM SDE patient ids for patients in this cohort
    SHA2(CONCAT('SDE_Lighthouse_06_Chen', "GmPseudo")) AS "Hash", -- used to provide a random (study-specific) ordering for the patient ids we provide
    $highestPatientId + ROW_NUMBER() OVER (ORDER BY "Hash") -- the patient id that we provide to the analysts
FROM "AllPseudos_SDE_Lighthouse_06_Chen";

-- Finally, we select from the output table which includes the GmPseudos, in order
-- to populate the table for the end users where the GmPseudo fields are redacted via a function
-- created in the 0.code-sets.sql file
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."5_PainDiagnoses";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."5_PainDiagnoses" AS
SELECT SDE_REPOSITORY.SHARED_UTILITIES.gm_pseudo_hash_SDE_Lighthouse_06_Chen("GmPseudo") AS "PatientID",
	* EXCLUDE "GmPseudo"
FROM SDE_REPOSITORY.SHARED_UTILITIES."5_PainDiagnoses_WITH_PSEUDO_IDS";