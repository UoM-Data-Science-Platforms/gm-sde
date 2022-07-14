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

--------------------------------------------------------------------------------------------------------
----------------------------------- DEFINE MAIN COHORT -----------------------------------------------
--------------------------------------------------------------------------------------------------------
-- COHORT WILL BE ANY PATIENT WITH BIOCHEMICAL EVIDENCE OF CKD, OR AT RISK OF CKD (HAS HYPERTENSION OR DIABETES)


-- LOAD CODESETS NEEDED FOR DEFINING COHORT

--> CODESET hypertension:1 diabetes:1
--> CODESET egfr:1 urinary-albumin-creatinine-ratio:1 glomerulonephritis:1 kidney-transplant:1 kidney-stones:1 vasculitis:1


---- FIND PATIENTS WITH BIOCHEMICAL EVIDENCE OF CKD

---- find all eGFR and ACR tests

IF OBJECT_ID('tempdb..#EGFR_ACR_TESTS') IS NOT NULL DROP TABLE #EGFR_ACR_TESTS;
SELECT gp.FK_Patient_Link_ID, 
	CAST(GP.EventDate AS DATE) AS EventDate, 
	SuppliedCode, 
	[value] = TRY_CONVERT(NUMERIC (18,5), [Value]),  
	[Units],
	egfr_Code = CASE WHEN SuppliedCode IN (
		SELECT [Code] FROM #AllCodes WHERE [Concept] IN ('egfr') AND [Version] = 1 ) THEN 1 ELSE 0 END,
	acr_Code = CASE WHEN SuppliedCode IN (
		SELECT [Code] FROM #AllCodes WHERE [Concept] IN ('urinary-albumin-creatinine-ratio') AND [Version] = 1 ) THEN 1 ELSE 0 END
INTO #EGFR_ACR_TESTS
FROM [RLS].[vw_GP_Events] gp
WHERE (
		gp.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('egfr', 'urinary-albumin-creatinine-ratio')  AND [Version]=1) OR
		gp.FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('egfr', 'urinary-albumin-creatinine-ratio')  AND [Version]=1)
	  )
	AND gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
	AND (gp.EventDate) BETWEEN '2016-01-01' and @EndDate
	AND [Value] IS NOT NULL AND UPPER([Value]) NOT LIKE '%[A-Z]%' -- REMOVE RECORDS WITH NO VALUE OR TEXT 

-- CATEGORISE EGFR AND ACR TESTS INTO CKD STAGES

IF OBJECT_ID('tempdb..#ckd_stages') IS NOT NULL DROP TABLE #ckd_stages;
SELECT FK_Patient_Link_ID,
	EventDate,
	egfr_evidence = CASE WHEN egfr_Code = 1 AND [Value] >= 90   THEN 'G1' 
		WHEN egfr_Code = 1 AND [Value] BETWEEN 60 AND 89 		THEN 'G2'
		WHEN egfr_Code = 1 AND [Value] BETWEEN 45 AND 59 		THEN 'G3a'
		WHEN egfr_Code = 1 AND [Value] BETWEEN 30 AND 44 		THEN 'G3b'
		WHEN egfr_Code = 1 AND [Value] BETWEEN 15 AND 29 		THEN 'G4'
		WHEN egfr_Code = 1 AND [Value] BETWEEN  0 AND 15 		THEN 'G5'
			ELSE NULL END,
	acr_evidence = CASE WHEN acr_Code = 1 AND [Value] > 30  	THEN 'A3' 
		WHEN acr_Code = 1 AND [Value] BETWEEN 3 AND 30 			THEN 'A2'
		WHEN acr_Code = 1 AND [Value] BETWEEN  0 AND 3 			THEN 'A1'
			ELSE NULL END 
INTO #ckd_stages
FROM #EGFR_ACR_TESTS

-- FIND EGFR TESTS INDICATIVE OF CKD STAGE 3-5, WITH THE DATES OF THE PREVIOUS TEST

IF OBJECT_ID('tempdb..#egfr_dates') IS NOT NULL DROP TABLE #egfr_dates;
SELECT *, 
	stage_previous_egfr = LAG(egfr_evidence, 1, NULL) OVER (PARTITION BY FK_Patient_Link_ID ORDER BY EventDate),
	date_previous_egfr = LAG(EventDate, 1, NULL) OVER (PARTITION BY FK_Patient_Link_ID ORDER BY EventDate)
INTO #egfr_dates
FROM #ckd_stages
ORDER BY FK_Patient_Link_ID, EventDate

-- CREATE TABLE OF PATIENTS THAT HAD TWO EGFR TESTS INDICATIVE OF CKD STAGE 3-5, WITHIN 3 MONTHS OF EACH OTHER

IF OBJECT_ID('tempdb..#egfr_ckd_evidence') IS NOT NULL DROP TABLE #egfr_ckd_evidence;
SELECT *
INTO #egfr_ckd_evidence
FROM #egfr_dates
WHERE datediff(month, date_previous_egfr, EventDate) <=  3 --only find patients with two tests in three months

-- CREATE TABLE OF PATIENTS THAT HAVE A HISTORY OF KIDNEY DAMAGE (TO BE USED AS EXTRA CRITERIA FOR FINDING CKD STAGE 1 AND 2)

IF OBJECT_ID('tempdb..#kidney_damage') IS NOT NULL DROP TABLE #kidney_damage;
SELECT DISTINCT FK_Patient_Link_ID
INTO #kidney_damage
FROM [RLS].[vw_GP_Events] gp
WHERE  gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #egfr_ckd_evidence)
AND (
	gp.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('glomerulonephritis', 'kidney-transplant', 'kidney-stones', 'vasculitis') AND [Version]=1) OR
    gp.FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('glomerulonephritis', 'kidney-transplant', 'kidney-stones', 'vasculitis') AND [Version]=1)
	)
	AND EventDate <= @StartDate


-- FIND PATIENTS THAT MEET THE FOLLOWING: "ACR > 3mg/mmol lasting for at least 3 months”

-- FIND ACR TESTS THAT ARE >3mg/mmol AND SHOW DATE OF PREVIOUS TEST

IF OBJECT_ID('tempdb..#acr_dates') IS NOT NULL DROP TABLE #acr_dates;
SELECT *, 
	stage_previous_acr = LAG(acr_evidence, 1, NULL) OVER (PARTITION BY FK_Patient_Link_ID ORDER BY EventDate),
	date_previous_acr = LAG(EventDate, 1, NULL) OVER (PARTITION BY FK_Patient_Link_ID ORDER BY EventDate)
INTO #acr_dates
FROM #ckd_stages
WHERE acr_evidence in ('A3','A2')
ORDER BY FK_Patient_Link_ID, EventDate

IF OBJECT_ID('tempdb..#acr_ckd_evidence') IS NOT NULL DROP TABLE #acr_ckd_evidence;
SELECT *
INTO #acr_ckd_evidence
FROM #acr_dates
WHERE datediff(month, date_previous_acr, EventDate) >=  3 --only find patients with acr stages A1/A2 lasting at least 3 months

---- CREATE COHORT:
	-- 1. PATIENTS WITH EGFR TESTS INDICATIVE OF CKD STAGES 1-2, PLUS RAISED ACR OR HISTORY OF KIDNEY DAMAGE
	-- 2. PATIENTS WITH EGFR TESTS INDICATIVE OF CKD STAGES 3-5
	-- 3. PATIENTS WITH ACR TESTS INDICATIVE OF CKD (A3 AND A2)

IF OBJECT_ID('tempdb..#Cohort') IS NOT NULL DROP TABLE #Cohort;
SELECT p.FK_Patient_Link_ID,
		p.EthnicMainGroup,
		p.DeathDate,
		EvidenceOfCKD_egfr = CASE 
		WHEN p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #egfr_ckd_evidence where egfr_evidence in ('G3a', 'G3b', 'G4', 'G5')) -- egfr indicating stages 3-5
			OR (p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #egfr_ckd_evidence where egfr_evidence in ('G1', 'G2')) 
				AND ((p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #acr_dates)) 
					OR p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #kidney_damage))) 											THEN 1 ELSE 0 END,
		EvidenceOfCKD_acr = CASE WHEN p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #acr_ckd_evidence) 							THEN 1 ELSE 0 END
INTO #Cohort
FROM #Patients p
WHERE p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #egfr_ckd_evidence where egfr_evidence in ('G3a', 'G3b', 'G4', 'G5')) -- egfr indicating stages 3-5
	OR (
		p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #egfr_ckd_evidence where egfr_evidence in ('G1', 'G2')) 
			AND ((p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #acr_dates)) OR p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #kidney_damage))
		) -- egfr stages 1-2 and (ACR evidence or kidney damage) 
	OR p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #acr_ckd_evidence) -- ACR evidence

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

---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------

-- FIND WHICH PATIENTS IN THE COHORT HAD HYPERTENSION OR DIABETES AND THE DATE OF EARLIEST DIAGNOSIS

IF OBJECT_ID('tempdb..#hypertension') IS NOT NULL DROP TABLE #hypertension;
SELECT FK_Patient_Link_ID, MIN(EventDate) as EarliestDiagnosis
INTO #hypertension
FROM [RLS].[vw_GP_Events] gp
WHERE  gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort)
AND (
	gp.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'hypertension' AND [Version]=1) OR
    gp.FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'hypertension' AND [Version]=1)
	)
GROUP BY FK_Patient_Link_ID

IF OBJECT_ID('tempdb..#diabetes') IS NOT NULL DROP TABLE #diabetes;
SELECT FK_Patient_Link_ID, MIN(EventDate) as EarliestDiagnosis
INTO #diabetes
FROM [RLS].[vw_GP_Events] gp
WHERE  gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort)
AND (
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



-- FIND NUMBER OF ATTENDED GP APPOINTMENTS FROM MARCH 2018 TO MARCH 2022

IF OBJECT_ID('tempdb..#gp_appointments') IS NOT NULL DROP TABLE #gp_appointments;
SELECT G.FK_Patient_Link_ID, 
	G.AppointmentDate, 
	BeforeOrAfter1stMarch2020 = CASE WHEN G.AppointmentDate < '2020-03-01' THEN 'BEFORE' ELSE 'AFTER' END
INTO #gp_appointments
FROM RLS.vw_GP_Appointments G
WHERE AppointmentCancelledDate IS NULL 
AND AppointmentDate BETWEEN '2018-03-01' AND '2022-03-01'
AND G.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort) 

SELECT FK_Patient_Link_ID, BeforeOrAfter1stMarch2020, COUNT(*) as gp_appointments
INTO #count_gp_appointments
FROM #gp_appointments
GROUP BY FK_Patient_Link_ID, BeforeOrAfter1stMarch2020
ORDER BY FK_Patient_Link_ID, BeforeOrAfter1stMarch2020

-- FIND NUMBER OF A&E APPOINTMENTS FROM MARCH 2018 TO MARCH 2022

IF OBJECT_ID('tempdb..#ae_encounters') IS NOT NULL DROP TABLE #ae_encounters;
SELECT a.FK_Patient_Link_ID, 
	a.AttendanceDate, 
	BeforeOrAfter1stMarch2020 = CASE WHEN a.AttendanceDate < '2020-03-01' THEN 'BEFORE' ELSE 'AFTER' END
INTO #ae_encounters
FROM RLS.vw_Acute_AE a
WHERE EventType = 'Attendance'
AND a.AttendanceDate BETWEEN '2018-03-01' AND '2022-03-01'
AND a.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort) 

SELECT FK_Patient_Link_ID, BeforeOrAfter1stMarch2020, COUNT(*) AS ae_encounters
INTO #count_ae_encounters
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
--> EXECUTE query-patient-year-of-birth.sql
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
		DeathDueToCovid_Year = CASE WHEN cd.FK_Patient_Link_ID IS NOT NULL THEN YEAR(p.DeathDate) ELSE null END,
		DeathDueToCovid_Month = CASE WHEN cd.FK_Patient_Link_ID IS NOT NULL THEN MONTH(p.DeathDate) ELSE null END,
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
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientIMDDecile imd ON imd.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientBMI bmi ON bmi.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSmokingStatus smok ON smok.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientAlcoholIntake alc ON alc.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientPracticeAndCCG prac ON prac.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #GPExitDates gpex ON gpex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDVaccinations vac ON vac.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDDeath cd ON cd.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #count_ae_encounters ae_b ON ae_b.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND ae_b.BeforeOrAfter1stMarch2020 = 'BEFORE'
LEFT OUTER JOIN #count_ae_encounters ae_a ON ae_a.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND ae_a.BeforeOrAfter1stMarch2020 = 'AFTER'
LEFT OUTER JOIN #count_gp_appointments gp_b ON gp_b.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND gp_b.BeforeOrAfter1stMarch2020 = 'BEFORE'
LEFT OUTER JOIN #count_gp_appointments gp_a ON gp_a.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND gp_a.BeforeOrAfter1stMarch2020 = 'AFTER'
LEFT OUTER JOIN #hypertension hyp ON hyp.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #diabetes dia ON dia.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #CovidPatientsMultipleDiagnoses cv ON cv.FK_Patient_Link_ID = P.FK_Patient_Link_ID

WHERE YEAR(@StartDate) - YearOfBirth > 18 -- OVER 18s ONLY
--320,594