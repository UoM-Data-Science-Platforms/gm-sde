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

-- NB1 - I'm only restricting BMI values to 2006 to present.
-- NB2 - The PI confirmed that instead of raw values of when statuses were
--			 recorded, they are happy with the information as currently used
--			 within the tables below.

{{create-output-table::"LH003-2b_Lifestyle_Alcohol_Smoking"}}
SELECT
	"GmPseudo",
	'Alcohol' AS "TestName",
	"EventDate" AS "TestDate",
	"Term" AS "Description",
	"Value" AS "TestResult",
	"Units" AS "TestUnits",
	"AlcoholStatus" AS "Status",
	"AlcoholConsumption" AS "Consumption"
FROM INTERMEDIATE.GP_RECORD."Readings_Alcohol"
WHERE "GmPseudo" IN (SELECT "GmPseudo" FROM {{cohort-table}})
UNION
SELECT
	"GmPseudo",
	'Smoking',	-- "TestName",
	"SmokingStatus_Date",	-- "TestDate",
	NULL, -- "Description",
	NULL, -- "TestResult",
	NULL, -- "TestUnits",
	"SmokingStatus", 	-- "Status",
	CASE
		WHEN "SmokingConsumption_Date" = "SmokingStatus_Date" THEN "SmokingConsumption"
		ELSE NULL
	END -- "Consumption"
FROM INTERMEDIATE.GP_RECORD."Readings_Smoking"
WHERE "GmPseudo" IN (SELECT "GmPseudo" FROM {{cohort-table}});