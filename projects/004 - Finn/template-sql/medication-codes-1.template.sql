--┌───────────────────────────────────────────────────┐
--│ Medication Code Descriptions CTV3 and ReadCodeV2  │
--└───────────────────────────────────────────────────┘


-- A mapping of the medication codes used in the medications data extract file and their descriptions. 

-- OUTPUT: Data with the following fields
--   SuppliedCode,
--   CodingType,
--   Term30,
--   Term60,
--   Term198,
--   FullDescription


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

SELECT 
   m.SuppliedCode,
   rc.CodingType,
   rc.Term30,
   rc.Term60,
   rc.Term198,
   rc.FullDescription
FROM #UniqueRefCodesMedications m
INNER JOIN [SharedCare].[Reference_Coding] rc ON m.SuppliedCode = rc.MainCode;
-- 22.018 rows with duplicate supplied codes. 
-- 7.219 unigue drug codes have description. CTV3 and ReadCodeV2
-- 16.479 has null descriptions - majority are EMIS 
-- as of 23rd May

