--┌────────────────────────────────────┐
--│ LH014 GP Contact Proxy             │
--└────────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK ---------
-- Richard Williams	2024-08-09	Review complete

set(StudyStartDate) = to_date('2018-01-01');
set(StudyEndDate)   = to_date('2024-06-30');

-- find all GP contacts for virtual ward cohort

DROP TABLE IF EXISTS {{project-schema}}."4_ContactProxy";
CREATE TABLE {{project-schema}}."4_ContactProxy" AS
SELECT
    "GmPseudo" -- NEEDS PSEUDONYMISING
    , "EventDate" as "GPProxyEncounterDate"
FROM PRESENTATION.GP_RECORD."Contacts_Proxy_Detail_SecondaryUses"
WHERE "GmPseudo" IN (select "GmPseudo" from {{cohort-table}})
AND "Contact" = 1
AND "EventDate" BETWEEN $StudyStartDate AND $StudyEndDate;
