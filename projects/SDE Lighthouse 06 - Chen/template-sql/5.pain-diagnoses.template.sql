--┌────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 06 - pain diagnoses           │
--└────────────────────────────────────────────────────┘

set(StudyStartDate) = to_date('2017-01-01');
set(StudyEndDate)   = to_date('2023-12-31');

-- !!NOTE!! : many codes will feature in both the 'chronic pain' code set and the more specific code set, and therefore feature twice in the final table.
-- this is the case because we would miss some chronic pain codes if we only keep the specific code sets
-- PI will be informed about this

--> CODESET chronic-pain:1 neck-problems:1 neuropathic-pain:1 chest-pain:1 post-herpetic-neuralgia:1 ankylosing-spondylitis:1
--> CODESET psoriatic-arthritis:1 fibromyalgia:1 temporomandibular-pain:1 phantom-limb-pain:1 chronic-pancreatitis:1

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
AND ec."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM {{cohort-table}});

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
WHERE "SuppliedCode" IN (SELECT code FROM {{code-set-table}}
		WHERE concept IN ('chronic-pain', 'neck-problems','neuropathic-pain', 'chest-pain','post-herpetic-neuralgia', 'ankylosing-spondylitis',
				'psoriatic-arthritis', 'fibromyalgia', 'temporomandibular-pain', 'phantom-limb-pain', 'chronic-pancreatitis' ))
AND e."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM {{cohort-table}})
AND TO_DATE("EventDate") BETWEEN $StudyStartDate AND $StudyEndDate;

-- final table combining diagnoses from clusters and those from research code set tables

DROP TABLE IF EXISTS {{project-schema}}."5_PainDiagnoses";
CREATE TABLE {{project-schema}}."5_PainDiagnoses" AS
SELECT * from diagnoses
UNION ALL
SELECT * from diagnosesClusters