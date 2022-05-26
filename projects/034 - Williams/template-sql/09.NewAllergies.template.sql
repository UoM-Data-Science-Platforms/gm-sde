--+---------------------------------------------------------------------------+
--¦ Patients with a new allergy code                                          ¦
--+---------------------------------------------------------------------------+

-------- RESEARCH DATA ENGINEER CHECK ---------

-- OUTPUT: Data with the following fields
-- PatientId
-- Date (YYYY/MM/DD) 

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2019-01-01';

--Just want the output, not the messages
SET NOCOUNT ON;

-- Create a table with all patients (ID)=========================================================================================================================
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT DISTINCT FK_Patient_Link_ID INTO #Patients FROM [RLS].vw_Patient;

--> CODESET allergy:1

-- Create a table of all patients with GP events after the start date========================================================================================================
IF OBJECT_ID('tempdb..#AllergyAll') IS NOT NULL DROP TABLE #AllergyAll;
SELECT DISTINCT FK_Patient_Link_ID, TRY_CONVERT(DATE, EventDate) AS EventDate, FK_Reference_Coding_ID
INTO #AllergyAll
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'allergy' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'allergy' AND Version = 1)
);

-- Create the table of new allergy code=============================================================================================================
IF OBJECT_ID('tempdb..#NewAllergies') IS NOT NULL DROP TABLE #NewAllergies;
SELECT FK_Patient_Link_ID AS PatientId, MIN(EventDate) AS Date
INTO #NewAllergies
FROM #AllergyAll
GROUP BY FK_Patient_Link_ID, FK_Reference_Coding_ID;
