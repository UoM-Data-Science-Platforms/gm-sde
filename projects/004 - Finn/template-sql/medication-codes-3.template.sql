--┌───────────────────────────────────────────────────┐
--│ Medication Code Descriptions SNOMED Codes         │
--└───────────────────────────────────────────────────┘


-- A mapping of the medication codes used in the medications data extract file and their descriptions. 

-- OUTPUT: Data with the following fields
--   SuppliedCode,
--   CodingType, 
--   ModuleID,
--   Module,
--   ConceptID,
--   Term 


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
	SuppliedCode,
	FK_Reference_SnomedCT_ID
INTO #UniqueRefCodesMedications
FROM RLS.vw_GP_Medications
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND MedicationDate >= DATEADD(year, -1, @StartDate)
AND [FK_Reference_SnomedCT_ID] != '-1'
AND SuppliedCode is not NULL;


--  21.269 rows (out of 23.698 unique suppliedCode)
-- as of 23rd May

SELECT distinct
   SuppliedCode,
   rc.CodingType, 
   ModuleID,
   Module,
   ConceptID,
   rs.Term 
FROM  #UniqueRefCodesMedications m
INNER JOIN [SharedCare].[Reference_SnomedCT] rs ON m.[FK_Reference_SnomedCT_ID] = rs.[PK_Reference_SnomedCT_ID]
LEFT OUTER JOIN [SharedCare].[Reference_Coding] rc ON m.SuppliedCode = rc.MainCode
-- 25.567 rows
-- as of 24th May



















-- -- Get unique supplied codes of the cohort's medications using same retstrictions as the medications file (all medications for all people in the cohort 1 year before the index date)
-- IF OBJECT_ID('tempdb..#UniqueRefCodesMedications') IS NOT NULL DROP TABLE #UniqueRefCodesMedications;
-- SELECT DISTINCT
-- 	SuppliedCode
-- INTO #UniqueRefCodesMedications
-- FROM RLS.vw_GP_Medications
-- WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
-- AND MedicationDate >= DATEADD(year, -1, @StartDate)

-- --  21.269 rows (out of 23.698 unique suppliedCode)
-- -- as of 23rd May


-- IF OBJECT_ID('tempdb..#UniqueRefCodesMedications') IS NOT NULL DROP TABLE #UniqueRefCodesMedications;
-- SELECT 
-- 	SuppliedCode,
-- 	FK_Reference_SnomedCT_ID
-- INTO #CodesMedications 
-- FROM #UniqueRefCodesMedications m
-- INNER JOIN [SharedCare].[Reference_Coding] rc ON m.FK_Reference_Coding_ID = rc.PK_Reference_Coding_ID;
-- AND [FK_Reference_SnomedCT_ID] != '-1';


-- SELECT 
--    SuppliedCode,
--    rc.CodingType, 
--    ModuleID,
--    Module,
--    ConceptID,
--    Term 
-- FROM  #UniqueRefCodesMedications m
-- INNER JOIN [SharedCare].[Reference_SnomedCT] rs ON m.[FK_Reference_SnomedCT_ID] = rs.[PK_Reference_SnomedCT_ID]
-- LEFT OUTER JOIN [SharedCare].[Reference_Coding] rc ON m.FK_Reference_Coding_ID = rc.PK_Reference_Coding_ID;
-- -- 21.269 rows
-- -- 21.096 unique supplied codes
-- -- as of 23rd May
