--┌─────────────┐
--│ Medications │
--└─────────────┘

-------- RESEARCH DATA ENGINEER CHECK ---------
-- Richard Williams	2021-11-26	Review complete

-- All prescriptions of medications for type 2 diabetes patients.

-- OUTPUT: Data with the following fields
-- 	-   PatientId (int)
--	-	MedicationCategory
--	-	PrescriptionDate (YYYY-MM-DD)

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2019-07-09';

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

------------------------------------------------------------------------------
--> EXECUTE query-build-rq032-cohort.sql
------------------------------------------------------------------------------

--> CODESET bnf-cardiovascular-meds:1 bnf-cns-meds:1 bnf-endocrine-meds:1

-- FIX ISSUE WITH DUPLICATE MEDICATIONS, CAUSED BY SOME CODES APPEARING MULTIPLE TIMES IN #VersionedCodeSets and #VersionedSnomedSets

IF OBJECT_ID('tempdb..#VersionedCodeSets_1') IS NOT NULL DROP TABLE #VersionedCodeSets_1;
SELECT DISTINCT FK_Reference_Coding_ID, Concept, [Version] INTO #VersionedCodeSets_1 FROM #VersionedCodeSets

IF OBJECT_ID('tempdb..#VersionedSnomedSets_1') IS NOT NULL DROP TABLE #VersionedSnomedSets_1;
SELECT DISTINCT FK_Reference_SnomedCT_ID, Concept, [Version] INTO #VersionedSnomedSets_1 FROM #VersionedSnomedSets


-- RX OF MEDS SINCE 09.07.19 FOR PATIENTS WITH T2D, WITH A FLAG FOR THE CATEGORY (CARDIOVASCULAR, ENDOCRINE, CNS)

IF OBJECT_ID('tempdb..#meds') IS NOT NULL DROP TABLE #meds;
SELECT 
	 m.FK_Patient_Link_ID,
	 CAST(MedicationDate AS DATE) as PrescriptionDate,
	 [concept] = CASE WHEN s.[concept] IS NOT NULL THEN s.[concept] ELSE c.[concept] END
INTO #meds
FROM RLS.vw_GP_Medications m
LEFT OUTER JOIN #VersionedSnomedSets_1 s ON s.FK_Reference_SnomedCT_ID = m.FK_Reference_SnomedCT_ID
LEFT OUTER JOIN #VersionedCodeSets_1 c ON c.FK_Reference_Coding_ID = m.FK_Reference_Coding_ID
WHERE m.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientIds)
	AND m.MedicationDate >= '2019-07-09' 
	AND (m.FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets_1) OR
		m.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets_1))
	AND UPPER(SourceTable) NOT LIKE '%REPMED%'  -- exclude duplicate prescriptions 
	AND RepeatMedicationFlag = 'N' 				-- exclude duplicate prescriptions 

-- Produce final table of all medication prescriptions for main and matched cohort
SELECT	 
	PatientId = m.FK_Patient_Link_ID
	,MainCohortMatchedPatientId = NULL
	,MedicationCategory = concept
	,PrescriptionDate
FROM #MainCohort m
LEFT JOIN #meds me ON me.FK_Patient_Link_ID = m.FK_Patient_Link_ID 
UNION
-- matched cohort
SELECT	 
	PatientId = m.FK_Patient_Link_ID
	,MainCohortMatchedPatientId = m.PatientWhoIsMatched 
	,MedicationCategory = concept
	,PrescriptionDate
FROM #MatchedCohort m
LEFT JOIN #meds me ON me.FK_Patient_Link_ID = m.FK_Patient_Link_ID 

