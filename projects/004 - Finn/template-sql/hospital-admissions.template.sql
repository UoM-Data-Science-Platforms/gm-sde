--┌─────────────────────────────────┐
--│ Hospital Admissions             │
--└─────────────────────────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------
-- RICHARD WILLIAMS |	DATE: 20/07/21

-- Study index date: 1st Feb 2020

-- Hospital admissions for all the cohort patients who had covid

-- OUTPUT: A single table with the following:
--	PatientId (Int)
--	AdmissionDate (YYYY-MM-DD)
--	Admission Type (Unplanned, Planned, Maternity, Transfer, Other)
--	LengthOfStay (Int)
--	DischargeDate (YYYY-MM-DD)


--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2020-02-01';

-- Get all the patients in the cohort
--> EXECUTE query-cancer-cohort-matching.sql
-- OUTPUT: #Patients

-- Categorise admissions to secondary care into 5 categories: Maternity, 
--		Unplanned, Planned, Transfer and Unknown.
--> EXECUTE query-classify-secondary-admissions.sql
-- OUTPUT: #AdmissionTypes (FK_Patient_Link_ID, AdmissionDate, AcuteProvider, AdmissionType)

--> EXECUTE query-get-admissions-and-length-of-stay.sql all-patients:true
-- OUTPUT: 
-- #LengthOfStay (FK_Patient_Link_ID, AdmissionDate, DischargeDate, LengthOfStay)
-- #Admissions (FK_Patient_Link_ID, AdmissionDate, AcuteProvider)

-- Get all positive covid test dates for each patient
--> EXECUTE query-patients-with-covid.sql start-date:2020-02-01 all-patients:true gp-events-table:RLS.vw_GP_Events
-- Output: #CovidPatientsAllDiagnoses (FK_Patient_Link_ID, CovidPositiveDate)

-- Modified query-admissions-covid-utilisation.sql to retrieve all covid positive dates not just the first covid date 
-- Classify every admission to secondary care based on whether is COVID or non-COVID related.
-- A COVID-related admission is classed as an admission within 4 weeks after, or up to 2 weeks before a positive test.
IF OBJECT_ID('tempdb..#COVIDUtilisationAdmissions') IS NOT NULL DROP TABLE #COVIDUtilisationAdmissions;
SELECT 
	a.*, 
	CASE
		WHEN c.FK_Patient_Link_ID IS NOT NULL THEN 'TRUE'
		ELSE 'FALSE'
	END AS CovidHealthcareUtilisation
INTO #COVIDUtilisationAdmissions 
FROM #Admissions a
LEFT OUTER join #CovidPatientsAllDiagnoses c ON 
	a.FK_Patient_Link_ID = c.FK_Patient_Link_ID 
	AND a.AdmissionDate <= DATEADD(WEEK, 4, c.CovidPositiveDate)
	AND a.AdmissionDate >= DATEADD(DAY, -14, c.CovidPositiveDate);


SELECT 
    c.FK_Patient_Link_ID AS PatientId,
    c.AdmissionDate,
    a.AdmissionType,
    l.DischargeDate,
    l.LengthOfStay
FROM #COVIDUtilisationAdmissions c
INNER JOIN #Patients p ON p.FK_Patient_Link_ID = c.FK_Patient_Link_ID
LEFT OUTER JOIN #AdmissionTypes a ON a.FK_Patient_Link_ID = c.FK_Patient_Link_ID AND a.AdmissionDate = c.AdmissionDate 
LEFT OUTER JOIN #LengthOfStay l ON l.FK_Patient_Link_ID = c.FK_Patient_Link_ID AND l.AdmissionDate = c.AdmissionDate 
WHERE c.CovidHealthcareUtilisation = 'TRUE';
-- 8.552 rows
-- as of 22nd Oct 2021






