--+--------------------------------------------------------------------------------+
--¦ Hormone replacement therapy longitudinal information (gynae cohort)            ¦
--+--------------------------------------------------------------------------------+

-------- RESEARCH DATA ENGINEER CHECK ---------

-- OUTPUT: Data with the following fields
-- PatientId
-- MedicationDate (YYYY-MM-DD)


--> CODESET gynaecological-cancer:1


-- Set the start date
DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2011-01-01';
SET @EndDate = GETDATE();

--Just want the output, not the messages
SET NOCOUNT ON;


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


--> CODESET hormone-replacement-therapy-meds:1 


-- The final table============================================================================================================================================
SELECT DISTINCT FK_Patient_Link_ID AS PatientId, 
		CONVERT(date, MedicationDate) AS MedicationDate
FROM SharedCare.GP_Medications
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'hormone-replacement-therapy-meds' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'hormone-replacement-therapy-meds' AND Version = 1)
) AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients) AND CONVERT(date, MedicationDate) < @EndDate
ORDER BY FK_Patient_Link_ID, MedicationDate;
