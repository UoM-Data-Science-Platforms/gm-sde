--┌──────────────────────────────────────────────┐
--│ Medications and treatments for LH009 cohort  │
--└──────────────────────────────────────────────┘

-- meds: HRT, birth control, steroids, NSAIDS, DMARDS, biologics, coil fittings 

-------- RESEARCH DATA ENGINEER CHECK ------------

--------------------------------------------------

set(StudyStartDate) = to_date('2020-01-01');
set(StudyEndDate)   = to_date('2024-09-30');

--> CODESET disease-modifying-med:1 corticosteroid:1 anabolic-steroids:1
--> CODESET male-sex-hormones:1 female-sex-hormones:1
--> CODESET contraceptives-emergency-pills:1 contraceptives-tablet:1 contraceptives-iud:1 contraceptives-injection:1 contraceptives-implant:1

DROP TABLE IF EXISTS LH009_med_codes;
CREATE TEMPORARY TABLE LH009_med_codes AS
SELECT DISTINCT
    "GmPseudo",
    CAST("MedicationDate" AS DATE) AS "Date",
    "SuppliedCode",
	SCTID AS "SnomedCode"
    "Dosage",
    "Units",
	co.concept as "CodeSet",
	"MedicationDescription" AS "Description"
FROM INTERMEDIATE.GP_RECORD."GP_Medications_SecondaryUses" gp
INNER JOIN {{cohort-table}} c ON gp."FK_Patient_ID" = c."FK_Patient_ID"
INNER JOIN {{code-set-table}} co ON co.code = gp."SuppliedCode"
WHERE co.concept in ('disease-modifying-med', 'corticosteroid', 'anabolic-steroids', 
				'male-sex-hormones', 'female-sex-hormones', 'contraceptives-emergency-pill',
				'contraceptives-tablet', 'contraceptives-iud', 'contraceptives-injection', 'contraceptives-implant');


-- meds from cluster tables: nsaids,

DROP TABLE IF EXISTS prescriptions;
CREATE TEMPORARY TABLE prescriptions AS
SELECT 
    co."GmPseudo"
    , TO_DATE(ec."Date") AS "Date"
    , ec."SCTID" AS "SnomedCode"
	, ec."SuppliedCode"
    , ec."Dosage"
	, ec."DosageUnits" AS "Units"
    , CASE WHEN ec."Cluster_ID" = 'ORALNSAIDDRUG_COD' THEN 'nsaid' -- oral nsaids
		   WHEN ec."Cluster_ID" = 'BIOLDRUG_COD' 	  THEN 'biologics' -- biologic immune modulators
		   WHEN ec."Cluster_ID" = 'DMARDSDRUG_COD'    THEN 'disease-modifying' -- disease modifying systemic meds
           ELSE 'other' END AS "CodeSet"
    , ec."Term" AS "Description"
FROM {{cohort-table}} co
LEFT JOIN INTERMEDIATE.GP_RECORD."Combined_EventsMedications_Clusters_SecondaryUses" ec ON co."FK_Patient_ID" = ec."FK_Patient_ID"
WHERE "Cluster_ID" in ('ORALNSAIDDRUG_COD', 'BIOLDRUG_COD', 'DMARDSDRUG_COD')
    AND TO_DATE(ec."Date") BETWEEN $StudyStartDate and $StudyEndDate;


-- join cluster and gmcr code set tables

{{create-output-table::"LH009-4_Medications"}}
SELECT 
	"GmPseudo"
	, "Date"
	, "SnomedCode"
	--, "SuppliedCode"
	, "CodeSet"
	, "Description"
FROM LH009_med_codes
UNION
SELECT 
	"GmPseudo"
	, "Date"
	, "SnomedCode"
	--, "SuppliedCode"
	, "CodeSet"
	, "Description"
FROM prescriptions