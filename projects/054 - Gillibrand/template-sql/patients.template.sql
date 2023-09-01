--┌────────────────────────────────────┐
--│ Patient information for SMI cohort │
--└────────────────────────────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------
--

-- OUTPUT: Data with the following fields
-- Patient Id
-- Month and year of birth (YYYY-MM)
-- Sex (male/female)
-- Ethnicity (white/black/asian/mixed/other)
-- IMD score
-- LSOA code


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
--patients in main cohort
SELECT	 PatientId = m.FK_Patient_Link_ID
		,m.YearOfBirth
		,m.Sex
		,LSOA_Code
		,m.EthnicMainGroup ----- CHANGE TO MORE SPECIFIC ETHNICITY
		,IMD2019Decile1IsMostDeprived10IsLeastDeprived
		,pp.PatientPractice 
FROM #Cohort m
LEFT OUTER JOIN RLS.vw_Patient_Link pl ON pl.PK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientPractice pp ON pp.FK_Patient_Link_ID = m.FK_Patient_Link_ID
WHERE M.FK_Patient_Link_ID in (SELECT FK_Patient_Link_ID FROM #Patients)
