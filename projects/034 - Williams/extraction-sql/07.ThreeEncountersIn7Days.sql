--+--------------------------------------------------------------------------------+
--¦ 3 or more GP encounters in 7 days                                              ¦
--+--------------------------------------------------------------------------------+

-------- RESEARCH DATA ENGINEER CHECK ---------

-- OUTPUT: Data with the following fields
-- PatientId
-- Date (YYYY/MM/DD) 

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2019-01-01';

--Just want the output, not the messages
SET NOCOUNT ON;


-- Create a table with all GP encouters (provided by the PI)========================================================================================================
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

SELECT DISTINCT FK_Patient_Link_ID, CAST(EventDate AS DATE) AS EntryDate FROM RLS.vw_GP_Events
WHERE FK_Reference_Coding_ID IN (SELECT PK_Reference_Coding_ID FROM #CodingClassifier)
AND EventDate >= '2019-01-01'
AND EventDate < '2019-02-01'
--2,242,912 records in 4m21

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

IF OBJECT_ID('tempdb..#GPEncounter') IS NOT NULL DROP TABLE #GPEncounter;
SELECT DISTINCT FK_Patient_Link_ID, EntryDate AS EncounterDate
INTO #GPEncounter
FROM #Encounters


-- Find the first last and the second last of each GP encounter for each patient=========================================================================
IF OBJECT_ID('tempdb..#Table') IS NOT NULL DROP TABLE #Table;
SELECT *,
		LAG(EncounterDate, 1) OVER (PARTITION BY FK_Patient_Link_ID ORDER BY EncounterDate) AS First_last_GP_encounter,
		LAG(EncounterDate, 2) OVER (PARTITION BY FK_Patient_Link_ID ORDER BY EncounterDate) AS Second_last_GP_encounter
INTO #Table
FROM #GPEncounter;


-- The final table=======================================================================================================================================
-- Do some checks
IF OBJECT_ID('tempdb..#TableCheck') IS NOT NULL DROP TABLE #TableCheck;
SELECT *,
		CASE WHEN EncounterDate <= DATEADD(DAY, 7, First_last_GP_encounter) AND EncounterDate <= DATEADD(DAY, 7, Second_last_GP_encounter)
	    THEN 'Y' ELSE 'N' END AS Check_criteria
INTO #TableCheck
FROM #Table;

-- Create the final table
IF OBJECT_ID('tempdb..#ThreeEncountersIn7Days') IS NOT NULL DROP TABLE #ThreeEncountersIn7Days;
SELECT FK_Patient_Link_ID AS PatientID, EncounterDate AS Date
INTO #ThreeEncountersIn7Days
FROM #TableCheck
WHERE Check_criteria = 'Y' AND YEAR (EncounterDate) >= 2019;


