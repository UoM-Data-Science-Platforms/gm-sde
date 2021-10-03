--┌─────────────────────────────────────────────┐
--│ Patients that undertook a COVID test        │
--└─────────────────────────────────────────────┘

-- OBJECTIVE: To get all patients with a positive and negative COVID test result.


-- INPUT: Takes one parameter
--  - start-date: string - (YYYY-MM-DD) the date to count diagnoses from. Usually this should be 2020-01-01.

-- OUTPUT: Two temp tables as follows:
-- #CovidPositiveTests (FK_Patient_Link_ID, CovidTestDate, CovidTestResult)
-- #CovidNegativeTests (FK_Patient_Link_ID, CovidTestDate, CovidTestResult)
-- 	- FK_Patient_Link_ID - unique patient id
--  - CovidTestDate - Date, assume that only 1 test per day
--	- CovidTestResult - Varchar, 'Positive', 'Negative'.

IF OBJECT_ID('tempdb..#CovidPositiveTests') IS NOT NULL DROP TABLE #CovidPositiveTests;
SELECT DISTINCT FK_Patient_Link_ID, CONVERT(DATE, [EventDate]) AS CovidTestDate, 'Positive' AS CovidTestResult INTO #CovidPositiveTests
FROM [RLS].[vw_COVID19]
WHERE (
	-- TODO: Verify that following condition is the right one.
	(GroupDescription = 'Confirmed' AND SubGroupDescription != 'Negative') OR
	(GroupDescription = 'Tested' AND SubGroupDescription = 'Positive')
)
AND EventDate >= '{param:start-date}'
AND EventDate <= GETDATE();

IF OBJECT_ID('tempdb..#CovidNegativeTests') IS NOT NULL DROP TABLE #CovidNegativeTests;
SELECT DISTINCT FK_Patient_Link_ID, CONVERT(DATE, [EventDate]) AS CovidTestDate, 'Negative' AS CovidTestResult INTO #CovidNegativeTests
FROM [RLS].[vw_COVID19]
WHERE (
	-- TODO: Verify that following conditions are the right ones.
	(GroupDescription = 'Confirmed' AND SubGroupDescription = 'Negative') OR
	(GroupDescription = 'Tested' AND SubGroupDescription = 'Negative') OR
	(GroupDescription = 'Excluded' AND SubGroupDescription = 'Negative') 
)
AND EventDate >= '{param:start-date}'
AND EventDate <= GETDATE();