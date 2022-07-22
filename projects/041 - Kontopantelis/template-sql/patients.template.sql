--┌──────────────────────────────────────────────────────────────────┐
--│ Patient information for those with biochemical evidence of CKD   │
--└──────────────────────────────────────────────────────────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------

------------------------------------------------------

-- PatientID
-- Year of birth (YYYY-MM)
-- Practice exit date (moved out of GM date) (YYYY-MM-DD)
-- Month and year of death (YYYY-MM)
-- Sex at birth (male/female)
-- Ethnicity (white/black/asian/mixed/other)
-- CCG of registered GP practice
-- Alcohol intake
-- Smoking status
-- BMI (closest to 2020-03-01)
-- BMI date
-- LSOA Code
-- IMD decile
-- First vaccination date (YYYY-MM or N/A)
-- Second vaccination date (YYYY-MM or N/A)
-- Third vaccination date (YYYY-MM or N/A)
-- Death within 28 days of Covid Diagnosis (Y/N)
-- Date of death due to Covid-19 (YYYY-MM or N/A)
-- Number of AE Episodes before covid (01.03.18 - 01.03.20)
-- Number of AE Episodes after covid (01.03.20 - 01.03.22)
-- Total AE Episodes (01.03.18 - 01.03.22)
-- Number of GP appointments before covid (01.03.18 - 01.03.20)
-- Number of GP appointments after covid (01.03.20 - 01.03.22)
-- Total GP appointments (01.03.18 - 01.03.22)
-- evidenceOfCKD_egfr (1/0)
-- evidenceOfCKD_acr (1/0)
-- HypertensionAtStudyStart
-- HypertensionDuringStudyPeriod
-- DiabetesAtStudyStart
-- DiabetesDuringStudyPeriod

-- Set the start date
DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2018-03-01';
SET @EndDate = '2022-03-01';

DECLARE @IndexDate datetime;
SET @IndexDate = '2020-03-01';

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


-- DEFINE COHORT
--> EXECUTE query-build-rq041-cohort.sql

-- FIND WHICH PATIENTS IN THE COHORT HAD HYPERTENSION OR DIABETES AND THE DATE OF EARLIEST DIAGNOSIS

IF OBJECT_ID('tempdb..#hypertension') IS NOT NULL DROP TABLE #hypertension;
SELECT FK_Patient_Link_ID, MIN(EventDate) as EarliestDiagnosis
INTO #hypertension
FROM #PatientEventData gp
WHERE  (
	gp.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'hypertension' AND [Version]=1) OR
    gp.FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'hypertension' AND [Version]=1)
	)
GROUP BY FK_Patient_Link_ID

IF OBJECT_ID('tempdb..#diabetes') IS NOT NULL DROP TABLE #diabetes;
SELECT FK_Patient_Link_ID, MIN(EventDate) as EarliestDiagnosis
INTO #diabetes
FROM #PatientEventData gp
WHERE  (
	gp.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'diabetes' AND [Version]=1) OR
    gp.FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'diabetes' AND [Version]=1)
	)
GROUP BY FK_Patient_Link_ID


--> EXECUTE query-get-covid-vaccines.sql gp-events-table:#PatientEventData gp-medications-table:RLS.vw_GP_Medications
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

--> EXECUTE query-patient-gp-encounters.sql all-patients:false gp-events-table:#PatientEventData start-date:'2018-03-01' end-date:'2022-03-01'


-- -- FIND NUMBER OF ATTENDED GP APPOINTMENTS FROM MARCH 2018 TO MARCH 2022

IF OBJECT_ID('tempdb..#GPEncounters1') IS NOT NULL DROP TABLE #GPEncounters1;
SELECT FK_Patient_Link_ID, 
	EncounterDate, 
	BeforeOrAfter1stMarch2020 = CASE WHEN EncounterDate < '2020-03-01' THEN 'BEFORE' ELSE 'AFTER' END -- before and after covid started
INTO #GPEncounters1
FROM #GPEncounters

IF OBJECT_ID('tempdb..#GPEncountersCount') IS NOT NULL DROP TABLE #GPEncountersCount;
SELECT FK_Patient_Link_ID, BeforeOrAfter1stMarch2020, COUNT(*) as gp_appointments
INTO #GPEncountersCount
FROM #GPEncounters1
GROUP BY FK_Patient_Link_ID, BeforeOrAfter1stMarch2020
ORDER BY FK_Patient_Link_ID, BeforeOrAfter1stMarch2020

-- FIND NUMBER OF A&E APPOINTMENTS FROM MARCH 2018 TO MARCH 2022

IF OBJECT_ID('tempdb..#ae_encounters') IS NOT NULL DROP TABLE #ae_encounters;
SELECT a.FK_Patient_Link_ID, 
	a.AttendanceDate, 
	BeforeOrAfter1stMarch2020 = CASE WHEN a.AttendanceDate < '2020-03-01' THEN 'BEFORE' ELSE 'AFTER' END -- before and after covid started
INTO #ae_encounters
FROM RLS.vw_Acute_AE a
WHERE EventType = 'Attendance'
AND a.AttendanceDate BETWEEN @StartDate AND @EndDate
AND a.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort) 

SELECT FK_Patient_Link_ID, BeforeOrAfter1stMarch2020, COUNT(*) AS ae_encounters
INTO #AEEncountersCount
FROM #ae_encounters
GROUP BY FK_Patient_Link_ID, BeforeOrAfter1stMarch2020
ORDER BY FK_Patient_Link_ID, BeforeOrAfter1stMarch2020


-- Get patient list of those with COVID death within 28 days of positive test
IF OBJECT_ID('tempdb..#COVIDDeath') IS NOT NULL DROP TABLE #COVIDDeath;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #COVIDDeath FROM RLS.vw_COVID19
WHERE DeathWithin28Days = 'Y'
	AND EventDate <= @EndDate

--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-imd.sql
--> EXECUTE query-patient-lsoa.sql
--> EXECUTE query-patient-bmi.sql gp-events-table:#PatientEventData
--> EXECUTE query-patient-smoking-status.sql gp-events-table:#PatientEventData
--> EXECUTE query-patient-alcohol-intake.sql gp-events-table:#PatientEventData

-- REDUCE THE #Patients TABLE SO THAT IT ONLY INCLUDES THE COHORT, AND REUSABLE QUERIES CAN USE IT TO BE RUN QUICKER 

DELETE FROM #Patients
WHERE FK_Patient_Link_ID NOT IN (SELECT FK_Patient_Link_ID FROM #Cohort)

--> EXECUTE query-patients-with-covid.sql start-date:2020-01-01 gp-events-table:#PatientEventData all-patients:false

---- CREATE OUTPUT TABLE OF ALL INFO NEEDED FOR THE COHORT

SELECT  PatientId = p.FK_Patient_Link_ID, 
		PracticeExitDate = gpex.MovedOutOfGMDate,
		PracticeCCG = prac.CCG,
		YearOfBirth, 
		Sex,
		BMI,
		BMIDate = bmi.EventDate,
		EthnicMainGroup,
	    LSOA_Code,
		IMD2019Decile1IsMostDeprived10IsLeastDeprived,
		CurrentSmokingStatus = smok.CurrentSmokingStatus,
		WorstSmokingStatus = smok.WorstSmokingStatus,
		CurrentAlcoholIntake,
		WorstAlcoholIntake,
		DeathWithin28DaysCovid = CASE WHEN cd.FK_Patient_Link_ID  IS NOT NULL THEN 'Y' ELSE 'N' END,
		Death_Year = YEAR(p.DeathDate),
		Death_Month = MONTH(p.DeathDate),
		FirstVaccineYear =  YEAR(VaccineDose1Date),
		FirstVaccineMonth = MONTH(VaccineDose1Date),
		SecondVaccineYear =  YEAR(VaccineDose2Date),
		SecondVaccineMonth = MONTH(VaccineDose2Date),
		ThirdVaccineYear =  YEAR(VaccineDose3Date),
		ThirdVaccineMonth = MONTH(VaccineDose3Date),
		FirstCovidPositiveDate,
		SecondCovidPositiveDate, 
		ThirdCovidPositiveDate, 
		FourthCovidPositiveDate, 
		FifthCovidPositiveDate,
		AEEncountersBefore1stMarch2020 = ae_b.ae_encounters,
		AEEncountersAfter1stMarch2020 = ae_a.ae_encounters,
		GPAppointmentsBefore1stMarch2020 = gp_b.gp_appointments,
		GPAppointmentsAfter1stMarch2020 =  gp_a.gp_appointments,
		EvidenceOfCKD_egfr,
		EvidenceOfCKD_acr,
		HypertensionAtStudyStart = CASE WHEN hyp.FK_Patient_Link_ID IS NOT NULL AND hyp.EarliestDiagnosis <= @StartDate THEN 1 ELSE 0 END,
		HypertensionDuringStudyPeriod = CASE WHEN hyp.FK_Patient_Link_ID IS NOT NULL AND hyp.EarliestDiagnosis BETWEEN @StartDate AND @EndDate THEN 1 ELSE 0 END,
		DiabetesAtStudyStart = CASE WHEN dia.FK_Patient_Link_ID IS NOT NULL AND dia.EarliestDiagnosis <= @StartDate THEN 1 ELSE 0 END,
		DiabetesDuringStudyPeriod = CASE WHEN dia.FK_Patient_Link_ID IS NOT NULL AND dia.EarliestDiagnosis BETWEEN @StartDate AND @EndDate THEN 1 ELSE 0 END
FROM #Cohort p
LEFT OUTER JOIN #PatientLSOA lsoa ON lsoa.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientIMDDecile imd ON imd.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientBMI bmi ON bmi.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSmokingStatus smok ON smok.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientAlcoholIntake alc ON alc.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientPracticeAndCCG prac ON prac.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #GPExitDates gpex ON gpex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDVaccinations vac ON vac.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDDeath cd ON cd.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #AEEncountersCount ae_b ON ae_b.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND ae_b.BeforeOrAfter1stMarch2020 = 'BEFORE'
LEFT OUTER JOIN #AEEncountersCount ae_a ON ae_a.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND ae_a.BeforeOrAfter1stMarch2020 = 'AFTER'
LEFT OUTER JOIN #GPEncountersCount gp_b ON gp_b.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND gp_b.BeforeOrAfter1stMarch2020 = 'BEFORE'
LEFT OUTER JOIN #GPEncountersCount gp_a ON gp_a.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND gp_a.BeforeOrAfter1stMarch2020 = 'AFTER'
LEFT OUTER JOIN #hypertension hyp ON hyp.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #diabetes dia ON dia.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #CovidPatientsMultipleDiagnoses cv ON cv.FK_Patient_Link_ID = P.FK_Patient_Link_ID
WHERE YEAR(@StartDate) - YearOfBirth > 18 -- EXTRA CHECK TO ENSURE OVER 18s ONLY
--320,594