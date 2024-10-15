--┌────────────────────────────────────┐
--│ COVID-related secondary admissions │
--└────────────────────────────────────┘

-- OBJECTIVE: To classify every admission to secondary care based on whether it is a COVID or non-COVID related.
--						A COVID-related admission is classed as an admission within 4 weeks after, or up to 2 weeks before
--						a positive test.

-- INPUT: Takes one parameter
--  - start-date: string - (YYYY-MM-DD) the date to count diagnoses from. Usually this should be 2020-01-01.
--	-	all-patients: boolean - (true/false) if true, then all patients are included, otherwise only those in the pre-existing #Patients table.
--	- gp-events-table: string - (table name) the name of the table containing the GP events. Usually is "RLS.vw_GP_Events" but can be anything with the columns: FK_Patient_Link_ID, EventDate, and SuppliedCode
-- And assumes there exists two temp tables as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort
-- #Admissions (FK_Patient_Link_ID, AdmissionDate, AcuteProvider)
--  A distinct list of the admissions for each patient in the cohort

-- OUTPUT: A temp table as follows:
-- #COVIDUtilisationAdmissions (FK_Patient_Link_ID, AdmissionDate, AcuteProvider, CovidHealthcareUtilisation)
--	- FK_Patient_Link_ID - unique patient id
--	- AdmissionDate - date of admission (YYYY-MM-DD)
--	- AcuteProvider - Bolton, SRFT, Stockport etc..
--	- CovidHealthcareUtilisation - 'TRUE' if admission within 4 weeks after, or up to 14 days before, a positive test

-- Get first positive covid test for each patient
--> EXECUTE query-patients-with-covid.sql start-date:{param:start-date} all-patients:{param:all-patients} gp-events-table:{param:gp-events-table}

IF OBJECT_ID('tempdb..#COVIDUtilisationAdmissions') IS NOT NULL DROP TABLE #COVIDUtilisationAdmissions;
SELECT 
	a.*, 
	CASE
		WHEN c.FK_Patient_Link_ID IS NOT NULL THEN 'TRUE'
		ELSE 'FALSE'
	END AS CovidHealthcareUtilisation
INTO #COVIDUtilisationAdmissions 
FROM #Admissions a
LEFT OUTER join #CovidPatients c ON 
	a.FK_Patient_Link_ID = c.FK_Patient_Link_ID 
	AND a.AdmissionDate <= DATEADD(WEEK, 4, c.FirstCovidPositiveDate)
	AND a.AdmissionDate >= DATEADD(DAY, -14, c.FirstCovidPositiveDate);