--┌───────────────────────────────────────────────────┐
--│ Medication Code Descriptions EMIS codes           │
--└───────────────────────────────────────────────────┘


-- A mapping of the medication codes used in the medications data extract file and their descriptions. 

-- OUTPUT: Data with the following fields
--     SuppliedCode (Nvarchar)
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


-- Get unique supplied codes of the cohort's medications using same retstrictions as the medications file (all medications for all people in the cohort 1 year before the index date)
IF OBJECT_ID('tempdb..#UniqueRefCodesMedications') IS NOT NULL DROP TABLE #UniqueRefCodesMedications;
SELECT DISTINCT
	SuppliedCode
INTO #UniqueRefCodesMedications
FROM RLS.vw_GP_Medications
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND MedicationDate >= DATEADD(year, -1, @StartDate)
-- 23.698 unique suppliedCode
-- as of 23rd May 2022

SELECT DISTINCT
   m.SuppliedCode,
   LocalCodeDescription,
   MappingCode,
   MappingCodeDescription,
   MappingCodeType
FROM #UniqueRefCodesMedications m
INNER JOIN [SharedCare].[Reference_Local_Code] rlc ON m.SuppliedCode = rlc.localCode;
-- 25.874 rows has duplicate supplied codes
-- 16.058 unique drug codes - majority if not all are EMIS codes
-- as of 23rd May



