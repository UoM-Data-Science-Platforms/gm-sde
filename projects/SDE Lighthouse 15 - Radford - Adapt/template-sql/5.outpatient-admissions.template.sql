--┌────────────────────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 15 - Radford - Outpatient hospital encounters │
--└────────────────────────────────────────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK ------------

--------------------------------------------------

set(StudyStartDate) = to_date('2019-01-01');
set(StudyEndDate)   = to_date('2024-10-31');

-- get all outpatient admissions

{{create-output-table::"LH015-5_OutpatientAdmissions"}}
SELECT 
    ROW_NUMBER() OVER (ORDER BY "Pseudo NHS Number","Appointment Date Time") AS "AppointmentID"	
	, SUBSTRING("Pseudo NHS Number", 2)::INT AS "GmPseudo" 
    , TO_DATE("Appointment Date Time") AS "AppointmentDate"
	, "Priority Type Code"
	, "Priority Type Desc"
	, "Main Specialty Code"
	, "Main Specialty Desc"
	, "Treatment Function Code"
	, "Treatment Function Desc"
	, "Operation Status Code"
	, "Operation Status Desc"
	, "Outcome Of Attendance Code"
	, "Outcome Of Attendance Desc"
FROM PRESENTATION.NATIONAL_FLOWS_OPA."DS709_Outpatients" ap
WHERE "AppointmentDate" BETWEEN $StudyStartDate AND $StudyEndDate
	AND SUBSTRING("Pseudo NHS Number", 2)::INT IN (SELECT "GmPseudo" FROM {{cohort-table}})
	AND "Attended Or Did Not Attend Code" = 5; -- attended 

