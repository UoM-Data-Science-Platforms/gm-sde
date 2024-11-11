--┌──────────────────────────────────────────┐
--│ SDELS03 - Kontopantelis - Demographics   │
--└──────────────────────────────────────────┘

-- From application:
--	Table 1: Patient Demographics
--		- PatientID
--		- Sex
--		- YearOfBirth
--		- Ethnicity
--		- EthnicityCategory
--		- EIMD2019Decile1IsMostDeprived10IsLeastDeprived
--		- FirstDementiaDate
--		- DeathYearAndMonth

-- NB1 PI did not request date of dementia diagnosis, but it seems likely
-- that they will need it, so including as well.

-- NB2 Date of death was requested in a separate file, but including it here
-- for brevity, and because it has a 1-2-1 relationship with patient.

set(StudyStartDate) = to_date('2006-01-01');
set(StudyEndDate)   = to_date('2024-06-30');

--> EXECUTE query-get-possible-patients.sql minimum-age:18

DROP TABLE IF EXISTS {{cohort-table}};
CREATE TABLE {{cohort-table}} (
	"GmPseudo" NUMBER(38,0),
	"FK_Patient_ID" NUMBER(38,0),
	"FirstDementiaDate" DATE
) AS
SELECT "GmPseudo", "FK_Patient_ID", MIN("Dementia_DiagnosisDate") AS FirstDementiaDate
FROM INTERMEDIATE.GP_RECORD."LongTermConditionRegister_SecondaryUses"
WHERE "Dementia_DiagnosisDate" IS NOT NULL AND "Dementia_DiagnosisDate" BETWEEN $StudyStartDate AND $StudyEndDate
AND "FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM AlivePatientsAtStart)
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
	DATE_TRUNC(month, alive."DeathDate") AS "DeathYearAndMonth"
FROM {{cohort-table}} cohort
LEFT OUTER JOIN AlivePatientsAtStart alive
	ON alive."GmPseudo" = cohort."GmPseudo"
QUALIFY row_number() OVER (PARTITION BY alive."GmPseudo" ORDER BY "Snapshot" DESC) = 1;