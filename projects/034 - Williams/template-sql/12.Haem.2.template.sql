--+---------------------------------------------------------------------------+
--¦ Haemoglobin <100g/L                                                       ¦
--+---------------------------------------------------------------------------+

-------- RESEARCH DATA ENGINEER CHECK ---------

-- OUTPUT: Data with one row for each time a patient has a haemoglobin value <100
-- Year (YYYY)
-- Month (1-12)
-- CCG (can be an anonymised id for each CCG)
-- GPPracticeId
-- NumberOfHaem (integer) The number of patients with a recorded haemoglobin 

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2019-01-01';

--Just want the output, not the messages
SET NOCOUNT ON;

-- Create a table with all patients (ID)=========================================================================================================================
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT DISTINCT FK_Patient_Link_ID INTO #Patients FROM [RLS].vw_Patient;

--> CODESET haemoglobin:1

--> EXECUTE query-patient-practice-and-ccg.sql


-- Haemoglobin tables=======================================================================================================================================================
-- Create a table of all patients with haemoglobin values after the start date
IF OBJECT_ID('tempdb..#Haemoglobin') IS NOT NULL DROP TABLE #Haemoglobin;
SELECT FK_Patient_Link_ID, MONTH(EventDate) AS Month, YEAR(EventDate) AS Year, FK_Reference_Coding_ID, FK_Reference_SnomedCT_ID, Value, Units
INTO #Haemoglobin
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'haemoglobin' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'haemoglobin' AND Version = 1)
)
AND EventDate >= @StartDate AND Value IS NOT NULL;

-- Only select haemoglobin values as number
IF OBJECT_ID('tempdb..#HaemoglobinConvert') IS NOT NULL DROP TABLE #HaemoglobinConvert;
SELECT *, TRY_CONVERT(NUMERIC (18,5), [Value]) AS Value_new
INTO #HaemoglobinConvert
FROM #Haemoglobin
WHERE UPPER([Value]) NOT LIKE '%[A-Z]%';

-- Convert different value units into g/L
UPDATE
#HaemoglobinConvert
SET
Value_new = Value_new * 10
WHERE
Units = 'g(hb)/dL';

UPDATE
#HaemoglobinConvert
SET
Value_new = Value_new * 10
WHERE
Units = 'g/dL';

UPDATE
#HaemoglobinConvert
SET
Value_new = Value_new * 10
WHERE
Units = 'gm/dl';

-- Create a final table with an unique row for each ID, year, month with min values of haemoglobin of that month
IF OBJECT_ID('tempdb..#HaemoglobinFinal') IS NOT NULL DROP TABLE #HaemoglobinFinal; 
SELECT FK_Patient_Link_ID, Year, Month, MIN(Value_new) AS Haemoglobin_values
INTO #HaemoglobinFinal
FROM #HaemoglobinConvert
WHERE Value_new > 0 AND Value_new <= 300 AND 
	  (Units = 'g(hb)/dL' OR Units = 'g/dl' OR Units = 'g/L' OR Units = 'g/L (115-165) L' OR Units = 'gm/dl' OR Units = 'gm/L' OR Units = 'mmol/l')
GROUP BY FK_Patient_Link_ID, Year, Month;

-- Drop some tables to clear space
DROP TABLE #Haemoglobin
DROP TABLE #HaemoglobinConvert


-- Create a table of all patients with GP events after the start date with all months rom Jan 2019 till the current month=====================================================
-- All IDs of patients with GP events after the start date
IF OBJECT_ID('tempdb..#PatientsID') IS NOT NULL DROP TABLE #PatientsID;
SELECT DISTINCT FK_Patient_Link_ID
INTO #PatientsID FROM [RLS].[vw_GP_Events]
WHERE EventDate >= @StartDate;

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
SELECT DISTINCT YEAR(d) AS Year, MONTH(d) AS Month
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


-- Merge table=================================================================================================================================================================
-- Merge all information
IF OBJECT_ID('tempdb..#Table') IS NOT NULL DROP TABLE #Table;
SELECT P.FK_Patient_Link_ID, p.[Year], p.[Month], gp.GPPracticeCode, gp.CCG, h.Haemoglobin_values
INTO #Table
FROM #PatientsAll p
LEFT OUTER JOIN #PatientPracticeAndCCG gp ON p.FK_Patient_Link_ID = GP.FK_Patient_Link_ID
LEFT OUTER JOIN #HaemoglobinFinal h ON p.FK_Patient_Link_ID = h.FK_Patient_Link_ID AND p.[Year] = h.[Year] AND p.[Month] = h.[Month];

-- Count for the final table
IF OBJECT_ID('tempdb..#Haem') IS NOT NULL DROP TABLE #Haem;
SELECT Year, Month, CCG, GPPracticeCode AS GPPracticeId, 
	   SUM(CASE WHEN Haemoglobin_values IS NOT NULL THEN 1 ELSE 0 END) AS NumberOfHaem
INTO #Haem
FROM #Table
WHERE Year IS NOT NULL AND Month IS NOT NULL AND (CCG IS NOT NULL OR GPPracticeCode IS NOT NULL)
GROUP BY [Year], [Month], CCG, GPPracticeCode;
