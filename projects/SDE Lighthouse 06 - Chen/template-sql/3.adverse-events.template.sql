--┌──────────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 06 - Chen - adverse events          │
--└──────────────────────────────────────────────────────────┘

-- NOTE: the SDE does have self harm and fracture code sets (eFI2_SelfHarm and eFI2_Fracture)
-- but our GMCR code sets seem more comprehensive

set(StudyStartDate) = to_date('2017-01-01');
set(StudyEndDate)   = to_date('2023-12-31');

--> CODESET selfharm-episodes:1 fracture:1

DROP TABLE IF EXISTS {{project-schema}}."3_AdverseEvents";
CREATE TABLE {{project-schema}}."3_AdverseEvents" AS
SELECT DISTINCT
	cohort."GmPseudo",  -- NEEDS PSEUDONYMISING
	to_date("EventDate") as "EventDate",
	cs.concept AS "Concept",
	"SuppliedCode", 
	"Term" AS "Description"
FROM {{cohort-table}} cohort
LEFT OUTER JOIN INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" events ON events."FK_Patient_ID" = cohort."FK_Patient_ID"
LEFT OUTER JOIN {{code-set-table}} cs ON cs.code = events."SuppliedCode" 
WHERE cs.concept IN ('selfharm-episodes', 'fracture')
	AND TO_DATE(events."EventDate") BETWEEN $StudyStartDate AND $StudyEndDate;
