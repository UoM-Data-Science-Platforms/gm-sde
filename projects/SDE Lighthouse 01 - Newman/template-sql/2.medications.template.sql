--┌─────────────────────┐
--│ LH001: Medications  │
--└─────────────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------
-- 
------------------------------------------------------

set(StartDate) = to_date('2012-01-01');
set(EndDate)   = to_date('2024-06-30');

-- one med missing: ondansetron 

DROP TABLE IF EXISTS prescriptions;
CREATE TEMPORARY TABLE prescriptions AS
SELECT 
    ec."FK_Patient_ID"
	, c."GmPseudo"
    , TO_DATE(ec."Date") AS "MedicationDate"
    , ec."SCTID" AS "SnomedCode"
	, ec."Quantity"
    , ec."Dosage" 
    , CASE WHEN ec."Field_ID" = 'Statin' THEN "FoundValue" -- statin
			--antidepressants
	       WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("Term") LIKE '%citalopram%')    THEN 'citalopram'
		   WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("Term") LIKE '%escitalopram%')  THEN 'escitalopram'
	       WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("Term") LIKE '%fluvoxamine%')   THEN 'fluvoxamine'
	       WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("Term") LIKE '%paroxetine%')    THEN 'paroxetine'
		   WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("Term") LIKE '%sertraline%')    THEN 'sertraline'
	       WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("Term") LIKE '%venlafaxine%')   THEN 'venlafaxine'
		   WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("Term") LIKE '%amitriptyline%') THEN 'amitriptyline'
           WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("Term") LIKE '%clomipramine%')  THEN 'clomipramine'
		   WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("Term") LIKE '%doxepin%')       THEN 'doxepin'
		   WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("Term") LIKE '%imipramine%')    THEN 'imipramine'
		   WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("Term") LIKE '%nortriptyline%') THEN 'nortiptyline'
		   WHEN ("Cluster_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("Term") LIKE '%trimipramine%')  THEN 'trimipramine'
			-- proton pump inhibitors
		   WHEN ("Cluster_ID" = 'ULCERHEALDRUG_COD') AND (LOWER("Term") LIKE '%esomeprazole%') THEN 'esomeprazole'
		   WHEN ("Cluster_ID" = 'ULCERHEALDRUG_COD') AND (LOWER("Term") LIKE '%lansoprazole%') THEN 'lansoprazole'
		   WHEN ("Cluster_ID" = 'ULCERHEALDRUG_COD') AND (LOWER("Term") LIKE '%omeprazole%')   THEN 'omeprazole'
		   WHEN ("Cluster_ID" = 'ULCERHEALDRUG_COD') AND (LOWER("Term") LIKE '%pantoprazole%') THEN 'pantoprazole'
		   WHEN ("Cluster_ID" = 'ULCERHEALDRUG_COD') AND (LOWER("Term") LIKE '%rabeprazole%')  THEN 'rabeprazole'
			--immunosuppressants
		   WHEN ("Cluster_ID" = 'IMTRTATRISKDRUG_COD' AND LOWER("Term") LIKE '%tacrolimus%') THEN 'tacrolimus'
		   --anticoagulants
		   WHEN ("Cluster_ID" = 'WARFARINDRUG_COD') 										 THEN 'warfarin'
		   --antiepilepsy
		   WHEN ("Cluster_ID" = 'EPILDRUG_COD' AND LOWER("Term") LIKE '%phenytoin%') 	     THEN 'phenytoin'
		   --nsaids
		   WHEN	("Cluster_ID" = 'ORALNSAIDDRUG_COD' AND LOWER("Term") LIKE '%celecoxib%') 	 THEN 'celecoxib'
		   WHEN ("Cluster_ID" = 'ORALNSAIDDRUG_COD' AND LOWER("Term") LIKE '%piroxicam%') 	 THEN 'piroxicam'
		   WHEN ("Cluster_ID" = 'ORALNSAIDDRUG_COD' AND LOWER("Term") LIKE '%diclofenac%')   THEN 'diclofenac'
		   WHEN ("Cluster_ID" = 'ORALNSAIDDRUG_COD' AND LOWER("Term") LIKE '%ibuprofen%')	 THEN 'ibuprofen'
		   --opioids
		   WHEN ("Cluster_ID" = 'OPIOIDDRUG_COD' AND LOWER("Term") LIKE '%tramadol%') 		 THEN 'tramadol'
		   WHEN ("Cluster_ID" = 'OPIOIDDRUG_COD' AND LOWER("Term") LIKE '%codeine%')		 THEN 'codeine'
		   --others
		   WHEN ("Cluster_ID" = 'CLODRUG_COD') 												 THEN 'clopidogrel'
		   ELSE 'other' END AS "Concept"

    , ec."Term" AS "Description"
FROM INTERMEDIATE.GP_RECORD."Combined_EventsMedications_Clusters_SecondaryUses" ec
INNER JOIN {{cohort-table}} c ON c."FK_Patient_ID" = ec."FK_Patient_ID"
WHERE 
	("Field_ID" IN ('Statin')) OR -- statins
	("Field_ID" IN ('ANTIDEPDRUG_COD') -- SSRIs
		AND (LOWER("Term") LIKE '%citalopram%' OR LOWER("Term") LIKE '%escitalopram%' OR LOWER("Term") LIKE '%fluvoxamine%' OR LOWER("Term") LIKE '%paroxetine%' OR LOWER("Term") LIKE '%sertraline%' OR LOWER("Term") LIKE '%venlafaxine%')
	) OR
	("Field_ID" IN ('ANTIDEPDRUG_COD') -- tricyclic antidepressants
		AND (LOWER("Term") LIKE '%amitriptyline%' OR LOWER("Term") LIKE '%clomipramine%' OR LOWER("Term") LIKE '%doxepin%' OR LOWER("Term") LIKE '%imipramine%' OR LOWER("Term") LIKE '%nortriptyline%' OR LOWER("Term") LIKE '%trimipramine%')
	) OR
	( "Field_ID" = 'ULCERHEALDRUG_COD' -- proton pump inhibitors
	  AND (LOWER("Term") LIKE '%esomeprazole%' OR LOWER("Term") LIKE '%lansoprazole%' OR LOWER("Term") LIKE '%omeprazole%' OR LOWER("Term") LIKE '%pantoprazole%' OR LOWER("Term") LIKE '%rabeprazole%' )
	) OR -- nsaids
	( "Field_ID" = 'ORALNSAIDDRUG_COD' 	
	  AND (LOWER("Term") LIKE '%celecoxib%' OR LOWER("Term") LIKE '%piroxicam%' OR LOWER("Term") LIKE '%piroxicam%' OR LOWER("Term") LIKE '%diclofenac%' OR LOWER("Term") LIKE '%ibuprofen%' )
	) OR
	-- others
	("Cluster_ID" = 'OPIOIDDRUG_COD' AND LOWER("Term") LIKE '%tramadol%') OR
	("Cluster_ID" = 'IMTRTATRISKDRUG_COD' AND LOWER("Term") LIKE '%tacrolimus%') OR
	("Cluster_ID" = 'WARFARINDRUG_COD') OR
	("Cluster_ID" = 'EPILDRUG_COD' AND LOWER("Term") LIKE '%phenytoin%') OR
	("Cluster_ID" = 'CLODRUG_COD') 	OR
	("Cluster_ID" = 'OPIOIDDRUG_COD' AND LOWER("Term") LIKE '%codeine%')
AND TO_DATE(ec."Date") BETWEEN $StartDate and $EndDate;


-- ONLY KEEP DOSAGE INFO IF IT HAS APPEARED > 50 TIMES, AS IT CAN BE BESPOKE

DROP TABLE IF EXISTS SafeDosages;
CREATE TEMPORARY TABLE SafeDosages AS
SELECT "Dosage" 
FROM prescriptions
GROUP BY "Dosage"
HAVING count(*) >= 50;

-- final table with redacted dosage info

{{create-output-table::"LH001-2_Medications"}}
SELECT 
    p."GmPseudo", 
	p."MedicationDate",
	p."Quantity",
	p."SnomedCode",
	p."Concept",
	p."Description",
    IFNULL(sd."Dosage", 'REDACTED') as Dosage
FROM prescriptions p
LEFT JOIN SafeDosages sd ON sd."Dosage" = p."Dosage"

