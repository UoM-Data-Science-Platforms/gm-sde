USE SCHEMA SDE_REPOSITORY.SHARED_UTILITIES;

--┌────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 06 - pain diagnoses           │
--└────────────────────────────────────────────────────┘

set(StudyStartDate) = to_date('2017-01-01');
set(StudyEndDate)   = to_date('2023-12-31');

-- !!NOTE!! : many codes will feature in both the 'chronic pain' code set and the more specific code set, and therefore feature twice in the final table.
-- this is the case because we would miss some chronic pain codes if we only keep the specific code sets
-- PI will be informed about this

-- >>> Codesets required... Inserting the code set code
-- >>> Codesets extracted into 0.code-sets.sql
-- >>> Following code sets injected: chronic-pain v1/neck-problems v1/neuropathic-pain v1/chest-pain v1/post-herpetic-neuralgia v1/ankylosing-spondylitis v1
-- >>> Following code sets injected: psoriatic-arthritis v1/fibromyalgia v1/temporomandibular-pain v1/phantom-limb-pain v1/chronic-pancreatitis v1

-- find diagnosis codes that exist in the clusters tables

DROP TABLE IF EXISTS diagnosesClusters;
CREATE TEMPORARY TABLE diagnosesClusters AS
SELECT 
    ec."FK_Patient_ID"
    , TO_DATE(ec."EventDate") AS "DiagnosisDate"
    , ec."SCTID" AS "SnomedCode"
    , CASE WHEN (lower("Term") like '%neuropa%' AND lower("Term") like '%diab%')  THEN  'diabetic-neuropathy'
           WHEN ("Cluster_ID" = 'eFI2_PeripheralNeuropathy')                        THEN  'peripheral-neuropathy' 
		   WHEN ("Cluster_ID" = 'RARTH_COD') THEN 'rheumatoid-arthritis'
		   WHEN ("Cluster_ID" = 'eFI2_Osteoarthritis') THEN 'osteoarthritis'
		   WHEN	("Cluster_ID" = 'eFI2_BackPainTimeSensitive') THEN 'back-pain' -- in last 5 years
           ELSE 'other' END AS "Concept"
    , ec."Term" AS "Description"
FROM INTERMEDIATE.GP_RECORD."EventsClusters" ec
WHERE 
	(
	(lower("Term") like '%neuropa%' AND lower("Term") like '%diabet%')  OR -- diabetic neuropathy
	("Cluster_ID" = 'eFI2_PeripheralNeuropathy') OR -- peripheral neuropathy
	("Cluster_ID" = 'RARTH_COD') OR -- rheumatoid arthritis diagnosis codes
	("Cluster_ID" = 'eFI2_Osteoarthritis') OR -- osteoarthritis
	("Cluster_ID" = 'eFI2_BackPainTimeSensitive') -- back pain in last 5 years
	)
AND TO_DATE(ec."EventDate") BETWEEN $StudyStartDate and $StudyEndDate
AND ec."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_06_Chen");

-- find diagnoses codes that don't exist in a cluster

DROP TABLE IF EXISTS diagnoses;
CREATE TEMPORARY TABLE diagnoses AS
SELECT 
	e."FK_Patient_ID"
	, to_date("EventDate") AS "DiagnosisDate"
	, e."SCTID" AS "SnomedCode"
	, ac.concept
	, e."Term" AS "Description"
FROM  INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" e
LEFT JOIN SDE_REPOSITORY.SHARED_UTILITIES.AllCodesPermanent ac ON ac.CODE = e."SuppliedCode" 
WHERE "SuppliedCode" IN (SELECT code FROM SDE_REPOSITORY.SHARED_UTILITIES."Code_Sets_SDE_Lighthouse_06_Chen"
		WHERE concept IN ('chronic-pain', 'neck-problems','neuropathic-pain', 'chest-pain','post-herpetic-neuralgia', 'ankylosing-spondylitis',
				'psoriatic-arthritis', 'fibromyalgia', 'temporomandibular-pain', 'phantom-limb-pain', 'chronic-pancreatitis' ))
AND e."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_06_Chen")
AND TO_DATE("EventDate") BETWEEN $StudyStartDate AND $StudyEndDate;

-- final table combining diagnoses from clusters and those from research code set tables

DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."5_PainDiagnoses";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."5_PainDiagnoses" AS
SELECT * from diagnoses
UNION ALL
SELECT * from diagnosesClusters