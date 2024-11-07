--┌─────────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 09 - Thompson - referrals          │
--└─────────────────────────────────────────────────────────┘

-- referrals to gynaecology services, cancer services
-- could not find codes for fertility or women's health referrals

-------- RESEARCH DATA ENGINEER CHECK ------------
--------------------------------------------------

set(StudyStartDate) = to_date('2020-01-01');
set(StudyEndDate)   = to_date('2024-10-31');

{{create-output-table::"LH009-8_Referrals"}}
SELECT DISTINCT
    co."GmPseudo"
    , TO_DATE(ec."Date") AS "Date"
    , ec."SCTID" AS "SnomedCode"
    , ec."Term" AS "Description"
FROM {{cohort-table}} co
LEFT JOIN INTERMEDIATE.GP_RECORD."Combined_EventsMedications_Clusters_SecondaryUses" ec ON co."FK_Patient_ID" = ec."FK_Patient_ID"
WHERE "Cluster_ID" = 'REFERRAL_COD'
	AND (SCTID IN 
		-- gynaecology referral
		('183549000', '183886008', '249011000000106', '306133003',
		'905011000006110', '718550001', '900941000000107', 
		'904991000006117', '785781000000101', '700125004',
		-- sexual healh and contraception service referral
		'892041000000100')
		-- cancer referrals
		OR UPPER(ec."Term") like '%CANCER%'
		)
    AND TO_DATE(ec."Date") BETWEEN $StudyStartDate and $StudyEndDate;
