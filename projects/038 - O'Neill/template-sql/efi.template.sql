--┌──────────┐
--│ EFI file │
--└──────────┘

-- OUTPUT: Data showing the cumulative deficits for each person over time with
--         the following fields:
--  - PatientId
--  - DateFrom - the date from which this number of deficits occurred
--  - NumberOfDeficits - the number of deficits on the DateFrom date

--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the temp end date until new legal basis
DECLARE @TEMPRQ038EndDate datetime;
SET @TEMPRQ038EndDate = '2022-06-01';

-- Build the main cohort
--> EXECUTE query-build-rq038-cohort.sql

-- Forces the code lists to insert here, so we can reference them in the below queries
--> CODESET efi-arthritis:1

-- To optimise the patient event data table further (as there are so many patients),
-- we can initially split it into 3:
-- 1. Patients with a SuppliedCode in our list
IF OBJECT_ID('tempdb..#PatientEventData1') IS NOT NULL DROP TABLE #PatientEventData1;
SELECT 
  FK_Patient_Link_ID,
  CAST(EventDate AS DATE) AS EventDate,
  SuppliedCode,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID,
  [Value]
INTO #PatientEventData1
FROM [SharedCare].GP_Events
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND	SuppliedCode IN (SELECT Code FROM #AllCodes)
AND EventDate < '2022-06-01';
-- 1m

-- 2. Patients with a FK_Reference_Coding_ID in our list
IF OBJECT_ID('tempdb..#PatientEventData2') IS NOT NULL DROP TABLE #PatientEventData2;
SELECT 
  FK_Patient_Link_ID,
  CAST(EventDate AS DATE) AS EventDate,
  SuppliedCode,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID,
  [Value]
INTO #PatientEventData2
FROM [SharedCare].GP_Events
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND	FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets)
AND EventDate < '2022-06-01';
--29s

-- 3. Patients with a FK_Reference_SnomedCT_ID in our list
IF OBJECT_ID('tempdb..#PatientEventData3') IS NOT NULL DROP TABLE #PatientEventData3;
SELECT 
  FK_Patient_Link_ID,
  CAST(EventDate AS DATE) AS EventDate,
  SuppliedCode,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID,
  [Value]
INTO #PatientEventData3
FROM [SharedCare].GP_Events
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets)
AND EventDate < '2022-06-01';

IF OBJECT_ID('tempdb..#PatientEventData') IS NOT NULL DROP TABLE #PatientEventData;
SELECT * INTO #PatientEventData FROM #PatientEventData1
UNION
SELECT * FROM #PatientEventData2
UNION
SELECT * FROM #PatientEventData3;

-- Improve performance later with an index (creates in ~1 minute - saves loads more than that)
DROP INDEX IF EXISTS eventData ON #PatientEventData;
CREATE INDEX eventData ON #PatientEventData (SuppliedCode) INCLUDE (FK_Patient_Link_ID, EventDate, [Value]);

-- Get the EFI over time
--> EXECUTE query-patients-calculate-efi-over-time.sql gp-events-table:#PatientEventData

-- Finally we just select from the EFI table with the required fields
SELECT
  FK_Patient_Link_ID AS PatientId,
  DateFrom,
  NumberOfDeficits
FROM #PatientEFIOverTime
ORDER BY FK_Patient_Link_ID, DateFrom;