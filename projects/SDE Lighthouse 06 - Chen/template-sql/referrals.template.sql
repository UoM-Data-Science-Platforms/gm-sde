--┌────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 06 - Chen - referrals         │
--└────────────────────────────────────────────────────┘

--> EXECUTE query-build-lh006-cohort.sql

--> CODESET acute-pain-service:1 social-care-prescribing:1 pain-management:1 surgery:1


DROP TABLE IF EXISTS Prescriptions;
CREATE TEMPORARY TABLE Prescriptions AS
SELECT 
	gp."FK_Patient_ID", 
	TO_DATE("EventDate") AS "EventDate", 
	"SuppliedCode"
FROM INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" gp
INNER JOIN VersionedCodeSets vcs ON vcs.FK_Reference_Coding_ID = gp."FK_Reference_Coding_ID" AND vcs.Version =1
INNER JOIN VersionedSnomedSets vss ON vss.FK_Reference_SnomedCT_ID = gp."FK_Reference_SnomedCT_ID" AND vss.Version =1
WHERE 
GP."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM Cohort) AND
vcs.Concept not in ('chronic-pain', 'opioids', 'cancer') AND
gp."EventDate" BETWEEN $StudyStartDate and $StudyEndDate;    -- only looking at referrals in the study period

