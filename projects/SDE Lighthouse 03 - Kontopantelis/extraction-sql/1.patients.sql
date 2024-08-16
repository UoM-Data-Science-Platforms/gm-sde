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

USE INTERMEDIATE.GP_RECORD;

DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_03_Kontopantelis";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_03_Kontopantelis" (
	GmPseudo NUMBER(38,0),
	FK_Patient_ID NUMBER(38,0),
	FirstDementiaDate DATE
) AS
SELECT "GmPseudo", "FK_Patient_ID", MIN("Dementia_DiagnosisDate") AS FirstDementiaDate
FROM PRESENTATION.GP_RECORD."LongTermConditionRegister_SecondaryUses"
WHERE "Dementia_DiagnosisDate" IS NOT NULL
AND "Age" >= 18
GROUP BY "GmPseudo", "FK_Patient_ID";

SELECT 
	cohort.GmPseudo AS PatientID,
	"Sex",
	YEAR("DateOfBirth") AS YearOfBirth,
	"EthnicityLatest" AS Ethnicity,
	"EthnicityLatest_Category" AS EthnicityCategory,
	"IMD_Decile" AS IMD2019Decile1IsMostDeprived10IsLeastDeprived,
	"RegisteredDateOfDeath"
FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_03_Kontopantelis" cohort
LEFT OUTER JOIN PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" demo
	ON demo."GmPseudo" = cohort.GmPseudo
LEFT OUTER JOIN PRESENTATION.NATIONAL_FLOWS_PCMD."DS1804_Pcmd" mortality
	ON mortality."GmPseudo" = cohort.GmPseudo
QUALIFY row_number() OVER (PARTITION BY demo."GmPseudo" ORDER BY "Snapshot" DESC) = 1;