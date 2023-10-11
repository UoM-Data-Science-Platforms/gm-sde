--+--------------------------------------------------------------------------------+
--¦ Skin cancer information from the Cancer Summary table (cohort 1)               ¦
--+--------------------------------------------------------------------------------+

-------- RESEARCH DATA ENGINEER CHECK ---------
-- George Tilston 06/10/23

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


--> CODESET skin-cancer:1


-- Set the start date
DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2011-01-01';
SET @EndDate = GETDATE();

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


-- Create a table with all patients within th e skin cohort=========================================================================================================================
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT PK_Patient_Link_ID AS FK_Patient_Link_ID INTO #Patients
FROM SharedCare.Patient_Link
WHERE PK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #SkinCohort);


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
	AND (TumourGroup = 'Skin (excl Melanoma)' OR TumourGroup = 'Melanoma')
	AND CONVERT(date, DiagnosisDate) < @EndDate
ORDER BY FK_Patient_Link_ID, DiagnosisDate;

