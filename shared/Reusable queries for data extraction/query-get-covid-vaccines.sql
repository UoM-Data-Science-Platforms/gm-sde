--┌────────────────────┐
--│ COVID vaccinations │
--└────────────────────┘

-- OBJECTIVE: To obtain a table with first and second vaccine doses per patient.

-- ASSUMPTIONS:
--	-	GP records can often be duplicated. The assumption is that if a patient receives
--    two vaccines within 14 days of each other then it is likely that both codes refer
--    to the same vaccine. However, it is possible that the first code's entry into the
--    record was delayed and therefore the second code is in fact a second dose. This
--    query simply gives the earliest and latest vaccine for each person together with
--    the number of days since the first vaccine.

-- INPUT: No pre-requisites

-- OUTPUT: A temp table as follows:
-- #COVIDVaccinations (FK_Patient_Link_ID, VaccineDate, DaysSinceFirstVaccine)
-- 	- FK_Patient_Link_ID - unique patient id
--	- VaccineDate - date of vaccine (YYYY-MM-DD)
--	- DaysSinceFirstVaccine - 0 if first vaccine, > 0 otherwise

-- Get patients with covid vaccine and earliest and latest date
IF OBJECT_ID('tempdb..#COVIDVaccines') IS NOT NULL DROP TABLE #COVIDVaccines;
SELECT 
  FK_Patient_Link_ID, 
  MIN(CONVERT(DATE, EventDate)) AS FirstVaccineDate, 
  MAX(CONVERT(DATE, EventDate)) AS SecondVaccineDate 
INTO #COVIDVaccines
FROM [RLS].[vw_GP_Events]
WHERE SuppliedCode IN (
  SELECT [code] FROM #AllCodes WHERE [concept] = 'covid-vaccination' AND [version] = 1
)
AND EventDate > '2020-12-01'
GROUP BY FK_Patient_Link_ID;

IF OBJECT_ID('tempdb..#COVIDVaccinations') IS NOT NULL DROP TABLE #COVIDVaccinations;
SELECT FK_Patient_Link_ID, FirstVaccineDate AS VaccineDate, 0 AS DaysSinceFirstVaccine
INTO #COVIDVaccinations
FROM #COVIDVaccines;

INSERT INTO #COVIDVaccinations
SELECT FK_Patient_Link_ID, SecondVaccineDate, DATEDIFF(day, FirstVaccineDate, SecondVaccineDate)
FROM #COVIDVaccines
WHERE FirstVaccineDate != SecondVaccineDate;

