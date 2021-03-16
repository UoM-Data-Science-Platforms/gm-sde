--┌────────────────────────────────────┐
--│ An example SQL generation template │
--└────────────────────────────────────┘

-- OUTPUT: Data with the following fields
-- 	- PatientId (int)
--  - DateOfFirstDiagnosis (YYYY-MM-DD) 

--Just want the output, not the messages
SET NOCOUNT ON;

--> EXECUTE query-get-random-patient-id.sql

--> EXECUTE load-code-sets.sql

SELECT FK_Patient_Link_ID, MIN(EventDate) FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Coding_ID IN (SELECT FK_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'hypertension' AND Version = 2) OR
  FK_SNOMED_ID IN (SELECT FK_SNOMED_ID FROM #VersionedSnomedSets WHERE Concept = 'hypertension' AND Version = 2)
)
GROUP BY FK_Patient_Link_ID