--┌──────────────────────────────────────────┐
--│ SDELS03 - Kontopantelis - Demographics   │
--└──────────────────────────────────────────┘

--┌───────────────────────────────────────────────────────────────────┐
--│ Define Cohort for LH003: patients that had a dementia diagnosis   │
--└───────────────────────────────────────────────────────────────────┘

-- OBJECTIVE: To build the cohort of patients needed for LH003. This reduces duplication of code in the template scripts.

-- COHORT: Any patient with a dementia diagnosis between start and end date.

-- INPUT: assumes there exists one temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: Temp tables as follows:
-- #Cohort

DROP TABLE IF EXISTS LH003_Cohort;
CREATE TEMPORARY TABLE LH003_Cohort (GmPseudo NUMBER(38,0), FirstDementiaDate DATE);
INSERT INTO LH003_Cohort VALUES 
(1763539,'2020-06-06'),(2926922,'2020-06-06'),(182597,'2020-06-06'),(1244665,'2020-06-06'),
(3134799,'2020-06-06'),(1544463,'2020-06-06'),(5678816,'2020-06-06'),(169030,'2020-06-06'),
(7015182,'2020-06-06'),(7089792,'2020-06-06');
-- TODO need to know schema where we can write this to

-- types are:



-- SELECT "GmPseudo", MIN("Dementia_DiagnosisDate") AS FirstDementiaDate
-- FROM PRESENTATION.GP_RECORD."LongTermConditionRegister_SecondaryUses"
-- WHERE "Dementia_DiagnosisDate" IS NOT NULL
-- AND "Age" >= 18
-- GROUP BY "GmPseudo"

SELECT 
	cohort.GmPseudo AS PatientID,
	"Sex",
	YEAR("DateOfBirth") AS YearOfBirth,
	"EthnicityLatest" AS Ethnicity,
	"EthnicityLatest_Category" AS EthnicityCategory,
	"IMD_Decile" AS IMD2019Decile1IsMostDeprived10IsLeastDeprived,
	"RegisteredDateOfDeath"
FROM LH003_Cohort cohort
LEFT OUTER JOIN PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" demo
	ON demo."GmPseudo" = cohort.GmPseudo
LEFT OUTER JOIN PRESENTATION.NATIONAL_FLOWS_PCMD."DS1804_Pcmd" mortality
	ON mortality."GmPseudo" = cohort.GmPseudo
QUALIFY row_number() OVER (PARTITION BY demo."GmPseudo" ORDER BY "Snapshot" DESC) = 1;