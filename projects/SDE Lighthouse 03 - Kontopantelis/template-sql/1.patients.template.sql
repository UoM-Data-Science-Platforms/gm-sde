--┌──────────────────────────────────────────┐
--│ SDELS03 - Kontopantelis - Demographics   │
--└──────────────────────────────────────────┘

--Just want the output, not the messages
SET NOCOUNT ON;

DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2006-01-01'; 
SET @EndDate = '2023-10-31';

--> EXECUTE query-build-lh003-cohort.sql

SELECT 
	"GmPseudo" AS PatientID,
	"Sex",
	YEAR("DateOfBirth") AS YearOfBirth,
	"EthnicityLatest" AS Ethnicity,
	"EthnicityLatest_Category" AS EthnicityCategory 
FROM PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses"
WHERE "GmPseudo" IN (1763539,2926922,182597,1244665,3134799,1544463,5678816,169030,7015182,7089792)
QUALIFY row_number() OVER (PARTITION BY "GmPseudo" ORDER BY "Snapshot" DESC) = 1 -- this brings back the values from the most recent snapshot