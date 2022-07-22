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
SET @StartDate = '2019-01-01';

--Just want the output, not the messages
SET NOCOUNT ON;

-- Create a table with all patients (ID)=========================================================================================================================
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT DISTINCT FK_Patient_Link_ID INTO #Patients FROM [RLS].vw_Patient;

--> EXECUTE query-patient-practice-and-ccg.sql
--> EXECUTE query-classify-secondary-admissions.sql


-- Count GP encouters each month (this script was provided by the PI)======================================================================================================================
SELECT 'Face2face' AS EncounterType, PK_Reference_Coding_ID, FK_Reference_SnomedCT_ID
INTO #CodingClassifier
FROM SharedCare.Reference_Coding
WHERE CodingType='ReadCodeV2'
AND (
	MainCode like '1%'
	or MainCode like '2%'
	or MainCode in ('6A2..','6A9..','6AA..','6AB..','662d.','662e.','66AS.','66AS0','66AT.','66BB.','66f0.','66YJ.','66YM.','661Q.','66480','6AH..','6A9..','66p0.','6A2..','66Ay.','66Az.','69DC.')
	or MainCode like '6A%'
	or MainCode like '65%'
	or MainCode like '8B31[356]%'
	or MainCode like '8B3[3569ADEfilOqRxX]%'
	or MainCode in ('8BS3.')
	or MainCode like '8H[4-8]%' 
	or MainCode like '94Z%'
	or MainCode like '9N1C%' 
	or MainCode like '9N21%'
	or MainCode in ('9kF1.','9kR..','9HB5.')
	or MainCode like '9H9%'
);

INSERT INTO #CodingClassifier
SELECT 'A+E', PK_Reference_Coding_ID, FK_Reference_SnomedCT_ID
FROM SharedCare.Reference_Coding
WHERE CodingType='ReadCodeV2'
AND (
	MainCode like '8H2%'
	or MainCode like '8H[1-3]%'
	or MainCode in ('9N19.','8HJA.','8HC..','8Hu..','8HC1.','ZL91.','9b00.','9b8D.','9b61.','8Hd1.','ZLD2100','8HE8.','8HJ..','8HJJ.','ZLE1.','ZL51.')
);

INSERT INTO #CodingClassifier
SELECT 'Telephone', PK_Reference_Coding_ID, FK_Reference_SnomedCT_ID
FROM SharedCare.Reference_Coding
WHERE CodingType='ReadCodeV2'
AND (
	MainCode like '8H9%'
	or MainCode like '9N31%'
	or MainCode like '9N3A%'
);

INSERT INTO #CodingClassifier
SELECT 'Hospital', PK_Reference_Coding_ID, FK_Reference_SnomedCT_ID
FROM SharedCare.Reference_Coding
WHERE CodingType='ReadCodeV2'
AND (
	MainCode like '7%'
	or MainCode like '8H[1-3]%'
	or MainCode like '9N%' 
);

-- Add the equivalent CTV3 codes
INSERT INTO #CodingClassifier
SELECT 'Face2face', PK_Reference_Coding_ID, FK_Reference_SnomedCT_ID FROM SharedCare.Reference_Coding
WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #CodingClassifier WHERE EncounterType='Face2face' AND FK_Reference_SnomedCT_ID != -1)
AND CodingType='CTV3';
INSERT INTO #CodingClassifier
SELECT 'A+E', PK_Reference_Coding_ID, FK_Reference_SnomedCT_ID FROM SharedCare.Reference_Coding
WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #CodingClassifier WHERE EncounterType='A+E' AND FK_Reference_SnomedCT_ID != -1)
AND CodingType='CTV3';
INSERT INTO #CodingClassifier
SELECT 'Telephone', PK_Reference_Coding_ID, FK_Reference_SnomedCT_ID FROM SharedCare.Reference_Coding
WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #CodingClassifier WHERE EncounterType='Telephone' AND FK_Reference_SnomedCT_ID != -1)
AND CodingType='CTV3';
INSERT INTO #CodingClassifier
SELECT 'Hospital', PK_Reference_Coding_ID, FK_Reference_SnomedCT_ID FROM SharedCare.Reference_Coding
WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #CodingClassifier WHERE EncounterType='Hospital' AND FK_Reference_SnomedCT_ID != -1)
AND CodingType='CTV3';

-- Add the equivalent EMIS codes
INSERT INTO #CodingClassifier
SELECT 'Face2face', FK_Reference_Coding_ID, FK_Reference_SnomedCT_ID FROM SharedCare.Reference_Local_Code
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #CodingClassifier WHERE EncounterType='Face2face' AND FK_Reference_SnomedCT_ID != -1) OR
	FK_Reference_Coding_ID IN (SELECT PK_Reference_Coding_ID FROM #CodingClassifier WHERE EncounterType='Face2face' AND PK_Reference_Coding_ID != -1)
);
INSERT INTO #CodingClassifier
SELECT 'A+E', FK_Reference_Coding_ID, FK_Reference_SnomedCT_ID FROM SharedCare.Reference_Local_Code
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #CodingClassifier WHERE EncounterType='A+E' AND FK_Reference_SnomedCT_ID != -1) OR
	FK_Reference_Coding_ID IN (SELECT PK_Reference_Coding_ID FROM #CodingClassifier WHERE EncounterType='A+E' AND PK_Reference_Coding_ID != -1)
);
INSERT INTO #CodingClassifier
SELECT 'Telephone', FK_Reference_Coding_ID, FK_Reference_SnomedCT_ID FROM SharedCare.Reference_Local_Code
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #CodingClassifier WHERE EncounterType='Telephone' AND FK_Reference_SnomedCT_ID != -1) OR
	FK_Reference_Coding_ID IN (SELECT PK_Reference_Coding_ID FROM #CodingClassifier WHERE EncounterType='Telephone' AND PK_Reference_Coding_ID != -1)
);
INSERT INTO #CodingClassifier
SELECT 'Hospital', FK_Reference_Coding_ID, FK_Reference_SnomedCT_ID FROM SharedCare.Reference_Local_Code
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #CodingClassifier WHERE EncounterType='Hospital' AND FK_Reference_SnomedCT_ID != -1) OR
	FK_Reference_Coding_ID IN (SELECT PK_Reference_Coding_ID FROM #CodingClassifier WHERE EncounterType='Hospital' AND PK_Reference_Coding_ID != -1)
);

-- All above takes ~30s

-- Below is split up, because doing it without the date filter led to 
-- an out of memory exception.

SELECT DISTINCT FK_Patient_Link_ID, CAST(EventDate AS DATE) AS EntryDate
INTO #Encounters
FROM RLS.vw_GP_Events
WHERE FK_Reference_Coding_ID IN (SELECT PK_Reference_Coding_ID FROM #CodingClassifier)
AND EventDate >= '2019-01-01'
AND EventDate < '2020-01-01';
-- 26,573,504 records, 6m26

INSERT INTO #Encounters
SELECT DISTINCT FK_Patient_Link_ID, CAST(EventDate AS DATE) AS EntryDate
FROM RLS.vw_GP_Events
WHERE FK_Reference_Coding_ID IN (SELECT PK_Reference_Coding_ID FROM #CodingClassifier)
AND EventDate >= '2020-01-01'
AND EventDate < '2021-01-01';
-- 21,971,922 records, 5m28

INSERT INTO #Encounters
SELECT DISTINCT FK_Patient_Link_ID, CAST(EventDate AS DATE) AS EntryDate
FROM RLS.vw_GP_Events
WHERE FK_Reference_Coding_ID IN (SELECT PK_Reference_Coding_ID FROM #CodingClassifier)
AND EventDate >= '2021-01-01'
AND EventDate < '2022-01-01';
-- 25,879,476 records, 5m23

INSERT INTO #Encounters
SELECT DISTINCT FK_Patient_Link_ID, CAST(EventDate AS DATE) AS EntryDate
FROM RLS.vw_GP_Events
WHERE FK_Reference_Coding_ID IN (SELECT PK_Reference_Coding_ID FROM #CodingClassifier)
AND EventDate >= '2022-01-01'
AND EventDate < '2023-01-01';
--5,488,868 records, 18m 54


-- Numbers of GP encounter=========================================================================================================================================
-- All GP encounters
IF OBJECT_ID('tempdb..#GPEncounter') IS NOT NULL DROP TABLE #GPEncounter;
SELECT DISTINCT FK_Patient_Link_ID, EntryDate,
	   YEAR (EntryDate) AS [Year], MONTH (EntryDate) AS [Month], DAY (EntryDate) AS [Day]
INTO #GPEncounter
FROM #Encounters;

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
WHERE AdmissionType = 'Unplanned';

-- Count unplanned admission for each month
IF OBJECT_ID('tempdb..#UnplannedAdmissionFinal') IS NOT NULL DROP TABLE #UnplannedAdmissionFinal;
SELECT FK_Patient_Link_ID, [Year], [Month], COUNT(Day) AS NumberOfUnplannedAdmissions
INTO #UnplannedAdmissionFinal
FROM #UnplannedAdmission
GROUP BY FK_Patient_Link_ID, [Year], [Month];


-- Create a table with all patients ===============================================================================================================================
IF OBJECT_ID('tempdb..#PatientsID') IS NOT NULL DROP TABLE #PatientsID;
SELECT DISTINCT FK_Patient_Link_ID INTO #PatientsID FROM [RLS].vw_Patient;

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
DROP TABLE #Dates
DROP TABLE #Time


-- Find patients who had unplanned admission within 10 days from GP encouter=============================================================================
IF OBJECT_ID('tempdb..#TableMerge') IS NOT NULL DROP TABLE #TableMerge;
SELECT p.FK_Patient_Link_ID, g.EntryDate, u.AdmissionDate
INTO #TableMerge
FROM #PatientsID p
LEFT OUTER JOIN #GPEncounter g ON p.FK_Patient_Link_ID = g.FK_Patient_Link_ID 
LEFT OUTER JOIN #UnplannedAdmission u ON p.FK_Patient_Link_ID = u.FK_Patient_Link_ID
WHERE u.AdmissionDate <= DATEADD(DAY, 10, g.EntryDate) AND u.AdmissionDate >= g.EntryDate;

IF OBJECT_ID('tempdb..#TableAdmissionAfterGP') IS NOT NULL DROP TABLE #TableAdmissionAfterGP;
SELECT DISTINCT FK_Patient_Link_ID, YEAR(EntryDate) AS [Year], MONTH(EntryDate) AS [Month], 'Y' AS AdmissionAfterGP
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
GROUP BY [Year], [Month], CCG, GPPracticeCode;


