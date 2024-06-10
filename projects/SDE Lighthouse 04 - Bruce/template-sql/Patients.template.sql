--┌────────────────────────────────────┐
--│ LH004 Patient file                 │
--└────────────────────────────────────┘

-- OUTPUT: Data with the following fields
-- 	- PatientId (int)
-- 

--Just want the output, not the messages
SET NOCOUNT ON;

DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2020-01-01'; 
SET @EndDate = '2023-10-31';

-- Set dates for BMI and blood tests
DECLARE @MinDate datetime;
SET @MinDate = '1900-01-01';
DECLARE @IndexDate datetime;
SET @IndexDate = '2023-10-31';

-- smoking, alcohol are based on most recent codes available

--> EXECUTE query-build-lh004-cohort.sql
--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-lsoa.sql
--> EXECUTE query-patient-imd.sql

-- CREATE COPY OF GP EVENTS TABLE, FILTERED TO COHORT FOR THIS STUDY

IF OBJECT_ID('tempdb..#GPEvents') IS NOT NULL DROP TABLE #GPEvents;
SELECT FK_Patient_Link_ID, EventDate, 
		FK_Reference_Coding_ID, FK_Reference_SnomedCT_ID, SuppliedCode,
		[Value],[Units]
INTO #GPEvents
FROM SharedCare.GP_Events gp
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort)

--> EXECUTE query-patient-bmi.sql gp-events-table:#GPEvents
--> EXECUTE query-patient-alcohol-intake.sql gp-events-table:#GPEvents
--> EXECUTE query-patient-smoking-status.sql gp-events-table:#GPEvents
--> CODESET chronic-kidney-disease:1 ckd-stage-1:1 ckd-stage-2:1 ckd-stage-3:1 ckd-stage-4:1 ckd-stage-5:1
--> CODESET creatinine:1 egfr:1

---------- GET DATE OF FIRST SLE DIAGNOSIS --------------
IF OBJECT_ID('tempdb..#SLEFirstDiagnosis') IS NOT NULL DROP TABLE #SLEFirstDiagnosis;
SELECT FK_Patient_Link_ID, 
	   SLEFirstDiagnosisDate = MIN(CONVERT(DATE,EventDate))
INTO #SLEFirstDiagnosis
FROM #SLECodes
GROUP BY FK_Patient_Link_ID

---------- GET CKD STAGE FOR EACH PATIENT ---------------

-- get all codes for CKD
IF OBJECT_ID('tempdb..#ckd') IS NOT NULL DROP TABLE #ckd;
SELECT 
	gp.FK_Patient_Link_ID,
	EventDate = CONVERT(DATE, gp.EventDate),
	a.Concept
INTO #ckd
FROM #GPEvents gp
INNER JOIN #AllCodes a ON a.Code = gp.SuppliedCode
WHERE Concept IN 
	('chronic-kidney-disease', 'ckd-stage-1', 'ckd-stage-2', 'ckd-stage-3', 'ckd-stage-4', 'ckd-stage-5')

IF OBJECT_ID('tempdb..#ckd_stages') IS NOT NULL DROP TABLE #ckd_stages;
SELECT FK_Patient_Link_ID,
		CKDStage = CASE WHEN concept = 'ckd-stage-1' then 1
			WHEN concept = 'ckd-stage-2' then 2
			WHEN concept = 'ckd-stage-3' then 3
			WHEN concept = 'ckd-stage-4' then 4
			WHEN concept = 'ckd-stage-5' then 5
				ELSE 0 END
INTO #ckd_stages
FROM #ckd

IF OBJECT_ID('tempdb..#CKDStage') IS NOT NULL DROP TABLE #CKDStage;
SELECT FK_Patient_Link_ID, 
		CKDStageMax = MAX(CKDStage)
INTO #CKDStage
FROM #ckd_stages
GROUP BY FK_Patient_Link_ID

----------- GET MOST RECENT TEST RESULTS FOR EACH PATIENT

--> EXECUTE query-get-closest-value-to-date.sql all-patients:#false date:2023-10-31 min-value:0 max-value:500 unit:% gp-events-table:#GPEvents code-set:egfr version:1 comparison:< temp-table-name:#egfr 
--> EXECUTE query-get-closest-value-to-date.sql all-patients:#false date:2023-10-31 min-value:0 max-value:500 unit:% gp-events-table:#GPEvents code-set:creatinine version:1 comparison:< temp-table-name:#creatinine 
--> EXECUTE query-get-closest-value-to-date.sql all-patients:#false date:2023-10-31 min-value:0 max-value:500 unit:% gp-events-table:#GPEvents code-set:hdl-cholesterol version:1 comparison:< temp-table-name:#hdl_cholesterol 
--> EXECUTE query-get-closest-value-to-date.sql all-patients:#false date:2023-10-31 min-value:0 max-value:500 unit:% gp-events-table:#GPEvents code-set:ldl-cholesterol version:1 comparison:< temp-table-name:#ldl_cholesterol 
--> EXECUTE query-get-closest-value-to-date.sql all-patients:#false date:2023-10-31 min-value:0 max-value:500 unit:% gp-events-table:#GPEvents code-set:triglycerides version:1 comparison:< temp-table-name:#triglycerides 

--bring together for final output
SELECT	 PatientId = m.FK_Patient_Link_ID
		,m.YearOfBirth
		,sex.Sex
		,lsoa.LSOA_Code
		,m.EthnicGroupDescription
		,imd.IMD2019Decile1IsMostDeprived10IsLeastDeprived
		,smok.WorstSmokingStatus
		,smok.CurrentSmokingStatus
		,bmi.BMI
		,bmi.DateOfBMIMeasurement
		,alc.WorstAlcoholIntake
		,alc.CurrentAlcoholIntake
		,sle.SLEFirstDiagnosisDate
		,CKDStage = ckd.CKDStageMax
		,Egfr = egf.[Value]
		,Egfr_dt = egf.DateOfFirstValue
		,Creatinine = cre.[Value]
		,Creatinine_dt = cre.DateOfFirstValue
		,HDL_Cholesterol = hdl.[Value]
		,HDL_dt = hdl.DateOfFirstValue
		,LDL_Cholesterol = ldl.[Value]
		,LDL_dt = ldl.DateOfFirstValue
		,Triglycerides = tri.[Value]
		,Triglycerides_dt = tri.DateOfFirstValue
FROM #Cohort m
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientLSOA lsoa ON lsoa.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientIMDDecile imd ON imd.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSmokingStatus smok ON smok.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientBMI bmi ON bmi.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientAlcoholIntake alc ON alc.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #SLEFirstDiagnosis sle ON sle.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #CKDStage ckd ON ckd.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #egfr egf ON egf.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #creatinine cre ON cre.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #hdl_cholesterol hdl ON hdl.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #ldl_cholesterol ldl ON ldl.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #triglycerides tri ON tri.FK_Patient_Link_ID = m.FK_Patient_Link_ID



