--┌──────────────────────────────────────────┐
--│ SDE Lighthouse study 06 - Chen           │
--└──────────────────────────────────────────┘

--Just want the output, not the messages
SET NOCOUNT ON;

DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2017-01-01';
SET @EndDate = '2023-12-31';

--> EXECUTE query-build-lh006-cohort.sql


-- CODESET fracture:1 suicide:1


--bring together for final output
--patients in main cohort
SELECT	 PatientId = FK_Patient_Link_ID
FROM #Cohort p
