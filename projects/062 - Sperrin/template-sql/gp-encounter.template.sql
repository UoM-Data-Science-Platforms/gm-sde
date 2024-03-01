--+--------------------------------------------------------------------------------+
--¦ GP encounter                                                                   ¦
--+--------------------------------------------------------------------------------+
-- !!! NEED TO DO: WHEN WE HAVE WEEK OF BIRTH, PLEASE CHANGE THE QUERY-BUILD-RQ062-COHORT.SQL TO UPDATE THE COHORT. ALSO ADD WEEK OF BRTH FOR THE TABLE BELOW. THANKS.
-- !!! NEED TO DO: DISCUSS TO MAKE SURE THE PROVIDED DATA IS NOT IDENTIFIABLE.

-------- RESEARCH DATA ENGINEER CHECK ---------


-- OUTPUT: Data with the following fields
-- - PatientId
-- - EncounterDate


--Just want the output, not the messages
SET NOCOUNT ON;

DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2011-01-01';
SET @EndDate = '2023-12-31';

--> EXECUTE query-build-rq062-cohort.sql

-- Create a table with all GP encounters ====================================================================================================================
IF OBJECT_ID('tempdb..#CodingClassifier') IS NOT NULL DROP TABLE #CodingClassifier;
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
SELECT 'Telephone', PK_Reference_Coding_ID, FK_Reference_SnomedCT_ID
FROM SharedCare.Reference_Coding
WHERE CodingType='ReadCodeV2'
AND (
	MainCode like '8H9%'
	or MainCode like '9N31%'
	or MainCode like '9N3A%'
);

-- Add the equivalent CTV3 codes
INSERT INTO #CodingClassifier
SELECT 'Face2face', PK_Reference_Coding_ID, FK_Reference_SnomedCT_ID FROM SharedCare.Reference_Coding
WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #CodingClassifier WHERE EncounterType='Face2face' AND FK_Reference_SnomedCT_ID != -1)
AND CodingType='CTV3';

INSERT INTO #CodingClassifier
SELECT 'Telephone', PK_Reference_Coding_ID, FK_Reference_SnomedCT_ID FROM SharedCare.Reference_Coding
WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #CodingClassifier WHERE EncounterType='Telephone' AND FK_Reference_SnomedCT_ID != -1)
AND CodingType='CTV3';

-- Add the equivalent EMIS codes
INSERT INTO #CodingClassifier
SELECT 'Face2face', FK_Reference_Coding_ID, FK_Reference_SnomedCT_ID FROM SharedCare.Reference_Local_Code
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #CodingClassifier WHERE EncounterType='Face2face' AND FK_Reference_SnomedCT_ID != -1) OR
	FK_Reference_Coding_ID IN (SELECT PK_Reference_Coding_ID FROM #CodingClassifier WHERE EncounterType='Face2face' AND PK_Reference_Coding_ID != -1)
);
INSERT INTO #CodingClassifier
SELECT 'Telephone', FK_Reference_Coding_ID, FK_Reference_SnomedCT_ID FROM SharedCare.Reference_Local_Code
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #CodingClassifier WHERE EncounterType='Telephone' AND FK_Reference_SnomedCT_ID != -1) OR
	FK_Reference_Coding_ID IN (SELECT PK_Reference_Coding_ID FROM #CodingClassifier WHERE EncounterType='Telephone' AND PK_Reference_Coding_ID != -1)
);

-- All above takes ~30s

IF OBJECT_ID('tempdb..#GPEncounters') IS NOT NULL DROP TABLE #GPEncounters;
CREATE TABLE #GPEncounters (
	FK_Patient_Link_ID BIGINT,
	EncounterDate DATE,
	FK_Reference_Coding_ID INT
);

INSERT INTO #GPEncounters 
SELECT DISTINCT FK_Patient_Link_ID, CAST(EventDate AS DATE) AS EncounterDate, FK_Reference_Coding_ID
FROM SharedCare.GP_Events
WHERE 
      FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
      AND FK_Reference_Coding_ID IN (SELECT PK_Reference_Coding_ID FROM #CodingClassifier WHERE PK_Reference_Coding_ID != -1)
      AND EventDate BETWEEN @StartDate AND @EndDate;


-- Merge with GP encounter types=================================================================================================================================
IF OBJECT_ID('tempdb..#GPEncountersFinal') IS NOT NULL DROP TABLE #GPEncountersFinal;
SELECT FK_Patient_Link_ID, EncounterDate, c.EncounterType
INTO #GPEncountersFinal
FROM #GPEncounters g
LEFT OUTER JOIN #CodingClassifier c ON g.FK_Reference_Coding_ID = c.PK_Reference_Coding_ID

--SELECT DISTINCT FK_Patient_Link_ID AS PatientId, EncounterDate, EncounterType
--FROM #GPEncountersFinal
--ORDER BY FK_Patient_Link_ID, EncounterDate;

SELECT FK_Patient_Link_ID, YEAR(EncounterDate) as [Year], COUNT(*) AS GPEncounters_Face2face
INTO #f2f
FROM #GPEncountersFinal
WHERE EncounterType = 'Face2face'
GROUP BY FK_Patient_Link_ID, YEAR(EncounterDate)

SELECT FK_Patient_Link_ID, YEAR(EncounterDate) as [Year], COUNT(*) AS GPEncounters_Telephone
INTO #telephone
FROM #GPEncountersFinal
WHERE EncounterType = 'Telephone'
GROUP BY FK_Patient_Link_ID, YEAR(EncounterDate)

-- The final table===============================================================================================================================================

SELECT 
    PatientId = f.FK_Patient_Link_ID,
    f.[Year], 
    f.GPEncounters_Face2face, 
    t.GPEncounters_Telephone 
FROM 
    #f2f f
LEFT JOIN 
    #telephone t ON t.FK_Patient_Link_ID = f.FK_Patient_Link_ID AND t.[Year] = f.[Year];