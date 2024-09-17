--┌──────────────────────────────────────────┐
--│ SDELS03 - Kontopantelis - Demographics   │
--└──────────────────────────────────────────┘

-- From application:
--	Table 1: Patient Demographics
--		- PatientID
--		- Sex
--		- YearOfBirth
--		- Ethnicity
--		- YearAndMonthOfDeath

-- NB1 PI did not request date of dementia diagnosis, but it seems likely
-- that they will need it, so including as well.

-- NB2 Date of death was requested in a separate file, but including it here
-- for brevity, and because it has a 1-2-1 relationship with patient.

DROP TABLE IF EXISTS {{cohort-table}};
CREATE TABLE {{cohort-table}} (
	"GmPseudo" NUMBER(38,0),
	"FK_Patient_ID" NUMBER(38,0),
	"FirstDementiaDate" DATE
) AS
SELECT "GmPseudo", "FK_Patient_ID", MIN("Dementia_DiagnosisDate") AS FirstDementiaDate
FROM PRESENTATION.GP_RECORD."LongTermConditionRegister_SecondaryUses"
WHERE "Dementia_DiagnosisDate" IS NOT NULL
AND "Age" >= 18
GROUP BY "GmPseudo", "FK_Patient_ID";

{{create-output-table::"LH003-1_Patients"}}
SELECT 
	cohort."GmPseudo",
	"Sex",
	YEAR("DateOfBirth") AS "YearOfBirth",
	"EthnicityLatest" AS "Ethnicity",
	"EthnicityLatest_Category" AS "EthnicityCategory",
	"IMD_Decile" AS "IMD2019Decile1IsMostDeprived10IsLeastDeprived",
	"FirstDementiaDate",
	CAST("RegisteredDateOfDeath" AS DATE) AS "RegisteredDateOfDeath"
FROM {{cohort-table}} cohort
LEFT OUTER JOIN PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" demo
	ON demo."GmPseudo" = cohort."GmPseudo"
LEFT OUTER JOIN PRESENTATION.NATIONAL_FLOWS_PCMD."DS1804_Pcmd" mortality
	ON mortality."GmPseudo" = cohort."GmPseudo"
QUALIFY row_number() OVER (PARTITION BY demo."GmPseudo" ORDER BY "Snapshot" DESC) = 1;