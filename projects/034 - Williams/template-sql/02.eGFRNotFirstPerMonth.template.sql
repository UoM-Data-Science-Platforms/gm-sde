--+---------------------------------------------------------------------------+
--¦ People with a drop of ≥10 ml/minute in eGFR compared with previous result ¦
--+---------------------------------------------------------------------------+

-------- RESEARCH DATA ENGINEER CHECK ---------

-- OUTPUT: Data with the following fields
-- Year (YYYY)
-- Month (1-12)
-- CCG (can be an anonymised id for each CCG)
-- GPPracticeId
-- NumberOfDroppedEGFRs (integer) The number of unique patients for this year, month, ccg and practice who received an eGFR that was ≥10 ml/minute lower than their previous reading
-- NumberOfSubsequentEGFRs (integer) The number of unique patients for this year, month, ccg and practice who received an eGFR that was not their first ever reading.

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2019-01-01';

--Just want the output, not the messages
SET NOCOUNT ON;

-- Create a table with all patients (ID)=========================================================================================================================
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT DISTINCT FK_Patient_Link_ID INTO #Patients FROM [RLS].vw_Patient;

--> CODESET egfr:1

--> EXECUTE query-patient-practice-and-ccg.sql


-- Create eGFR tables======================================================================================================================================
-- All eGFR reading records
IF OBJECT_ID('tempdb..#eGFR') IS NOT NULL DROP TABLE #eGFR;
SELECT FK_Patient_Link_ID, EventDate, FK_Reference_Coding_ID, FK_Reference_SnomedCT_ID, Value, Units
INTO #eGFR
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'egfr' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'egfr' AND Version = 1)
);

-- Only select eGFR as number
IF OBJECT_ID('tempdb..#eGFRConvert') IS NOT NULL DROP TABLE #eGFRConvert;
SELECT *, TRY_CONVERT(NUMERIC (18,5), [Value]) AS Value_new
INTO #eGFRConvert
FROM #eGFR
WHERE UPPER([Value]) NOT LIKE '%[A-Z]%';

-- Only select eGFR values > 0 and <= 300, no conversion needed (PI approved)
IF OBJECT_ID('tempdb..#eGFRFinal') IS NOT NULL DROP TABLE #eGFRFinal;
SELECT FK_Patient_Link_ID, EventDate, Value_new
INTO #eGFRFinal
FROM #eGFRConvert
WHERE Value_new IS NOT NULL AND Value_new > 0 AND Value_new <= 300;

-- Drop some tables to clear space
DROP TABLE #eGFR
DROP TABLE #eGFRConvert


-- Create a table of all eGFR and their previous readings=========================================================================================================================
IF OBJECT_ID('tempdb..#Table') IS NOT NULL DROP TABLE #Table;
SELECT FK_Patient_Link_ID, EventDate, Value_new, YEAR(EventDate) AS [Year], MONTH(EventDate) AS [Month],
	   LAG (Value_new) OVER (PARTITION  BY FK_Patient_Link_ID ORDER BY EventDate) AS Value_previous, 
	   Value_new - LAG (Value_new) OVER (PARTITION BY FK_Patient_Link_ID ORDER BY EventDate) AS Difference_eGFR,
	   CASE WHEN LAG (Value_new) OVER (PARTITION BY FK_Patient_Link_ID ORDER BY EventDate) IS NULL THEN 'Y' ELSE 'N' END AS First_reading
INTO #Table
FROM #eGFRFinal


-- Create a table of all patients with GP events after the start date with all months from Jan 2019 till the current month=====================================================
-- All IDs of patients with GP events after the start date
IF OBJECT_ID('tempdb..#PatientsID') IS NOT NULL DROP TABLE #PatientsID;
SELECT DISTINCT FK_Patient_Link_ID
INTO #PatientsID FROM [RLS].[vw_GP_Events];

-- All years and months from the start date
IF OBJECT_ID('tempdb..#Dates') IS NOT NULL DROP TABLE #Dates;
CREATE TABLE #Dates (
  d DATE,
  PRIMARY KEY (d)
)
DECLARE @dStart DATE = '2019-01-01'
DECLARE @dEnd DATE = getdate()

WHILE ( @dStart < @dEnd )
BEGIN
  INSERT INTO #Dates (d) VALUES( @dStart )
  SELECT @dStart = DATEADD(MONTH, 1, @dStart )
END

IF OBJECT_ID('tempdb..#Time') IS NOT NULL DROP TABLE #Time;
SELECT DISTINCT YEAR(d) AS [Year], MONTH(d) AS [Month]
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


-- Merge with CCG and GP practice ID================================================================================================================================================
-- Several egFR before 2019 will be missed in this table but it doesnt affect the final counts
IF OBJECT_ID('tempdb..#TableCount') IS NOT NULL DROP TABLE #TableCount;
SELECT a.FK_Patient_Link_ID, a.[Year], a.[Month], 
	   p.EventDate, p.Value_new, p.Value_previous, p.Difference_eGFR, p.First_reading, gp.GPPracticeCode, gp.CCG
INTO #TableCount
FROM #PatientsAll a
LEFT OUTER JOIN #PatientPracticeAndCCG gp ON a.FK_Patient_Link_ID = gp.FK_Patient_Link_ID
LEFT OUTER JOIN #Table p ON a.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND a.[Year] = p.[Year] AND a.[Month] = p.[Month];


-- Count for the final table================================================================================================================================================
-- Group into an unique row for each patients in each month
IF OBJECT_ID('tempdb..#TableFinal') IS NOT NULL DROP TABLE #TableFinal;
SELECT FK_Patient_Link_ID, [Year], [Month], CCG, GPPracticeCode, MIN(Difference_eGFR) AS Difference_eGFR_min, MAX(First_reading) AS First_reading_max
INTO #TableFinal
FROM #TableCount
GROUP BY FK_Patient_Link_ID, [Year], [Month], CCG, GPPracticeCode;

-- Count
SELECT [Year], [Month], CCG, GPPracticeCode AS GPPracticeId, 
	   SUM(CASE WHEN Difference_eGFR_min <= -10 THEN 1 ELSE 0 END) AS NumberOfDroppedEGFRs,
	   SUM(CASE WHEN First_reading_max = 'N' THEN 1 ELSE 0 END) AS NumberOfSubsequentEGFRs
FROM #TableFinal
WHERE [Year] IS NOT NULL AND [Month] IS NOT NULL AND (CCG IS NOT NULL OR GPPracticeCode IS NOT NULL) 
      AND GPPracticeCode NOT LIKE '%DO NOT USE%' AND GPPracticeCode NOT LIKE '%TEST%'
GROUP BY [Year], [Month], CCG, GPPracticeCode;



