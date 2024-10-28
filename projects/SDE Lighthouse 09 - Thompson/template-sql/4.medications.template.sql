--┌──────────────────────────────────────────────┐
--│ Medications and treatments for LH009 cohort  │
--└──────────────────────────────────────────────┘

-- meds: HRT, birth control, steroids, NSAIDS, DMARDS, biologics, coil fittings 

-------- RESEARCH DATA ENGINEER CHECK ------------

--------------------------------------------------

set(StudyStartDate) = to_date('2020-01-01');
set(StudyEndDate)   = to_date('2024-09-30');

--> CODESET contraceptives-combined-hormonal:1 contraceptives-devices:1 contraceptives-emergency-pills:1
--> CODESET contraceptives-progesterone-only:1 female-sex-hormones:1 male-sex-hormones:1


 ---- BELOW NEEDS VALIDATING

--> CODESET disease-modifying-med:1 corticosteroid:1 anabolic-steroids:1
--> CODESET male-sex-hormones:1 female-sex-hormones:1
--> CODESET contraceptives-emergency-pill:1 contraceptives-tablet:1 contraceptives-iud:1 contraceptives-injection:1 contraceptives-implant:1


----- code sets needed: biologics, implant, coil, 

DROP TABLE IF EXISTS LH009_med_codes;
CREATE TEMPORARY TABLE LH009_med_codes AS
SELECT
    "GmPseudo",
    CAST("MedicationDate" AS DATE) AS "MedicationDate",
    "SuppliedCode",
    "Dosage",
    "Quantity",
    "Units"
FROM INTERMEDIATE.GP_RECORD."GP_Medications_SecondaryUses" gp
INNER JOIN {{cohort-table}} c ON gp."FK_Patient_ID" = c."FK_Patient_ID"
WHERE "SuppliedCode" IN (SELECT code FROM {{code-set-table}} 
								WHERE concept in ('belimumab','hydroxychloroquine','chloroquine'));


-- meds from cluster tables: nsaids,

DROP TABLE IF EXISTS prescriptions;
CREATE TEMPORARY TABLE prescriptions AS
SELECT 
    co."GmPseudo"
    , TO_DATE(ec."Date") AS "MedicationDate"
    , ec."SCTID" AS "SnomedCode"
	, ec."Quantity"
    , ec."Dosage_GP_Medications" AS "Dosage"
    , CASE WHEN ec."Cluster_ID" = 'ORALNSAIDDRUG_COD' THEN 'nsaid' -- oral nsaids


           ELSE 'other' END AS "CodeSet"
    , ec."MedicationDescription" AS "Description"
FROM {{cohort-table}} co
LEFT JOIN INTERMEDIATE.GP_RECORD."Combined_EventsMedications_Clusters_SecondaryUses" ec ON co."FK_Patient_ID" = ec."FK_Patient_ID"
WHERE "Cluster_ID" in ('ORALNSAIDDRUG_COD')
    AND TO_DATE(ec."Date") BETWEEN $StudyStartDate and $StudyEndDate;

-- ONLY KEEP DOSAGE INFO IF IT HAS APPEARED > 50 TIMES

DROP TABLE IF EXISTS SafeDosages;
CREATE TEMPORARY TABLE SafeDosages AS
SELECT "Dosage" 
FROM prescriptions
GROUP BY "Dosage"
HAVING count(*) >= 50;

-- table with redacted dosage info

DROP TABLE IF EXISTS prescriptions1;
CREATE TEMPORARY TABLE prescriptions1 AS
SELECT 
    p."GmPseudo",
    p."MedicationDate",
    p."SnomedCode",
    p."Quantity",
    p."CodeSet",
    p."Description",
	CASE WHEN "CodeSet" = 'benzodiazepine' THEN 1 ELSE 0 END AS "Benzodiazepine",
	CASE WHEN "CodeSet" = 'gabapentinoid' THEN 1 ELSE 0 END AS "Gabapentinoid",
	CASE WHEN "CodeSet" = 'nsaid' THEN 1 ELSE 0 END AS "Nsaid",
	CASE WHEN "CodeSet" = 'opioid' THEN 1 ELSE 0 END AS "Opioid",
	CASE WHEN "CodeSet" = 'antidepressant' THEN 1 ELSE 0 END AS "Antidepressant",
    IFNULL(sd."Dosage", 'REDACTED') as "Dosage"
FROM prescriptions p
LEFT JOIN SafeDosages sd ON sd."Dosage" = p."Dosage";

-- transform into wide format to reduce the number of rows in final table

{{create-output-table::"LH001-2_Medications"}}
SELECT "GmPseudo",
	YEAR("MedicationDate") AS "Year",
    MONTH("MedicationDate") AS "Month",
	SUM("Benzodiazepine") AS "Benzodiazepines",
FROM prescriptions1
GROUP BY "GmPseudo",
	YEAR("MedicationDate"),
    MONTH("MedicationDate")
ORDER BY 
	YEAR("MedicationDate"),
    MONTH("MedicationDate");