--┌────────────────────────────────────┐
--│ Generate the patient file for RQ050│
--└────────────────────────────────────┘

----- RESEARCH DATA ENGINEER CHECK ------
-- 18th August 2022 - Richard Williams --
-----------------------------------------

-- INCLUSION: Women aged 14 - 59 who have had a pregnancy during the study period (March 2012 - March 2022)

-- OUTPUT: Data with the following fields
-- 	- PatientId (int)
--  - Date that patient left Greater Manchester GP (YYYY-MM)
--  - Year of birth (YYYY-MM)
--  - Month and year of death (YYYY-MM)
--  - Ethnicity (white/black/asian/mixed/other)
--  - IMD decile (1-10)
--  - BMI
--  - BMI Date
--  - Smoking Status
--  - LSOA

--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2012-01-01';
SET @EndDate = '2023-08-31'; --'2022-01-01';

DECLARE @IndexDate datetime;
SET @IndexDate = '2022-01-01';

--Just want the output, not the messages
SET NOCOUNT ON;

----------------------------------------
--> EXECUTE query-build-rq050-cohort.sql
----------------------------------------

--> EXECUTE query-patient-gp-history.sql
--> EXECUTE query-patient-practice-and-ccg.sql

-- FIND PATIENTS THAT HAVE LEFT GM DURING STUDY PERIOD AND THE DATE THAT THEY LEFT

IF OBJECT_ID('tempdb..#GM_GPs') IS NOT NULL DROP TABLE #GM_GPs;
SELECT * 
INTO #GM_GPs
FROM #PatientGPHistory
WHERE 
--StartDate <= @StartDate and EndDate > @StartDate and 
GPPracticeCode <> 'OutOfArea'

IF OBJECT_ID('tempdb..#GM_GP_range') IS NOT NULL DROP TABLE #GM_GP_range;
SELECT FK_Patient_Link_ID, MIN(StartDate) AS MinDate, MAX(EndDate) AS MaxDate
INTO #GM_GP_range
FROM #GM_GPs
GROUP BY FK_Patient_Link_ID
ORDER BY FK_Patient_Link_ID, MIN(StartDate)

IF OBJECT_ID('tempdb..#GPExitDates') IS NOT NULL DROP TABLE #GPExitDates;
SELECT *,
	MovedOutOfGMDate = CASE WHEN MaxDate <  @EndDate THEN MaxDate ELSE NULL END
INTO #GPExitDates
FROM #GM_GP_range


-- Get patient list of those with COVID death within 28 days of positive test
IF OBJECT_ID('tempdb..#COVIDDeathPositiveTest') IS NOT NULL DROP TABLE #COVIDDeathPositiveTest;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #COVIDDeathPositiveTest 
FROM SharedCare.COVID19
where DeathWithin28Days = 'Y' 

-- Get patient list of those with COVID death within 28 days of positive test, and any deaths within 28 days of a confirmed covid-19 record
IF OBJECT_ID('tempdb..#COVIDDeathConfirmed') IS NOT NULL DROP TABLE #COVIDDeathConfirmed;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #COVIDDeathConfirmed 
FROM SharedCare.COVID19
where (DeathWithin28Days = 'Y' 
        OR
    (GroupDescription = 'Confirmed' AND SubGroupDescription IN ('','Positive', 'Post complication', 'Post Assessment', 'Organism', NULL))
	) and DeathDate <= DATEADD(dd,28, EventDate)

-- REDUCE THE #Patients TABLE SO THAT IT ONLY INCLUDES THE COHORT, AND REUSABLE QUERIES CAN USE IT TO BE RUN QUICKER 

DELETE FROM #Patients
WHERE FK_Patient_Link_ID NOT IN (SELECT FK_Patient_Link_ID FROM #Cohort)



--> EXECUTE query-patient-imd.sql
--> EXECUTE query-patient-lsoa.sql
--> EXECUTE query-patient-smoking-status.sql gp-events-table:#PatientEventData
--> EXECUTE query-patient-bmi.sql gp-events-table:#PatientEventData


SELECT  PatientId = p.FK_Patient_Link_ID, 
		PracticeExitDate = gpex.MovedOutOfGMDate,
		PracticeCCG = prac.CCG,
		YearOfBirth, 
		Sex,
		EthnicMainGroup,
	    LSOA_Code,
		IMD2019Decile1IsMostDeprived10IsLeastDeprived,
		BMI,
		BMIDate = DateOfBMIMeasurement,
		CurrentSmokingStatus = smok.CurrentSmokingStatus,
		WorstSmokingStatus = smok.WorstSmokingStatus,
		DeathWithin28DaysPositiveCOVIDTest = CASE WHEN cdp.FK_Patient_Link_ID  IS NOT NULL THEN 'Y' ELSE 'N' END,
		DeathWithin28DaysCOVIDConfirmed = CASE WHEN cdc.FK_Patient_Link_ID  IS NOT NULL THEN 'Y' ELSE 'N' END,
		Death_Year = YEAR(p.DeathDate),
		Death_Month = MONTH(p.DeathDate)
FROM #Patients p
LEFT OUTER JOIN #PatientLSOA lsoa ON lsoa.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientIMDDecile imd ON imd.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientBMI bmi ON bmi.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSmokingStatus smok ON smok.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientPracticeAndCCG prac ON prac.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #GPExitDates gpex ON gpex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDDeathPositiveTest cdp ON cdp.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDDeathConfirmed cdc ON cdc.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE 
	YEAR(@StartDate) - YearOfBirth BETWEEN 14 AND 49 -- EXTRA CHECK FOR OVER 18s ONLY
	AND p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort)
--320,594