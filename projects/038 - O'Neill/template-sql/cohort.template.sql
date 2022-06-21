--┌────────────────────────────────────┐
--│ An example SQL generation template │
--└────────────────────────────────────┘

-- OUTPUT: Data with the following fields
-- 	- PatientId (int)
--  - DateOfFirstDiagnosis (YYYY-MM-DD) 

--Just want the output, not the messages
SET NOCOUNT ON;

--> CODESET hypertension:1
SELECT FK_Patient_Link_ID AS PatientId, MIN(EventDate) AS DateOfFirstDiagnosis FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'hypertension' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'hypertension' AND Version = 1)
)
GROUP BY FK_Patient_Link_ID;