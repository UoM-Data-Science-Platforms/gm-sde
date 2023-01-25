--┌──────────────────────────────────────────────┐
--│ Patients with multimorbidity and covid	     │
--└──────────────────────────────────────────────┘

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

-- Set the date variables for the LTC code

DECLARE @IndexDate datetime;
DECLARE @MinDate datetime;
SET @IndexDate = '2022-05-01';
SET @MinDate = '1900-01-01';

--> EXECUTE query-patient-ltcs-date-range.sql 
--> EXECUTE query-patient-ltcs-number-of.sql

-- FIND ALL PATIENTS WITH A MENTAL CONDITION

IF OBJECT_ID('tempdb..#PatientsWithMentalCondition') IS NOT NULL DROP TABLE #PatientsWithMentalCondition;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #PatientsWithMentalCondition
FROM #PatientsWithLTCs
WHERE LTC IN ('Anorexia Or Bulimia', 'Anxiety And Other Somatoform Disorders', 'Dementia', 'Depression', 'Schizophrenia Or Bipolar')
	AND FirstDate < '2020-03-01'
--872,174

-- FIND ALL PATIENTS WITH 2 OR MORE CONDITIONS, INCLUDING A MENTAL CONDITION

IF OBJECT_ID('tempdb..#2orMoreLTCsIncludingMental') IS NOT NULL DROP TABLE #2orMoreLTCsIncludingMental;
SELECT DISTINCT FK_Patient_Link_ID
INTO #2orMoreLTCsIncludingMental
FROM #NumLTCs 
WHERE NumberOfLTCs = 2
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsWithMentalCondition)
--677,226


--> EXECUTE query-patient-year-of-birth.sql
--> EXECUTE query-patients-with-covid.sql start-date:2020-01-01 gp-events-table:RLS.vw_GP_Events all-patients:false

------------------------------------ CREATE COHORT -------------------------------------
	-- REGISTERED WITH A GM GP
	-- OVER  18
	-- HAD A COVID19 INFECTION
	-- 2 OR MORE LTCs INCLUDING ONE MENTAL CONDITION (diagnosed before March 2020)

IF OBJECT_ID('tempdb..#Cohort') IS NOT NULL DROP TABLE #Cohort;
SELECT p.FK_Patient_Link_ID, 
	EthnicMainGroup,
	DeathDate,
	yob.YearOfBirth
INTO #Cohort
FROM #Patients p
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE YEAR(@StartDate) - YearOfBirth >= 19 														 -- Over 18
	AND p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #CovidPatientsMultipleDiagnoses) -- had at least one covid19 infection
	AND p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #2orMoreLTCsIncludingMental)     -- at least 2 LTCs including one mental

-- Get patient list of those with COVID death within 28 days of positive test
IF OBJECT_ID('tempdb..#COVIDDeath') IS NOT NULL DROP TABLE #COVIDDeath;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #COVIDDeath FROM RLS.vw_COVID19
WHERE EventDate <= @EndDate
AND (DeathWithin28Days = 'Y' 
		OR
	(GroupDescription = 'Confirmed' AND SubGroupDescription != 'Negative'
		AND DeathDate <= DATEADD(DD,28,EventDate))
)

-- TABLE OF GP EVENTS FOR COHORT TO SPEED UP REUSABLE QUERIES

IF OBJECT_ID('tempdb..#PatientEventData') IS NOT NULL DROP TABLE #PatientEventData;
SELECT 
  FK_Patient_Link_ID,
  CAST(EventDate AS DATE) AS EventDate,
  SuppliedCode,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID,
  [Value],
  Units
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
	[Value] = TRY_CONVERT(NUMERIC (18,5), [Value]),
	Units
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
	FK_Patient_Link_ID, CAST(EventDate AS DATE) EventDate, Concept, [Value], Units
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
	Units,
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
	,SystolicBP_1_unit = MAX(CASE WHEN [Concept] = 'systolic-blood-pressure' AND BeforeOrAfterCovid = 'before' THEN Units ELSE NULL END)
	,SystolicBP_2 = MAX(CASE WHEN [Concept] = 'systolic-blood-pressure' AND BeforeOrAfterCovid = 'after' THEN [Value] ELSE NULL END)
	,SystolicBP_2_dt = MAX(CASE WHEN [Concept] = 'systolic-blood-pressure' AND BeforeOrAfterCovid = 'after' THEN EventDate ELSE NULL END)
	,SystolicBP_2_unit = MAX(CASE WHEN [Concept] = 'systolic-blood-pressure' AND BeforeOrAfterCovid = 'after' THEN Units ELSE NULL END)
	,diastolicBP_1 = MAX(CASE WHEN [Concept] = 'diastolic-blood-pressure' AND BeforeOrAfterCovid = 'before' THEN [Value] ELSE NULL END)
	,diastolicBP_1_dt = MAX(CASE WHEN [Concept] = 'diastolic-blood-pressure' AND BeforeOrAfterCovid = 'before' THEN EventDate ELSE NULL END)
	,diastolicBP_1_unit = MAX(CASE WHEN [Concept] = 'diastolic-blood-pressure' AND BeforeOrAfterCovid = 'before' THEN Units ELSE NULL END)
	,diastolicBP_2 = MAX(CASE WHEN [Concept] = 'diastolic-blood-pressure' AND BeforeOrAfterCovid = 'after' THEN [Value] ELSE NULL END)
	,diastolicBP_2_dt = MAX(CASE WHEN [Concept] = 'diastolic-blood-pressure' AND BeforeOrAfterCovid = 'after' THEN EventDate ELSE NULL END)
	,diastolicBP_2_unit = MAX(CASE WHEN [Concept] = 'diastolic-blood-pressure' AND BeforeOrAfterCovid = 'after' THEN Units ELSE NULL END)
	,cholesterol_1 = MAX(CASE WHEN [Concept] = 'cholesterol' AND BeforeOrAfterCovid = 'before' THEN [Value] ELSE NULL END)
	,cholesterol_1_dt = MAX(CASE WHEN [Concept] = 'cholesterol' AND BeforeOrAfterCovid = 'before' THEN EventDate ELSE NULL END)
	,cholesterol_1_unit = MAX(CASE WHEN [Concept] = 'cholesterol' AND BeforeOrAfterCovid = 'before' THEN Units ELSE NULL END)
	,cholesterol_2 = MAX(CASE WHEN [Concept] = 'cholesterol' AND BeforeOrAfterCovid = 'after' THEN [Value] ELSE NULL END)
	,cholesterol_2_dt = MAX(CASE WHEN [Concept] = 'cholesterol' AND BeforeOrAfterCovid = 'after' THEN EventDate ELSE NULL END)
	,cholesterol_2_unit = MAX(CASE WHEN [Concept] = 'cholesterol' AND BeforeOrAfterCovid = 'after' THEN Units ELSE NULL END)
	,HDLcholesterol_1 = MAX(CASE WHEN [Concept] = 'hdl-cholesterol' AND BeforeOrAfterCovid = 'before' THEN [Value] ELSE NULL END)
	,HDLcholesterol_1_dt = MAX(CASE WHEN [Concept] = 'hdl-cholesterol' AND BeforeOrAfterCovid = 'before' THEN EventDate ELSE NULL END)
	,HDLcholesterol_1_unit = MAX(CASE WHEN [Concept] = 'hdl-cholesterol' AND BeforeOrAfterCovid = 'before' THEN Units ELSE NULL END)
	,HDLcholesterol_2 = MAX(CASE WHEN [Concept] = 'hdl-cholesterol' AND BeforeOrAfterCovid = 'after' THEN [Value] ELSE NULL END)
	,HDLcholesterol_2_dt = MAX(CASE WHEN [Concept] = 'hdl-cholesterol' AND BeforeOrAfterCovid = 'after' THEN EventDate ELSE NULL END)
	,HDLcholesterol_2_unit = MAX(CASE WHEN [Concept] = 'hdl-cholesterol' AND BeforeOrAfterCovid = 'after' THEN Units ELSE NULL END)
	,LDL_cholesterol_1 = MAX(CASE WHEN [Concept] = 'ldl-cholesterol' AND BeforeOrAfterCovid = 'before' THEN [Value] ELSE NULL END)
	,LDL_cholesterol_1_dt = MAX(CASE WHEN [Concept] = 'ldl-cholesterol' AND BeforeOrAfterCovid = 'before' THEN EventDate ELSE NULL END)
	,LDL_cholesterol_1_unit = MAX(CASE WHEN [Concept] = 'ldl-cholesterol' AND BeforeOrAfterCovid = 'before' THEN Units ELSE NULL END)
	,LDL_cholesterol_2 = MAX(CASE WHEN [Concept] = 'ldl-cholesterol' AND BeforeOrAfterCovid = 'after' THEN [Value] ELSE NULL END)
	,LDL_cholesterol_2_dt = MAX(CASE WHEN [Concept] = 'ldl-cholesterol' AND BeforeOrAfterCovid = 'after' THEN EventDate ELSE NULL END)
	,LDL_cholesterol_2_unit = MAX(CASE WHEN [Concept] = 'ldl-cholesterol' AND BeforeOrAfterCovid = 'after' THEN Units ELSE NULL END)
	,Triglyceride_1 = MAX(CASE WHEN [Concept] = 'triglycerides' AND BeforeOrAfterCovid = 'before' THEN [Value] ELSE NULL END)
	,Triglyceride_1_dt = MAX(CASE WHEN [Concept] = 'triglycerides' AND BeforeOrAfterCovid = 'before' THEN EventDate ELSE NULL END)
	,Triglyceride_1_unit = MAX(CASE WHEN [Concept] = 'triglycerides' AND BeforeOrAfterCovid = 'before' THEN Units ELSE NULL END)
	,Triglyceride_2 = MAX(CASE WHEN [Concept] = 'triglycerides' AND BeforeOrAfterCovid = 'after' THEN [Value] ELSE NULL END)
	,Triglyceride_2_dt = MAX(CASE WHEN [Concept] = 'triglycerides' AND BeforeOrAfterCovid = 'after' THEN EventDate ELSE NULL END)
	,Triglyceride_2_unit = MAX(CASE WHEN [Concept] = 'triglycerides' AND BeforeOrAfterCovid = 'after' THEN Units ELSE NULL END)
	,egfr_1 = MAX(CASE WHEN [Concept] = 'egfr' AND BeforeOrAfterCovid = 'before' THEN [Value] ELSE NULL END)
	,egfr_1_dt = MAX(CASE WHEN [Concept] = 'egfr' AND BeforeOrAfterCovid = 'before' THEN EventDate ELSE NULL END)
	,egfr_1_unit = MAX(CASE WHEN [Concept] = 'egfr' AND BeforeOrAfterCovid = 'before' THEN Units ELSE NULL END)
	,egfr_2 = MAX(CASE WHEN [Concept] = 'egfr' AND BeforeOrAfterCovid = 'after' THEN [Value] ELSE NULL END)
	,egfr_2_dt = MAX(CASE WHEN [Concept] = 'egfr' AND BeforeOrAfterCovid = 'after' THEN EventDate ELSE NULL END)
	,egfr_2_unit = MAX(CASE WHEN [Concept] = 'egfr' AND BeforeOrAfterCovid = 'after' THEN Units ELSE NULL END)
	,hba1c_1 = MAX(CASE WHEN [Concept] = 'hba1c' AND BeforeOrAfterCovid = 'before' THEN [Value] ELSE NULL END)
	,hba1c_1_dt = MAX(CASE WHEN [Concept] = 'hba1c' AND BeforeOrAfterCovid = 'before' THEN EventDate ELSE NULL END)
	,hba1c_1_unit = MAX(CASE WHEN [Concept] = 'hba1c' AND BeforeOrAfterCovid = 'before' THEN Units ELSE NULL END)
	,hba1c_2 = MAX(CASE WHEN [Concept] = 'hba1c' AND BeforeOrAfterCovid = 'after' THEN [Value] ELSE NULL END)
	,hba1c_2_dt = MAX(CASE WHEN [Concept] = 'hba1c' AND BeforeOrAfterCovid = 'after' THEN EventDate ELSE NULL END)
	,hba1c_2_unit = MAX(CASE WHEN [Concept] = 'hba1c' AND BeforeOrAfterCovid = 'after' THEN Units ELSE NULL END)
INTO #observations_wide
FROM #closest_observations
WHERE ROW_NUM = 1
GROUP BY FK_Patient_Link_ID
-- BRING TOGETHER FOR FINAL DATA EXTRACT

SELECT  
	PatientId = p.FK_Patient_Link_ID
	,SystolicBP_1
	,SystolicBP_1_dt 
	,SystolicBP_1_unit
	,SystolicBP_2
	,SystolicBP_2_dt 
	,SystolicBP_2_unit
	,diastolicBP_1
	,diastolicBP_1_dt
	,diastolicBP_1_unit
	,diastolicBP_2
	,diastolicBP_2_dt
	,diastolicBP_2_unit
	,cholesterol_1
	,cholesterol_1_dt
	,cholesterol_1_unit
	,cholesterol_2
	,cholesterol_2_dt
	,cholesterol_2_unit
	,HDLcholesterol_1
	,HDLcholesterol_1_dt 
	,HDLcholesterol_1_unit
	,HDLcholesterol_2
	,HDLcholesterol_2_dt 
	,HDLcholesterol_2_unit
	,LDL_cholesterol_1
	,LDL_cholesterol_1_dt
	,LDL_cholesterol_1_unit
	,LDL_cholesterol_2
	,LDL_cholesterol_2_dt
	,LDL_cholesterol_2_unit
	,Triglyceride_1
	,Triglyceride_1_dt
	,Triglyceride_1_unit
	,Triglyceride_2
	,Triglyceride_2_dt
	,Triglyceride_2_unit
	,egfr_1
	,egfr_1_dt 
	,egfr_1_unit
	,egfr_2
	,egfr_2_dt 
	,egfr_2_unit
	,hba1c_1
	,hba1c_1_dt
	,hba1c_1_unit
	,hba1c_2
	,hba1c_2_dt
	,hba1c_2_unit
FROM #Cohort p 
INNER JOIN #observations_wide obs on obs.FK_Patient_Link_ID = p.FK_Patient_Link_ID