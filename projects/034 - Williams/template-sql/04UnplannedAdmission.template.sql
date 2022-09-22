--+--------------------------------------------------------------------------------+
--¦ Primary care encounter followed by unplanned hospital admission within 10 days ¦
--+--------------------------------------------------------------------------------+

-------- RESEARCH DATA ENGINEER CHECK ---------

-- OUTPUT: Data with the following fields
-- Year (YYYY)
-- Month (1-12)
-- CCG (can be an anonymised id for each CCG)
-- GPPracticeId
-- NumberOfUnplannedAdmissionsFollowingEncounter (integer) The number of unique patients for this year, month, ccg and practice, who had an unplanned hospital admission within 10 days of a GP encounter
-- NumberOfGPEncounter (integer) The number of GP encounters for this month, year, ccg and gp
-- NumberOfUnplannedAdmissions (integer) The number of unplanned hospital admissions

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


--> EXECUTE query-patient-practice-and-ccg.sql
--> EXECUTE query-classify-secondary-admissions.sql
--> EXECUTE query-patient-gp-encounters.sql all-patients:F gp-events-table:[RLS].[vw_GP_Events] start-date:'2019-01-01' end-date:'2022-06-01'


-- Numbers of GP encounter=========================================================================================================================================
-- All GP encounters
IF OBJECT_ID('tempdb..#GPEncounter') IS NOT NULL DROP TABLE #GPEncounter;
SELECT DISTINCT FK_Patient_Link_ID, EncounterDate,
	   YEAR (EncounterDate) AS [Year], MONTH (EncounterDate) AS [Month], DAY (EncounterDate) AS [Day]
INTO #GPEncounter
FROM #GPEncounters;

-- Count the number of GP encounters for each month
IF OBJECT_ID('tempdb..#GPEncounterFinal') IS NOT NULL DROP TABLE #GPEncounterFinal;
SELECT FK_Patient_Link_ID, [Year], [Month], COUNT(Day) AS NumberOfGPEncounter
INTO #GPEncounterFinal
FROM #GPEncounter
GROUP BY FK_Patient_Link_ID, [Year], [Month];


-- Numbers of unplanned admission=============================================================================================================================
-- All unplanned admission
IF OBJECT_ID('tempdb..#UnplannedAdmission') IS NOT NULL DROP TABLE #UnplannedAdmission;
SELECT DISTINCT FK_Patient_Link_ID, AdmissionDate,
	   YEAR (AdmissionDate) AS [Year], MONTH (AdmissionDate) AS [Month], DAY (AdmissionDate) AS [Day]
INTO #UnplannedAdmission
FROM #AdmissionTypes
WHERE AdmissionType = 'Unplanned' AND AdmissionDate < @EndDate;

-- Count unplanned admission for each month
IF OBJECT_ID('tempdb..#UnplannedAdmissionFinal') IS NOT NULL DROP TABLE #UnplannedAdmissionFinal;
SELECT FK_Patient_Link_ID, [Year], [Month], COUNT(Day) AS NumberOfUnplannedAdmissions
INTO #UnplannedAdmissionFinal
FROM #UnplannedAdmission
GROUP BY FK_Patient_Link_ID, [Year], [Month];


-- Create a table with all patients ===============================================================================================================================
IF OBJECT_ID('tempdb..#PatientsID') IS NOT NULL DROP TABLE #PatientsID;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #PatientsID 
FROM [RLS].vw_Patient
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

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
DROP TABLE #Dates
DROP TABLE #Time


-- Find patients who had unplanned admission within 10 days from GP encouter=============================================================================
IF OBJECT_ID('tempdb..#TableMerge') IS NOT NULL DROP TABLE #TableMerge;
SELECT p.FK_Patient_Link_ID, g.EncounterDate, u.AdmissionDate
INTO #TableMerge
FROM #PatientsID p
LEFT OUTER JOIN #GPEncounter g ON p.FK_Patient_Link_ID = g.FK_Patient_Link_ID 
LEFT OUTER JOIN #UnplannedAdmission u ON p.FK_Patient_Link_ID = u.FK_Patient_Link_ID
WHERE u.AdmissionDate <= DATEADD(DAY, 10, g.EncounterDate) AND u.AdmissionDate >= g.EncounterDate;

IF OBJECT_ID('tempdb..#TableAdmissionAfterGP') IS NOT NULL DROP TABLE #TableAdmissionAfterGP;
SELECT DISTINCT FK_Patient_Link_ID, YEAR(EncounterDate) AS [Year], MONTH(EncounterDate) AS [Month], 'Y' AS AdmissionAfterGP
INTO #TableAdmissionAfterGP
FROM #TableMerge;


-- Merge table=================================================================================================================================================================
-- Merge all information
IF OBJECT_ID('tempdb..#Table') IS NOT NULL DROP TABLE #Table;
SELECT p.FK_Patient_Link_ID, p.[Year], p.[Month], gp.GPPracticeCode, gp.CCG, u.NumberOfUnplannedAdmissions, e.NumberOfGPEncounter, t.AdmissionAfterGP
INTO #Table
FROM #PatientsAll p
LEFT OUTER JOIN #PatientPracticeAndCCG gp ON p.FK_Patient_Link_ID = GP.FK_Patient_Link_ID
LEFT OUTER JOIN #UnplannedAdmissionFinal u ON p.FK_Patient_Link_ID = u.FK_Patient_Link_ID AND p.[Year] = u.[Year] AND p.[Month] = u.[Month]
LEFT OUTER JOIN #GPEncounterFinal e ON p.FK_Patient_Link_ID = e.FK_Patient_Link_ID AND p.[Year] = e.[Year] AND p.[Month] = e.[Month]
LEFT OUTER JOIN #TableAdmissionAfterGP t ON p.FK_Patient_Link_ID = t.FK_Patient_Link_ID AND p.[Year] = t.[Year] AND p.[Month] = t.[Month];

-- Count
SELECT [Year], [Month], CCG, GPPracticeCode AS GPPracticeId, 
	   SUM (CASE WHEN AdmissionAfterGP = 'Y' THEN 1 ELSE 0 END) AS NumberOfUnplannedAdmissionsFollowingEncounter,
	   SUM (NumberOfGPEncounter) AS NumberOfGPEncounter,
	   SUM (NumberOfUnplannedAdmissions) AS NumberOfUnplannedAdmissions
FROM #Table
WHERE [Year] IS NOT NULL AND [Month] IS NOT NULL AND (CCG IS NOT NULL OR GPPracticeCode IS NOT NULL)
	  AND GPPracticeCode NOT LIKE '%DO NOT USE%' AND GPPracticeCode NOT LIKE '%TEST%'
GROUP BY [Year], [Month], CCG, GPPracticeCode
ORDER BY [Year], [Month], CCG, GPPracticeCode;


