--┌───────────┐
--│ GP Events │
--└───────────┘

------------- RDE CHECK --------------
-- RDE Name: George Tilston, Date of check: 06/05/21

-- All GP events for the cohort of RA patients

-- OUTPUT: Data with the following fields
-- 	- PatientId (int)
-- 	- GPPracticeCode
--	-	EventDate (YYYY-MM-DD)
--	-	SuppliedCode
--	-	Units
--	-	Value
--	-	SensitivityDormant
--	-	EventNo

--Just want the output, not the messages
SET NOCOUNT ON;

-- For now let's use the in-built QOF rule for the RA cohort. We can refine this over time
--> EXECUTE query-qof-cohort.sql condition:"Rheumatoid Arthritis" outputtable:Patients

SELECT 
	FK_Patient_Link_ID AS PatientId,
	GPPracticeCode,
	CAST(EventDate AS DATE) AS EventDate,
	SuppliedCode,
	Units,
	Value,
	SensitivityDormant,
	EventNo
FROM RLS.vw_GP_Events
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);
