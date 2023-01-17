--┌────────────┐
--│ Falls file │
--└────────────┘

-- OUTPUT: Longitudinal record of falls in the cohort with fields:
-- 	- PatientId
--  - FallDate
--  - FallCode
--  - FallCodeDescription

--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the temp end date until new legal basis
DECLARE @TEMPRQ038EndDate datetime;
SET @TEMPRQ038EndDate = '2022-06-01';

-- Build the main cohort
--> EXECUTE query-build-rq038-cohort.sql

--> CODESET efi-falls:1

-- Get unique description for each code
IF OBJECT_ID('tempdb..#FallCodeDescriptions') IS NOT NULL DROP TABLE #FallCodeDescriptions;
SELECT Code AS FallCode, MAX([description]) AS FallCodeDescription
INTO #FallCodeDescriptions
FROM #AllCodes
WHERE Concept = 'efi-falls'
AND [Version] = 1
GROUP BY Code;

-- Final select to generate table
SELECT
  e.FK_Patient_Link_ID AS PatientId,
  CAST(e.EventDate AS DATE) AS FallDate,
  fc.FallCode,
  fc.FallCodeDescription
FROM SharedCare.GP_Events e
LEFT OUTER JOIN #FallCodeDescriptions fc ON fc.FallCode = e.SuppliedCode
WHERE SuppliedCode IN (
  SELECT Code FROM #AllCodes 
  WHERE Concept = 'efi-falls'
  AND VERSION = 1
)
AND EventDate < @TEMPRQ038EndDate
ORDER BY e.FK_Patient_Link_ID, e.EventDate;