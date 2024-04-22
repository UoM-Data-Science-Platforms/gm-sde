--+--------------------------------------------------------------------------------+
--¦ Immunosupression (including HIV) longitudinal information (both cohorts)       ¦
--+--------------------------------------------------------------------------------+

-------- RESEARCH DATA ENGINEER CHECK ---------
-- George Tilston 06/10/23

-- OUTPUT: Data with the following fields
-- PatientId
-- EventDate (YYYY-MM-DD)


--> CODESET skin-cancer:1
--> CODESET gynaecological-cancer:1


-- Set the start date
DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2011-01-01';
SET @EndDate = '2023-09-22';

--Just want the output, not the messages
SET NOCOUNT ON;


-- Create the skin cancer cohort=====================================================================================================================================
IF OBJECT_ID('tempdb..#SkinCohort') IS NOT NULL DROP TABLE #SkinCohort;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #SkinCohort
FROM SharedCare.GP_Events
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'skin-cancer' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'skin-cancer' AND Version = 1)
) AND EventDate >= @StartDate AND EventDate < @EndDate;


-- Create the gynae cancer cohort========================================================================================================
IF OBJECT_ID('tempdb..#GynaeCohort') IS NOT NULL DROP TABLE #GynaeCohort;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #GynaeCohort
FROM SharedCare.GP_Events
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'gynaecological-cancer' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'gynaecological-cancer' AND Version = 1)
) AND EventDate >= @StartDate AND EventDate < @EndDate;


-- Create a table with all patients within 2 cohorts=========================================================================================================================
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT PK_Patient_Link_ID AS FK_Patient_Link_ID INTO #Patients
FROM SharedCare.Patient_Link
WHERE PK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #SkinCohort) 
      OR PK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #GynaeCohort);


--> CODESET immunosuppression:1 
--> CODESET hiv:1 


-- The final table============================================================================================================================================
IF OBJECT_ID('tempdb..#Table') IS NOT NULL DROP TABLE #Table;
SELECT 
	FK_Patient_Link_ID,
	EventDate
INTO #Table
FROM SharedCare.GP_Events
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'immunosuppression' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'immunosuppression' AND Version = 1)
) AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients) AND CONVERT(date, EventDate) < @EndDate
UNION
SELECT 
	FK_Patient_Link_ID,
	EventDate
FROM SharedCare.GP_Events
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'hiv' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'hiv' AND Version = 1)
) AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients) AND CONVERT(date, EventDate) < @EndDate;


SELECT DISTINCT FK_Patient_Link_ID AS PatientId, 
		CONVERT(date, EventDate) AS EventDate
FROM #Table
ORDER BY FK_Patient_Link_ID, EventDate;
