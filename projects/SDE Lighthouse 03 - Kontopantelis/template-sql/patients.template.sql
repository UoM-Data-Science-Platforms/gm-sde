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
--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-lsoa.sql
--> EXECUTE query-patient-imd.sql

-- Date of first dementia diagnosis
SELECT PatientId, MIN(EventDate) as FirstDiagnosis
INTO #FirstDementiaDiagnosis
FROM #DementiaCodes 
GROUP BY PatientId

--bring together for final output
SELECT	 PatientId = m.FK_Patient_Link_ID
		,YearOfBirth
		,Sex
		,LSOA_Code
		,EthnicGroupDescription
		,IMD2019Decile1IsMostDeprived10IsLeastDeprived
		,DeathDate = CONVERT(DATE,DeathDate)
		,FirstDementiaDiagnosis = CONVERT(DATE,fdd.FirstDiagnosis)
FROM #Cohort m
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientLSOA lsoa ON lsoa.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientIMDDecile imd ON imd.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #FirstDementiaDiagnosis fdd ON fdd.PatientId = m.FK_Patient_Link_ID