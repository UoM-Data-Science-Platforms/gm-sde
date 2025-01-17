--┌──────────────────────────────────────────┐
--│ SDE Lighthouse study 03 - Kontopantelis  │
--└──────────────────────────────────────────┘

-- From application:
--	Table 2: Lifestyle factors (from 2006 to present)
--		- PatientID
--		- TestName ( Alcohol, Smoking)
--		- TestDate
--		- Description
--		- TestResult
--		- TestUnits
--		- Status
--		- Consumption

-- NB1 - I'm only restricting BMI values to 2006 to present.
-- NB2 - The PI confirmed that instead of raw values of when statuses were
--			 recorded, they are happy with the information as currently used
--			 within the tables below.


set(StudyStartDate) = to_date('2006-01-01');
set(StudyEndDate)   = to_date('2024-10-31');


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
FROM INTERMEDIATE.GP_RECORD."Readings_Alcohol_SecondaryUses"
WHERE "GmPseudo" IN (SELECT "GmPseudo" FROM {{cohort-table}}) AND "EventDate" BETWEEN $StudyStartDate AND $StudyEndDate
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
FROM INTERMEDIATE.GP_RECORD."Readings_Smoking_SecondaryUses"
WHERE "GmPseudo" IN (SELECT "GmPseudo" FROM {{cohort-table}}) AND "SmokingStatus_Date" BETWEEN $StudyStartDate AND $StudyEndDate;