--┌──────────────────────────────────────────┐
--│ SDE Lighthouse study 03 - Kontopantelis  │
--└──────────────────────────────────────────┘

-- From application:
--	Table 2: Lifestyle factors (from 2006 to present)
--		- PatientID
--		- TestDate
--		- TestResult


set(StudyStartDate) = to_date('2006-01-01');
set(StudyEndDate)   = to_date('2024-06-30');


{{create-output-table::"LH003-2a_Lifestyl_BMI"}}
SELECT 
  "GmPseudo",
	"EventDate" AS "TestDate",
	"BMI" AS "TestResult"
FROM INTERMEDIATE.GP_RECORD."Readings_BMI_SecondaryUses"
WHERE "GmPseudo" IN (SELECT "GmPseudo" FROM {{cohort-table}}) AND "EventDate" BETWEEN $StudyStartDate AND $StudyEndDate
AND YEAR("EventDate") >= 2006;