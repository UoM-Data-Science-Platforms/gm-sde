--┌─────────────┐
--│ Medications │
--└─────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------
-- 
------------------------------------------------------

-- In the request this is in 3 files, but the PI has confirmed that a single long file
-- with columns PatientID, Date, MedicationCategory, Medication, Dose, Units is fine.
-- Medications to includes are : Prednisolone, MycophenolateMofetil, Azathioprine, 
-- Tacrolimus, Methotrexate, Ciclosporin, HydroxychloroquineOrChloroquine, Belimumab, 
-- ACEInhibitorOrARB*, SGLT2Inhibitor*, AntiplateletDrug*, Statin*, Anticoagulant*,
-- Cyclophosphamide and Rituximab

-- Medication categories such as "antiplatelet" should give the actual drug within that
-- category


--Just want the output, not the messages
SET NOCOUNT ON;

--> EXECUTE query-build-lh004-cohort.sql

SELECT "FK_Patient_ID", "MedicationDate",
    CASE 
        WHEN "Field_ID" IN ('SAL_COD','NONASPANTIPLTDRUG_COD') THEN 'Antiplatelet'
        WHEN "Field_ID" IN ('Immunosuppression_Drugs') THEN 'Immunosuppression'
        WHEN "Field_ID" IN ('ACEInhibitor','ARB') THEN 'ACEInhibitorOrARB'
        WHEN "Field_ID" IN ('SGLT2') THEN 'SGLT2Inhibitor'
        WHEN "Field_ID" IN ('DOAC','Warfarin','ORANTICOAGDRUG_COD') THEN 'Anticoagulant'
        ELSE "Field_ID"
    END AS MedicationCategory, 
    SPLIT_PART(LOWER("MedicationDescription"), ' ',0) AS Medication, "Dosage_GP_Medications", "Quantity", "Units"
FROM GP_RECORD."MedicationsClusters"
WHERE "Field_ID" IN ('Immunosuppression_Drugs', 'Prednisolone', 'ACEInhibitor','SGLT2','SAL_COD','NONASPANTIPLTDRUG_COD','Statin','DOAC','Warfarin','ORANTICOAGDRUG_COD','ARB');
UNION
SELECT 
    "FK_Patient_ID", 
    "MedicationDate", 
    'HydroxychloroquineOrChloroquine' AS MedicationCategory, 
    'hydroxychloroquine' AS Medication,
    "Dosage",
    "Quantity",
    "Units"
FROM GP_RECORD."GP_Medications_SecondaryUses"
WHERE "SuppliedCode" IN ()
UNION
SELECT 
    "FK_Patient_ID", 
    "MedicationDate", 
    'HydroxychloroquineOrChloroquine' AS MedicationCategory, 
    'chloroquine' AS Medication,
    "Dosage",
    "Quantity",
    "Units"
FROM GP_RECORD."GP_Medications_SecondaryUses"
WHERE "SuppliedCode" IN ();


