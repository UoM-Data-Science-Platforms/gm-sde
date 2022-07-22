--+--------------------------------------------------------------------------------+
--¦ People >65 years co-prescribed NSAIDs, ACEIs/ARBs, and diuretics               ¦
--+--------------------------------------------------------------------------------+

-------- RESEARCH DATA ENGINEER CHECK ---------

-- OUTPUT: Data with the following fields
-- Year (YYYY)
-- Month (1-12)
-- CCG (can be an anonymised id for each CCG)
-- GPPracticeId
-- NumberOfOver65PolyPharm (integer) The number of unique patients per month, ccg and practice who received a prescription for an NSAID, an ACEI/ARB and a diuretic in this month or the previous month.
-- NumberOfOver65s (integer) The number of over 65s for this month, year, ccg and gp

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2019-01-01';

--Just want the output, not the messages
SET NOCOUNT ON;

-- Create a table with all patients (ID)=========================================================================================================================
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT DISTINCT FK_Patient_Link_ID INTO #Patients FROM [RLS].vw_Patient;

--> CODESET ace-inhibitor:1
--> CODESET nsaids:1
--> CODESET diuretic:1

--> EXECUTE query-patient-practice-and-ccg.sql
--> EXECUTE query-patient-year-of-birth.sql

-- Create a table of patients using NSAIDS============================================================================================================
-- All NSAIDS records
IF OBJECT_ID('tempdb..#NSAIDSAll') IS NOT NULL DROP TABLE #NSAIDSAll;
SELECT FK_Patient_Link_ID, MONTH(MedicationDate) AS [Month], YEAR(MedicationDate) AS [Year], 
	   FK_Reference_Coding_ID, FK_Reference_SnomedCT_ID, 'NSAIDS' AS NSAIDS
INTO #NSAIDSAll
FROM [RLS].[vw_GP_Medications]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'nsaids' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'nsaids' AND Version = 1)
)
AND MedicationDate >= @StartDate AND MedicationDate <= @EndDate;

-- Each NSAIDS record for each month
IF OBJECT_ID('tempdb..#NSAIDS') IS NOT NULL DROP TABLE #NSAIDS;
SELECT DISTINCT FK_Patient_Link_ID, [Year], [Month], MAX(NSAIDS) AS NSAIDS
INTO #NSAIDS
FROM #NSAIDSAll
GROUP BY FK_Patient_Link_ID, [Year], [Month];


-- Create a table of patients using ACEI/ARB============================================================================================================
-- All ACEI/ARB records
IF OBJECT_ID('tempdb..#ACEIARBAll') IS NOT NULL DROP TABLE #ACEIARBAll;
SELECT FK_Patient_Link_ID, MONTH(MedicationDate) AS [Month], YEAR(MedicationDate) AS [Year], 
	   FK_Reference_Coding_ID, FK_Reference_SnomedCT_ID, 'ACEIARB' AS ACEIARB
INTO #ACEIARBAll
FROM [RLS].[vw_GP_Medications]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'nsaids' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'nsaids' AND Version = 1)
)
AND MedicationDate >= @StartDate AND MedicationDate <= @EndDate;

-- Unique ACEI/ARB record for each month
IF OBJECT_ID('tempdb..#ACEIARB') IS NOT NULL DROP TABLE #ACEIARB;
SELECT DISTINCT FK_Patient_Link_ID, [Year], [Month], MAX(ACEIARB) AS ACEIARB
INTO #ACEIARB
FROM #ACEIARBAll
GROUP BY FK_Patient_Link_ID, [Year], [Month];


-- Create a table of patients using diuretic============================================================================================================
-- All diuretic records
IF OBJECT_ID('tempdb..#DiureticAll') IS NOT NULL DROP TABLE #DiureticAll;
SELECT FK_Patient_Link_ID, MONTH(MedicationDate) AS [Month], YEAR(MedicationDate) AS [Year], 
	   FK_Reference_Coding_ID, FK_Reference_SnomedCT_ID, 'Diuretic' AS Diuretic
INTO #DiureticAll
FROM [RLS].[vw_GP_Medications]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'diuretic' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'diuretic' AND Version = 1)
)
AND MedicationDate >= @StartDate AND MedicationDate <= @EndDate;

-- Unique diuretic for each month
IF OBJECT_ID('tempdb..#Diuretic') IS NOT NULL DROP TABLE #Diuretic;
SELECT DISTINCT FK_Patient_Link_ID, [Year], [Month], MAX(Diuretic) AS Diuretic
INTO #Diuretic
FROM #DiureticAll
GROUP BY FK_Patient_Link_ID, [Year], [Month];


-- Create a table of all patients with medication date after the start date with all months from Jan 2019 till the current month=====================================================
-- All IDs of patients with GP events after the start date
IF OBJECT_ID('tempdb..#PatientsID') IS NOT NULL DROP TABLE #PatientsID;
SELECT DISTINCT FK_Patient_Link_ID
INTO #PatientsID FROM [RLS].[vw_GP_Medications]
WHERE MedicationDate >= @StartDate AND MedicationDate <= @EndDate;

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


-- Merge table=================================================================================================================================================================
-- Merge all information
IF OBJECT_ID('tempdb..#Table') IS NOT NULL DROP TABLE #Table;
SELECT p.FK_Patient_Link_ID, p.[Year], p.[Month], (p.[Year] - y.YearOfBirth) AS Age, gp.GPPracticeCode, gp.CCG, 
	   n.NSAIDS, d.Diuretic, a.ACEIARB
INTO #Table
FROM #PatientsAll p
LEFT OUTER JOIN #PatientYearOfBirth y ON p.FK_Patient_Link_ID = y.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientPracticeAndCCG gp ON p.FK_Patient_Link_ID = GP.FK_Patient_Link_ID
LEFT OUTER JOIN #NSAIDS n ON p.FK_Patient_Link_ID = n.FK_Patient_Link_ID AND p.[Year] = n.[Year] AND p.[Month] = n.[Month]
LEFT OUTER JOIN #Diuretic d ON p.FK_Patient_Link_ID = d.FK_Patient_Link_ID AND p.[Year] = d.[Year] AND p.[Month] = d.[Month]
LEFT OUTER JOIN #ACEIARB a ON p.FK_Patient_Link_ID = a.FK_Patient_Link_ID AND p.[Year] = a.[Year] AND p.[Month] = a.[Month];

-- Insert informaion of last month medications
IF OBJECT_ID('tempdb..#TableCount') IS NOT NULL DROP TABLE #TableCount;
SELECT *,
		LAG(NSAIDS) OVER (PARTITION BY FK_Patient_Link_ID ORDER BY [Year], [Month]) AS NSAIDS_last_month,
		LAG(Diuretic) OVER (PARTITION BY FK_Patient_Link_ID ORDER BY [Year], [Month]) AS Diuretic_last_month,
		LAG(ACEIARB) OVER (PARTITION BY FK_Patient_Link_ID ORDER BY [Year], [Month]) AS ACEIARB_last_month
INTO #TableCount
FROM #Table;

-- Count
SELECT [Year], [Month], CCG, GPPracticeCode AS GPPracticeId, 
	   SUM(CASE WHEN Age > 65 AND (ACEIARB IS NOT NULL OR ACEIARB_last_month IS NOT NULL) 
							  AND (Diuretic IS NOT NULL OR Diuretic_last_month IS NOT NULL) 
							  AND (NSAIDS IS NOT NULL OR NSAIDS_last_month IS NOT NULL) THEN 1 ELSE 0 END) AS NumberOfOver65PolyPharm,
	   SUM(CASE WHEN Age > 65 THEN 1 ELSE 0 END) AS NumberOfOver65s
FROM #TableCount
WHERE [Year] IS NOT NULL AND [Month] IS NOT NULL AND (CCG IS NOT NULL OR GPPracticeCode IS NOT NULL)
	  AND GPPracticeCode NOT LIKE '%DO NOT USE%' AND GPPracticeCode NOT LIKE '%TEST%'
GROUP BY [Year], [Month], CCG, GPPracticeCode;




