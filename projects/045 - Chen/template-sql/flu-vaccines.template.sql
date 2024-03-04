
--┌────────────────────┐
--│ Flu vaccinations   │
--└────────────────────┘

-- OBJECTIVE: To obtain a table with all flu vaccinations for each patient.

-- OUTPUT: 
-- 	- PatientId - unique patient id
--	- FluVaccineYearAndMonth - date of vaccine administration (YYYY-MM)

-- Set the start date
DECLARE @EndDate datetime;
SET @EndDate = '2023-12-31';


--> EXECUTE query-build-rq045-cohort.sql

--> EXECUTE query-received-flu-vaccine.sql date-from:1900-01-01 date-to:2023-12-31 id:1

-- final table of flu vaccinations

SELECT 
	PatientId = FK_Patient_Link_ID, 
	FluVaccineYearAndMonth = FORMAT(FluVaccineDate, 'MM-yyyy')
FROM #PatientsWithFluVacConcept1
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
