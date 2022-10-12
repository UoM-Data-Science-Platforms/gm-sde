--┌────────────────────┐
--│ COVID vaccinations │
--└────────────────────┘

-- OBJECTIVE: To obtain a table with first, second, third... etc vaccine doses per patient.

-- ASSUMPTIONS:
--	-	GP records can often be duplicated. The assumption is that if a patient receives
--    two vaccines within 14 days of each other then it is likely that both codes refer
--    to the same vaccine.
--  - The vaccine can appear as a procedure or as a medication. We assume that the
--    presence of either represents a vaccination

-- INPUT: Takes two parameters:
--	- gp-events-table: string - (table name) the name of the table containing the GP events. Usually is "RLS.vw_GP_Events" but can be anything with the columns: FK_Patient_Link_ID, EventDate, and SuppliedCode
--	- gp-medications-table: string - (table name) the name of the table containing the GP medications. Usually is "RLS.vw_GP_Medications" but can be anything with the columns: FK_Patient_Link_ID, EventDate, and SuppliedCode

-- OUTPUT: A temp table as follows:
-- #COVIDVaccinations (FK_Patient_Link_ID, VaccineDate, DaysSinceFirstVaccine)
-- 	- FK_Patient_Link_ID - unique patient id
--	- VaccineDose1Date - date of first vaccine (YYYY-MM-DD)
--	-	VaccineDose2Date - date of second vaccine (YYYY-MM-DD)
--	-	VaccineDose3Date - date of third vaccine (YYYY-MM-DD)
--	-	VaccineDose4Date - date of fourth vaccine (YYYY-MM-DD)
--	-	VaccineDose5Date - date of fifth vaccine (YYYY-MM-DD)
--	-	VaccineDose6Date - date of sixth vaccine (YYYY-MM-DD)
--	-	VaccineDose7Date - date of seventh vaccine (YYYY-MM-DD)

-- Get patients with covid vaccine and earliest and latest date
--> CODESET covid-vaccination:1


IF OBJECT_ID('tempdb..#VacEvents') IS NOT NULL DROP TABLE #VacEvents;
SELECT FK_Patient_Link_ID, CONVERT(DATE, EventDate) AS EventDate into #VacEvents
FROM {param:gp-events-table}
WHERE SuppliedCode IN (
	SELECT [Code] FROM #AllCodes WHERE [Concept] = 'covid-vaccination' AND [Version] = 1
)
AND EventDate > '2020-12-01'
AND EventDate < '2022-06-01'; --TODO temp addition for COPI expiration

IF OBJECT_ID('tempdb..#VacMeds') IS NOT NULL DROP TABLE #VacMeds;
SELECT FK_Patient_Link_ID, CONVERT(DATE, MedicationDate) AS EventDate into #VacMeds
FROM {param:gp-medications-table}
WHERE SuppliedCode IN (
	SELECT [Code] FROM #AllCodes WHERE [Concept] = 'covid-vaccination' AND [Version] = 1
)
AND MedicationDate > '2020-12-01'
AND MedicationDate < '2022-06-01';--TODO temp addition for COPI expiration

IF OBJECT_ID('tempdb..#COVIDVaccines') IS NOT NULL DROP TABLE #COVIDVaccines;
SELECT FK_Patient_Link_ID, EventDate into #COVIDVaccines FROM #VacEvents
UNION
SELECT FK_Patient_Link_ID, EventDate FROM #VacMeds;
--4426892 5m03

-- Tidy up
DROP TABLE #VacEvents;
DROP TABLE #VacMeds;

-- Get first vaccine dose
IF OBJECT_ID('tempdb..#VacTemp1') IS NOT NULL DROP TABLE #VacTemp1;
select FK_Patient_Link_ID, MIN(EventDate) AS VaccineDoseDate
into #VacTemp1
from #COVIDVaccines
group by FK_Patient_Link_ID;
--2046837

-- Get second vaccine dose (if exists) - assume dose within 14 days is same dose
IF OBJECT_ID('tempdb..#VacTemp2') IS NOT NULL DROP TABLE #VacTemp2;
select c.FK_Patient_Link_ID, MIN(c.EventDate) AS VaccineDoseDate
into #VacTemp2
from #VacTemp1 v
inner join #COVIDVaccines c on c.EventDate > DATEADD(day, 14, v.VaccineDoseDate) and c.FK_Patient_Link_ID = v.FK_Patient_Link_ID
group by c.FK_Patient_Link_ID;
--1810762

-- Get third vaccine dose (if exists) - assume dose within 14 days is same dose
IF OBJECT_ID('tempdb..#VacTemp3') IS NOT NULL DROP TABLE #VacTemp3;
select c.FK_Patient_Link_ID, MIN(c.EventDate) AS VaccineDoseDate
into #VacTemp3
from #VacTemp2 v
inner join #COVIDVaccines c on c.EventDate > DATEADD(day, 14, v.VaccineDoseDate) and c.FK_Patient_Link_ID = v.FK_Patient_Link_ID
group by c.FK_Patient_Link_ID;
--578468

-- Get fourth vaccine dose (if exists) - assume dose within 14 days is same dose
IF OBJECT_ID('tempdb..#VacTemp4') IS NOT NULL DROP TABLE #VacTemp4;
select c.FK_Patient_Link_ID, MIN(c.EventDate) AS VaccineDoseDate
into #VacTemp4
from #VacTemp3 v
inner join #COVIDVaccines c on c.EventDate > DATEADD(day, 14, v.VaccineDoseDate) and c.FK_Patient_Link_ID = v.FK_Patient_Link_ID
group by c.FK_Patient_Link_ID;
--1860

-- Get fifth vaccine dose (if exists) - assume dose within 14 days is same dose
IF OBJECT_ID('tempdb..#VacTemp5') IS NOT NULL DROP TABLE #VacTemp5;
select c.FK_Patient_Link_ID, MIN(c.EventDate) AS VaccineDoseDate
into #VacTemp5
from #VacTemp4 v
inner join #COVIDVaccines c on c.EventDate > DATEADD(day, 14, v.VaccineDoseDate) and c.FK_Patient_Link_ID = v.FK_Patient_Link_ID
group by c.FK_Patient_Link_ID;
--39

-- Get sixth vaccine dose (if exists) - assume dose within 14 days is same dose
IF OBJECT_ID('tempdb..#VacTemp6') IS NOT NULL DROP TABLE #VacTemp6;
select c.FK_Patient_Link_ID, MIN(c.EventDate) AS VaccineDoseDate
into #VacTemp6
from #VacTemp5 v
inner join #COVIDVaccines c on c.EventDate > DATEADD(day, 14, v.VaccineDoseDate) and c.FK_Patient_Link_ID = v.FK_Patient_Link_ID
group by c.FK_Patient_Link_ID;
--2

-- Get seventh vaccine dose (if exists) - assume dose within 14 days is same dose
IF OBJECT_ID('tempdb..#VacTemp7') IS NOT NULL DROP TABLE #VacTemp7;
select c.FK_Patient_Link_ID, MIN(c.EventDate) AS VaccineDoseDate
into #VacTemp7
from #VacTemp6 v
inner join #COVIDVaccines c on c.EventDate > DATEADD(day, 14, v.VaccineDoseDate) and c.FK_Patient_Link_ID = v.FK_Patient_Link_ID
group by c.FK_Patient_Link_ID;
--2

IF OBJECT_ID('tempdb..#COVIDVaccinations') IS NOT NULL DROP TABLE #COVIDVaccinations;
SELECT v1.FK_Patient_Link_ID, v1.VaccineDoseDate AS VaccineDose1Date,
v2.VaccineDoseDate AS VaccineDose2Date,
v3.VaccineDoseDate AS VaccineDose3Date,
v4.VaccineDoseDate AS VaccineDose4Date,
v5.VaccineDoseDate AS VaccineDose5Date,
v6.VaccineDoseDate AS VaccineDose6Date,
v7.VaccineDoseDate AS VaccineDose7Date
INTO #COVIDVaccinations
FROM #VacTemp1 v1
LEFT OUTER JOIN #VacTemp2 v2 ON v2.FK_Patient_Link_ID = v1.FK_Patient_Link_ID
LEFT OUTER JOIN #VacTemp3 v3 ON v3.FK_Patient_Link_ID = v1.FK_Patient_Link_ID
LEFT OUTER JOIN #VacTemp4 v4 ON v4.FK_Patient_Link_ID = v1.FK_Patient_Link_ID
LEFT OUTER JOIN #VacTemp5 v5 ON v5.FK_Patient_Link_ID = v1.FK_Patient_Link_ID
LEFT OUTER JOIN #VacTemp6 v6 ON v6.FK_Patient_Link_ID = v1.FK_Patient_Link_ID
LEFT OUTER JOIN #VacTemp7 v7 ON v7.FK_Patient_Link_ID = v1.FK_Patient_Link_ID;

-- Tidy up
DROP TABLE #VacTemp1;
DROP TABLE #VacTemp2;
DROP TABLE #VacTemp3;
DROP TABLE #VacTemp4;
DROP TABLE #VacTemp5;
DROP TABLE #VacTemp6;
DROP TABLE #VacTemp7;

