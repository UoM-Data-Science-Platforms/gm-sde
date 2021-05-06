--┌────────────────┐
--│ Patient orders │
--└────────────────┘

------------------- RDE CHECK ---------------------
-- RDE Name: George Tilston, Date checked: 06/05/21

-- OUTPUT: Data with the following fields
-- 	- PatientId (int)
-- 	- ResultType
--	-	ResultCode
--	-	ResultDescription

--Just want the output, not the messages
SET NOCOUNT ON;

-- For now let's use the in-built QOF rule for the RA cohort. We can refine this over time
--> EXECUTE query-qof-cohort.sql condition:"Rheumatoid Arthritis" outputtable:Patients

SELECT FK_Patient_Link_ID AS PatientId, ResultType, ResultCode, ResultDescription
FROM RLS.vw_Orders
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);
