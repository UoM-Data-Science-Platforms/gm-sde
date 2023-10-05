--+--------------------------------------------------------------------------------+
--¦ Gynae cancer information from the Cancer Summary table (cohort 2)              ¦
--+--------------------------------------------------------------------------------+

-------- RESEARCH DATA ENGINEER CHECK ---------

-- OUTPUT: Data with the following fields
-- PatientId
-- DiagnosisDate (YYYY-MM-DD)
-- Benign (No)
-- TStatus (code values)
-- TumourGroup (Skin (excl Melanoma)/ Melanoma)
-- TumourSite (code values)
-- Histology (code values)
-- Differentiation (code values)
-- T_Stage (code values)
-- N_Stage (code values)
-- M_Stage (code values)


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


-- Create a table with all patients within the gynae cohort=========================================================================================================================
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT PK_Patient_Link_ID AS FK_Patient_Link_ID INTO #Patients
FROM SharedCare.Patient_Link
WHERE PK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #GynaeCohort);


-- The final table====================================================================================================================
SELECT  DISTINCT FK_Patient_Link_ID AS PatientId, 
	CONVERT(date, DiagnosisDate) AS DiagnosisDate,
	Benign,
	TStatus,
	TumourGroup,
	TumourSite,
	Histology,
	Differentiation,
	T_Stage,
	N_Stage,
	M_Stage
FROM [SharedCare].[CCC_PrimaryTumourDetails]
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
	  AND TumourGroup = 'Gynaecological'
	  AND CONVERT(date, DiagnosisDate) < @EndDate
ORDER BY FK_Patient_Link_ID, DiagnosisDate;

