--┌────────────────────────────────────┐
--│ Patient information for SMI cohort │
--└────────────────────────────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------
--

-- OUTPUT: Data with the following fields
-- Patient Id
-- Name of Co-morbidity
-- Diangosis Date


-- Set the start date
DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2014-10-01';
SET @EndDate = '2022-09-31';

--Just want the output, not the messages
SET NOCOUNT ON;

--> EXECUTE query-get-possible-patients.sql

--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-imd.sql
--> EXECUTE query-patient-year-of-birth.sql
--> EXECUTE query-patient-lsoa.sql
--> EXECUTE query-patient-practice-and-ccg.sql

----- create cohort: people with a cervix
IF OBJECT_ID('tempdb..#Cohort') IS NOT NULL DROP TABLE #Cohort;
SELECT DISTINCT
	p.FK_Patient_Link_ID,
	YearOfBirth, 
	Sex,
	EthnicMainGroup,
	EthnicGroupDescription
INTO #Cohort
FROM #Patients p
where YEAR(StartDate) - YearOfBirth BETWEEN 25 AND 64 
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID

--bring together for final output

