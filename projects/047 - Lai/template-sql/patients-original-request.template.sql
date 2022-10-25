--┌────────────────────────────────────┐
--│ Patient demographics               │
--└────────────────────────────────────┘

-- OUTPUT: Data with the following fields (1 row per demographic combination)
--  - Age
--  - Sex (M/F)
--  - Ethnicity
--  - IMDGroup Individual index of multiple deprivation quintile score
--  - LSOA (Geographical location)
--  - Count

--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2018-01-01';
SET @EndDate = '2022-06-01';


-- Create a table with all patients (ID)=========================================================================================================================
IF OBJECT_ID('tempdb..#PatientsToInclude') IS NOT NULL DROP TABLE #PatientsToInclude;
SELECT FK_Patient_Link_ID INTO #PatientsToInclude
FROM RLS.vw_Patient_GP_History
GROUP BY FK_Patient_Link_ID
HAVING MIN(StartDate) < '2022-06-01';

IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #Patients 
FROM #PatientsToInclude;


--> EXECUTE query-patient-year-of-birth.sql
--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-lsoa.sql
--> EXECUTE query-patient-imd.sql


-- Create the table of IDM================================================================================================================================
IF OBJECT_ID('tempdb..#IMDGroup') IS NOT NULL DROP TABLE #IMDGroup;
SELECT FK_Patient_Link_ID, IMDGroup = CASE 
		WHEN IMD2019Decile1IsMostDeprived10IsLeastDeprived IN (1,2) THEN 1 
		WHEN IMD2019Decile1IsMostDeprived10IsLeastDeprived IN (3,4) THEN 2 
		WHEN IMD2019Decile1IsMostDeprived10IsLeastDeprived IN (5,6) THEN 3
		WHEN IMD2019Decile1IsMostDeprived10IsLeastDeprived IN (7,8) THEN 4
		WHEN IMD2019Decile1IsMostDeprived10IsLeastDeprived IN (9,10) THEN 5
		ELSE NULL END
INTO #IMDGroup
FROM #PatientIMDDecile;


-- Create the table of ethnic================================================================================================================================
IF OBJECT_ID('tempdb..#Ethnic') IS NOT NULL DROP TABLE #Ethnic;
SELECT PK_Patient_Link_ID AS FK_Patient_Link_ID, EthnicMainGroup AS Ethnicity
INTO #Ethnic
FROM RLS.vw_Patient_Link;


-- Final table===============================================================================================================================================
IF OBJECT_ID('tempdb..#PatientsDemographics') IS NOT NULL DROP TABLE #PatientsDemographics;
SELECT
  (2022 - YearOfBirth) AS Age,
  Sex,
  Ethnicity,
  IMDGroup,
  LSOA_Code AS LSOA,
  Count(FK_Patient_Link_ID)
FROM #Patients p
LEFT OUTER JOIN #PatientYearOfBirth pyob ON p.FK_Patient_Link_ID = pyob.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex ps ON p.FK_Patient_Link_ID = ps.FK_Patient_Link_ID
LEFT OUTER JOIN #Ethnic e ON e.PK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #IMDGroup imd ON imd.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientLSOA plsoa ON plsoa.FK_Patient_Link_ID = p.FK_Patient_Link_ID
GROUP BY (2022 - YearOfBirth), Sex, Ethnicity, IMDGroup, LSOA;


