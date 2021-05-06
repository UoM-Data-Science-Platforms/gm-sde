--┌─────────────────────┐
--│ Observation results │
--└─────────────────────┘

----------------------- RDE CHECK -----------------------
--RDE Name: George Tilston, Date of check: 06/05/21

-- OUTPUT: Data with the following fields
-- 	- PatientId (int)
--	-	TestDescription
--	-	ResultMinimumValue (Currently redacted)
--	-	ResultMaximumValue(Currently redacted)
--	-	ResultFlag
--	-	ResultStatus
--	-	ResultValue	(Currently redacted)
--	-	ResultUnit

--Just want the output, not the messages
SET NOCOUNT ON;

-- For now let's use the in-built QOF rule for the RA cohort. We can refine this over time
--> EXECUTE query-qof-cohort.sql condition:"Rheumatoid Arthritis" outputtable:Patients

SELECT 
	FK_Patient_Link_ID AS PatientId,
	TestDescription,
	ResultMinimumValue,
	ResultMaximumValue,
	ResultFlag,
	ResultStatus,
	ResultValue,
	ResultUnit
FROM RLS.vw_Observation_Results
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);
