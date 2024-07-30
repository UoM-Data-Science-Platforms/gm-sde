--┌─────────────────────┐
--│ LH001: Medications  │
--└─────────────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------
-- 
------------------------------------------------------

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
    , ec."Dosage_GP_Medications" AS "Dosage" -- NEED TO ANONYMISE
    , CASE WHEN ec."Field_ID" = 'Statin' THEN 'statin' -- statin
	       WHEN ("Field_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("Term") LIKE '%citalopram%' OR LOWER("Term") LIKE '%escitalopram%' OR LOWER("Term") LIKE '%fluvoxamine%' OR LOWER("Term") LIKE '%paroxetine%' OR LOWER("Term") LIKE '%sertraline%') THEN 'selective-serotonin-reuptake-inhibitor'
		   WHEN ("Field_ID" = 'ANTIDEPDRUG_COD') AND (LOWER("Term") LIKE '%amitriptyline%' OR LOWER("Term") LIKE '%clomipramine%' OR LOWER("Term") LIKE '%doxepin%' OR LOWER("Term") LIKE '%imipramine%' OR LOWER("Term") LIKE '%nortriptyline%' OR LOWER("Term") LIKE '%trimipramine%') THEN 'tricyclic-antidepressant'
           WHEN ("Field_ID" = 'ULCERHEALDRUG_COD') AND (LOWER("Term") LIKE '%esomeprazole%' OR LOWER("Term") LIKE '%lansoprazole%' OR LOWER("Term") LIKE '%omeprazole%' OR LOWER("Term") LIKE '%pantoprazole%' OR LOWER("Term") LIKE '%rabeprazole%' ) THEN 'proton-pump-inhibitors'
		   ELSE 'other' END AS "Concept"
    , ec."MedicationDescription" AS "Description"
FROM INTERMEDIATE.GP_RECORD."MedicationsClusters" ec
WHERE 
	("Field_ID" IN ('Statin')) OR -- statins
	("Field_ID" IN ('ANTIDEPDRUG_COD') -- SSRIs
		AND (LOWER("Term") LIKE '%citalopram%' OR LOWER("Term") LIKE '%escitalopram%' OR LOWER("Term") LIKE '%fluvoxamine%' OR LOWER("Term") LIKE '%paroxetine%' OR LOWER("Term") LIKE '%sertraline%')
	) OR
	("Field_ID" IN ('ANTIDEPDRUG_COD') -- tricyclic antidepressants
		AND (LOWER("Term") LIKE '%amitriptyline%' OR LOWER("Term") LIKE '%clomipramine%' OR LOWER("Term") LIKE '%doxepin%' OR LOWER("Term") LIKE '%imipramine%' OR LOWER("Term") LIKE '%nortriptyline%' OR LOWER("Term") LIKE '%trimipramine%')
	) OR
	( "Field_ID" = 'ULCERHEALDRUG_COD' -- proton pump inhibitors
	  AND (LOWER("Term") LIKE '%esomeprazole%' OR LOWER("Term") LIKE '%lansoprazole%' OR LOWER("Term") LIKE '%omeprazole%' OR LOWER("Term") LIKE '%pantoprazole%' OR LOWER("Term") LIKE '%rabeprazole%' )
	) 
AND TO_DATE(ec."MedicationDate") BETWEEN $StudyStartDate and $StudyEndDate
AND ec."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM Cohort);

