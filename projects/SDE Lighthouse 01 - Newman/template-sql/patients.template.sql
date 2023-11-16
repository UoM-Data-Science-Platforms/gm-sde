--┌──────────────────────────────────────────┐
--│ SDE Lighthouse study 01 - Newman 		 │
--└──────────────────────────────────────────┘

--Just want the output, not the messages
SET NOCOUNT ON;

DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = CHANGE; 
SET @EndDate = CHANGE;




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