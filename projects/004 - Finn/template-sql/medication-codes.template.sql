--┌─────────────────────────────────┐
--│ Medication Code Ref              │
--└─────────────────────────────────┘


-- A mapping of the medication codes used in the medications data extract file and their descriptions. 

-- OUTPUT: Data with the following fields
--     DrugCode (Nvarchar)
--     LocalCodeDescription (Nvarchar)
--     MappingCode (Nvarchar)
--     MappingCodeDescription (Nvarchar)
--     MappingCodeType (Nvarchar)


--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2020-02-01';

-- Get all the patients in the cohort
--> EXECUTE query-cancer-cohort-matching.sql
-- OUTPUTS: #Patients

-- Get unique drug codes using same retstrictions as the medications file (all medications for all people in the cohort 1 year before the index date)
IF OBJECT_ID('tempdb..#UniqueDrugCodeMedications') IS NOT NULL DROP TABLE #UniqueDrugCodeMedications;
SELECT DISTINCT
	SuppliedCode AS DrugCode
INTO #UniqueDrugCodeMedications
FROM RLS.vw_GP_Medications
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND MedicationDate >= DATEADD(year, -1, @StartDate);

SELECT 
   udcm.DrugCode,
   rlc.LocalCodeDescription,
   rlc.MappingCode,
   rlc.MappingCodeDescription,
   rlc.MappingCodeType
FROM #UniqueDrugCodeMedications udcm
LEFT OUTER JOIN [SharedCare].[Reference_Local_Code] rlc ON udcm.DrugCode = rlc.LocalCode
-- As of 11th May 2022
-- running time 15.48min
-- 84.159 rows
-- 23.698 distinct drug codes. 