USE SCHEMA SDE_REPOSITORY.SHARED_UTILITIES;

--┌────────────────────────────────────┐
--│ LH001 GP Contact Proxy             │
--└────────────────────────────────────┘

set(StudyStartDate) = to_date('2018-01-01');
set(StudyEndDate)   = to_date('2024-06-30');

-- find all GP contacts for the pharmacogenetic patients and the matched cohort

SELECT
    "GmPseudo" -- NEEDS PSEUDONYMISING
    , "EventDate" as "GPProxyEncounterDate"
FROM PRESENTATION.GP_RECORD."Contacts_Proxy_Detail_SecondaryUses"
WHERE "Contact" = 1 
	AND "GmPseudo" IN (SELECT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_01_Newman")
	AND "EventDate" BETWEEN $StudyStartDate AND $StudyEndDate;


