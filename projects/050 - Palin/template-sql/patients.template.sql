--┌────────────────────────────────────┐
--│ Generate the patient file for RQ050│
--└────────────────────────────────────┘

-- INCLUSION: Women aged 14 - 59 who have had a pregnancy during the study period (March 2012 - March 2022)

-- OUTPUT: Data with the following fields
-- 	- PatientId (int)
--  - Registration date with GP (YYYY-MM)
--  - Date that patient left GP (YYYY-MM)
--  - Month and year of birth (YYYY-MM)
--  - Month and year of death (YYYY-MM)
--  - Ethnicity (white/black/asian/mixed/other)
--  - IMD decile (1-10)
--  - LSOA
--  - History of Comorbidities (one column per condition - info on conditions here. Other conditions included will be: preeclampsia, gestational diabetes, miscarriage, stillbirth, fetal growth restriction) (1,0)
--  - Pregnancy1: Estimated Pregnancy start month (YYYY-MM)
--  - Pregnancy1: Pregnancy Delivery month (YYYY-MM)
--  - Pregnancy1: Date of admission
--  - Pregnancy1: Length of stay
--  - Pregnancy1: Number of total medications prescribed in previous 12 months
--  - Pregnancy1: Number of unique medications prescribed in previous 12 months
--  - Number of pregnancies during study period


--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2012-03-01';
SET @EndDate = '2022-03-01';

DECLARE @IndexDate datetime;
SET @IndexDate = '2022-03-01';

--Just want the output, not the messages
SET NOCOUNT ON;

-- Find all patients alive at start date
IF OBJECT_ID('tempdb..#PossiblePatients') IS NOT NULL DROP TABLE #PossiblePatients;
SELECT PK_Patient_Link_ID as FK_Patient_Link_ID, EthnicMainGroup, DeathDate INTO #PossiblePatients FROM [RLS].vw_Patient_Link
WHERE (DeathDate IS NULL OR DeathDate >= @StartDate);

-- Find all patients registered with a GP
IF OBJECT_ID('tempdb..#PatientsWithGP') IS NOT NULL DROP TABLE #PatientsWithGP;
SELECT DISTINCT FK_Patient_Link_ID INTO #PatientsWithGP FROM [RLS].vw_Patient
where FK_Reference_Tenancy_ID = 2;

-- Make cohort from patients alive at start date and registered with a GP
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT pp.* INTO #Patients FROM #PossiblePatients pp
INNER JOIN #PatientsWithGP gp on gp.FK_Patient_Link_ID = pp.FK_Patient_Link_ID;


--> CODESET pregnancy:1

-- identify all patients that had a pregnancy code during the study period


-- table of all pregnancy codes within the study period

IF OBJECT_ID('tempdb..#PregnancyPatientsGP') IS NOT NULL DROP TABLE #PregnancyPatientsGP;
SELECT 
	FK_Patient_Link_ID,
	SuppliedCode,
	EventDate
INTO #PregnancyPatientsGP
FROM [RLS].[vw_GP_Events]
WHERE (
    FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'pregnancy' AND Version = 1) OR
    FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'pregnancy' AND Version = 1)
	)
	AND EventDate BETWEEN @StartDate AND @EndDate
	AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)

--> EXECUTE query-classify-secondary-admissions.sql

-- identify patients that had a maternity episode during study period (from secondary care data)

IF OBJECT_ID('tempdb..#PregnancyPatientsHosp') IS NOT NULL DROP TABLE #PregnancyPatientsHosp;
SELECT
	DISTINCT FK_Patient_Link_ID
INTO #PregnancyPatientsHosp
FROM #AdmissionTypes
WHERE AdmissionType = 'Maternity'
	AND AdmissionDate BETWEEN @StartDate and @EndDate
		AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)


-- COMBINE (FROM PRIMARY AND SECONDARY CARE DATA) PATIENTS IDENTIFIED AS HAVING A PREGNANCY DURING STUDY PERIOD 

IF OBJECT_ID('tempdb..#Cohort') IS NOT NULL DROP TABLE #Cohort;
SELECT DISTINCT FK_Patient_Link_ID
INTO #Cohort
FROM #PregnancyPatientsHosp
UNION ALL 
SELECT DISTINCT FK_Patient_Link_ID
FROM #PregnancyPatientsGP


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
IF OBJECT_ID('tempdb..#COVIDDeath') IS NOT NULL DROP TABLE #COVIDDeath;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #COVIDDeath FROM RLS.vw_COVID19
WHERE DeathWithin28Days = 'Y'
	AND EventDate <= @EndDate


-- REDUCE THE #Patients TABLE SO THAT IT ONLY INCLUDES THE COHORT, AND REUSABLE QUERIES CAN USE IT TO BE RUN QUICKER 

DELETE FROM #Patients
WHERE FK_Patient_Link_ID NOT IN (SELECT FK_Patient_Link_ID FROM #Cohort)

-- TABLE OF GP EVENTS FOR COHORT TO SPEED UP REUSABLE QUERIES

IF OBJECT_ID('tempdb..#PatientEventData') IS NOT NULL DROP TABLE #PatientEventData;
SELECT 
  FK_Patient_Link_ID,
  CAST(EventDate AS DATE) AS EventDate,
  SuppliedCode,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID,
  [Value]
INTO #PatientEventData
FROM [RLS].vw_GP_Events
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort);

--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-imd.sql
--> EXECUTE query-patient-year-of-birth.sql
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
		BMI,
		BMIDate = bmi.EventDate,
		IMD2019Decile1IsMostDeprived10IsLeastDeprived,
		CurrentSmokingStatus = smok.CurrentSmokingStatus,
		WorstSmokingStatus = smok.WorstSmokingStatus,
		DeathWithin28DaysCovid = CASE WHEN cd.FK_Patient_Link_ID  IS NOT NULL THEN 'Y' ELSE 'N' END,
		DeathDueToCovid_Year = CASE WHEN cd.FK_Patient_Link_ID IS NOT NULL THEN YEAR(p.DeathDate) ELSE null END,
		DeathDueToCovid_Month = CASE WHEN cd.FK_Patient_Link_ID IS NOT NULL THEN MONTH(p.DeathDate) ELSE null END
FROM #Patients p
LEFT OUTER JOIN #PatientLSOA lsoa ON lsoa.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientIMDDecile imd ON imd.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientBMI bmi ON bmi.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSmokingStatus smok ON smok.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientPracticeAndCCG prac ON prac.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #GPExitDates gpex ON gpex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDDeath cd ON cd.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE 
	YEAR(@StartDate) - YearOfBirth BETWEEN 14 AND 49 -- OVER 18s ONLY
	AND Sex = 'F'
	AND p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort)
--320,594