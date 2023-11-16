--┌─────────────┐
--│ Medications │
--└─────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------
-- 
------------------------------------------------------

-- All prescriptions of: antipsychotic medication.

-- OUTPUT: Data with the following fields
-- 	-   PatientId (int)
--	-	MedicationDescription
--	-	MostRecentPrescriptionDate (YYYY-MM-DD)

--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = 'CHANGE';
SET @EndDate = 'CHANGE';

--> EXECUTE query-build-lh003-cohort.sql


-- PATIENTS WITH RX OF MEDS

IF OBJECT_ID('tempdb..#meds') IS NOT NULL DROP TABLE #meds;
SELECT 
	 m.FK_Patient_Link_ID,
		CAST(MedicationDate AS DATE) as PrescriptionDate,
		[description] = CASE WHEN s.[description] IS NOT NULL THEN s.[description] ELSE c.[description] END
INTO #meds
FROM RLS.vw_GP_Medications m
LEFT OUTER JOIN #VersionedSnomedSets s ON s.FK_Reference_SnomedCT_ID = m.FK_Reference_SnomedCT_ID
LEFT OUTER JOIN #VersionedCodeSets c ON c.FK_Reference_Coding_ID = m.FK_Reference_Coding_ID
WHERE m.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort)
AND m.MedicationDate BETWEEN @StartDate AND @EndDate
AND (
	m.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN () AND [Version]=1) OR
    m.FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN () AND [Version]=1)
);




