--+---------------------------------------------------------------------------+
--¦ People >75 years old with haemoglobin <100 g/L or ferritin <15 ng/ml      ¦
--+---------------------------------------------------------------------------+

-------- RESEARCH DATA ENGINEER CHECK ---------

-- OUTPUT: Data with the following fields
-- Year (YYYY)
-- Month (1-12)
-- CCG (can be an anonymised id for each CCG)
-- GPPracticeId
-- NumberOfOver75WithLowHaem (integer) The number of over 75s with a haemoglobin <100 or a ferritin <15 in this year, month and for this ccg and gp
-- NumberOfOver75s (integer) The number of over 75s for this year, month, ccg and gp

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


--> CODESET haemoglobin:1
--> CODESET ferritin:1

--> EXECUTE query-patient-year-of-birth.sql
--> EXECUTE query-patient-practice-and-ccg.sql


-- Haemoglobin tables=======================================================================================================================================================
-- Create a table of all patients with haemoglobin values after the start date
IF OBJECT_ID('tempdb..#Haemoglobin') IS NOT NULL DROP TABLE #Haemoglobin;
SELECT FK_Patient_Link_ID, MONTH(EventDate) AS [Month], YEAR(EventDate) AS [Year], FK_Reference_Coding_ID, FK_Reference_SnomedCT_ID, Value, Units
INTO #Haemoglobin
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'haemoglobin' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'haemoglobin' AND Version = 1)
)
AND EventDate >= @StartDate AND EventDate < @EndDate AND Value IS NOT NULL;

-- Only select haemoglobin values as number
IF OBJECT_ID('tempdb..#HaemoglobinConvert') IS NOT NULL DROP TABLE #HaemoglobinConvert;
SELECT *, TRY_CONVERT(NUMERIC (18,5), [Value]) AS Value_new
INTO #HaemoglobinConvert
FROM #Haemoglobin
WHERE UPPER([Value]) NOT LIKE '%[A-Z]%';

-- Convert different value units into g/L (PI approved the conversions)
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
-- PI agreed about only keeping haemoglobin values > 0, not null and <= 300 g/L from some specific units
IF OBJECT_ID('tempdb..#HaemoglobinFinal') IS NOT NULL DROP TABLE #HaemoglobinFinal; 
SELECT FK_Patient_Link_ID, [Year], [Month], MIN(Value_new) AS Haemoglobin_values -- select min value forquickly counting later
INTO #HaemoglobinFinal
FROM #HaemoglobinConvert
WHERE Value_new > 0 AND Value_new <= 300 AND 
	  (Units = 'g(hb)/dL' OR Units = 'g/dl' OR Units = 'g/L' OR Units = 'g/L (115-165) L' OR Units = 'gm/dl' OR Units = 'gm/L' OR Units = 'mmol/l')
GROUP BY FK_Patient_Link_ID, [Year], [Month];

-- Drop some tables to clear space
DROP TABLE #Haemoglobin
DROP TABLE #HaemoglobinConvert


-- Ferritin tables==========================================================================================================================================================
-- Create a table of all patients with ferritin values after the start date
IF OBJECT_ID('tempdb..#Ferritin') IS NOT NULL DROP TABLE #Ferritin;
SELECT FK_Patient_Link_ID, MONTH(EventDate) AS [Month], YEAR(EventDate) AS [Year], FK_Reference_Coding_ID, FK_Reference_SnomedCT_ID, Value, Units
INTO #Ferritin
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'ferritin' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'ferritin' AND Version = 1)
)
AND EventDate >= @StartDate AND EventDate < @EndDate AND Value IS NOT NULL;

-- Select only values as number
IF OBJECT_ID('tempdb..#FerritinConvert') IS NOT NULL DROP TABLE #FerritinConvert;
SELECT *, TRY_CONVERT(NUMERIC (18,5), [Value]) AS Value_new
INTO #FerritinConvert
FROM #Ferritin
WHERE UPPER([Value]) NOT LIKE '%[A-Z]%';

-- No conversion needed for ferritin values

-- Create a final table with an unique row for each ID, year, month with min values of ferritin of that month
-- PI agreed about only keeping ferritin values > 0, not null and <= 500 ng/mL from some specific units
IF OBJECT_ID('tempdb..#FerritinFinal') IS NOT NULL DROP TABLE #FerritinFinal;
SELECT FK_Patient_Link_ID, [Year], [Month], MIN(Value_new) AS Ferritin_values -- select min value forquickly counting later
INTO #FerritinFinal
FROM #FerritinConvert
WHERE Value_new > 0 AND Value_new <= 500 AND (Units = 'mcg per litre' OR Units = 'mcg/l' OR Units = 'microg/L' OR Units = 'ng/mL' OR Units = 'ug/L')
GROUP BY FK_Patient_Link_ID, [Year], [Month];

-- Drop some tables to clear space
DROP TABLE #Ferritin
DROP TABLE #FerritinConvert


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


-- Merge table=================================================================================================================================================================
-- Merge all information
IF OBJECT_ID('tempdb..#Table') IS NOT NULL DROP TABLE #Table;
SELECT P.FK_Patient_Link_ID, p.[Year], p.[Month], (p.[Year] - y.YearOfBirth) AS Age, gp.GPPracticeCode, gp.CCG, h.Haemoglobin_values, f.Ferritin_values
INTO #Table
FROM #PatientsAll p
LEFT OUTER JOIN #PatientYearOfBirth y ON p.FK_Patient_Link_ID = y.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientPracticeAndCCG gp ON p.FK_Patient_Link_ID = GP.FK_Patient_Link_ID
LEFT OUTER JOIN #HaemoglobinFinal h ON p.FK_Patient_Link_ID = h.FK_Patient_Link_ID AND p.[Year] = h.[Year] AND p.[Month] = h.[Month]
LEFT OUTER JOIN #FerritinFinal f ON p.FK_Patient_Link_ID = f.FK_Patient_Link_ID AND p.[Year] = f.[Year] AND p.[Month] = f.[Month];

-- Count for the final table
SELECT [Year], [Month], CCG, GPPracticeCode AS GPPracticeId, 
	   SUM(CASE WHEN Age > 75 AND (Haemoglobin_values < 100 OR Ferritin_values < 15) THEN 1 ELSE 0 END) AS NumberOfOver75WithLowHaem,
	   SUM(CASE WHEN Age > 75 THEN 1 ELSE 0 END) AS NumberOfOver75s
FROM #Table
WHERE [Year] IS NOT NULL AND [Month] IS NOT NULL AND (CCG IS NOT NULL OR GPPracticeCode IS NOT NULL) 
	    AND GPPracticeCode NOT LIKE '%DO NOT USE%' AND GPPracticeCode NOT LIKE '%TEST%'
GROUP BY [Year], [Month], CCG, GPPracticeCode
ORDER BY [Year], [Month], CCG, GPPracticeCode;