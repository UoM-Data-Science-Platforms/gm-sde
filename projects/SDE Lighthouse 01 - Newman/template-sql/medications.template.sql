--┌─────────────────────┐
--│ LH001: Medications  │
--└─────────────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------
-- 
------------------------------------------------------

set(StartDate) = to_date('2012-01-01');
set(EndDate)   = to_date('2024-06-30');

-- one med missing: ondansetron 

USE DATABASE PRESENTATION;
USE SCHEMA GP_RECORD;

--> EXECUTE query-build-lh001-cohort.sql

DROP TABLE IF EXISTS prescriptions;
CREATE TEMPORARY TABLE prescriptions AS
SELECT 
    ec."FK_Patient_ID"
    , TO_DATE(ec."MedicationDate") AS "MedicationDate"
    , ec."SCTID" AS "SnomedCode"
	, ec."Quantity"
    , ec."Dosage_GP_Medications" AS "Dosage" 
    , CASE WHEN ec."Field_ID" = 'Statin' THEN "FoundValue" -- statin
			--antidepressants
	       WHEN ("Field_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("MedicationDescription") LIKE '%citalopram%')    THEN 'citalopram'
		   WHEN ("Field_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("MedicationDescription") LIKE '%escitalopram%')  THEN 'escitalopram'
	       WHEN ("Field_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("MedicationDescription") LIKE '%fluvoxamine%')   THEN 'fluvoxamine'
	       WHEN ("Field_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("MedicationDescription") LIKE '%paroxetine%')    THEN 'paroxetine'
		   WHEN ("Field_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("MedicationDescription") LIKE '%sertraline%')    THEN 'sertraline'
	       WHEN ("Field_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("MedicationDescription") LIKE '%venlafaxine%')   THEN 'venlafaxine'
		   WHEN ("Field_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("MedicationDescription") LIKE '%amitriptyline%') THEN 'amitriptyline'
           WHEN ("Field_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("MedicationDescription") LIKE '%clomipramine%')  THEN 'clomipramine'
		   WHEN ("Field_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("MedicationDescription") LIKE '%doxepin%')       THEN 'doxepin'
		   WHEN ("Field_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("MedicationDescription") LIKE '%imipramine%')    THEN 'imipramine'
		   WHEN ("Field_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("MedicationDescription") LIKE '%nortriptyline%') THEN 'nortiptyline'
		   WHEN ("Field_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("MedicationDescription") LIKE '%trimipramine%')  THEN 'trimipramine'
			-- proton pump inhibitors
		   WHEN ("Field_ID" = 'ULCERHEALDRUG_COD') AND (LOWER("MedicationDescription") LIKE '%esomeprazole%') THEN 'esomeprazole'
		   WHEN ("Field_ID" = 'ULCERHEALDRUG_COD') AND (LOWER("MedicationDescription") LIKE '%lansoprazole%') THEN 'lansoprazole'
		   WHEN ("Field_ID" = 'ULCERHEALDRUG_COD') AND (LOWER("MedicationDescription") LIKE '%omeprazole%')   THEN 'omeprazole'
		   WHEN ("Field_ID" = 'ULCERHEALDRUG_COD') AND (LOWER("MedicationDescription") LIKE '%pantoprazole%') THEN 'pantoprazole'
		   WHEN ("Field_ID" = 'ULCERHEALDRUG_COD') AND (LOWER("MedicationDescription") LIKE '%rabeprazole%')  THEN 'rabeprazole'
			--immunosuppressants
		   WHEN ("Cluster_ID" = 'IMTRTATRISKDRUG_COD' AND LOWER("MedicationDescription") LIKE '%tacrolimus%') THEN 'tacrolimus'
		   --anticoagulants
		   WHEN ("Cluster_ID" = 'WARFARINDRUG_COD') 										 THEN 'warfarin'
		   --antiepilepsy
		   WHEN ("Cluster_ID" = 'EPILDRUG_COD' AND LOWER("MedicationDescription") LIKE '%phenytoin%') 	     THEN 'phenytoin'
		   --nsaids
		   WHEN	("Field_ID" = 'ORALNSAIDDRUG_COD' AND LOWER("MedicationDescription") LIKE '%celecoxib%') 	 THEN 'celecoxib'
		   WHEN ("Field_ID" = 'ORALNSAIDDRUG_COD' AND LOWER("MedicationDescription") LIKE '%piroxicam%') 	 THEN 'piroxicam'
		   WHEN ("Cluster_ID" = 'ORALNSAIDDRUG_COD' AND LOWER("MedicationDescription") LIKE '%diclofenac%')   THEN 'diclofenac'
		   WHEN ("Cluster_ID" = 'ORALNSAIDDRUG_COD' AND LOWER("MedicationDescription") LIKE '%ibuprofen%')	 THEN 'ibuprofen'
		   --opioids
		   WHEN ("Cluster_ID" = 'OPIOIDDRUG_COD' AND LOWER("MedicationDescription") LIKE '%tramadol%') 		 THEN 'tramadol'
		   WHEN ("Cluster_ID" = 'OPIOIDDRUG_COD' AND LOWER("MedicationDescription") LIKE '%codeine%')		 THEN 'codeine'
		   --others
		   WHEN ("Cluster_ID" = 'CLODRUG_COD') 												 THEN 'clopidogrel'
		   ELSE 'other' END AS "Concept"

    , ec."MedicationDescription" AS "Description"
FROM INMedicationDescriptionEDIATE.GP_RECORD."MedicationsClusters" ec
WHERE 
	("Field_ID" IN ('Statin')) OR -- statins
	("Field_ID" IN ('ANTIDEPDRUG_COD') -- SSRIs
		AND (LOWER("MedicationDescription") LIKE '%citalopram%' OR LOWER("MedicationDescription") LIKE '%escitalopram%' OR LOWER("MedicationDescription") LIKE '%fluvoxamine%' OR LOWER("MedicationDescription") LIKE '%paroxetine%' OR LOWER("MedicationDescription") LIKE '%sertraline%' OR LOWER("MedicationDescription") LIKE '%venlafaxine%')
	) OR
	("Field_ID" IN ('ANTIDEPDRUG_COD') -- tricyclic antidepressants
		AND (LOWER("MedicationDescription") LIKE '%amitriptyline%' OR LOWER("MedicationDescription") LIKE '%clomipramine%' OR LOWER("MedicationDescription") LIKE '%doxepin%' OR LOWER("MedicationDescription") LIKE '%imipramine%' OR LOWER("MedicationDescription") LIKE '%nortriptyline%' OR LOWER("MedicationDescription") LIKE '%trimipramine%')
	) OR
	( "Field_ID" = 'ULCERHEALDRUG_COD' -- proton pump inhibitors
	  AND (LOWER("MedicationDescription") LIKE '%esomeprazole%' OR LOWER("MedicationDescription") LIKE '%lansoprazole%' OR LOWER("MedicationDescription") LIKE '%omeprazole%' OR LOWER("MedicationDescription") LIKE '%pantoprazole%' OR LOWER("MedicationDescription") LIKE '%rabeprazole%' )
	) OR -- nsaids
	( "Field_ID" = 'ORALNSAIDDRUG_COD' 	
	  AND (LOWER("MedicationDescription") LIKE '%celecoxib%' OR LOWER("MedicationDescription") LIKE '%piroxicam%' OR LOWER("MedicationDescription") LIKE '%piroxicam%' OR LOWER("MedicationDescription") LIKE '%diclofenac%' OR LOWER("MedicationDescription") LIKE '%ibuprofen%' )
	) OR
	-- others
	("Cluster_ID" = 'OPIOIDDRUG_COD' AND LOWER("MedicationDescription") LIKE '%tramadol%') OR
	("Cluster_ID" = 'IMTRTATRISKDRUG_COD' AND LOWER("MedicationDescription") LIKE '%tacrolimus%') OR
	("Cluster_ID" = 'WARFARINDRUG_COD') OR
	("Cluster_ID" = 'EPILDRUG_COD' AND LOWER("MedicationDescription") LIKE '%phenytoin%') OR
	("Cluster_ID" = 'CLODRUG_COD') 	OR
	("Cluster_ID" = 'OPIOIDDRUG_COD' AND LOWER("MedicationDescription") LIKE '%codeine%')
AND TO_DATE(ec."MedicationDate") BETWEEN $StartDate and $EndDate
AND ec."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM Cohort);


-- ONLY KEEP DOSAGE INFO IF IT HAS APPEARED > 50 TIMES, AS IT CAN BE BESPOKE

DROP TABLE IF EXISTS SafeDosages;
CREATE TEMPORARY TABLE SafeDosages AS
SELECT "Dosage" 
FROM prescriptions
GROUP BY "Dosage"
HAVING count(*) >= 50;

-- final table with redacted dosage info

SELECT 
    p.*,
    IFNULL(sd."Dosage", 'REDACTED') as Dosage
FROM prescriptions p
LEFT JOIN SafeDosages sd ON sd."Dosage" = p."Dosage"

