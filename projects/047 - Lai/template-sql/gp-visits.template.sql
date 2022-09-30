--┌────────────────────────────────────┐
--│ GP Visits                          │
--└────────────────────────────────────┘

-- OUTPUT: Data with the following fields
-- PatientId
-- YearOfBirth
-- Sex
-- Ethnicity
-- LSOA_Code
-- IMDGroup
-- DateOfGPVisit (YYYY-MM-DD)
-- GPVisitType


--Just want the output, not the messages
SET NOCOUNT ON;


-- Set the start and end date====================================================================================================================================
DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2018-01-01';
SET @EndDate = '2022-06-01';


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


--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-year-of-birth.sql
--> EXECUTE query-patient-practice-and-ccg.sql
--> EXECUTE query-patient-lsoa.sql
--> EXECUTE query-patient-imd.sql


-- Create a cohort table (all patients with skin cancer or gynaecology)===========================================================================================
IF OBJECT_ID('tempdb..#Cohort') IS NOT NULL DROP TABLE #Cohort;
SELECT DISTINCT(FK_Patient_Link_ID)
INTO #Cohort
FROM [SharedCare].[CCC_PrimaryTumourDetails]
WHERE (TumourGroup = 'Gynaecological' OR TumourGroup = 'Skin (excl Melanoma)') 
      AND DiagnosisDate < @EndDate AND DiagnosisDate >= @StartDate;


-- Add GP visit type to table #GPEncounters=======================================================================================================================
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

BEGIN
  IF 'F'='true'
    INSERT INTO #GPEncounters 
    SELECT DISTINCT FK_Patient_Link_ID, CAST(EventDate AS DATE) AS EncounterDate, FK_Reference_Coding_ID
    FROM [RLS].[vw_GP_Events]
    WHERE 
      FK_Reference_Coding_ID IN (SELECT PK_Reference_Coding_ID FROM #CodingClassifier WHERE PK_Reference_Coding_ID != -1)
      AND EventDate BETWEEN '2018-01-01' AND '2022-06-01'
  ELSE 
    INSERT INTO #GPEncounters 
    SELECT DISTINCT FK_Patient_Link_ID, CAST(EventDate AS DATE) AS EncounterDate, FK_Reference_Coding_ID
    FROM [RLS].[vw_GP_Events]
    WHERE 
      FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
      AND FK_Reference_Coding_ID IN (SELECT PK_Reference_Coding_ID FROM #CodingClassifier WHERE PK_Reference_Coding_ID != -1)
      AND EventDate BETWEEN '2018-01-01' AND '2022-06-01'
  END


-- Select ethnicity from PatientLink table================================================================================================================================
IF OBJECT_ID('tempdb..#PatientLinkTable') IS NOT NULL DROP TABLE #PatientLinkTable;
SELECT PK_Patient_Link_ID AS FK_Patient_Link_ID, EthnicMainGroup AS Ethnic
INTO #PatientLinkTable
FROM RLS.vw_Patient_Link;


-- Create the table of IDM================================================================================================================================
IF OBJECT_ID('tempdb..#IMDGroup') IS NOT NULL DROP TABLE #IMDGroup;
SELECT FK_Patient_Link_ID, IMDGroup = CASE 
		WHEN IMD2019Decile1IsMostDeprived10IsLeastDeprived IN (1,2) THEN 1 
		WHEN IMD2019Decile1IsMostDeprived10IsLeastDeprived IN (3,4) THEN 2 
		WHEN IMD2019Decile1IsMostDeprived10IsLeastDeprived IN (5,6) THEN 3
		WHEN IMD2019Decile1IsMostDeprived10IsLeastDeprived IN (7,8) THEN 4
		WHEN IMD2019Decile1IsMostDeprived10IsLeastDeprived IN (9,10) THEN 5
		ELSE NULL END
INTO #IMDGroup
FROM #PatientIMDDecile;


-- Create the GP visit table==============================================================================================
SELECT c.FK_Patient_Link_ID AS PatientId, yob.YearOfBirth, s.Sex, l.Ethnic,
		lsoa.LSOA_Code, imd.IMDGroup, e.EncounterDate AS DateOfGPVisit, code.EncounterType AS GPVisitType
FROM #Cohort c
LEFT OUTER JOIN #PatientSex s ON s.FK_Patient_Link_ID = c.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = c.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientLSOA lsoa ON lsoa.FK_Patient_Link_ID = c.FK_Patient_Link_ID
LEFT OUTER JOIN #IMDGroup imd ON imd.FK_Patient_Link_ID = c.FK_Patient_Link_ID
LEFT OUTER JOIN #GPEncounters e ON e.FK_Patient_Link_ID = c.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientLinkTable l ON l.FK_Patient_Link_ID = c.FK_Patient_Link_ID
LEFT OUTER JOIN #CodingClassifier code ON code.PK_Reference_Coding_ID = e.FK_Reference_Coding_ID;








