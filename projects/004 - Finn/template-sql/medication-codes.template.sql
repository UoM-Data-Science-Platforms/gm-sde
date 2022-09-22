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


-- Get unique supplied codes of the cohort's medications using same retstrictions as the medications file (all medications for all people in the cohort 1 year before the index date)
IF OBJECT_ID('tempdb..#UniqueRefCodesMedications') IS NOT NULL DROP TABLE #UniqueRefCodesMedications;
SELECT DISTINCT
	SuppliedCode
INTO #UniqueRefCodesMedications
FROM RLS.vw_GP_Medications
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND MedicationDate >= DATEADD(year, -1, @StartDate)
-- 23.698 unique suppliedCode

SELECT DISTINCT
   SuppliedCode,
   LocalCodeDescription,
   MappingCode,
   MappingCodeDescription,
   MappingCodeType
FROM #UniqueRefCodesMedications m
LEFT OUTER JOIN [SharedCare].[Reference_Local_Code] rlc ON m.SuppliedCode = rlc.localCode
WHERE localCodeDescription is not null or MappingCodeDescription is not null;




-- Get unique ref coding IDs of the cohort's medications using same retstrictions as the medications file (all medications for all people in the cohort 1 year before the index date)
IF OBJECT_ID('tempdb..#UniqueRefCodesMedications') IS NOT NULL DROP TABLE #UniqueRefCodesMedications;
SELECT DISTINCT
	FK_Reference_Coding_ID
INTO #UniqueRefCodesMedications
FROM RLS.vw_GP_Medications
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND MedicationDate >= DATEADD(year, -1, @StartDate)
AND FK_Reference_Coding_ID !=  -1;


-- Get unique ref snomed ID codes for the medications. 
IF OBJECT_ID('tempdb..#UniqueSnomedCodesMedications') IS NOT NULL DROP TABLE #UniqueSnomedCodesMedications;
SELECT DISTINCT
	FK_Reference_SnomedCT_ID
INTO #UniqueSnomedCodesMedications
FROM RLS.vw_GP_Medications
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND MedicationDate >= DATEADD(year, -1, @StartDate)
AND FK_Reference_SnomedCT_ID !=  -1;

-- Get descriptions for the medication joining on ref code ID.
IF OBJECT_ID('tempdb..#UniqueRefCodesDescriptions') IS NOT NULL DROP TABLE #UniqueRefCodesDescriptions;
SELECT 
   urc.FK_Reference_Coding_ID,
   rlc.FK_Reference_SnomedCT_ID,
   rlc.LocalCode,
   rlc.LocalCodeDescription,
   rlc.MappingCode,
   rlc.MappingCodeDescription,
   rlc.MappingCodeType
INTO #UniqueRefCodesDescriptions
FROM #UniqueRefCodesMedications urc
LEFT OUTER JOIN [SharedCare].[Reference_Local_Code] rlc ON urc.FK_Reference_Coding_ID = rlc.FK_Reference_Coding_ID;

-- Get descriptions for the medication joining on ref snomed ID.
IF OBJECT_ID('tempdb..#UniqueSnomedCodesDescriptions') IS NOT NULL DROP TABLE #UniqueSnomedCodesDescriptions;
SELECT 
   rlc.FK_Reference_Coding_ID,
   urc.FK_Reference_SnomedCT_ID,
   rlc.LocalCode,
   rlc.LocalCodeDescription,
   rlc.MappingCode,
   rlc.MappingCodeDescription,
   rlc.MappingCodeType
INTO #UniqueSnomedCodesDescriptions
FROM #UniqueSnomedCodesMedications urc
LEFT OUTER JOIN [SharedCare].[Reference_Local_Code] rlc ON urc.FK_Reference_SnomedCT_ID = rlc.FK_Reference_SnomedCT_ID;


-- Get the union of the descriptions table
IF OBJECT_ID('tempdb..#AllCodesDescriptions') IS NOT NULL DROP TABLE #AllCodesDescriptions;
SELECT *
INTO #AllCodesDescriptions
FROM #UniqueRefCodesDescriptions
UNION
SELECT *
FROM #UniqueSnomedCodesDescriptions;


--De-dupe the descriptions table. 
SELECT DISTINCT
   FK_Reference_Coding_ID,
   FK_Reference_SnomedCT_ID,
   LocalCode,
   LocalCodeDescription,
   MappingCode,
   MappingCodeDescription,
   MappingCodeType
FROM #AllCodesDescriptions;

-- 34.825 rows
-- 17.583 unique local codes (out of ~23k)
-- missing: 7.645 

-- 23.698 unique drug codes in the new medications file (cz new matching cohort) - Gareth's file has 23.150


-- Get all drug codes from the medications extract file (for the cohort)
IF OBJECT_ID('tempdb..#DrugCodes') IS NOT NULL DROP TABLE #DrugCodes;
SELECT DISTINCT
	suppliedCode
INTO #DrugCodes
FROM RLS.vw_GP_Medications
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND MedicationDate >= DATEADD(year, -1, @StartDate)

-- Get drug codes without a description match
IF OBJECT_ID('tempdb..#missing') IS NOT NULL DROP TABLE #missing;
select SuppliedCode 
into  #missing
from #DrugCodes dc
LEFT outer join #deduped d ON d.localCOde = dc.suppliedCode
where d.localCode is null;

--get extra drug codes without 
IF OBJECT_ID('tempdb..#extra') IS NOT NULL DROP TABLE #extra;
select LocalCode 
into  #extra
from #deduped d
LEFT outer join #DrugCodes dc ON d.localCOde = dc.suppliedCode
where dc.suppliedCode is null;

IF OBJECT_ID('tempdb..#nonEmis') IS NOT NULL DROP TABLE #nonEmis;
select 
	m.SuppliedCode,
	rc.CodingType,
	rc.[FullDescription],
	rc.[PK_Reference_Coding_ID]
INTO #nonEmis
from  #missing m
inner join [SharedCare].[Reference_Coding] rc ON m.SuppliedCode = rc.MainCode







--  m.suppliedCode,
--   m.FK_Reference_Coding_ID,
--   c.CodingType,
--   m.FK_Reference_SnomedCT_ID,
--   sct.ConceptID AS SnomedCTcode,
--   sct.Term AS SnomedCTDescription,
--   lc.localCode,
--   [LocalCodeDescription]
--       ,[MappingCode]
--       ,[MappingCodeDescription]
--       ,[MappingCodeType]





-- Get the description of EMIS drug codes
-- Grain: multiple descriptions per drug code.
-- IF OBJECT_ID('tempdb..#EMISDrugCodeMedications') IS NOT NULL DROP TABLE #EMISDrugCodeMedications;
-- SELECT 
--    udcm.DrugCode,
--    rlc.LocalCodeDescription,
--    rlc.MappingCode,
--    rlc.MappingCodeDescription,
--    rlc.MappingCodeType
-- INTO #EMISDrugCodeMedications
-- FROM #UniqueDrugCodeMedications udcm
-- LEFT OUTER JOIN [SharedCare].[Reference_Local_Code] rlc ON udcm.DrugCode = rlc.LocalCode 

-- --Get the unmatched drug codes, most of them are non-EMIS codes
-- IF OBJECT_ID('tempdb..#UnmatchedDrugCodeMedications') IS NOT NULL DROP TABLE #UnmatchedDrugCodeMedications;
-- SELECT DISTINCT
--    DrugCode
-- INTO #UnmatchedDrugCodeMedications
-- FROM #EMISDrugCodeMedications
-- where LocalCodeDescription IS NULL;


-- Get the descriptions for the non-EMIS drug codes
-- IF OBJECT_ID('tempdb..#NONEMISDrugCodeMedications') IS NOT NULL DROP TABLE #NONEMISDrugCodeMedications;
-- SELECT 
--    nedc.DrugCode,
--    rlc.LocalCodeDescription,
--    rlc.MappingCode,
--    rlc.MappingCodeDescription,
--    rlc.MappingCodeType
-- INTO #EMISDrugCodeMedications
-- FROM #UnmatchedDrugCodeMedications nedc
-- LEFT OUTER JOIN [SharedCare].[Reference_Local_Code] rlc ON nedc.DrugCode = rlc.MappingCode






-- Grain: multiple rows per drug code. 




-- As of 11th May 2022
-- running time 15.48min
-- 84.159 rows
-- 23.698 distinct drug codes. 