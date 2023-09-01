--+--------------------------------------------------------------------------------+
--¦ People with coded heart failure prescribed NSAIDs as repeat medication         ¦
--+--------------------------------------------------------------------------------+

-------- RESEARCH DATA ENGINEER CHECK ---------

-- OUTPUT: Data with the following fields
-- Year (YYYY)
-- Month (1-12)
-- CCG (can be an anonymised id for each CCG)
-- GPPracticeId
-- NumberOfHFandNSAID (integer) The number of unique patients per month, ccg and practice who have a previous diagnosis of heart failure, and who received a prescription for an NSAID in this month AND who also had an NSAID prescription in the preceding 2 months OR who had 2 or more NSAID prescriptions on different days in this month.
-- NumberOfNSAIDs (integer) The number of patients prescribed an NSAID in this month, ccg and practice.

-- Set the start date and end date
DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2018-01-01';
SET @EndDate = '2022-06-01';

--Just want the output, not the messages
SET NOCOUNT ON;


-- Create a table with all patients (ID)=========================================================================================================================
IF OBJECT_ID('tempdb..#PatientsToInclude') IS NOT NULL DROP TABLE #PatientsToInclude;
SELECT FK_Patient_Link_ID INTO #PatientsToInclude
FROM SharedCare.Patient_GP_History
GROUP BY FK_Patient_Link_ID
HAVING MIN(StartDate) < '2022-06-01';

IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #Patients 
FROM #PatientsToInclude;

--> CODESET nsaids:1
--> CODESET heart-failure:1

--> EXECUTE query-patient-practice-and-ccg.sql


-- Create a table of all patients ======================================================================================================================
-- All IDs of patients
IF OBJECT_ID('tempdb..#PatientsID') IS NOT NULL DROP TABLE #PatientsID;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #PatientsID 
FROM SharedCare.Patient
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

-- All years and months from the start date
IF OBJECT_ID('tempdb..#Dates') IS NOT NULL DROP TABLE #Dates;
CREATE TABLE #Dates (
  d DATE,
  PRIMARY KEY (d)
)

DECLARE @DateCounter DATE
SET @DateCounter = @StartDate

WHILE ( @DateCounter < @EndDate )
BEGIN
  INSERT INTO #Dates (d) VALUES( @DateCounter )
  SELECT @DateCounter = DATEADD(MONTH, 1, @DateCounter )
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


-- Create HF tables================================================================================================================================================
-- All HF records
IF OBJECT_ID('tempdb..#HFAll') IS NOT NULL DROP TABLE #HFAll;
SELECT FK_Patient_Link_ID, MONTH(EventDate) AS [Month], YEAR(EventDate) AS [Year], FK_Reference_Coding_ID, FK_Reference_SnomedCT_ID, 'HF' AS HF
INTO #HFAll
FROM SharedCare.GP_Events
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'heart-failure' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'heart-failure' AND Version = 1)
)
AND EventDate < @EndDate;

-- Delete duplicates
IF OBJECT_ID('tempdb..#HF') IS NOT NULL DROP TABLE #HF;
SELECT DISTINCT FK_Patient_Link_ID, [Year], [Month], HF
INTO #HF
FROM #HFAll;

-- Drop table
DROP TABLE #HFAll


-- NSAIDS tables====================================================================================================================================================
-- NSAIDS records in dates from 2018 (so we can count consecutive months for 2019)
IF OBJECT_ID('tempdb..#NSAIDSAll') IS NOT NULL DROP TABLE #NSAIDSAll;
SELECT DISTINCT FK_Patient_Link_ID, MONTH(MedicationDate) AS [Month], YEAR(MedicationDate) AS [Year], DAY(MedicationDate) AS NSAIDSDate, 'NSAIDS' AS NSAIDS
INTO #NSAIDSAll
FROM SharedCare.GP_Medications
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'nsaids' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'nsaids' AND Version = 1)
)
AND MedicationDate >= @StartDate AND MedicationDate <= @EndDate;

-- Delete duplicates
IF OBJECT_ID('tempdb..#NSAIDS') IS NOT NULL DROP TABLE #NSAIDS;
SELECT DISTINCT FK_Patient_Link_ID, [Year], [Month], MAX(NSAIDS) AS NSAIDS
INTO #NSAIDS
FROM #NSAIDSAll
GROUP BY FK_Patient_Link_ID, [Year], [Month];

-- A table with every month from Jan 2018 and NSAIDS information each month for each patients
IF OBJECT_ID('tempdb..#NSAIDSEveryMonth') IS NOT NULL DROP TABLE #NSAIDSEveryMonth;
SELECT p.FK_Patient_Link_ID, p.[Year], p.[Month], n.NSAIDS
INTO #NSAIDSEveryMonth
FROM #PatientsAll p
LEFT OUTER JOIN #NSAIDS n on p.FK_Patient_Link_ID = n.FK_Patient_Link_ID AND p.[Year] = n.[Year] AND p.[Month] = n.[Month];

-- Find NSAIDS from the preceding 2 months
IF OBJECT_ID('tempdb..#NSAIDSPreceding2Months') IS NOT NULL DROP TABLE #NSAIDSPreceding2Months;
SELECT FK_Patient_Link_ID, [Year], [Month],
	   CASE WHEN NSAIDS IS NOT NULL AND LAG(NSAIDS, 1) OVER (PARTITION BY FK_Patient_Link_ID ORDER BY [Year], [Month]) IS NOT NULL
				 AND LAG(NSAIDS, 2) OVER (PARTITION BY FK_Patient_Link_ID ORDER BY [Year], [Month]) IS NOT NULL
				 THEN 'Y' ELSE NULL END AS NSAIDS_3_consecutive_months
INTO #NSAIDSPreceding2Months
FROM #NSAIDSEveryMonth

-- Count numbers of NSAIDS a month
IF OBJECT_ID('tempdb..#NSAIDSNumberAMonth') IS NOT NULL DROP TABLE #NSAIDSNumberAMonth;
SELECT FK_Patient_Link_ID, [Year], [Month], COUNT (NSAIDSDate) AS NSAIDS_per_month
INTO #NSAIDSNumberAMonth
FROM #NSAIDSAll
GROUP BY FK_Patient_Link_ID, [Year], [Month];

-- Drop some tables
DROP TABLE #NSAIDS
DROP TABLE #NSAIDSEveryMonth


-- Merge table=================================================================================================================================================================
-- Merge all information
IF OBJECT_ID('tempdb..#Table') IS NOT NULL DROP TABLE #Table;
SELECT P.FK_Patient_Link_ID, p.[Year], p.[Month], p.d, gp.GPPracticeCode, gp.CCG, e.NSAIDS_3_consecutive_months, c.NSAIDS_per_month, h.HF
INTO #Table
FROM #PatientsAll p
LEFT OUTER JOIN #PatientPracticeAndCCG gp ON p.FK_Patient_Link_ID = GP.FK_Patient_Link_ID
LEFT OUTER JOIN #NSAIDSPreceding2Months e ON p.FK_Patient_Link_ID = e.FK_Patient_Link_ID AND p.[Year] = e.[Year] AND p.[Month] = e.[Month]
LEFT OUTER JOIN #NSAIDSNumberAMonth c ON p.FK_Patient_Link_ID = c.FK_Patient_Link_ID AND p.[Year] = c.[Year] AND p.[Month] = c.[Month]
LEFT OUTER JOIN #HF h ON p.FK_Patient_Link_ID = h.FK_Patient_Link_ID AND p.[Year] = h.[Year] AND p.[Month] = h.[Month]
ORDER BY p.FK_Patient_Link_ID, p.[Year], p.[Month];

-- Forward fill all HF diagnosis
IF OBJECT_ID('tempdb..#TableCount') IS NOT NULL DROP TABLE #TableCount;
SELECT *
		, CASE
			WHEN HF IS NULL THEN (
			SELECT TOP 1
				inner_table.HF
			FROM
				#Table AS inner_table
			WHERE
					inner_table.FK_Patient_Link_ID = t.FK_Patient_Link_ID
				AND inner_table.d < t.d
				AND inner_table.HF IS NOT NULL
				ORDER BY inner_table.d
			)
		ELSE
			HF
		END AS HF_fill
INTO #TableCount
FROM #Table t

--- Count
SELECT [Year], Month, CCG, GPPracticeCode AS GPPracticeId, 
	   SUM(CASE WHEN HF_fill IS NOT NULL AND (NSAIDS_3_consecutive_months = 'Y' OR NSAIDS_per_month >= 2) THEN 1 ELSE 0 END) AS NumberOfHFandNSAID,
	   SUM(CASE WHEN NSAIDS_per_month IS NOT NULL THEN 1 ELSE 0 END) AS NumberOfNSAIDs
FROM #TableCount
WHERE [Year] >= 2019 AND Month IS NOT NULL AND (CCG IS NOT NULL OR GPPracticeCode IS NOT NULL)
	  AND GPPracticeCode NOT LIKE '%DO NOT USE%' AND GPPracticeCode NOT LIKE '%TEST%'
GROUP BY [Year], [Month], CCG, GPPracticeCode
ORDER BY [Year], [Month], CCG, GPPracticeCode;




