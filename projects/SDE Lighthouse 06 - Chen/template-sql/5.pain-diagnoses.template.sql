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

--> CODESET chronic-pain:1 neck-problems:1 neuropathic-pain:1 chest-pain:1 post-herpetic-neuralgia:1 ankylosing-spondylitis:1
--> CODESET psoriatic-arthritis:1 fibromyalgia:1 temporomandibular-pain:1 phantom-limb-pain:1 chronic-pancreatitis:1

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
FROM {{cohort-table}} cohort
LEFT OUTER JOIN INTERMEDIATE.GP_RECORD."EventsClusters" ec ON ec."FK_Patient_ID" = cohort."FK_Patient_ID"
WHERE 
	(
	("Cluster_ID" = 'eFI2_PeripheralNeuropathy') OR -- peripheral neuropathy
	("Cluster_ID" = 'RARTH_COD') OR -- rheumatoid arthritis diagnosis codes
	("Cluster_ID" = 'eFI2_Osteoarthritis') OR -- osteoarthritis
	("Cluster_ID" = 'eFI2_BackPainTimeSensitive') -- back pain in last 5 years
	)
AND TO_DATE(ec."EventDate") BETWEEN $StudyStartDate and $StudyEndDate
AND ec."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM {{cohort-table}})
UNION
-- find diagnoses codes that don't exist in a cluster
SELECT 
	cohort."GmPseudo"
	, to_date("EventDate") AS "DiagnosisDate"
	, events."SCTID" AS "SnomedCode"
	, cs.concept AS "Concept"
	, events."Term" AS "Description"
FROM {{cohort-table}} cohort
LEFT OUTER JOIN INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" events ON events."FK_Patient_ID" = cohort."FK_Patient_ID"
LEFT OUTER JOIN {{code-set-table}} cs ON cs.code = events."SuppliedCode" 
WHERE cs.concept IN ('diabetic-neuropathy','chronic-pain', 'neck-problems','neuropathic-pain', 'chest-pain','post-herpetic-neuralgia', 'ankylosing-spondylitis',
				'psoriatic-arthritis', 'fibromyalgia', 'temporomandibular-pain', 'phantom-limb-pain', 'chronic-pancreatitis' )
	AND events."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM {{cohort-table}})
	AND TO_DATE("EventDate") BETWEEN $StudyStartDate AND $StudyEndDate;


-- final table
-- some codes appear in multiple code sets (e.g. back pain appearing in the more speciifc 'back-pain' and the more broad 'chronic-pain'), 
-- so we're using sum case when statements to reduce the number of rows but indicate which code sets each code belongs to.

{{create-output-table::"5_PainDiagnoses"}}
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