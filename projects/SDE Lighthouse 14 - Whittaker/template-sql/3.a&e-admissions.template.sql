--┌──────────────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 14 - Whittaker - A&E Encounters         │
--└──────────────────────────────────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK ---------
-- Richard Williams	2024-08-09	Review complete

-- Date range: 2018 to present

set(StudyStartDate) = to_date('2018-01-01');
set(StudyEndDate)   = to_date('2024-11-31');

-- get all a&e admissions for the virtual ward cohort

{{create-output-table::"LH014-3_AEAdmissions"}}
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
WHERE "IsAttendance" = 1 -- advised to use this for A&E attendances -- contact Dan Young if more info needed (daniel.young1@nhs.net)
	AND "GmPseudo" IN (select "GmPseudo" from {{cohort-table}})
	AND TO_DATE(E."ArrivalDate") BETWEEN $StudyStartDate AND $StudyEndDate;

-- 152.9k admissions
-- 19,681 patients