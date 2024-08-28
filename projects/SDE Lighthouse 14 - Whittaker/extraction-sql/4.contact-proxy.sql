--┌────────────────────────────────────┐
--│ LH014 GP Contact Proxy             │
--└────────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK ---------
-- Richard Williams	2024-08-09	Review complete

USE PRESENTATION.LOCAL_FLOWS_VIRTUAL_WARDS;

set(StudyStartDate) = to_date('2018-01-01');
set(StudyEndDate)   = to_date('2024-06-30');

---- find the latest snapshot for each spell, to get all virtual ward patients
/*
drop table if exists virtualWards;
create temporary table virtualWards as
select  
	distinct SUBSTRING(vw."Pseudo NHS Number", 2)::INT as "GmPseudo"
from PRESENTATION.LOCAL_FLOWS_VIRTUAL_WARDS.VIRTUAL_WARD_OCCUPANCY vw
where TO_DATE(vw."Admission Date") BETWEEN $StudyStartDate AND $StudyEndDate;
*/

-- find all GP contacts for virtual ward cohort

DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."4_ContactProxy";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."4_ContactProxy" AS
SELECT
    "GmPseudo"
    , "FK_Patient_ID"
    , "EventDate" as "GPProxyEncounterDate"
FROM PRESENTATION.GP_RECORD."Contacts_Proxy_Detail_SecondaryUses"
WHERE "GmPseudo" IN (select "GmPseudo" from SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_14_Whittaker")
AND "Contact" = 1
AND "EventDate" BETWEEN $StudyStartDate AND $StudyEndDate;
