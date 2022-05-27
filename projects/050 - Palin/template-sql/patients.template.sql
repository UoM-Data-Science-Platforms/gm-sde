--┌────────────────────────────────────┐
--│ An example SQL generation template │
--└────────────────────────────────────┘

-- OUTPUT: Data with the following fields
-- 	- PatientId (int)
--  - Registration date with GP (YYYY-MM)
--  - Date that patient left GP (YYYY-MM)
--  - Month and year of birth (YYYY-MM)
--  - Month and year of death (YYYY-MM)
--  - Ethnicity (white/black/asian/mixed/other)
--  - IMD decile (1-10)
--  - LSOA
--  - History of Comorbidities (one column per condition - info on conditions here. Other conditions included will be: preeclampsia, gestational diabetes, miscarriage, stillbirth, fetal growth restriction) (1,0)
--  - Pregnancy1: Estimated Pregnancy start month (YYYY-MM)
--  - Pregnancy1: Pregnancy Delivery month (YYYY-MM)
--  - Pregnancy1: Date of admission
--  - Pregnancy1: Length of stay
--  - Pregnancy1: Number of total medications prescribed in previous 12 months
--  - Pregnancy1: Number of unique medications prescribed in previous 12 months
--  - Number of pregnancies during study period


--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2018-03-01';
SET @EndDate = '2022-03-01';

--Just want the output, not the messages
SET NOCOUNT ON;

-- Find all patients alive at start date
IF OBJECT_ID('tempdb..#PossiblePatients') IS NOT NULL DROP TABLE #PossiblePatients;
SELECT PK_Patient_Link_ID as FK_Patient_Link_ID, EthnicMainGroup, DeathDate INTO #PossiblePatients FROM [RLS].vw_Patient_Link
WHERE (DeathDate IS NULL OR DeathDate >= @StartDate);

-- Find all patients registered with a GP
IF OBJECT_ID('tempdb..#PatientsWithGP') IS NOT NULL DROP TABLE #PatientsWithGP;
SELECT DISTINCT FK_Patient_Link_ID INTO #PatientsWithGP FROM [RLS].vw_Patient
where FK_Reference_Tenancy_ID = 2;

-- Make cohort from patients alive at start date and registered with a GP
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT pp.* INTO #Patients FROM #PossiblePatients pp
INNER JOIN #PatientsWithGP gp on gp.FK_Patient_Link_ID = pp.FK_Patient_Link_ID;


--> CODESET pregnancy:1



SELECT 
	FK_Patient_Link_ID AS PatientId, 
	MIN(EventDate) AS DateOfFirstDiagnosis 
FROM [RLS].[vw_GP_Events]
WHERE (
    FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'pregnancy' AND Version = 1) OR
    FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'pregnancy' AND Version = 1)
	)
	AND EventDate BETWEEN @StartDate
GROUP BY FK_Patient_Link_ID;