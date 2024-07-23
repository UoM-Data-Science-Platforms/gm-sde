--┌──────────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 06 - Chen - adverse events          │
--└──────────────────────────────────────────────────────────┘

-- events: self-harm, fracture

set(StudyStartDate) = to_date('2017-01-01');
set(StudyEndDate)   = to_date('2023-12-31');

--> EXECUTE query-build-lh006-cohort.sql

select ec."FK_Patient_ID",
    TO_DATE(ec."EventDate") AS "EventDate",
    ec."Cluster_ID",
    ec."SuppliedCode",
    ec."Term"
from INTERMEDIATE.GP_RECORD."EventsClusters" ec
WHERE "Cluster_ID" in 
    ('eFI2_Fracture',
     'eFI2_SelfHarm',
     'SELFHARM_COD')
AND TO_DATE(ec."EventDate") BETWEEN $StudyStartDate AND $StudyEndDate
AND "FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM Cohort)