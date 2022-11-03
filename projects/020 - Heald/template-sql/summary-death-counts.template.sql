--┌───────────────────────────────────┐
--│ Summary of death counts per month │
--└───────────────────────────────────┘

------------------------ RDE CHECK -------------------------
-- RDE NAME: ___, DATE OF CHECK: ___ -------
------------------------------------------------------------

-- Cohort is diabetic patients with a positive covid test. Also a 1:5 matched cohort, 
-- matched on year of birth (+-5 years), sex, and date of positive covid test (+-14 days).
-- For each we provide the following:

-- Table with the following columns:
--  - Year
--  - Month
--  - T1Population  - Number of T1DM patients in GM alive at the start of the month
--  - T1Deaths  - Number of T1DM patients in GM dying during the month
--  - T2Population  - Number of T2DM patients in GM alive at the start of the month
--  - T2Deaths  - Number of T2DM patients in GM dying during the month
--  - TotalPopulation  - Number of patients in GM alive at the start of the month
--  - TotalDeaths  - Number of patients in GM dying during the month

--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the temp end date until new legal basis
DECLARE @TEMPRQ020EndDate datetime;
SET @TEMPRQ020EndDate = '2022-06-01';

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2019-01-01';

-- Only include patients who were first registered at a GP practice prior
-- to June 2022. This is 1 month before COPI expired and so acts as a buffer.
-- If we only looked at patients who first registered before July 2022, then
-- there is a chance that their data was processed after COPI expired.
IF OBJECT_ID('tempdb..#PatientsToInclude') IS NOT NULL DROP TABLE #PatientsToInclude;
SELECT FK_Patient_Link_ID INTO #PatientsToInclude
FROM SharedCare.Patient_GP_History
GROUP BY FK_Patient_Link_ID
HAVING MIN(StartDate) < @TEMPRQ020EndDate;

-- Get all patients with T1DM and the first diagnosis date
--> CODESET diabetes-type-i:1
IF OBJECT_ID('tempdb..#DiabeticTypeIPatients') IS NOT NULL DROP TABLE #DiabeticTypeIPatients;
CREATE TABLE #DiabeticTypeIPatients(FK_Patient_Link_ID BIGINT, FirstT1DiagnosisDate DATE, DeathDate DATE);
INSERT INTO #DiabeticTypeIPatients
SELECT FK_Patient_Link_ID, MIN(CAST(EventDate AS DATE)) AS FirstT1DiagnosisDate, NULL
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('diabetes-type-i') AND [Version]=1) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('diabetes-type-i') AND [Version]=1)
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude)
AND EventDate < @TEMPRQ020EndDate
GROUP BY FK_Patient_Link_ID;

-- Add death date where applicable
UPDATE d
SET d.DeathDate = p.DeathDate
FROM #DiabeticTypeIPatients d
INNER JOIN [RLS].vw_Patient_Link p ON p.PK_Patient_Link_ID = d.FK_Patient_Link_ID;

-- Get all patients with T2DM and the first diagnosis date
--> CODESET diabetes-type-ii:1
IF OBJECT_ID('tempdb..#DiabeticTypeIIPatients') IS NOT NULL DROP TABLE #DiabeticTypeIIPatients;
CREATE TABLE #DiabeticTypeIIPatients(FK_Patient_Link_ID BIGINT, FirstT2DiagnosisDate DATE, DeathDate DATE);
INSERT INTO #DiabeticTypeIIPatients
SELECT FK_Patient_Link_ID, MIN(CAST(EventDate AS DATE)) AS FirstT2DiagnosisDate, NULL
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('diabetes-type-ii') AND [Version]=1) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('diabetes-type-ii') AND [Version]=1)
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude)
AND EventDate < @TEMPRQ020EndDate
GROUP BY FK_Patient_Link_ID;

-- Add death date where applicable
UPDATE d
SET d.DeathDate = p.DeathDate
FROM #DiabeticTypeIIPatients d
INNER JOIN [RLS].vw_Patient_Link p ON p.PK_Patient_Link_ID = d.FK_Patient_Link_ID;

-- Get all patients and death dates
IF OBJECT_ID('tempdb..#AllPatientsForSummaryDeathCount') IS NOT NULL DROP TABLE #AllPatientsForSummaryDeathCount;
SELECT PK_Patient_Link_ID, DeathDate INTO #AllPatientsForSummaryDeathCount FROM [RLS].vw_Patient_Link
INNER JOIN [RLS].vw_Patient p ON p.FK_Patient_Link_ID = PK_Patient_Link_ID
WHERE FK_Reference_Tenancy_ID = 2;

--> EXECUTE query-patient-gp-history.sql

-- Table of dates for future joining
IF OBJECT_ID('tempdb..#DatesFrom2019') IS NOT NULL DROP TABLE #DatesFrom2019;
CREATE TABLE #DatesFrom2019 ([date] date);
declare @dt datetime = '2019-01-01'
declare @dtEnd datetime = @TEMPRQ020EndDate;
WHILE (@dt <= @dtEnd) BEGIN
    insert into #DatesFrom2019([date])
        values(@dt)
    SET @dt = DATEADD(month, 1, @dt)
END;

-- T1 population per month
IF OBJECT_ID('tempdb..#T1PopPerMonth') IS NOT NULL DROP TABLE #T1PopPerMonth;
SELECT YEAR(d.date) AS Year, MONTH(d.date) AS Month, COUNT(*) AS T1Population INTO #T1PopPerMonth FROM #DatesFrom2019 d
INNER JOIN #DiabeticTypeIPatients t1 
	ON d.date > t1.FirstT1DiagnosisDate --only count people starting in the month AFTER their diagnosis and onwards
	AND (d.date <= t1.DeathDate OR t1.DeathDate IS NULL) --don't count people who have died before the month
LEFT OUTER JOIN #PatientGPHistory h
	on h.StartDate <= d.date -- match the current practice for each patient each month
	AND h.EndDate >=d.date
	AND h.FK_Patient_Link_ID=t1.FK_Patient_Link_ID
where h.GPPracticeCode != 'OutOfArea' -- don't count people each month who are not GM GP registered
OR h.GPPracticeCode IS NULL 
GROUP BY YEAR(d.date), MONTH(d.date)
ORDER BY YEAR(d.date), MONTH(d.date);

-- T1 deaths per month
IF OBJECT_ID('tempdb..#T1DeathsPerMonth') IS NOT NULL DROP TABLE #T1DeathsPerMonth;
SELECT YEAR(d.date) AS Year, MONTH(d.date) AS Month, COUNT(*) AS T1Deaths INTO #T1DeathsPerMonth FROM #DatesFrom2019 d
INNER JOIN #DiabeticTypeIPatients t1 
	ON d.date > t1.FirstT1DiagnosisDate --only count people starting in the month AFTER their diagnosis and onwards
	AND d.date <= t1.DeathDate
	AND DATEADD(month, 1, d.date) > t1.DeathDate --only count people who have died in this month
LEFT OUTER JOIN #PatientGPHistory h
	on h.StartDate <= d.date -- match the current practice for each patient each month
	AND h.EndDate >=d.date
	AND h.FK_Patient_Link_ID=t1.FK_Patient_Link_ID
where h.GPPracticeCode != 'OutOfArea' -- don't count people each month who are not GM GP registered
OR h.GPPracticeCode IS NULL 
GROUP BY YEAR(d.date), MONTH(d.date)
ORDER BY YEAR(d.date), MONTH(d.date);

-- T2 population per month
IF OBJECT_ID('tempdb..#T2PopPerMonth') IS NOT NULL DROP TABLE #T2PopPerMonth;
SELECT YEAR(d.date) AS Year, MONTH(d.date) AS Month, COUNT(*) AS T2Population INTO #T2PopPerMonth FROM #DatesFrom2019 d
INNER JOIN #DiabeticTypeIIPatients T2 
	ON d.date > T2.FirstT2DiagnosisDate --only count people starting in the month AFTER their diagnosis and onwards
	AND (d.date <= T2.DeathDate OR T2.DeathDate IS NULL) --don't count people who have died before the month
LEFT OUTER JOIN #PatientGPHistory h
	on h.StartDate <= d.date -- match the current practice for each patient each month
	AND h.EndDate >=d.date
	AND h.FK_Patient_Link_ID=T2.FK_Patient_Link_ID
where h.GPPracticeCode != 'OutOfArea' -- don't count people each month who are not GM GP registered
OR h.GPPracticeCode IS NULL 
GROUP BY YEAR(d.date), MONTH(d.date)
ORDER BY YEAR(d.date), MONTH(d.date);

-- T2 deaths per month
IF OBJECT_ID('tempdb..#T2DeathsPerMonth') IS NOT NULL DROP TABLE #T2DeathsPerMonth;
SELECT YEAR(d.date) AS Year, MONTH(d.date) AS Month, COUNT(*) AS T2Deaths INTO #T2DeathsPerMonth FROM #DatesFrom2019 d
INNER JOIN #DiabeticTypeIIPatients T2 
	ON d.date > T2.FirstT2DiagnosisDate --only count people starting in the month AFTER their diagnosis and onwards
	AND d.date <= T2.DeathDate
	AND DATEADD(month, 1, d.date) > T2.DeathDate --only count people who have died in this month
LEFT OUTER JOIN #PatientGPHistory h
	on h.StartDate <= d.date -- match the current practice for each patient each month
	AND h.EndDate >=d.date
	AND h.FK_Patient_Link_ID=T2.FK_Patient_Link_ID
where h.GPPracticeCode != 'OutOfArea' -- don't count people each month who are not GM GP registered
OR h.GPPracticeCode IS NULL 
GROUP BY YEAR(d.date), MONTH(d.date)
ORDER BY YEAR(d.date), MONTH(d.date);

-- ALL population per month
IF OBJECT_ID('tempdb..#ALLPopPerMonth') IS NOT NULL DROP TABLE #ALLPopPerMonth;
SELECT YEAR(d.date) AS Year, MONTH(d.date) AS Month, COUNT(*) AS ALLPopulation INTO #ALLPopPerMonth FROM #DatesFrom2019 d
INNER JOIN #AllPatientsForSummaryDeathCount a 
	ON (d.date <= a.DeathDate OR a.DeathDate IS NULL) --don't count people who have died before the month
LEFT OUTER JOIN #PatientGPHistory h
	on h.StartDate <= d.date -- match the current practice for each patient each month
	AND h.EndDate >=d.date
	AND h.FK_Patient_Link_ID=a.PK_Patient_Link_ID
where h.GPPracticeCode != 'OutOfArea' -- don't count people each month who are not GM GP registered
OR h.GPPracticeCode IS NULL 
GROUP BY YEAR(d.date), MONTH(d.date)
ORDER BY YEAR(d.date), MONTH(d.date);

-- ALL deaths per month
IF OBJECT_ID('tempdb..#ALLDeathsPerMonth') IS NOT NULL DROP TABLE #ALLDeathsPerMonth;
SELECT YEAR(d.date) AS Year, MONTH(d.date) AS Month, COUNT(*) AS ALLDeaths INTO #ALLDeathsPerMonth FROM #DatesFrom2019 d
INNER JOIN #AllPatientsForSummaryDeathCount a 
	ON d.date <= a.DeathDate
	AND DATEADD(month, 1, d.date) > a.DeathDate --only count people who have died in this month
LEFT OUTER JOIN #PatientGPHistory h
	on h.StartDate <= d.date -- match the current practice for each patient each month
	AND h.EndDate >=d.date
	AND h.FK_Patient_Link_ID=a.PK_Patient_Link_ID
where h.GPPracticeCode != 'OutOfArea' -- don't count people each month who are not GM GP registered
OR h.GPPracticeCode IS NULL 
GROUP BY YEAR(d.date), MONTH(d.date)
ORDER BY YEAR(d.date), MONTH(d.date);

-- Final extract
SELECT YEAR(d.date) AS Year, MONTH(d.date) AS Month, T1Population, T1Deaths, T2Population, T2Deaths, ALLPopulation, ALLDeaths FROM #DatesFrom2019 d
LEFT OUTER JOIN #T1DeathsPerMonth t1d on t1d.Year = YEAR(d.date) and t1d.Month = MONTH(d.date)
LEFT OUTER JOIN #T1PopPerMonth t1 on t1.Year = YEAR(d.date) and t1.Month = MONTH(d.date)
LEFT OUTER JOIN #T2DeathsPerMonth t2d on t2d.Year = YEAR(d.date) and t2d.Month = MONTH(d.date)
LEFT OUTER JOIN #T2PopPerMonth t2 on t2.Year = YEAR(d.date) and t2.Month = MONTH(d.date)
LEFT OUTER JOIN #ALLDeathsPerMonth ad on ad.Year = YEAR(d.date) and ad.Month = MONTH(d.date)
LEFT OUTER JOIN #ALLPopPerMonth a on a.Year = YEAR(d.date) and a.Month = MONTH(d.date)
WHERE YEAR(d.date) < YEAR(@TEMPRQ020EndDate)
OR MONTH(d.date) < MONTH(@TEMPRQ020EndDate); -- No deaths in "current" month so no point returning
