--┌────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 06 - pain diagnoses           │
--└────────────────────────────────────────────────────┘

set(StartDate) = to_date('2017-01-01');
set(EndDate)   = to_date('2023-12-31');

--> EXECUTE query-build-lh006-cohort.sql

-- !!NOTE!! : many codes will feature in both the 'chronic pain' code set and the more specific code set, and therefore feature twice in the final table.

-- find diagnoses for chronic pain conditions

-- find diagnosis codes that exist in the clusters tables

DROP TABLE IF EXISTS diagnosesClusters;
CREATE TEMPORARY TABLE diagnosesClusters AS
SELECT 
    ec."FK_Patient_ID"
    , TO_DATE(ec."EventDate") AS "MedicationDate"
    , ec."SCTID" AS "SnomedCode"
    , CASE WHEN  ((lower("Term") like '%neuropa%' AND lower("Term") like '%diab%'))  THEN  'diabetic-neuropathy'
           ELSE 'other' END AS "CodeSet"
    , ec."Term" AS "Description"
FROM INTERMEDIATE.GP_RECORD."EventsClusters" ec
WHERE 
	(
	((lower("Term") like '%neuropa%' AND lower("Term") like '%diab%'))  -- diabetic neuropathy
	)
AND TO_DATE(ec."EventDate") BETWEEN $StudyStartDate and $StudyEndDate;
    AND ec."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM Cohort);


DROP TABLE IF EXISTS diagnoses;
CREATE TEMPORARY TABLE diagnoses AS
SELECT 
	e."FK_Patient_ID"
	, to_date("EventDate") AS "EventDate"
	, case when co.concept IS NOT NULL THEN co.concept ELSE sn.concept END AS concept
FROM  INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" e
LEFT JOIN SDE_REPOSITORY.SHARED_UTILITIES.VERSIONEDCODESETS_PERMANENT co ON co.FK_Reference_Coding_ID = e."FK_Reference_Coding_ID"
LEFT JOIN SDE_REPOSITORY.SHARED_UTILITIES.VERSIONEDSNOMEDSETS_PERMANENT sn ON sn.FK_Reference_SnomedCT_ID = e."FK_Reference_SnomedCT_ID"
WHERE ( 
  "FK_Reference_Coding_ID" IN (SELECT FK_Reference_Coding_ID FROM SDE_REPOSITORY.SHARED_UTILITIES.VERSIONEDCODESETS_PERMANENT WHERE Concept IN 
  ('chronic-pain', 'rheumatoid-arthritis', 'osteoarthritis', 'back-problems', 'neck-problems', 'neuropathic-pain', 
   'chest-pain', 'post-herpetic-neuralgia', 'ankylosing-spondylitis', 'psoriatic-arthritis', 'fibromyalgia', 'temporomandibular-pain',
   'phantom-limb-pain') AND Version = 1) 
    OR
  "FK_Reference_SnomedCT_ID" IN (SELECT FK_Reference_SnomedCT_ID FROM SDE_REPOSITORY.SHARED_UTILITIES.VERSIONEDSNOMEDSETS_PERMANENT WHERE Concept IN   
  ('chronic-pain', 'rheumatoid-arthritis', 'osteoarthritis', 'back-problems', 'neck-problems', 'neuropathic-pain', 
   'chest-pain', 'post-herpetic-neuralgia', 'ankylosing-spondylitis', 'psoriatic-arthritis', 'fibromyalgia', 'temporomandibular-pain',
   'phantom-limb-pain') AND Version = 1)
	)
AND e."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM Cohort) --only look in patients with chronic pain
AND TO_DATE("EventDate") BETWEEN $StudyStartDate AND $StudyEndDate;
