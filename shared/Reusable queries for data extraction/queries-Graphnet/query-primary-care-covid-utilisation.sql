--┌──────────────────────────────────────────┐
--│ COVID utilisation from primary care data │
--└──────────────────────────────────────────┘

-- OBJECTIVE:	Classifies a list of events as COVID or non-COVID. An event is classified as
--						"COVID" if the date of the event is within 4 weeks after, or up to 14 days 
--						before, a positive COVID test.

-- INPUT: Takes one parameter
--  - start-date: string - (YYYY-MM-DD) the date to count COVID diagnoses from. Usually this should be 2020-01-01.
--	-	all-patients: boolean - (true/false) if true, then all patients are included, otherwise only those in the pre-existing #Patients table.
--	- gp-events-table: string - (table name) the name of the table containing the GP events. Usually is "RLS.vw_GP_Events" but can be anything with the columns: FK_Patient_Link_ID, EventDate, and SuppliedCode
-- And assumes there exists two temp tables as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort
-- #PatientDates (FK_Patient_Link_ID, EventDate)
--	- FK_Patient_Link_ID - unique patient id
--	- EventDate - date of the event to classify as COVID/non-COVID
--  A distinct list of the dates of the event for each patient in the cohort

-- OUTPUT: A temp table as follows:
-- #COVIDUtilisationPrimaryCare (FK_Patient_Link_ID, AdmissionDate, AcuteProvider, CovidHealthcareUtilisation)
--	- FK_Patient_Link_ID - unique patient id
--	- EventDate - date of the event to classify as COVID/non-COVID
--	- CovidHealthcareUtilisation - 'TRUE' if event within 4 weeks after, or up to 14 days before, a positive test

-- Get positive covid test dates for each patient
--> EXECUTE query-patients-with-covid.sql start-date:{param:start-date} all-patients:{param:all-patients} gp-events-table:{param:gp-events-table}

IF OBJECT_ID('tempdb..#COVIDUtilisationPrimaryCare') IS NOT NULL DROP TABLE #COVIDUtilisationPrimaryCare;
SELECT 
	pd.FK_Patient_Link_ID,
	pd.EventDate,
	CASE WHEN MAX(CASE
		WHEN c.FK_Patient_Link_ID IS NOT NULL THEN 1
		ELSE 0
	END) = 1 THEN 'TRUE' ELSE 'FALSE' END AS CovidHealthcareUtilisation
INTO #COVIDUtilisationPrimaryCare 
FROM #PatientDates pd
LEFT OUTER join #CovidPatientsAllDiagnoses c ON 
	pd.FK_Patient_Link_ID = c.FK_Patient_Link_ID 
	AND pd.EventDate <= DATEADD(WEEK, 4, c.CovidPositiveDate)
	AND pd.EventDate >= DATEADD(DAY, -14, c.CovidPositiveDate)
GROUP BY pd.FK_Patient_Link_ID,	pd.EventDate;