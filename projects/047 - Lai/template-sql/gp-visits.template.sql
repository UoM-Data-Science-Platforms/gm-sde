--┌────────────────────────────────────┐
--│ GP Visits                          │
--└────────────────────────────────────┘

-- OUTPUT: Data with the following fields
-- 	- PatientId (int)
--  - DateOfVisit (YYYY-MM-DD)
--  - Purpose of visit/Diagnosis (Cancer site)
--  - GP encounter type

--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2018-01-01';

-- TODO: We need the patients table here. We can either copy the code from patients.template.sql 
-- or add the code in the shared folder. 

SELECT 
	FK_Patient_Link_ID AS PatientId,
	GPPracticeCode,
	CAST(EncounterDate AS DATE) AS DateOfVisit,
	SuppliedCode, -- Is this needed? 
	EncounterDescription,
	EncounterGroupDescription
FROM RLS.vw_GP_Encounters
WHERE 
    FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
    AND EncounterDate >= @StartDate;
