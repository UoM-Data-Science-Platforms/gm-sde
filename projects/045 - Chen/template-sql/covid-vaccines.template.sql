--┌────────────────────────────────────┐
--│ Covid vaccination dates            │
--└────────────────────────────────────┘

-- OBJECTIVE: To find patients' covid vaccine dates (1 row per patient)

-- OUTPUT: Data with the following fields
---- PatientId
---- VaccineDose1_YearAndMonth
---- VaccineDose2_YearAndMonth
---- VaccineDose3_YearAndMonth
---- VaccineDose4_YearAndMonth
---- VaccineDose5_YearAndMonth
---- VaccineDose6_YearAndMonth
---- VaccineDose7_YearAndMonth

--> EXECUTE query-build-rq045-cohort.sql
--> EXECUTE query-get-covid-vaccines.sql gp-events-table:SharedCare.GP_Events gp-medications-table:SharedCare.GP_Medications

DECLARE @EndDate datetime;
SET @EndDate = '2023-12-31'

SELECT PatientId = FK_Patient_Link_ID, 
	VaccineDose1_YearAndMonth = FORMAT(VaccineDose1Date, 'MM-yyyy'), 
	VaccineDose2_YearAndMonth = FORMAT(VaccineDose2Date, 'MM-yyyy'), -- hide the day by setting to first of the month
	VaccineDose3_YearAndMonth = FORMAT(VaccineDose3Date, 'MM-yyyy'), -- hide the day by setting to first of the month
	VaccineDose4_YearAndMonth = FORMAT(VaccineDose4Date, 'MM-yyyy'), -- hide the day by setting to first of the month
	VaccineDose5_YearAndMonth = FORMAT(VaccineDose5Date, 'MM-yyyy'), -- hide the day by setting to first of the month
	VaccineDose6_YearAndMonth = FORMAT(VaccineDose6Date, 'MM-yyyy'), -- hide the day by setting to first of the month
	VaccineDose7_YearAndMonth = FORMAT(VaccineDose7Date, 'MM-yyyy') -- hide the day by setting to first of the month
FROM #COVIDVaccinations
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
	AND (VaccineDose1Date IS NULL OR VaccineDose1Date <= @EndDate)
	AND (VaccineDose2Date IS NULL OR VaccineDose2Date <= @EndDate)
	AND (VaccineDose3Date IS NULL OR VaccineDose3Date <= @EndDate)
	AND (VaccineDose4Date IS NULL OR VaccineDose4Date <= @EndDate)               
	AND (VaccineDose5Date IS NULL OR VaccineDose5Date <= @EndDate)
	AND (VaccineDose6Date IS NULL OR VaccineDose6Date <= @EndDate)
	AND (VaccineDose7Date IS NULL OR VaccineDose7Date <= @EndDate)
