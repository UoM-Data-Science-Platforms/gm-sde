--┌─────────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 03 - Kontopantelis - comorbidities │
--└─────────────────────────────────────────────────────────┘

--Just want the output, not the messages
SET NOCOUNT ON;

DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2006-01-01';
SET @EndDate = '2023-12-31'; -- CHECK

DECLARE @MinDate datetime;
DECLARE @IndexDate datetime;
SET @MinDate = '1900-01-01';
SET @IndexDate = '2023-12-31'; -- CHECK

--> EXECUTE query-build-lh003-cohort.sql

-- REDUCE THE #Patients TABLE SO THAT IT ONLY INCLUDES THE COHORT, AND REUSABLE QUERIES CAN USE IT TO BE RUN QUICKER 

DELETE FROM #Patients
WHERE FK_Patient_Link_ID NOT IN (SELECT FK_Patient_Link_ID FROM #Cohort)

--> EXECUTE query-patient-ltcs-date-range.sql

-- final table

select  
	PatientId = FK_Patient_Link_ID, 
  	Condition,
  	FirstDate, 
  	LastDate,
    ConditionOccurences 
from #PatientsWithLTCs