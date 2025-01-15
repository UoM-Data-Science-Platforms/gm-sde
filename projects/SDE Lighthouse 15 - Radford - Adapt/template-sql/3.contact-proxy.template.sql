--┌────────────────────────────────────┐
--│ LH015 GP Contact Proxy             │
--└────────────────────────────────────┘

set(StudyStartDate) = to_date('2015-03-01');
set(StudyEndDate)   = to_date('2024-10-31');

-- find all GP contacts for the adapt patients and the matched cohort

{{create-output-table::"LH015-3_ContactProxy"}}
SELECT
    "GmPseudo"
    , "EventDate" as "GPProxyEncounterDate"
FROM PRESENTATION.GP_RECORD."Contacts_Proxy_Detail_SecondaryUses"
WHERE "Contact" = 1 
	AND "GmPseudo" IN (SELECT "GmPseudo" FROM {{cohort-table}})
	AND "EventDate" BETWEEN $StudyStartDate AND $StudyEndDate;


