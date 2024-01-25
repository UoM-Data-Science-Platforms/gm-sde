--┌──────────────────────────────────────────┐
--│ SDE Lighthouse study 09 - Kontopantelis  │
--└──────────────────────────────────────────┘

--Just want the output, not the messages
SET NOCOUNT ON;

DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = 'CHANGE'; -- CHECK THIS AND  - CURRENTLY EXCLUDING ANY PATIENTS THAT WEREN'T 18 IN 2006
SET @EndDate = 'CHANGE';

--> EXECUTE query-build-lh009-cohort.sql

--> EXECUTE query-patient-lsoa.sql
--> EXECUTE query-patient-imd.sql
--> EXECUTE query-patient-smoking-status.sql
--> EXECUTE query-patient-alcohol-intake.sql

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
LEFT OUTER JOIN #PatientLSOA lsoa ON lsoa.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientIMDDecile imd ON imd.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSmokingStatus smok ON smok.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientAlcoholIntake alc ON alc.FK_Patient_Link_ID = m.FK_Patient_Link_ID
