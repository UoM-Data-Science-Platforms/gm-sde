--┌──────────────────────────────────────────┐
--│ SDE Lighthouse study 06 - Chen           │
--└──────────────────────────────────────────┘

--Just want the output, not the messages
SET NOCOUNT ON;

DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2017-01-01';
SET @EndDate = '2023-12-31';

--> EXECUTE query-build-lh006-cohort.sql

--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-lsoa.sql
--> EXECUTE query-patient-imd.sql
--> EXECUTE query-patient-practice-and-ccg.sql

--bring together for final output
--patients in main cohort
SELECT	 PatientId = FK_Patient_Link_ID
		,p.YearOfBirth
		,sex.Sex
		,LSOA = lsoa.LSOA_Code
		,Ethnicity = p.EthnicGroupDescription
		,imd.IMD2019Decile1IsMostDeprived10IsLeastDeprived
		,DeathYearAndMonth,
		,prac.GPPracticeCode
FROM #Cohort p
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientLSOA lsoa ON lsoa.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientIMDDecile imd ON imd.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientPracticeAndCCG prac ON prac.FK_Patient_Link_ID = p.FK_Patient_Link_ID
