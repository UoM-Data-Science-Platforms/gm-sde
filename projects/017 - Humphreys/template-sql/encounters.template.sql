--┌───────────────────────┐
--│ Patient GP encounters │
--└───────────────────────┘

------------- RDE CHECK --------------
-- RDE Name: George Tilston, Date of check: 06/05/21

-- OUTPUT: Data with the following fields
-- 	- PatientId (int)
--	-	GPPracticeCode
--	-	CAST(EncounterDate AS DATE) AS EncounterDate
--	-	SuppliedCode
--	-	EncounterDescription (Currently redacted)
--	-	EncounterGroupDescription (Currently unused)
--	-	Notes (Currently redacted)

--Just want the output, not the messages
SET NOCOUNT ON;

-- For now let's use the in-built QOF rule for the RA cohort. We can refine this over time
--> EXECUTE query-qof-cohort.sql condition:"Rheumatoid Arthritis" outputtable:Patients

SELECT 
	FK_Patient_Link_ID AS PatientId,
	GPPracticeCode,
	CAST(EncounterDate AS DATE) AS EncounterDate,
	SuppliedCode,
	EncounterDescription,
	EncounterGroupDescription,
	Notes
FROM RLS.vw_GP_Encounters
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);
