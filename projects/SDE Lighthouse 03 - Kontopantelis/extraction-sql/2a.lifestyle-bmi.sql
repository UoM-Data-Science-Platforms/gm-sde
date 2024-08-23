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

DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."2a_Lifestyl_BMI";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."2a_Lifestyl_BMI" AS
SELECT 
  "GmPseudo" AS PatientID,
	"EventDate" AS TestDate,
	"BMI" AS TestResult
FROM INTERMEDIATE.GP_RECORD."Readings_BMI"
WHERE "GmPseudo" IN (SELECT GmPseudo FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_03_Kontopantelis")
AND YEAR("EventDate") >= 2006;