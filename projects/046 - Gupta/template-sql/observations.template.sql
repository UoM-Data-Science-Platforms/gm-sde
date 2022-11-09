--┌──────────────────────────────┐
--│ Patients with diabetes 	     │
--└──────────────────────────────┘

---- RESEARCH DATA ENGINEER CHECK ----
-- 1st July 2022 - Richard Williams --
--------------------------------------	

-- OUTPUT: Data with the following fields


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
FROM [RLS].[vw_GP_Events]
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
FROM [RLS].[vw_GP_Events]
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
	AND p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude) 			 -- exclude new patients processed post-COPI notice


----------------------------------------------------------------------------------------

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
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort)
	AND EventDate < '2022-06-01';

------------------------------- OBSERVATIONS -------------------------------------

--> CODESET systolic-blood-pressure:1 diastolic-blood-pressure:1 hba1c:2
--> CODESET cholesterol:2 ldl-cholesterol:1 hdl-cholesterol:1 triglycerides:1 egfr:1

-- CREATE TABLE OF OBSERVATIONS REQUESTED BY THE PI

IF OBJECT_ID('tempdb..#observations') IS NOT NULL DROP TABLE #observations;
SELECT 
	FK_Patient_Link_ID,
	CAST(EventDate AS DATE) AS EventDate,
	Concept = CASE WHEN sn.Concept IS NOT NULL THEN sn.Concept ELSE co.Concept END,
	[Version] =  CASE WHEN sn.[Version] IS NOT NULL THEN sn.[Version] ELSE co.[Version] END,
	[Value] = TRY_CONVERT(NUMERIC (18,5), [Value])
INTO #observations
FROM #PatientEventData gp
LEFT JOIN #VersionedSnomedSets sn ON sn.FK_Reference_SnomedCT_ID = gp.FK_Reference_SnomedCT_ID
LEFT JOIN #VersionedCodeSets co ON co.FK_Reference_Coding_ID = gp.FK_Reference_Coding_ID
WHERE
	((gp.FK_Reference_SnomedCT_ID IN (
		SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets sn WHERE sn.Concept In ('systolic-blood-pressure', 'diastolic-blood-pressure', 'ldl-cholesterol', 'hdl-cholesterol', 'triglycerides', 'egfr') AND [Version] = 1) 
			OR sn.Concept IN ('hba1c', 'cholesterol') AND sn.[Version] = 2 )
		OR (gp.FK_Reference_Coding_ID   IN (
		SELECT FK_Reference_Coding_ID   FROM #VersionedCodeSets co WHERE co.Concept In ('systolic-blood-pressure', 'diastolic-blood-pressure', 'ldl-cholesterol', 'hdl-cholesterol', 'triglycerides', 'egfr') AND [Version] = 1) 
			OR co.Concept IN ('hba1c', 'cholesterol') AND co.[Version] = 2 ))
	AND [Value] IS NOT NULL AND [Value] != '0' AND UPPER([Value]) NOT LIKE '%[A-Z]%'  -- CHECKS IN CASE ANY ZERO, NULL OR TEXT VALUES REMAINED

-- WHERE CODES EXIST IN BOTH VERSIONS OF THE CODE SET (OR IN OTHER SIMILAR CODE SETS), THERE WILL BE DUPLICATES, SO EXCLUDE THEM FROM THE SETS/VERSIONS THAT WE DON'T WANT 

IF OBJECT_ID('tempdb..#all_observations') IS NOT NULL DROP TABLE #all_observations;
select 
	FK_Patient_Link_ID, CAST(EventDate AS DATE) EventDate, Concept, [Value]
into #all_observations
from #observations
WHERE 
	((Concept in ('systolic-blood-pressure', 'diastolic-blood-pressure', 'ldl-cholesterol', 'hdl-cholesterol', 'triglycerides', 'egfr') AND [Version] = 1) OR
	(Concept IN ('cholesterol', 'hba1c') AND [Version] = 2)) -- e.g. hba1c level appears twice with same value: from version 1 and version 2. We only want version 2 so exclude any others.
	AND [Value] > 0 AND [Value] <> '0.00000' 


-- FIND CLOSEST OBSERVATIONS BEFORE AND AFTER PANDEMIC STARTED

IF OBJECT_ID('tempdb..#most_recent_date_before_covid') IS NOT NULL DROP TABLE #most_recent_date_before_covid;
SELECT o.FK_Patient_Link_ID, Concept, MAX(EventDate) as MostRecentDate
INTO #most_recent_date_before_covid
FROM #all_observations o
WHERE EventDate < '2020-03-01'
GROUP BY o.FK_Patient_Link_ID, Concept

IF OBJECT_ID('tempdb..#most_recent_date_after_covid') IS NOT NULL DROP TABLE #most_recent_date_after_covid;
SELECT o.FK_Patient_Link_ID, Concept, MIN(EventDate) as MostRecentDate
INTO #most_recent_date_after_covid
FROM #all_observations o
WHERE EventDate >= '2020-03-01'
GROUP BY o.FK_Patient_Link_ID, Concept

IF OBJECT_ID('tempdb..#closest_observations') IS NOT NULL DROP TABLE #closest_observations;
SELECT o.FK_Patient_Link_ID, 
	o.EventDate, 
	o.Concept, 
	o.[Value],
	BeforeOrAfterCovid = CASE WHEN bef.MostRecentDate = o.EventDate THEN 'before' WHEN aft.MostRecentDate = o.EventDate THEN 'after' ELSE 'check' END,
	ROW_NUM = ROW_NUMBER () OVER (PARTITION BY o.FK_Patient_Link_ID, o.EventDate, o.Concept ORDER BY [Value] DESC) -- THIS WILL BE USED IN NEXT QUERY TO TAKE THE MAX VALUE WHERE THERE ARE MULTIPLE
INTO #closest_observations
FROM #all_observations o
LEFT JOIN #most_recent_date_before_covid bef ON bef.FK_Patient_Link_ID = o.FK_Patient_Link_ID AND bef.MostRecentDate = o.EventDate and bef.Concept = o.Concept
LEFT JOIN #most_recent_date_after_covid aft ON aft.FK_Patient_Link_ID = o.FK_Patient_Link_ID AND aft.MostRecentDate = o.EventDate and aft.Concept = o.Concept
WHERE bef.MostRecentDate = o.EventDate OR aft.MostRecentDate = o.EventDate

-- CREATE WIDE TABLE WITH CLOSEST OBSERVATIONS BEFORE AND AFTER COVID POSITIVE DATE

IF OBJECT_ID('tempdb..#observations_wide') IS NOT NULL DROP TABLE #observations_wide;
SELECT
	 FK_Patient_Link_ID
	,SystolicBP_1 = MAX(CASE WHEN [Concept] = 'systolic-blood-pressure' AND BeforeOrAfterCovid = 'before' THEN [Value] ELSE NULL END)
	,SystolicBP_1_dt = MAX(CASE WHEN [Concept] = 'systolic-blood-pressure' AND BeforeOrAfterCovid = 'before' THEN EventDate ELSE NULL END)
	,SystolicBP_2 = MAX(CASE WHEN [Concept] = 'systolic-blood-pressure' AND BeforeOrAfterCovid = 'after' THEN [Value] ELSE NULL END)
	,SystolicBP_2_dt = MAX(CASE WHEN [Concept] = 'systolic-blood-pressure' AND BeforeOrAfterCovid = 'after' THEN EventDate ELSE NULL END)
	,diastolicBP_1 = MAX(CASE WHEN [Concept] = 'diastolic-blood-pressure' AND BeforeOrAfterCovid = 'before' THEN [Value] ELSE NULL END)
	,diastolicBP_1_dt = MAX(CASE WHEN [Concept] = 'diastolic-blood-pressure' AND BeforeOrAfterCovid = 'before' THEN EventDate ELSE NULL END)
	,diastolicBP_2 = MAX(CASE WHEN [Concept] = 'diastolic-blood-pressure' AND BeforeOrAfterCovid = 'after' THEN [Value] ELSE NULL END)
	,diastolicBP_2_dt = MAX(CASE WHEN [Concept] = 'diastolic-blood-pressure' AND BeforeOrAfterCovid = 'after' THEN EventDate ELSE NULL END)
	,cholesterol_1 = MAX(CASE WHEN [Concept] = 'cholesterol' AND BeforeOrAfterCovid = 'before' THEN [Value] ELSE NULL END)
	,cholesterol_1_dt = MAX(CASE WHEN [Concept] = 'cholesterol' AND BeforeOrAfterCovid = 'before' THEN EventDate ELSE NULL END)
	,cholesterol_2 = MAX(CASE WHEN [Concept] = 'cholesterol' AND BeforeOrAfterCovid = 'after' THEN [Value] ELSE NULL END)
	,cholesterol_2_dt = MAX(CASE WHEN [Concept] = 'cholesterol' AND BeforeOrAfterCovid = 'after' THEN EventDate ELSE NULL END)
	,HDLcholesterol_1 = MAX(CASE WHEN [Concept] = 'hdl-cholesterol' AND BeforeOrAfterCovid = 'before' THEN [Value] ELSE NULL END)
	,HDLcholesterol_1_dt = MAX(CASE WHEN [Concept] = 'hdl-cholesterol' AND BeforeOrAfterCovid = 'before' THEN EventDate ELSE NULL END)
	,HDLcholesterol_2 = MAX(CASE WHEN [Concept] = 'hdl-cholesterol' AND BeforeOrAfterCovid = 'after' THEN [Value] ELSE NULL END)
	,HDLcholesterol_2_dt = MAX(CASE WHEN [Concept] = 'hdl-cholesterol' AND BeforeOrAfterCovid = 'after' THEN EventDate ELSE NULL END)
	,LDL_cholesterol_1 = MAX(CASE WHEN [Concept] = 'ldl-cholesterol' AND BeforeOrAfterCovid = 'before' THEN [Value] ELSE NULL END)
	,LDL_cholesterol_1_dt = MAX(CASE WHEN [Concept] = 'ldl-cholesterol' AND BeforeOrAfterCovid = 'before' THEN EventDate ELSE NULL END)
	,LDL_cholesterol_2 = MAX(CASE WHEN [Concept] = 'ldl-cholesterol' AND BeforeOrAfterCovid = 'after' THEN [Value] ELSE NULL END)
	,LDL_cholesterol_2_dt = MAX(CASE WHEN [Concept] = 'ldl-cholesterol' AND BeforeOrAfterCovid = 'after' THEN EventDate ELSE NULL END)
	,Triglyceride_1 = MAX(CASE WHEN [Concept] = 'triglycerides' AND BeforeOrAfterCovid = 'before' THEN [Value] ELSE NULL END)
	,Triglyceride_1_dt = MAX(CASE WHEN [Concept] = 'triglycerides' AND BeforeOrAfterCovid = 'before' THEN EventDate ELSE NULL END)
	,Triglyceride_2 = MAX(CASE WHEN [Concept] = 'triglycerides' AND BeforeOrAfterCovid = 'after' THEN [Value] ELSE NULL END)
	,Triglyceride_2_dt = MAX(CASE WHEN [Concept] = 'triglycerides' AND BeforeOrAfterCovid = 'after' THEN EventDate ELSE NULL END)
	,egfr_1 = MAX(CASE WHEN [Concept] = 'egfr' AND BeforeOrAfterCovid = 'before' THEN [Value] ELSE NULL END)
	,egfr_1_dt = MAX(CASE WHEN [Concept] = 'egfr' AND BeforeOrAfterCovid = 'before' THEN EventDate ELSE NULL END)
	,egfr_2 = MAX(CASE WHEN [Concept] = 'egfr' AND BeforeOrAfterCovid = 'after' THEN [Value] ELSE NULL END)
	,egfr_2_dt = MAX(CASE WHEN [Concept] = 'egfr' AND BeforeOrAfterCovid = 'after' THEN EventDate ELSE NULL END)
	,hba1c_1 = MAX(CASE WHEN [Concept] = 'hba1c' AND BeforeOrAfterCovid = 'before' THEN [Value] ELSE NULL END)
	,hba1c_1_dt = MAX(CASE WHEN [Concept] = 'hba1c' AND BeforeOrAfterCovid = 'before' THEN EventDate ELSE NULL END)
	,hba1c_2 = MAX(CASE WHEN [Concept] = 'hba1c' AND BeforeOrAfterCovid = 'after' THEN [Value] ELSE NULL END)
	,hba1c_2_dt = MAX(CASE WHEN [Concept] = 'hba1c' AND BeforeOrAfterCovid = 'after' THEN EventDate ELSE NULL END)
INTO #observations_wide
FROM #closest_observations
WHERE ROW_NUM = 1
GROUP BY FK_Patient_Link_ID

-- BRING TOGETHER FOR FINAL DATA EXTRACT

SELECT  
	PatientId = p.FK_Patient_Link_ID
	,SystolicBP_1
	,SystolicBP_1_dt 
	,SystolicBP_2
	,SystolicBP_2_dt 
	,diastolicBP_1
	,diastolicBP_1_dt
	,diastolicBP_2
	,diastolicBP_2_dt
	,cholesterol_1
	,cholesterol_1_dt
	,cholesterol_2
	,cholesterol_2_dt
	,HDLcholesterol_1
	,HDLcholesterol_1_dt 
	,HDLcholesterol_2
	,HDLcholesterol_2_dt 
	,LDL_cholesterol_1
	,LDL_cholesterol_1_dt
	,LDL_cholesterol_2
	,LDL_cholesterol_2_dt
	,Triglyceride_1
	,Triglyceride_1_dt
	,Triglyceride_2
	,Triglyceride_2_dt
	,egfr_1
	,egfr_1_dt 
	,egfr_2
	,egfr_2_dt 
	,hba1c_1
	,hba1c_1_dt
	,hba1c_2
	,hba1c_2_dt
FROM #Cohort p 
LEFT OUTER JOIN #observations_wide obs on obs.FK_Patient_Link_ID = p.FK_Patient_Link_ID