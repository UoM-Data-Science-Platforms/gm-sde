--┌──────────────────────────────────────────┐
--│ SDE Lighthouse study 03 - Kontopantelis  │
--└──────────────────────────────────────────┘

--> EXECUTE query-build-lh003-cohort.sql

SELECT 
  "GmPseudo" AS PatientID,
	"EventDate" AS TestDate,
	"BMI" AS TestResult
FROM INTERMEDIATE.GP_RECORD."Readings_BMI"
WHERE "GmPseudo" IN (SELECT GmPseudo FROM LH003_Cohort);