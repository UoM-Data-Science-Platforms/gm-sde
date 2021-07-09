--┌─────────────────────────────────┐
--│ Comorbidities                   │
--└─────────────────────────────────┘

-- This file contains comorbidity information for every patient in the study cohort from 1st February 2019.

-- OUTPUT: A single table with the following:
--	PatientId
--	First record date (YYYY-MM-DD) TODO
--	Last record date (YYYY-MM-DD) TODO
--	Comorbidity



--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2019-02-01';

--> EXECUTE query-cancer-cohort-matching.sql
-- OUTPUTS: #Patients2
-- OUTPUTS: #Patients

--> EXECUTE query-patient-ltcs.sql
-- OUTPUT: #PatientsWithLTCs (FK_Patient_Link_ID, LTC)

--> EXECUTE query-patient-ltcs-number-of.sql
-- OUTPUT: #NumLTCs (FK_Patient_Link_ID, NumberOfLTCs)


SELECT
  FK_Patient_Link_ID,
  ltc.LTC,
  nltc.NumberOfLTCs
FROM #Patients2 p 
LEFT OUTER JOIN #PatientsWithLTCs ltc ON ltc.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #NumLTCs nltc ON nltc.FK_Patient_Link_ID = p.FK_Patient_Link_ID;







