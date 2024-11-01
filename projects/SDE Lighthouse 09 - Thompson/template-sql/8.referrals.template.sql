--┌─────────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 09 - Thompson - referrals          │
--└─────────────────────────────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK ------------
--------------------------------------------------

set(StudyStartDate) = to_date('2020-01-01');
set(StudyEndDate)   = to_date('2024-10-31');

{{create-output-table::"LH009-3_AdverseEvents"}}
SELECT 
    co."GmPseudo"
    , TO_DATE(ec."Date") AS "Date"
    , ec."SCTID" AS "SnomedCode"
    , ec."Term" AS "Description"
FROM {{cohort-table}} co
LEFT JOIN INTERMEDIATE.GP_RECORD."Combined_EventsMedications_Clusters_SecondaryUses" ec ON co."FK_Patient_ID" = ec."FK_Patient_ID"
WHERE "Cluster_ID" = 'REFERRAL_COD'
    AND TO_DATE(ec."Date") BETWEEN $StudyStartDate and $StudyEndDate;
