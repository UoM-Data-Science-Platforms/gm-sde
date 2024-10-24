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
FROM {{cohort-table}} cohort
LEFT OUTER JOIN INTERMEDIATE.GP_RECORD."Combined_EventsMedications_Clusters_SecondaryUses" ec ON ec."FK_Patient_ID" = cohort."FK_Patient_ID"
WHERE 
	("Cluster_ID" IN())
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

{{create-output-table::"LH009-3_Diagnoses"}}
SELECT 
	"GmPseudo", -- NEEDS PSEUDONYMISING 
	"DiagnosisDate", 
	"SnomedCode", 
	"Description", 
	SUM(CASE WHEN "Concept" = 'chronic-pain' THEN 1 ELSE 0 END) AS "ChronicPain",
    SUM(CASE WHEN "Concept" = 'diabetic-neuropathy' THEN 1 ELSE 0 END) AS "DiabeticNeuropathy",
FROM diagnoses
GROUP BY "GmPseudo", "DiagnosisDate", "SnomedCode", "Description";