--┌────────────┐
--│ Admissions │
--└────────────┘

--------------------- RDE CHECK ---------------------
-- Le Mai Parkes  - 25 May 2022 - via pull request --
-----------------------------------------------------

-- OUTPUT: Data with the following fields
--  - PatientId (int)
--  - AdmissionDate (YYYYMMDD)
--  - DischargeDate (YYYYMMDD)
--  - Status (planned/unplanned/maternity/transfer/other)

--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2020-01-01';

-- Set the end date
DECLARE @EndDate datetime;
SET @EndDate = '2022-07-01';

--> EXECUTE query-build-rq048-cohort.sql

--> EXECUTE query-classify-secondary-admissions.sql
--> EXECUTE query-get-admissions-and-length-of-stay.sql all-patients:false

SELECT 
  o.FK_Patient_Link_ID AS PatientId,
  admit.AdmissionDate,
  los.DischargeDate,
  admit.AdmissionType AS [Status],
  admit.AcuteProvider
FROM #Patients o
LEFT OUTER JOIN #AdmissionTypes admit ON admit.FK_Patient_Link_ID = o.FK_Patient_Link_ID
LEFT OUTER JOIN #LengthOfStay los 
  ON los.FK_Patient_Link_ID = o.FK_Patient_Link_ID
  AND los.AdmissionDate = admit.AdmissionDate
WHERE admit.AdmissionDate < @EndDate
AND (los.DischargeDate IS NULL OR los.DischargeDate < @EndDate);