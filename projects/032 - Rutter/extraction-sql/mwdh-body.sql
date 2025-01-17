--┌────────────────────────────────────────────────────────────┐
--│ Patient observations - data from My Way Digital Health     │
--└────────────────────────────────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK ----------
-- Richard Williams	2022-08-04	Review complete 
------------------------------------------------

-- OUTPUT: Data with the following fields
-- Patient Id
-- Record Id
-- EventDateTime
-- HealthRecord
-- Value
-- LookupText

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2019-07-09';

--Just want the output, not the messages
SET NOCOUNT ON;

-- Find all patients alive at start date
IF OBJECT_ID('tempdb..#PossiblePatients') IS NOT NULL DROP TABLE #PossiblePatients;
SELECT PK_Patient_Link_ID as FK_Patient_Link_ID, EthnicMainGroup, DeathDate INTO #PossiblePatients FROM [RLS].vw_Patient_Link
WHERE (DeathDate IS NULL OR DeathDate >= @StartDate);

-- Find all patients registered with a GP
IF OBJECT_ID('tempdb..#PatientsWithGP') IS NOT NULL DROP TABLE #PatientsWithGP;
SELECT DISTINCT FK_Patient_Link_ID INTO #PatientsWithGP FROM [RLS].vw_Patient
where FK_Reference_Tenancy_ID = 2;

-- Make cohort from patients alive at start date and registered with a GP
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT pp.* INTO #Patients FROM #PossiblePatients pp
INNER JOIN #PatientsWithGP gp on gp.FK_Patient_Link_ID = pp.FK_Patient_Link_ID;

-- FINAL TABLE: TAKE DATA AS IT IS FROM MYWAY TABLES

SELECT 
	PatientId = lh.FK_Patient_Link_ID,
	ObservationId = PK_Live_Body_ID,
	EventDateTime = EventStamp,
	HealthRecord,
	[Value],
	LookupText
FROM MWDH.Live_Body lg
LEFT JOIN MWDH.Live_Header lh on lh.PK_Live_Header_ID = lg.FK_Live_Header_ID
WHERE lh.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients) AND
	([VALUE] IS NULL OR [VALUE] NOT LIKE '%[A-Z]%') -- KEEP NULL VALUES BUT REMOVE ANY OTHER POTENTIAL TEXT