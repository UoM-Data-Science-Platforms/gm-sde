--┌─────────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 09 - Thompson - referrals          │
--└─────────────────────────────────────────────────────────┘

-- referrals to gynaecology services, cancer services
-- could not find codes for fertility or women's health referrals

-------- RESEARCH DATA ENGINEER CHECK ------------
--------------------------------------------------

set(StudyStartDate) = to_date('2020-01-01');
set(StudyEndDate)   = to_date('2024-10-31');

-- REFERRALS NOT IN CLUSTERS TABLE

{{create-output-table::"LH009-8_Referrals"}}
SELECT DISTINCT
	co."GmPseudo",
	TO_DATE(gp."EventDate") AS "Date",
	gp."SCTID" AS "SnomedCode",
	gp."Term" AS "Description"
FROM {{cohort-table}} co
LEFT OUTER JOIN intermediate.gp_record."GP_Events_SecondaryUses" gp ON gp."FK_Patient_ID" = co."FK_Patient_ID" 
WHERE "SCTID" = '183862006' -- referral to fertility clinic (not in clusters table)
	AND TO_DATE(gp."EventDate") BETWEEN $StudyStartDate and $StudyEndDate
UNION
SELECT DISTINCT
    co."GmPseudo"
    , TO_DATE(ec."Date") AS "Date"
    , ec."SCTID" AS "SnomedCode"
    , ec."Term" AS "Description"
FROM {{cohort-table}} co
LEFT JOIN INTERMEDIATE.GP_RECORD."Combined_EventsMedications_Clusters_SecondaryUses" ec ON co."FK_Patient_ID" = ec."FK_Patient_ID"
WHERE "Cluster_ID" = 'REFERRAL_COD'
    AND TO_DATE(ec."Date") BETWEEN $StudyStartDate and $StudyEndDate;
