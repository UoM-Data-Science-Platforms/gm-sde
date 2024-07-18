--┌─────────────┐
--│ Medications │
--└─────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------
-- 
------------------------------------------------------

-- All prescriptions of: antipsychotic medication.

-- OUTPUT: Data with the following fields
-- 	-   PatientId (int)
--	-	MedicationDescription
--	-	MostRecentPrescriptionDate (YYYY-MM-DD)

--> EXECUTE query-build-lh003-cohort.sql

--> CODESET anti-dementia-drugs:1 
-- acetylcholinesterase-inhibitors:1 anticholinergic-medications:1 drowsy-medications:3

--DONE antipsychotics
--anti-dementia meds
--anticholinergics,
--DONE benzodiazepines, z-drugs
--sedating antihistamines

CREATE TEMPORARY TABLE LH003_Medication_Codes AS
SELECT GmPseudo, "SuppliedCode", to_date("MedicationDate") as MedicationDate
FROM LH003_Cohort cohort
LEFT OUTER JOIN INTERMEDIATE.GP_RECORD."GP_Medications_SecondaryUses" meds 
    ON meds."FK_Patient_ID" = cohort.FK_Patient_ID
WHERE "SuppliedCode" IN (SELECT code FROM AllCodes WHERE concept IN('anti-dementia-drugs'));

SELECT
    GmPseudo AS "PatientID",
	MedicationDate AS "PrescriptionDate",
    CASE
        WHEN "SuppliedCode" IN (SELECT code FROM AllCodes WHERE concept='anti-dementia-drugs') THEN 'Antidementia drug'
        WHEN "SuppliedCode" IN (SELECT code FROM AllCodes WHERE concept='acb1') THEN 'ACB1'
        WHEN "SuppliedCode" IN (SELECT code FROM AllCodes WHERE concept='acb2') THEN 'ACB2'
        WHEN "SuppliedCode" IN (SELECT code FROM AllCodes WHERE concept='acb3') THEN 'ACB3'
    END AS "MedicationGroup",
    '' AS "Medication"
FROM LH003_Medication_Codes
WHERE MedicationDate >= '2006-01-01'
UNION
SELECT GmPseudo, TO_DATE("MedicationDate") AS "MedicationDate", 
    CASE
        WHEN "Field_ID" = 'BENZODRUG_COD' THEN 'Benzodiazipine related'
        WHEN "Field_ID" = 'ANTIPSYDRUG_COD' THEN 'Antipsychotic'
    END AS "MedicationCategory",
		-- to get the medication the quickest way is to just split the description by ' ' and take the first part
    split_part(
        regexp_replace( -- this replace removes characters at the start e.g. "~DRUGNAME"
            regexp_replace( -- this replace removes certain trailing characters
								-- to lower case so that CAPITAL and capital come out the same
                lower("MedicationDescription"), '[_,\.\\(0-9]', ' ' 
            ), 
            '[\*\\]~\\[]',
            ''
        ), 
    ' ', 1) AS "Medication"
FROM LH003_Cohort cohort
LEFT OUTER JOIN INTERMEDIATE.GP_RECORD."MedicationsClusters" meds 
    ON meds."FK_Patient_ID" = cohort.FK_Patient_ID
WHERE "Field_ID" IN ('ANTIPSYDRUG_COD','BENZODRUG_COD')
AND TO_DATE("MedicationDate") >= '2006-01-01';