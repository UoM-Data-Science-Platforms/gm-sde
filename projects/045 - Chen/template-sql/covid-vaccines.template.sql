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
	VaccineDose1_YearAndMonth = DATEADD(dd, -( DAY( VaccineDose1Date) -1 ), VaccineDose1Date), -- hide the day by setting to first of the month
	VaccineDose2_YearAndMonth = DATEADD(dd, -( DAY( VaccineDose2Date) -1 ), VaccineDose2Date), -- hide the day by setting to first of the month
	VaccineDose3_YearAndMonth = DATEADD(dd, -( DAY( VaccineDose3Date) -1 ), VaccineDose3Date), -- hide the day by setting to first of the month
	VaccineDose4_YearAndMonth = DATEADD(dd, -( DAY( VaccineDose4Date) -1 ), VaccineDose4Date), -- hide the day by setting to first of the month
	VaccineDose5_YearAndMonth = DATEADD(dd, -( DAY( VaccineDose5Date) -1 ), VaccineDose5Date), -- hide the day by setting to first of the month
	VaccineDose6_YearAndMonth = DATEADD(dd, -( DAY( VaccineDose6Date) -1 ), VaccineDose6Date), -- hide the day by setting to first of the month
	VaccineDose7_YearAndMonth = DATEADD(dd, -( DAY( VaccineDose7Date) -1 ), VaccineDose7Date) -- hide the day by setting to first of the month
FROM #COVIDVaccinations
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
	AND (VaccineDose1Date IS NULL OR VaccineDose1Date <= @EndDate)
	AND (VaccineDose2Date IS NULL OR VaccineDose2Date <= @EndDate)
	AND (VaccineDose3Date IS NULL OR VaccineDose3Date <= @EndDate)
	AND (VaccineDose4Date IS NULL OR VaccineDose4Date <= @EndDate)               
	AND (VaccineDose5Date IS NULL OR VaccineDose5Date <= @EndDate)
	AND (VaccineDose6Date IS NULL OR VaccineDose6Date <= @EndDate)
	AND (VaccineDose7Date IS NULL OR VaccineDose7Date <= @EndDate)
