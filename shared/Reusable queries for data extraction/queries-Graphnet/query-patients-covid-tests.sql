--┌─────────────────────────────────────────────┐
--│ Patients with a COVID test result           │
--└─────────────────────────────────────────────┘

-- OBJECTIVE: To get all patients with a positive and negative COVID test result.


-- INPUT: Takes one parameter
--  - start-date: string - (YYYY-MM-DD) the date to count diagnoses from. Usually this should be 2020-01-01.

-- OUTPUT: Three temp tables as follows:
-- #CovidPositiveTests (FK_Patient_Link_ID, CovidTestDate, CovidTestResult)
-- #CovidNegativeTests (FK_Patient_Link_ID, CovidTestDate, CovidTestResult)
-- 	- FK_Patient_Link_ID - unique patient id
--  - CovidTestDate - Date, assume that only 1 test per day
--	- CovidTestResult - Varchar, 'Positive', 'Negative'.
-- #AllCovidTests (FK_Patient_Link_ID, CovidTestDate, CovidTestDescription, ClinicalCode)
-- 	- FK_Patient_Link_ID - unique patient id
--  - CovidTestDate - Date, assume that only 1 test per day
--	- CovidTestResult - Varchar, This field concatenates the information in the GroupDescription and SubGroupDescription from the COVID19 table.
--  - ClinicalCode - The clinical code retrieved from 'MainCode' in the COVID19 table. 


IF OBJECT_ID('tempdb..#CovidPositiveTests') IS NOT NULL DROP TABLE #CovidPositiveTests;
SELECT DISTINCT FK_Patient_Link_ID, CONVERT(DATE, [EventDate]) AS CovidTestDate, 'Positive' AS CovidTestResult INTO #CovidPositiveTests
FROM [SharedCare].[COVID19]
WHERE (
	(GroupDescription = 'Confirmed' AND SubGroupDescription != 'Negative') OR
	(GroupDescription = 'Tested' AND SubGroupDescription = 'Positive')
)
AND EventDate >= '{param:start-date}'
AND EventDate <= GETDATE();

IF OBJECT_ID('tempdb..#CovidNegativeTests') IS NOT NULL DROP TABLE #CovidNegativeTests;
SELECT DISTINCT FK_Patient_Link_ID, CONVERT(DATE, [EventDate]) AS CovidTestDate, 'Negative' AS CovidTestResult INTO #CovidNegativeTests
FROM [SharedCare].[COVID19]
WHERE (
	(GroupDescription = 'Confirmed' AND SubGroupDescription = 'Negative') OR
	(GroupDescription = 'Tested' AND SubGroupDescription = 'Negative') OR
	(GroupDescription = 'Excluded' AND SubGroupDescription = 'Negative') 
)
AND EventDate >= '{param:start-date}'
AND EventDate <= GETDATE();


-- Get all covid tests, the date, and the clinical code. This includes positive, negative, excluded, suspected. 
IF OBJECT_ID('tempdb..#AllCovidTests') IS NOT NULL DROP TABLE #AllCovidTests;
SELECT DISTINCT FK_Patient_Link_ID, CONVERT(DATE, [EventDate]) AS CovidTestDate, CONCAT(GroupDescription, ' - ', SubGroupDescription)  AS CovidTestResult, MainCode AS ClinicalCode INTO #AllCovidTests
FROM [SharedCare].[COVID19]
WHERE (
	GroupDescription = 'Assessed'  OR
	GroupDescription = 'Confirmed'  OR
	GroupDescription = 'Tested'  OR
	GroupDescription = 'Excluded' OR
	GroupDescription = 'Suspected'  OR
	GroupDescription = 'Unknown' 
)
AND EventDate >= '{param:start-date}'
AND EventDate <= GETDATE();