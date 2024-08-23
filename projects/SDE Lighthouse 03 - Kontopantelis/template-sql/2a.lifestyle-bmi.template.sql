--┌──────────────────────────────────────────┐
--│ SDE Lighthouse study 03 - Kontopantelis  │
--└──────────────────────────────────────────┘

-- From application:
--	Table 2: Lifestyle factors (from 2006 to present)
--		- PatientID
--		- TestName ( smoking status, BMI, alcohol consumption)
--		- TestDate
--		- TestResult
--		- TestUnit

DROP TABLE IF EXISTS {{project-schema}}."2a_Lifestyl_BMI";
CREATE TABLE {{project-schema}}."2a_Lifestyl_BMI" AS
SELECT 
  "GmPseudo" AS PatientID,
	"EventDate" AS TestDate,
	"BMI" AS TestResult
FROM INTERMEDIATE.GP_RECORD."Readings_BMI"
WHERE "GmPseudo" IN (SELECT GmPseudo FROM {{cohort-table}})
AND YEAR("EventDate") >= 2006;