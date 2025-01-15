USE SCHEMA SDE_REPOSITORY.SHARED_UTILITIES;

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
INNER JOIN SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_01_Newman" c ON c."FK_Patient_ID" = ec."FK_Patient_ID"
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


-- ... processing [[create-output-table::"LH001-2_Medications"]] ... 
-- ... Need to create an output table called "LH001-2_Medications" and replace 
-- ... the GmPseudo column with a study-specific random patient id.

-- First we create a table in an area only visible to the RDEs which contains
-- the GmPseudos. THESE CANNOT BE RELEASED TO END USERS.
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH001-2_Medications_WITH_IDENTIFIER";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH001-2_Medications_WITH_IDENTIFIER" AS
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

;

-- Then we check to see if there are any new GmPseudo ids. We do this by making a temp table 
-- of all "new" GmPseudo ids. I.e. any GmPseudo ids that we've already got a unique id for
-- for this study are excluded
DROP TABLE IF EXISTS "AllPseudos_SDE_Lighthouse_01_Newman";
CREATE TEMPORARY TABLE "AllPseudos_SDE_Lighthouse_01_Newman" AS
SELECT DISTINCT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."LH001-2_Medications_WITH_IDENTIFIER"
EXCEPT
SELECT "GmPseudo" FROM "Patient_ID_Mapping_SDE_Lighthouse_01_Newman";

-- Find the highest currently assigned id. Ids are given incrementally, so now ones
-- need to start at +1 of the current highest
SET highestPatientId = (
    SELECT IFNULL(MAX("StudyPatientPseudoId"),0) FROM "Patient_ID_Mapping_SDE_Lighthouse_01_Newman"
);

-- Make a study specific hash for each new GmPseudo and insert it
-- into the patient lookup table
INSERT INTO "Patient_ID_Mapping_SDE_Lighthouse_01_Newman"
SELECT
    "GmPseudo", -- the GM SDE patient ids for patients in this cohort
    SHA2(CONCAT('SDE_Lighthouse_01_Newman', "GmPseudo")) AS "Hash", -- used to provide a random (study-specific) ordering for the patient ids we provide
    $highestPatientId + ROW_NUMBER() OVER (ORDER BY "Hash") -- the patient id that we provide to the analysts
FROM "AllPseudos_SDE_Lighthouse_01_Newman";

-- Finally, we select from the output table which includes the GmPseudos, in order
-- to populate the table for the end users where the GmPseudo fields are redacted via a function
-- created in the 0.code-sets.sql file
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH001-2_Medications";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH001-2_Medications" AS
SELECT SDE_REPOSITORY.SHARED_UTILITIES.gm_pseudo_hash_SDE_Lighthouse_01_Newman("GmPseudo") AS "PatientID",
	* EXCLUDE "GmPseudo"
FROM SDE_REPOSITORY.SHARED_UTILITIES."LH001-2_Medications_WITH_IDENTIFIER";