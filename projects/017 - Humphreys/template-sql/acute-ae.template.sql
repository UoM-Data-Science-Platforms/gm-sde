--┌────────────────┐
--│ Acute A&E data │
--└────────────────┘

-- OUTPUT: Data with the following fields
-- 	- PatientId (int)
-- 	- AttendanceDate (YYYY-MM-DD)
--	-	DischargeDate (YYYY-MM-DD)
--	-	ReasonForAttendanceCode
--	-	ReasonForAttendanceDescription

--Just want the output, not the messages
SET NOCOUNT ON;

-- For now let's use the in-built QOF rule for the RA cohort. We can refine this over time
--> EXECUTE query-qof-cohort.sql condition:"Rheumatoid Arthritis" outputtable:Patients

SELECT 
	FK_Patient_Link_ID AS PatientId,
	CAST(AttendanceDate AS DATE) AS AttendanceDate,
	CAST(DischargeDate AS DATE) AS DischargeDate,
	ReasonForAttendanceCode,
	ReasonForAttendanceDescription
FROM RLS.vw_Acute_AE
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);
