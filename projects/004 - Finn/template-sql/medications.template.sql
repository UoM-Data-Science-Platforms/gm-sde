--┌─────────────────────────────────┐
--│ Medications                     │
--└─────────────────────────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------
-- RICHARD WILLIAMS |	DATE: 20/07/21

-- All medications for all patients in the study cohort one year before the index date.

-- OUTPUT: Data with the following fields
--     PatientId (Int)
--     MedicationDate (YYYY-MM-DD)
--     DrugCode (Nvarchar)
--     Quantity (Nvarchar)
--     Dosage (Nvarchar)
--     Last Issue Date (YYYY-MM-DD)
--	   Units
--     RepeatMedicationFlag e.g. (Y, N, Null)
--     MedicationStartDate (YYYY-MM-DD)
--     MedicationEndDate (YYYY-MM-DD)




--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2020-02-01';

-- Get all the patients in the cohort
--> EXECUTE query-cancer-cohort-matching.sql
-- OUTPUTS: #Patients


SELECT 
	FK_Patient_Link_ID AS PatientId,
	CAST(MedicationDate AS DATE) AS MedicationDate,
	SuppliedCode AS DrugCode,
	Quantity,
	'''' + Dosage + '''' As Dosage,
	LastIssueDate,
	Units,  
	RepeatMedicationFlag,
	CAST(MedicationStartDate AS DATE) AS MedicationStartDate,
	CAST(MedicationEndDate AS DATE) AS MedicationEndDate
FROM RLS.vw_GP_Medications
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND MedicationDate >= DATEADD(year, -1, @StartDate);

