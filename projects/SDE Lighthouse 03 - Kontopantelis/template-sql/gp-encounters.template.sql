--┌───────────────────────────────────────────────────┐
--│ Dates of GP Encounters for dementia cohort        │
--└───────────────────────────────────────────────────┘

-- this sscript uses a reusable query to estimate gp encounters based on in-person events like 'blood pressure taken' 
-- and telephone/virtual events like phone calls 


---- RESEARCH DATA ENGINEER CHECK ----

--------------------------------------

-- OUTPUT: Data with the following fields
-- Patient Id
-- EncounterDate (DD-MM-YYYY)

-- Set the start date
DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2006-01-01';
SET @EndDate = '2023-10-31';

--Just want the output, not the messages
SET NOCOUNT ON;

--> EXECUTE query-build-lh003-cohort.sql
----------------------------------------------------------------------------------------

-- REDUCE THE #Patients TABLE SO THAT IT ONLY INCLUDES THE COHORT, AND REUSABLE QUERIES CAN USE IT TO BE RUN QUICKER 

DELETE FROM #Patients
WHERE FK_Patient_Link_ID NOT IN (SELECT FK_Patient_Link_ID FROM #Cohort)

--------------------- IDENTIFY GP ENCOUNTERS -------------------------

--> EXECUTE query-patient-gp-encounters.sql all-patients:false gp-events-table:SharedCare.GP_Events start-date:'2006-01-01' end-date:'2023-10-31'

------------ FIND ALL GP ENCOUNTERS FOR COHORT
SELECT PatientId = FK_Patient_Link_ID,
	[Year] = YEAR(EncounterDate), 
	GPEncounters = COUNT(*)
FROM #GPEncounters
GROUP BY FK_Patient_Link_ID, YEAR(EncounterDate)
ORDER BY FK_Patient_Link_ID, YEAR(EncounterDate)
