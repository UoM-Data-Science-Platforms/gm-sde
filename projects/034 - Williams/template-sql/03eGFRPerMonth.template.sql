--+---------------------------------------------------------------------------+
--¦ People with eGFR <60 ml/minute but not coded as CKD                       ¦
--+---------------------------------------------------------------------------+

-------- RESEARCH DATA ENGINEER CHECK ---------

-- OUTPUT: Data with the following fields
-- Year (YYYY)
-- Month (1-12)
-- CCG (can be an anonymised id for each CCG)
-- GPPracticeId
-- NumberOfUncodedCKD (integer) The number of unique patients for this year, month, ccg and practice who received an eGFR <60 but who at that time did not have a diagnosis of CKD
-- NumberOfEGFRs (integer) The number of unique patients for this year, month, ccg and practice who received an eGFR this month.

-- Set the start date
DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2019-01-01';
SET @EndDate = '2022-06-01';

--Just want the output, not the messages
SET NOCOUNT ON;

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

--> CODESET egfr:1
--> CODESET chronic-kidney-disease:1

--> EXECUTE query-patient-practice-and-ccg.sql


-- Create a table of all patients with GP events after the start date with all months from Jan 2019 till May 2022 (COPI)=====================================================
-- All IDs of patients with GP events after the start date
IF OBJECT_ID('tempdb..#PatientsID') IS NOT NULL DROP TABLE #PatientsID;
SELECT DISTINCT FK_Patient_Link_ID
INTO #PatientsID FROM [RLS].[vw_GP_Events]
WHERE EventDate >= @StartDate AND EventDate < @EndDate AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

-- All years and months from the start date
IF OBJECT_ID('tempdb..#Dates') IS NOT NULL DROP TABLE #Dates;
CREATE TABLE #Dates (
  d DATE,
  PRIMARY KEY (d)
)

WHILE ( @StartDate < @EndDate )
BEGIN
  INSERT INTO #Dates (d) VALUES( @StartDate )
  SELECT @StartDate = DATEADD(MONTH, 1, @StartDate )
END

IF OBJECT_ID('tempdb..#Time') IS NOT NULL DROP TABLE #Time;
SELECT DISTINCT YEAR(d) AS [Year], MONTH(d) AS [Month], d
INTO #Time FROM #Dates

-- Merge 2 tables
IF OBJECT_ID('tempdb..#PatientsAll') IS NOT NULL DROP TABLE #PatientsAll;
SELECT *
INTO #PatientsAll
FROM #PatientsID, #Time;

-- Drop some tables
DROP TABLE #PatientsID
DROP TABLE #Dates
DROP TABLE #Time


-- Create eGFR tables==================================================================================================================================
-- All eGFR readings after the start date
IF OBJECT_ID('tempdb..#eGFR') IS NOT NULL DROP TABLE #eGFR;
SELECT FK_Patient_Link_ID, MONTH(EventDate) AS [Month], YEAR(EventDate) AS [Year], FK_Reference_Coding_ID, FK_Reference_SnomedCT_ID, Value, Units
INTO #eGFR
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'egfr' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'egfr' AND Version = 1)
)
AND Value IS NOT NULL AND EventDate >= @StartDate AND EventDate < @EndDate;

-- Only select eGFR as number
IF OBJECT_ID('tempdb..#eGFRConvert') IS NOT NULL DROP TABLE #eGFRConvert;
SELECT *, TRY_CONVERT(NUMERIC (18,5), [Value]) AS Value_new
INTO #eGFRConvert
FROM #eGFR
WHERE UPPER([Value]) NOT LIKE '%[A-Z]%';

-- Create an unique row for each patient each month with the min value of eGFR that month
IF OBJECT_ID('tempdb..#eGFRFinal') IS NOT NULL DROP TABLE #eGFRFinal;
SELECT FK_Patient_Link_ID, [Year], [Month], MIN(Value_new) AS eGFR
INTO #eGFRFinal
FROM #eGFRConvert
WHERE Value_new IS NOT NULL AND Value_new > 0 AND Value_new <= 300
GROUP BY FK_Patient_Link_ID, [Year], [Month];

-- Drop some tables to clear space
DROP TABLE #eGFR
DROP TABLE #eGFRConvert


-- Create CKD tables=================================================================================================================================================
-- All CKD records
IF OBJECT_ID('tempdb..#CKDAll') IS NOT NULL DROP TABLE #CKDAll;
SELECT FK_Patient_Link_ID, MONTH(EventDate) AS [Month], YEAR(EventDate) AS [Year], FK_Reference_Coding_ID, FK_Reference_SnomedCT_ID, 'CKD' AS CKD
INTO #CKDAll
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'chronic-kidney-disease' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'chronic-kidney-disease' AND Version = 1)
)
AND EventDate >= @StartDate AND EventDate < @EndDate;

-- Unique CKD record for each month
IF OBJECT_ID('tempdb..#CKD') IS NOT NULL DROP TABLE #CKD;
SELECT DISTINCT FK_Patient_Link_ID, [Year], [Month], CKD
INTO #CKD
FROM #CKDAll;

-- Drop table
DROP TABLE #CKDAll


-- Merge table=================================================================================================================================================================
-- Merge all information
IF OBJECT_ID('tempdb..#Table') IS NOT NULL DROP TABLE #Table;
SELECT P.FK_Patient_Link_ID, p.[Year], p.[Month], p.d, gp.GPPracticeCode, gp.CCG, e.eGFR, c.CKD
INTO #Table
FROM #PatientsAll p
LEFT OUTER JOIN #PatientPracticeAndCCG gp ON p.FK_Patient_Link_ID = GP.FK_Patient_Link_ID
LEFT OUTER JOIN #eGFRFinal e ON p.FK_Patient_Link_ID = e.FK_Patient_Link_ID AND p.[Year] = e.[Year] AND p.[Month] = e.[Month]
LEFT OUTER JOIN #CKD c ON p.FK_Patient_Link_ID = c.FK_Patient_Link_ID AND p.[Year] = c.[Year] AND p.[Month] = c.[Month]
ORDER BY p.FK_Patient_Link_ID, p.[Year], p.[Month];

-- Forward fill CKD diagnosis
IF OBJECT_ID('tempdb..#TableCount') IS NOT NULL DROP TABLE #TableCount;
SELECT *
		, CASE
			WHEN CKD IS NULL THEN (
			SELECT TOP 1
				inner_table.CKD
			FROM
				#Table AS inner_table
			WHERE
				inner_table.FK_Patient_Link_ID = t.FK_Patient_Link_ID
				AND inner_table.d < t.d
				AND inner_table.CKD IS NOT NULL
				ORDER BY inner_table.d
			)
		ELSE
			CKD
		END AS CKD_fill
INTO #TableCount
FROM #Table t;

-- Count
IF OBJECT_ID('tempdb..#eGFRPerMonth') IS NOT NULL DROP TABLE #eGFRPerMonth;
SELECT [Year], [Month], CCG, GPPracticeCode AS GPPracticeId, 
	   SUM(CASE WHEN eGFR < 60 and CKD IS NULL THEN 1 ELSE 0 END) AS NumberOfUncodedCKD,
	   SUM(CASE WHEN eGFR IS NOT NULL THEN 1 ELSE 0 END) AS NumberOfEGFRs
FROM #TableCount
WHERE [Year] IS NOT NULL AND [Month] IS NOT NULL AND (CCG IS NOT NULL OR GPPracticeCode IS NOT NULL)
	  AND GPPracticeCode NOT LIKE '%DO NOT USE%' AND GPPracticeCode NOT LIKE '%TEST%'
GROUP BY [Year], [Month], CCG, GPPracticeCode
ORDER BY [Year], [Month], CCG, GPPracticeCode;