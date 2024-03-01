--┌───────────────────────────────────┐
--│ Get all events for RQ065 cohort   │
--└───────────────────────────────────┘

------------------------------------------------------------------------------

-- Create a table of events for all the people in our cohort.
-- We do this for Ref_Coding_ID and SNOMED_ID separately for performance reasons.
-- 1. Patients with a FK_Reference_Coding_ID
IF OBJECT_ID('tempdb..#PatientEventData1') IS NOT NULL DROP TABLE #PatientEventData1;
SELECT 
  FK_Patient_Link_ID,
  CAST(EventDate AS DATE) AS EventDate,
  CASE WHEN ISNUMERIC([Value]) = 1 THEN CAST([Value] AS float) ELSE NULL END AS [Value],
  Units,
  SuppliedCode,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID
INTO #PatientEventData1
FROM [SharedCare].GP_Events
WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);
--23s

-- 2. Patients with a FK_Reference_SnomedCT_ID
IF OBJECT_ID('tempdb..#PatientEventData2') IS NOT NULL DROP TABLE #PatientEventData2;
SELECT 
  FK_Patient_Link_ID,
  CAST(EventDate AS DATE) AS EventDate,
  CASE WHEN ISNUMERIC([Value]) = 1 THEN CAST([Value] AS float) ELSE NULL END AS [Value],
  Units,
  SuppliedCode,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID
INTO #PatientEventData2
FROM [SharedCare].GP_Events
WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);
--23s

-- 3. Merge the 2 tables together
IF OBJECT_ID('tempdb..#PatientEventData') IS NOT NULL DROP TABLE #PatientEventData;
SELECT * INTO #PatientEventData FROM #PatientEventData1
UNION
SELECT * FROM #PatientEventData2;
--6s

-- 4. Add indexes for future speed increase
DROP INDEX IF EXISTS eventFKData1 ON #PatientEventData;
CREATE INDEX eventFKData1 ON #PatientEventData (FK_Reference_Coding_ID) INCLUDE (FK_Patient_Link_ID, EventDate, [Value], Units);
DROP INDEX IF EXISTS eventFKData2 ON #PatientEventData;
CREATE INDEX eventFKData2 ON #PatientEventData (FK_Reference_SnomedCT_ID) INCLUDE (FK_Patient_Link_ID, EventDate, [Value], Units);
DROP INDEX IF EXISTS eventFKData3 ON #PatientEventData;
CREATE INDEX eventFKData3 ON #PatientEventData (SuppliedCode) INCLUDE (FK_Patient_Link_ID, EventDate, [Value], Units);
--5s for both