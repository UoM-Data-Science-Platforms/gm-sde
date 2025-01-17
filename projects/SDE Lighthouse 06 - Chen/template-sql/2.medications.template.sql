--┌──────────────────────────────┐
--│ Medications for LH006 cohort │
--└──────────────────────────────┘

-- meds: benzodiazepines, gabapentinoids, nsaids, opioids, antidepressants

-------- RESEARCH DATA ENGINEER CHECK ------------
-- Richard Williams	2024-08-30	Review complete --
--------------------------------------------------

set(StudyStartDate) = to_date('2017-01-01');
set(StudyEndDate)   = to_date('2024-10-31');

DROP TABLE IF EXISTS prescriptions;
CREATE TEMPORARY TABLE prescriptions AS
SELECT 
    co."GmPseudo"
    , TO_DATE(ec."Date") AS "MedicationDate"
    , ec."SCTID" AS "SnomedCode"
    , ec."Dosage"
    , CASE WHEN ec."Cluster_ID" = 'BENZODRUG_COD' THEN 'benzodiazepine' -- benzodiazepines
           WHEN ec."Cluster_ID" = 'GABADRUG_COD' THEN 'gabapentinoid' -- gabapentinoids
           WHEN ec."Cluster_ID" = 'ORALNSAIDDRUG_COD' THEN 'nsaid' -- oral nsaids
		   WHEN ec."Cluster_ID" = 'OPIOIDDRUG_COD' THEN 'opioid' -- opioids except heroin addiction substitutes
	       WHEN ec."Cluster_ID" = 'ANTIDEPDRUG_COD' THEN 'antidepressant' -- antidepressants
           ELSE 'other' END AS "CodeSet"
    , ec."Term" AS "Description"
FROM {{cohort-table}} co
LEFT JOIN INTERMEDIATE.GP_RECORD."Combined_EventsMedications_Clusters_SecondaryUses" ec ON co."FK_Patient_ID" = ec."FK_Patient_ID"
WHERE "Cluster_ID" in ('BENZODRUG_COD', 'GABADRUG_COD', 'ORALNSAIDDRUG_COD', 'OPIOIDDRUG_COD', 'ANTIDEPDRUG_COD')
    AND TO_DATE(ec."Date") BETWEEN $StudyStartDate and $StudyEndDate;


DROP TABLE IF EXISTS prescriptions1;
CREATE TEMPORARY TABLE prescriptions1 AS
SELECT 
    p."GmPseudo",
    p."MedicationDate",
    p."SnomedCode",
    p."Dosage",
    p."CodeSet",
    p."Description",
	CASE WHEN "CodeSet" = 'benzodiazepine' THEN 1 ELSE 0 END AS "Benzodiazepine",
	CASE WHEN "CodeSet" = 'gabapentinoid' THEN 1 ELSE 0 END AS "Gabapentinoid",
	CASE WHEN "CodeSet" = 'nsaid' THEN 1 ELSE 0 END AS "Nsaid",
	CASE WHEN "CodeSet" = 'opioid' THEN 1 ELSE 0 END AS "Opioid",
	CASE WHEN "CodeSet" = 'antidepressant' THEN 1 ELSE 0 END AS "Antidepressant",
FROM prescriptions p;
-- transform into wide format to reduce the number of rows in final table

{{create-output-table::"LH006-2_Medications"}}
SELECT "GmPseudo",
	YEAR("MedicationDate") AS "Year",
    --MONTH("MedicationDate") AS "Month",
	SUM("Benzodiazepine") AS "Benzodiazepines",
	SUM("Gabapentinoid") AS "Gabapentinoids",
	SUM("Nsaid") AS "Nsaids",
	SUM("Opioid") AS "Opioids",
	SUM("Antidepressant") AS "Antidepressants"
FROM prescriptions1
GROUP BY "GmPseudo",
	YEAR("MedicationDate")
    --,MONTH("MedicationDate")
ORDER BY 
	YEAR("MedicationDate");
    --,MONTH("MedicationDate");