--┌──────────────────────────────┐
--│ Medications for LH006 cohort │
--└──────────────────────────────┘

-- meds: benzodiazepines, gabapentinoids, nsaids, opioids, antidepressants

------------ RESEARCH DATA ENGINEER CHECK ------------
-- 
------------------------------------------------------

USE DATABASE PRESENTATION;
USE SCHEMA GP_RECORD;

--> EXECUTE query-build-lh006-cohort.sql

DROP TABLE IF EXISTS prescriptions;
CREATE TEMPORARY TABLE prescriptions AS
SELECT 
    ec."FK_Patient_ID"
    , TO_DATE(ec."MedicationDate") AS "MedicationDate"
    , ec."SCTID" AS "SnomedCode"
    , ec."Units"
    , ec."Dosage"
    , ec."Dosage_GP_Medications"
    , CASE WHEN ec."Cluster_ID" = 'BENZODRUG_COD' THEN 'benzodiazepine' -- benzodiazepines
           WHEN ec."Cluster_ID" = 'GABADRUG_COD' THEN 'gabapentinoid' -- gabapentinoids
           WHEN ec."Cluster_ID" = 'ORALNSAIDDRUG_COD' THEN 'nsaid' -- oral nsaids
		   WHEN ec."Cluster_ID" = 'OPIOIDDRUG_COD' THEN 'opioid' -- opioids except heroin addiction substitutes
           ELSE 'other' END AS "CodeSet"
    , ec."MedicationDescription" AS "Description"
FROM INTERMEDIATE.GP_RECORD."MedicationsClusters" ec
WHERE "Cluster_ID" in 
    ('BENZODRUG_COD', 'GABADRUG_COD', 'ORALNSAIDDRUG_COD', 'OPIOIDDRUG_COD', 'ANTIDEPDRUG_COD')
    AND TO_DATE(ec."MedicationDate") BETWEEN $StudyStartDate and $StudyEndDate
    AND ec."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM Cohort);


