--┌────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 06 - pain diagnoses           │
--└────────────────────────────────────────────────────┘

--> EXECUTE query-build-lh006-cohort.sql

-- !!NOTE!! : many codes will feature in both the 'chronic pain' code set and the more specific code set, and therefore feature twice in the final table.
-- this is the case because we would miss some chronic pain codes if we only keep the specific code sets
-- PI will be informed about this

-- find diagnosis codes that exist in the clusters tables

DROP TABLE IF EXISTS diagnosesClusters;
CREATE TEMPORARY TABLE diagnosesClusters AS
SELECT 
    ec."FK_Patient_ID"
    , TO_DATE(ec."EventDate") AS "DiagnosisDate"
    , ec."SCTID" AS "SnomedCode"
    , CASE WHEN ((lower("Term") like '%neuropa%' AND lower("Term") like '%diab%'))  THEN  'diabetic-neuropathy'
           WHEN ("Cluster_ID" = 'eFI2_PeripheralNeuropathy')                        THEN  'peripheral-neuropathy' 
		   WHEN ("Cluster_ID" = 'RARTH_COD') THEN 'rheumatoid-arthritis'
		   WHEN ("Cluster_ID" = 'eFI2_Osteoarthritis') THEN 'osteoarthritis'
		   WHEN	("Cluster_ID" = 'eFI2_BackPainTimeSensitive') THEN 'back-pain' -- in last 5 years
           ELSE 'other' END AS "Concept"
    , ec."Term" AS "Description"
FROM INTERMEDIATE.GP_RECORD."EventsClusters" ec
WHERE 
	(
	((lower("Term") like '%neuropa%' AND lower("Term") like '%diab%'))  -- diabetic neuropathy
	("Cluster_ID" = 'eFI2_PeripheralNeuropathy') OR -- peripheral neuropathy
	("Cluster_ID" = 'RARTH_COD') OR -- rheumatoid arthritis diagnosis codes
	("Cluster_ID" = 'eFI2_Osteoarthritis') OR -- osteoarthritis
	("Cluster_ID" = 'eFI2_BackPainTimeSensitive') -- back pain in last 5 years
	)
AND TO_DATE(ec."EventDate") BETWEEN $StudyStartDate and $StudyEndDate;
    AND ec."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM Cohort);

-- find diagnoses codes that don't exist in a cluster

DROP TABLE IF EXISTS diagnoses;
CREATE TEMPORARY TABLE diagnoses AS
SELECT 
	e."FK_Patient_ID"
	, to_date("EventDate") AS "DiagnosisDate"
	, e."SCTID" AS "SnomedCode"
	, case when co.concept IS NOT NULL THEN co.concept ELSE sn.concept END AS "Concept"
	, e."Term" AS "Description"
FROM  INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" e
LEFT JOIN SDE_REPOSITORY.SHARED_UTILITIES.VERSIONEDCODESETS_PERMANENT co ON co.FK_Reference_Coding_ID = e."FK_Reference_Coding_ID"
LEFT JOIN SDE_REPOSITORY.SHARED_UTILITIES.VERSIONEDSNOMEDSETS_PERMANENT sn ON sn.FK_Reference_SnomedCT_ID = e."FK_Reference_SnomedCT_ID"
WHERE ( 
  "FK_Reference_Coding_ID" IN (SELECT FK_Reference_Coding_ID FROM SDE_REPOSITORY.SHARED_UTILITIES.VERSIONEDCODESETS_PERMANENT WHERE Concept IN 
  ('chronic-pain', 'neck-problems', 'neuropathic-pain', 'chest-pain', 'post-herpetic-neuralgia',
   'ankylosing-spondylitis', 'psoriatic-arthritis', 'fibromyalgia', 'temporomandibular-pain', 'phantom-limb-pain', 'chronic-pancreatitis') AND Version = 1) 
    OR
  "FK_Reference_SnomedCT_ID" IN (SELECT FK_Reference_SnomedCT_ID FROM SDE_REPOSITORY.SHARED_UTILITIES.VERSIONEDSNOMEDSETS_PERMANENT WHERE Concept IN   
  ('chronic-pain', 'neck-problems', 'neuropathic-pain', 'chest-pain', 'post-herpetic-neuralgia',
    'ankylosing-spondylitis', 'psoriatic-arthritis', 'fibromyalgia', 'temporomandibular-pain', 'phantom-limb-pain', 'chronic-pancreatitis') AND Version = 1)
	)
AND e."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM Cohort)
AND TO_DATE("EventDate") BETWEEN $StudyStartDate AND $StudyEndDate;

-- final table combining diagnoses from clusters and those from research code set tables

SELECT * from diagnoses
UNION ALL
SELECT * from DIAGNOSESCLUSTERS