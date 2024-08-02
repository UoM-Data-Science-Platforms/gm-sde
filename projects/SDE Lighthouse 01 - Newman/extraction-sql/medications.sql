--┌─────────────────────┐
--│ LH001: Medications  │
--└─────────────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------
-- 
------------------------------------------------------

USE DATABASE PRESENTATION;
USE SCHEMA GP_RECORD;

--┌────────────────────────────────────────────────────────────────────────────────────────────┐
--│ Define Cohort for LH001: patients that had pharmacogenetic testing, and matched controls   │
--└────────────────────────────────────────────────────────────────────────────────────────────┘

-- OBJECTIVE: To build the cohort of patients needed for LH001. This reduces duplication of code in the template scripts.

-- COHORT: Any patient with a pharmacogenetic test, or a matched control.

-- OUTPUT: Temp tables as follows:
-- Cohort


USE INTERMEDIATE.GP_RECORD;

set(StudyStartDate) = to_date('2023-06-01');
set(StudyEndDate)   = to_date('2024-06-30');

--ALL DEATHS 

DROP TABLE IF EXISTS Death;
CREATE TEMPORARY TABLE Death AS
SELECT 
    DEATH."GmPseudo",
    TO_DATE(DEATH."RegisteredDateOfDeath") AS DeathDate
FROM PRESENTATION.NATIONAL_FLOWS_PCMD."DS1804_Pcmd" DEATH;

-- GET LATEST SNAPSHOT OF DEMOGRAPHICS TABLE

DROP TABLE IF EXISTS LatestSnapshotAdults;
CREATE TEMPORARY TABLE LatestSnapshotAdults AS
SELECT 
    p.*
FROM INTERMEDIATE.GP_RECORD."DemographicsProtectedCharacteristics" p 
INNER JOIN (
    SELECT "GmPseudo", MAX("Snapshot") AS LatestSnapshot
    FROM INTERMEDIATE.GP_RECORD."DemographicsProtectedCharacteristics" p 
    WHERE DATEDIFF(YEAR, TO_DATE("DateOfBirth"), $StudyStartDate) >= 18 -- adults only
    GROUP BY "GmPseudo"
    ) t2
ON t2."GmPseudo" = p."GmPseudo" AND t2.LatestSnapshot = p."Snapshot";

-- FIND ALL ADULT PATIENTS ALIVE AT STUDY START DATE

DROP TABLE IF EXISTS AlivePatientsAtStart;
CREATE TEMPORARY TABLE AlivePatientsAtStart AS 
SELECT  
    dem.*, 
    Death.DeathDate
FROM LatestSnapshotAdults dem
LEFT JOIN Death ON Death."GmPseudo" = dem."GmPseudo"
WHERE 
    (DeathDate IS NULL OR DeathDate > $StudyStartDate); -- alive on study start date



-- table of pharmacogenetic test patients

------


DROP TABLE IF EXISTS Cohort;
CREATE TEMPORARY TABLE AS
SELECT DISTINCT 
	 "FK_Patient_ID",
	 "GmPseudo"
INTO Cohort
FROM Pharmacogenetic p



---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------


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

