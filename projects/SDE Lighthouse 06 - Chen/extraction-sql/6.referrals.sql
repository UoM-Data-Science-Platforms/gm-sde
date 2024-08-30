USE SCHEMA SDE_REPOSITORY.SHARED_UTILITIES;

--┌────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 06 - Chen - referrals         │
--└────────────────────────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK ------------
-- Richard Williams	2024-08-30	Review complete --
--------------------------------------------------

set(StudyStartDate) = to_date('2017-01-01');
set(StudyEndDate)   = to_date('2023-12-31');


-- First we create a table in an area only visible to the RDEs which contains
-- the GmPseudo or FK_Patient_IDs. These cannot be released to end users.
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."6_Referrals_WITH_PSEUDO_IDS";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."6_Referrals_WITH_PSEUDO_IDS" AS
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
FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_06_Chen" co 
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

-- Then we select from that table, to populate the table for the end users
-- where the GmPseudo or FK_Patient_ID fields are redacted via a function
-- created in the 0.code-sets.sql
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."6_Referrals";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."6_Referrals" AS
SELECT SDE_REPOSITORY.SHARED_UTILITIES.gm_pseudo_hash_SDE_Lighthouse_06_Chen("GmPseudo") AS "PatientID", * EXCLUDE "GmPseudo"
FROM SDE_REPOSITORY.SHARED_UTILITIES."6_Referrals_WITH_PSEUDO_IDS";