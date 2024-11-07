
--┌─────────────────────────────────────┐
--│ Define Cohort for LH015: gp events  │
--└─────────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK ------------

--------------------------------------------------

-- OBJECTIVE: To provide all GP events, except any sensitive codes, for the studuy cohort and matched controls

set(StudyStartDate) = to_date('2015-03-01');
set(StudyEndDate)   = to_date('2022-03-31');

-- SELECT ALL GP EVENTS 

{{create-output-table::"LH015-6_OutpatientAdmissions"}}
SELECT c."GmPseudo" 
	"EventDate", 
	"SCTID", 
	"SuppliedCode", 
	"Term", 
	"Value", 
	"Units"
FROM INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" gp  
INNER JOIN {{cohort-table}} c ON c."FK_Patient_ID" = gp."FK_Patient_ID"
WHERE "EventDate" BETWEEN $StudyStartDate and $StudyEndDate;

-- TODO : exclude sensitive codes (Andy Holden has list)