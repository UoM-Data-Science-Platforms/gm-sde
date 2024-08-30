--┌────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 06 - Chen - referrals         │
--└────────────────────────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK ------------
-- Richard Williams	2024-08-30	Review complete --
--------------------------------------------------

set(StudyStartDate) = to_date('2017-01-01');
set(StudyEndDate)   = to_date('2023-12-31');

{{create-output-table::"6_Referrals"::"GmPseudo"}}
SELECT 
    co."GmPseudo" -- NEEDS PSEUDONYMISING
    , TO_DATE(ec."EventDate") AS "MedicationDate"
    , ec."SCTID" AS "SnomedCode"
    , CASE WHEN ec."Cluster_ID" = 'SOCPRESREF_COD' THEN 'social prescribing referral'
			WHEN ("Cluster_ID" in ('REFERRAL_COD') AND lower("Term") LIKE '%physiotherap%') THEN 'physiotherapy-referral'
			WHEN ("Cluster_ID" in ('REFERRAL_COD') AND lower("Term") LIKE '%psych%') THEN 'psychological-therapy-referral'
			WHEN ("Cluster_ID" in ('REFERRAL_COD') AND lower("Term") LIKE '%acupun%') THEN 'acupuncture-referral'
			WHEN ("Cluster_ID" in ('REFERRAL_COD') AND lower("Term") LIKE '%pain%') THEN 'pain-related-referral' 
			WHEN ("Cluster_ID" in ('REFERRAL_COD') AND (lower("Term") like '%surgeon%' or lower("Term") like '%surgery%' or lower("Term") like '%surgical%' )) THEN 'surgery-referral' 
           ELSE 'other' END AS "CodeSet"
    , ec."Term" AS "Description"
FROM {{cohort-table}} co 
LEFT OUTER JOIN INTERMEDIATE.GP_RECORD."EventsClusters" ec ON ec."FK_Patient_ID" = co."FK_Patient_ID"
WHERE 
	(
    ("Cluster_ID" in ('SOCPRESREF_COD')) OR-- social prescribing referral
	("Cluster_ID" in ('REFERRAL_COD') AND lower("Term") LIKE '%physiotherap%') OR -- physiotherapy referral
	("Cluster_ID" in ('REFERRAL_COD') AND lower("Term") LIKE '%psych%') OR -- psychological therapy referral
	("Cluster_ID" in ('REFERRAL_COD') AND lower("Term") LIKE '%acupun%') OR -- acupuncture referral 
	("Cluster_ID" in ('REFERRAL_COD') AND lower("Term") LIKE '%pain%') OR -- pain-related  referral  
	("Cluster_ID" in ('REFERRAL_COD') AND (lower("Term") like '%surgeon%' or lower("Term") like '%surgery%' or lower("Term") like '%surgical%' )) -- surgery referral 
    )
AND TO_DATE(ec."EventDate") BETWEEN $StudyStartDate and $StudyEndDate;