--+------------------------------------------------------------------------------------------------------------+
--¦ Create counting tables for each medications based on GPEvents table - RQ051                                ¦
--+------------------------------------------------------------------------------------------------------------+

-- OBJECTIVE: To build the counting tables for each mental medications for RQ051. This reduces duplication of code in the template scripts.

-- COHORT: Any patient in the [RLS].[vw_GP_Medications]

-- INPUT: Assumes there exists one temp table as follows:
-- #GPMedications (FK_Patient_Link_ID, MedicationDate, FK_Reference_Coding_ID, FK_Reference_SnomedCT_ID)
-- Need to fill the 'medication' and 'version' and 'conditionname'

-- OUTPUT: Temp tables as follows:
-- #First{param:medicationname}Counts

------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Table for episode counts
IF OBJECT_ID('tempdb..#First{param:medicationname}Counts') IS NOT NULL DROP TABLE #First{param:medicationname}Counts;
SELECT DISTINCT FK_Patient_Link_ID, CAST(MedicationDate AS DATE) AS EpisodeDate  --DISTINCT + CAST to ensure only one episode per day per patient is counted
INTO #First{param:medicationname}Counts
FROM #GPMedications
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = '{param:medication}' AND Version = '{param:version}') OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = '{param:medication}' AND Version = '{param:version}')
) AND MedicationDate < '2022-06-01' AND CAST(MedicationDate AS DATE) >= '2019-01-01' AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude); 
