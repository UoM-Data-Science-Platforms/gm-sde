--┌──────────────────────────────┐
--│ Patients with diabetes 	     │
--└──────────────────────────────┘

---- RESEARCH DATA ENGINEER CHECK ----
-- 1st July 2022 - Richard Williams --
--------------------------------------	

DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2020-01-01';
SET @EndDate = '2022-05-01';

--Just want the output, not the messages
SET NOCOUNT ON;

--> EXECUTE query-get-possible-patients.sql

------------------------------------ CREATE COHORT -------------------------------------
	-- REGISTERED WITH A GM GP
	-- OVER  18
	-- DIABETES DIAGNOSIS

--> EXECUTE query-patient-year-of-birth.sql

--> CODESET diabetes-type-i:1 diabetes-type-ii:1

-- FIND ALL DIAGNOSES OF TYPE 1 DIABETES

IF OBJECT_ID('tempdb..#DiabetesT1Patients') IS NOT NULL DROP TABLE #DiabetesT1Patients;
SELECT 
	FK_Patient_Link_ID,
	SuppliedCode,
	CAST(EventDate AS DATE) AS EventDate
INTO #DiabetesT1Patients
FROM [SharedCare].[GP_Events]
WHERE (SuppliedCode IN (SELECT [Code] FROM #AllCodes WHERE [Concept] IN ('diabetes-type-i') AND [Version] = 1))
	AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
	AND EventDate <= @StartDate

-- FIND EARLIEST DIAGNOSIS OF TYPE 1 DIABETES FOR EACH PATIENT

IF OBJECT_ID('tempdb..#T1Min') IS NOT NULL DROP TABLE #T1Min;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS MinDate
INTO #T1Min
FROM #DiabetesT1Patients
GROUP BY FK_Patient_Link_ID

-- FIND ALL DIAGNOSES OF TYPE 2 DIABETES

IF OBJECT_ID('tempdb..#DiabetesT2Patients') IS NOT NULL DROP TABLE #DiabetesT2Patients;
SELECT 
	FK_Patient_Link_ID,
	SuppliedCode,
	CAST(EventDate AS DATE) AS EventDate
INTO #DiabetesT2Patients
FROM [SharedCare].[GP_Events]
WHERE (SuppliedCode IN (SELECT [Code] FROM #AllCodes WHERE [Concept] IN ('diabetes-type-ii') AND [Version] = 1))
	AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
	AND EventDate <= @StartDate

-- FIND EARLIEST DIAGNOSIS OF TYPE 2 DIABETES FOR EACH PATIENT

IF OBJECT_ID('tempdb..#T2Min') IS NOT NULL DROP TABLE #T2Min;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS MinDate
INTO #T2Min
FROM #DiabetesT2Patients
GROUP BY FK_Patient_Link_ID

-- CREATE COHORT OF DIABETES PATIENTS

IF OBJECT_ID('tempdb..#Cohort') IS NOT NULL DROP TABLE #Cohort;
SELECT p.FK_Patient_Link_ID, 
	EthnicMainGroup,
	DeathDate,
	yob.YearOfBirth,
	DiabetesT1 = CASE WHEN t1.FK_Patient_Link_ID IS NOT NULL THEN 1 ELSE 0 END,
	DiabetesT1_EarliestDiagnosis = CASE WHEN t1.FK_Patient_Link_ID IS NOT NULL THEN t1.MinDate ELSE NULL END,
	DiabetesT2 = CASE WHEN t2.FK_Patient_Link_ID IS NOT NULL THEN 1 ELSE 0 END,
	DiabetesT2_EarliestDiagnosis = CASE WHEN t2.FK_Patient_Link_ID IS NOT NULL THEN t2.MinDate ELSE NULL END
INTO #Cohort
FROM #Patients p
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #T1Min t1 ON t1.FK_Patient_Link_ID = p.FK_Patient_Link_ID 
LEFT OUTER JOIN #T2Min t2 ON t2.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE YEAR(@StartDate) - YearOfBirth >= 19 														 -- Over 18
	AND (
		p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #DiabetesT1Patients)  OR			 -- Diabetes T1 diagnosis
		p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #DiabetesT2Patients) 			     -- Diabetes T2 diagnosis
		)

----------------------------------------------------------------------------------------


--> EXECUTE query-patient-smoking-status.sql gp-events-table:SharedCare.GP_Events

-- BRING TOGETHER FOR FINAL DATA EXTRACT

SELECT  
	PatientId = p.FK_Patient_Link_ID, 
	p.YearOfBirth, 
	CurrentSmokingStatus = smok.CurrentSmokingStatus,
	WorstSmokingStatus = smok.WorstSmokingStatus
FROM #Cohort p 
LEFT OUTER JOIN #PatientSmokingStatus smok ON smok.FK_Patient_Link_ID = p.FK_Patient_Link_ID
