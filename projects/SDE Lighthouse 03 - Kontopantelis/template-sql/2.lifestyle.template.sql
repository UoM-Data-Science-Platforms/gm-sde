--┌──────────────────────────────────────────┐
--│ SDE Lighthouse study 03 - Kontopantelis  │
--└──────────────────────────────────────────┘

--> EXECUTE query-build-lh003-cohort.sql

SELECT
	"GmPseudo" AS PatientID,
	'Alcohol' AS TestName,
	"EventDate" AS TestDate,
	"Term" AS Description,
	"Value" AS TestResult,
	"Units" AS TestUnits,
	"AlcoholStatus" AS Status,
	"AlcoholConsumption" AS Consumption
FROM INTERMEDIATE.GP_RECORD."Readings_Alcohol"
WHERE "GmPseudo" IN (1763539,2926922,182597,1244665,3134799,1544463,5678816,169030,7015182,7089792)
UNION
SELECT
	"GmPseudo" AS PatientID,
	'Smoking' AS TestName,
	"SmokingStatus_Date" AS EventDate,
	NULL AS Description,
	NULL AS TestResult,
	NULL AS TestUnits,
	"SmokingStatus" AS Status, 
	CASE
		WHEN "SmokingConsumption_Date" = "SmokingStatus_Date" THEN "SmokingConsumption"
		ELSE NULL
	END AS Consumption
FROM INTERMEDIATE.GP_RECORD."Readings_Smoking"
WHERE "GmPseudo" IN (1763539,2926922,182597,1244665,3134799,1544463,5678816,169030,7015182,7089792)
UNION
SELECT 
  "GmPseudo" AS PatientID,
	'BMI' AS TestName,
	"EventDate" AS TestDate,
	NULL AS Description,
	"BMI" AS TestResult,
	NULL AS TestUnits,
	"BMI_Description" AS Status, 
	NULL AS Consumption
FROM INTERMEDIATE.GP_RECORD."Readings_BMI"
WHERE "GmPseudo" IN (1763539,2926922,182597,1244665,3134799,1544463,5678816,169030,7015182,7089792)