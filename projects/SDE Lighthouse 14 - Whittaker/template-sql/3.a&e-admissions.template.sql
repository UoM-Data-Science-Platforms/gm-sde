--┌──────────────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 14 - Whittaker - A&E Encounters         │
--└──────────────────────────────────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK ---------
-- Richard Williams	2024-08-09	Review complete

-- Date range: 2018 to present

set(StudyStartDate) = to_date('2018-01-01');
set(StudyEndDate)   = to_date('2024-06-30');

-- get all a&e admissions for the virtual ward cohort

DROP TABLE IF EXISTS {{project-schema}}."3_AEAdmissions";
CREATE TABLE {{project-schema}}."3_AEAdmissions" AS
SELECT 
E."GmPseudo",  -- NEEDS PSEUDONYMISING
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
WHERE "IsAttendance" = 1 -- advised to use this for A&E attendances
	AND "GmPseudo" IN (select "GmPseudo" from {{cohort-table}})
	AND TO_DATE(E."ArrivalDate") BETWEEN $StudyStartDate AND $StudyEndDate;