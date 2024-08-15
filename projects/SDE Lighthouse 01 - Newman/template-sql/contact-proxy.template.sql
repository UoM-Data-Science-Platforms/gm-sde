--┌────────────────────────────────────┐
--│ LH001 GP Contact Proxy             │
--└────────────────────────────────────┘

USE PRESENTATION.GP_RECORD;

set(StudyStartDate) = to_date('2018-01-01');
set(StudyEndDate)   = to_date('2024-06-30');

--> EXECUTE query-build-lh001-cohort.sql

---- find the latest snapshot for each spell, to get all virtual ward patients
drop table if exists virtualWards;
create temporary table virtualWards as
select  
	distinct SUBSTRING(vw."Pseudo NHS Number", 2)::INT as "GmPseudo"
from PRESENTATION.LOCAL_FLOWS_VIRTUAL_WARDS.VIRTUAL_WARD_OCCUPANCY vw
where TO_DATE(vw."Admission Date") BETWEEN $StudyStartDate AND $StudyEndDate;

-- find all GP contacts for virtual ward cohort

SELECT
    "GmPseudo"
    , "FK_Patient_ID"
    , "EventDate" as "GPProxyEncounterDate"
FROM PRESENTATION.GP_RECORD."Contacts_Proxy_Detail_SecondaryUses"
WHERE "GmPseudo" IN (SELECT "GmPseudo" FROM virtualWards)
AND "EventDate" BETWEEN $StudyStartDate AND $StudyEndDate;


