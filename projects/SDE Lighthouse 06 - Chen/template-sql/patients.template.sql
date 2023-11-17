--┌──────────────────────────────────────────┐
--│ SDE Lighthouse study 03 - Kontopantelis  │
--└──────────────────────────────────────────┘

--Just want the output, not the messages
SET NOCOUNT ON;

DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2006-01-01'; -- CHECK THIS AND  - CURRENTLY EXCLUDING ANY PATIENTS THAT WEREN'T 18 IN 2006
SET @EndDate = '2022-12-31';

--> EXECUTE query-build-lh006-cohort.sql

--bring together for final output
--patients in main cohort
SELECT	 PatientId = FK_Patient_Link_ID
		,YearOfBirth
		,Sex
		,LSOA_Code
		,EthnicMainGroup ----- CHANGE TO MORE SPECIFIC ETHNICITY ?
		,IMD2019Decile1IsMostDeprived10IsLeastDeprived
		,DeathDate
FROM #Cohort m