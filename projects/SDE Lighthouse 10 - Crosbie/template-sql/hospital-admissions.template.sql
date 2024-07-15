--┌───────────────────────────────────────────┐
--│ Hospital stay information for cohort      │
--└───────────────────────────────────────────┘

---- RESEARCH DATA ENGINEER CHECK ----

--------------------------------------

-- OUTPUT: Data with the following fields
-- Patient Id
-- AdmissionDate (DD-MM-YYYY)
-- DischargeDate (DD-MM-YYYY)

--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = 'CHANGE';
SET @EndDate = 'CHANGE';

--> EXECUTE query-build-lh009-cohort.sql
----------------------------------------------------------------------------------------

--> EXECUTE query-get-admissions-and-length-of-stay.sql all-patients:false
--> EXECUTE query-classify-secondary-admissions.sql 

--bring together for final output
SELECT 
	PatientId = m.FK_Patient_Link_ID,
	l.AdmissionDate,
	l.DischargeDate,
	a.AdmissionType
FROM #Cohort m 
LEFT JOIN #LengthOfStay l ON m.FK_Patient_Link_ID = l.FK_Patient_Link_ID
LEFT JOIN #AdmissionTypes a ON a.FK_Patient_Link_ID = l.FK_Patient_Link_ID AND a.AdmissionDate = l.AdmissionDate
WHERE l.AdmissionDate BETWEEN @StartDate AND @EndDate
