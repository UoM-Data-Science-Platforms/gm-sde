--┌─────────────────────┐
--│ Observation results │
--└─────────────────────┘

----------------------- RDE CHECK -----------------------
--RDE Name: George Tilston, Date of check: 06/05/21

-- OUTPUT: Data with the following fields
-- 	- PatientId (int)
--	-	ResultType
--	-	ResultCode
--	-	ResultDescription
--	-	SourceDate
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
	ord.FK_Patient_Link_ID AS PatientId, 
	ord.ResultType,
	ord.ResultCode,
	ord.ResultDescription,
	ord.SourceDate,
	res.TestDescription,
	res.ResultMinimumValue,
	res.ResultMaximumValue,
	res.ResultFlag,
	res.ResultStatus,
	res.ResultValue,
	res.ResultUnit
FROM RLS.vw_Orders ord
LEFT OUTER JOIN RLS.vw_Observation_Results res ON res.FK_Order_ID = ord.PK_Order_ID
WHERE ord.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);
