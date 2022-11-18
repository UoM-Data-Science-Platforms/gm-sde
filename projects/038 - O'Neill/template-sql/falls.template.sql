--┌────────────┐
--│ Falls file │
--└────────────┘

-- OUTPUT: Longitudinal record of falls in the cohort with fields:
-- 	- PatientId
--  - FallDate
--  - FallCode

--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the temp end date until new legal basis
DECLARE @TEMPRQ038EndDate datetime;
SET @TEMPRQ038EndDate = '2022-06-01';

-- Build the main cohort
--> EXECUTE query-build-rq038-cohort.sql

--> CODESET efi-falls:1

-- Final select to generate table
SELECT
  FK_Patient_Link_ID AS PatientId,
  CAST(EventDate AS DATE) AS FallDate,
  SuppliedCode AS FallCode
FROM SharedCare.GP_Events
WHERE SuppliedCode IN (
  SELECT Code FROM #AllCodes 
  WHERE Concept = 'efi-falls'
  AND VERSION = 1
)
AND EventDate < @TEMPRQ038EndDate