USE SCHEMA SDE_REPOSITORY.SHARED_UTILITIES;

--┌────────────────────────────────────┐
--│ LH014 GP Contact Proxy             │
--└────────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK ---------
-- Richard Williams	2024-08-09	Review complete

set(StudyStartDate) = to_date('2018-01-01');
set(StudyEndDate)   = to_date('2024-06-30');

-- find all GP contacts for virtual ward cohort

DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."4_ContactProxy";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."4_ContactProxy" AS
SELECT
    "GmPseudo" -- NEEDS PSEUDONYMISING
    , "EventDate" as "GPProxyEncounterDate"
FROM PRESENTATION.GP_RECORD."Contacts_Proxy_Detail_SecondaryUses"
WHERE "GmPseudo" IN (select "GmPseudo" from SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_14_Whittaker")
AND "Contact" = 1
AND "EventDate" BETWEEN $StudyStartDate AND $StudyEndDate;
