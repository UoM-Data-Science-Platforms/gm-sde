--┌────────────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 09 - diagnoses and symptoms           │
--└────────────────────────────────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK ---------------
-----------------------------------------------------

set(StudyStartDate) = to_date('2020-01-01');
set(StudyEndDate)   = to_date('2024-10-31');

--> CODESET menopause:1 cognitive-impairment:1 hot-flash:1 irregular-periods:1 musculoskeletal-pain:1 heavy-period:1 fertility-problems:1

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
		   WHEN ("Cluster_ID" = 'C19PREG_COD')    					THEN 'pregnancy' 
		   -- symptoms
		   WHEN "SCTID" = '42984000' 								THEN 'night-sweats'
		   WHEN "SCTID" = '31908003' 								THEN 'vaginal-dryness'
		   WHEN "SCTID" = '339341000000102'							THEN 'contraceptive-implant-removal'
		   WHEN "SCTID" IN ('169553002', '698972004', '301806003',
		   					 '755621000000101', '384201000000103') 	THEN 'contraceptive-implant-fitting'
		   WHEN "SCTID" = '43548008' 								THEN 'ovulation-pain'
           ELSE 'other' END AS "Concept"
    , ec."Term" AS "Description"
FROM {{cohort-table}} cohort
LEFT OUTER JOIN INTERMEDIATE.GP_RECORD."Combined_EventsMedications_Clusters_SecondaryUses" ec ON ec."FK_Patient_ID" = cohort."FK_Patient_ID"
WHERE (
		"Cluster_ID" IN ('SLUPUS_COD', 'RARTH_COD', 'C19PREG_COD')
		OR "SCTID" IN ('42984000','31908003','339341000000102','169553002', 
					   '698972004', '301806003','755621000000101', '384201000000103') 
	  )
AND TO_DATE(ec."Date") BETWEEN $StudyStartDate and $StudyEndDate
AND ec."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM {{cohort-table}})
UNION
-- find diagnoses codes that don't exist in a cluster
SELECT 
	cohort."GmPseudo"
	, to_date("EventDate") AS "Date"
	, events."SCTID" AS "SnomedCode"
	, cs.concept AS "Concept"
	, events."Term" AS "Description"
FROM {{cohort-table}} cohort
LEFT OUTER JOIN INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" events ON events."FK_Patient_ID" = cohort."FK_Patient_ID"
LEFT OUTER JOIN {{code-set-table}} cs ON cs.code = events."SuppliedCode" 
WHERE cs.concept IN ('cognitive-impairment', 'hot-flash', 'irregular-periods', 
						'musculoskeletal-pain', 'heavy-period', 'fertility-problems', 'menopause')
	AND events."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM {{cohort-table}})
	AND TO_DATE("EventDate") BETWEEN $StudyStartDate AND $StudyEndDate;


-- final table

{{create-output-table::"LH009-3_DiagnosesAndSymptoms"}}
SELECT * from diagnoses