--┌──────────────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 14 - Whittaker - A&E Encounters         │
--└──────────────────────────────────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK ---------
-- Richard Williams	2024-08-09	Review complete

USE PRESENTATION.LOCAL_FLOWS_VIRTUAL_WARDS;

-- Date range: 2018 to present

set(StudyStartDate) = to_date('2018-01-01');
set(StudyEndDate)   = to_date('2024-06-30');

---- find the latest snapshot for each spell, to get all virtual ward patients in the study period

drop table if exists virtualWards;
create temporary table virtualWards as
select  
	distinct SUBSTRING(vw."Pseudo NHS Number", 2)::INT as "GmPseudo"
from PRESENTATION.LOCAL_FLOWS_VIRTUAL_WARDS.VIRTUAL_WARD_OCCUPANCY vw
where TO_DATE(vw."Admission Date") BETWEEN $StudyStartDate AND $StudyEndDate;

-- get all a&e admissions for the virtual ward cohort

SELECT 
E."GmPseudo", 
TO_DATE(E."ArrivalDate") AS "ArrivalDate",
TO_DATE(E."EcDepartureDate") AS "DepartureDate",
E."EcDuration" AS LOS_Mins,
E."EcChiefComplaintSnomedCtCode" AS ChiefComplaintCode,
E."EcChiefComplaintSnomedCtDesc" AS ChiefComplaintDesc,
E."EmAttendanceCategoryCode",
E."EmAttendanceCategoryDesc", 
E."EmAttendanceDisposalCode",
E."EmAttendanceDisposalDesc"
FROM PRESENTATION.NATIONAL_FLOWS_ECDS."DS707_Ecds" E
WHERE "IsAttendance" = 1
	AND "GmPseudo" IN (SELECT "GmPseudo" FROM virtualWards)
	AND TO_DATE(E."ArrivalDate") BETWEEN $StudyStartDate AND $StudyEndDate;