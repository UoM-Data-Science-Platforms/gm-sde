--┌──────────────────────────────────────────┐
--│ SDELS03 - Kontopantelis - Demographics   │
--└──────────────────────────────────────────┘

--> EXECUTE query-build-lh003-cohort.sql

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