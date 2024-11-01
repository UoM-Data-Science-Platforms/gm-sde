--┌──────────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 06 - Chen - adverse events          │
--└──────────────────────────────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK ------------
-- Richard Williams	2024-08-30	Review complete --
--------------------------------------------------

set(StudyStartDate) = to_date('2017-01-01');
set(StudyEndDate)   = to_date('2024-10-31');

{{create-output-table::"LH006-3_AdverseEvents"}}
SELECT 
    co."GmPseudo"
    , TO_DATE(ec."Date") AS "MedicationDate"
    , ec."SCTID" AS "SnomedCode"
    , CASE WHEN ec."Cluster_ID" = 'eFI2_Fracture' THEN 'fracture' -- fracture
           WHEN ec."Cluster_ID" = 'eFI2_SelfHarm' THEN 'self-harm' -- self harm
           ELSE 'other' END AS "CodeSet"
    , ec."Term" AS "Description"
FROM {{cohort-table}} co
LEFT JOIN INTERMEDIATE.GP_RECORD."Combined_EventsMedications_Clusters_SecondaryUses" ec ON co."FK_Patient_ID" = ec."FK_Patient_ID"
WHERE "Cluster_ID" in ('eFI2_Fracture', 'eFI2_SelfHarm')
    AND TO_DATE(ec."Date") BETWEEN $StudyStartDate and $StudyEndDate;
