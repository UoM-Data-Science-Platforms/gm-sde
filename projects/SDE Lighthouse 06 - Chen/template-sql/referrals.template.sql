--┌────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 06 - Chen - referrals         │
--└────────────────────────────────────────────────────┘

--> EXECUTE query-build-lh006-cohort.sql

--> CODESET social-care-prescribing-referral:1 surgery-referral:1

-- ** NEED TO ADD THE BELOW CODE SETS ONCE THEY HAVE BEEN FINALISED
-- acute-pain-service:1 pain-management:1 
/*
SELECT 
	gp."FK_Patient_ID", 
	TO_DATE("EventDate") AS "EventDate", 
	"SuppliedCode",
    "Term",
    CASE WHEN vcs.Concept is not null then vcs.Concept else vss.Concept end as Concept
FROM INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" gp
INNER JOIN VersionedCodeSets vcs ON vcs.FK_Reference_Coding_ID = gp."FK_Reference_Coding_ID" AND vcs.Version =1
INNER JOIN VersionedSnomedSets vss ON vss.FK_Reference_SnomedCT_ID = gp."FK_Reference_SnomedCT_ID" AND vss.Version =1
WHERE 
GP."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM Cohort) AND
vcs.Concept in ('social-care-prescribing-referral', 'surgery-referral') AND
gp."EventDate" BETWEEN $StudyStartDate and $StudyEndDate;    -- only looking at referrals in the study period
*/

DROP TABLE IF EXISTS referrals;
CREATE TEMPORARY TABLE referrals AS
SELECT 
    ec."FK_Patient_ID"
    , TO_DATE(ec."MedicationDate") AS "MedicationDate"
    , ec."SCTID" AS "SnomedCode"
    , ec."Units"
    , ec."Dosage"
    , ec."Dosage_GP_Medications"
    , CASE WHEN ec."Cluster_ID" = 'SOCPRESREF_COD' THEN 'social prescribing referral'
           ELSE 'other' END AS "CodeSet"
    , ec."MedicationDescription" AS "Description"
FROM INTERMEDIATE.GP_RECORD."MedicationsClusters" ec
WHERE "Cluster_ID" in ('SOCPRESREF_COD')
    AND TO_DATE(ec."MedicationDate") BETWEEN $StudyStartDate and $StudyEndDate
    AND ec."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM Cohort);


