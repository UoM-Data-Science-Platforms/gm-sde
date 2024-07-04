--┌────────────────────────────────────┐
--│ LH004 Patient file                 │
--└────────────────────────────────────┘

-- OUTPUT: Data with the following fields
--	PatientId, Sex, YearOfBirth, Ethnicity, IMDQuartile, SmokerEver, SmokerCurrent,
--	BMI, AlcoholIntake, DateOfSLEdiagnosis, DateOfLupusNephritisDiagnosis, CKDStage,
--	EgfrResult, EgfrDate, CreatinineResult, CreatinineDate, LDLCholesterol
--	LDLCholesterolDate, HDLCholesterol, HDLCholesterolDate, Triglycerides, TrigylceridesDate
-- 
--	All values need most recent value

-- smoking, alcohol are based on most recent codes available

--> EXECUTE query-build-lh004-cohort.sql

-- Get eGFRs
SELECT DISTINCT "GmPseudo", 
    last_value("eGFR") OVER (PARTITION BY "GmPseudo" ORDER BY "EventDate") AS "eGFRValue", 
    last_value("EventDate") OVER (PARTITION BY "GmPseudo" ORDER BY "EventDate") AS "eGFRDate"
FROM INTERMEDIATE.GP_RECORD."Readings_eGFR"
WHERE "GmPseudo" IN (1763539,2926922,182597,1244665,3134799,1544463,5678816,169030,7015182,7089792)
GROUP BY "GmPseudo";

-- Get creatinine
SELECT DISTINCT "GmPseudo", 
    last_value("SerumCreatinine") OVER (PARTITION BY "GmPseudo" ORDER BY "EventDate") AS "SerumCreatinineValue", 
    last_value("EventDate") OVER (PARTITION BY "GmPseudo" ORDER BY "EventDate") AS "SerumCreatinineDate"
FROM INTERMEDIATE.GP_RECORD."Readings_SerumCreatinine"
WHERE "GmPseudo" IN (1763539,2926922,182597,1244665,3134799,1544463,5678816,169030,7015182,7089792)
GROUP BY "GmPseudo";


SELECT 
	"GmPseudo" AS "PatientID",
	"Sex",
	YEAR("DateOfBirth") AS "YearOfBirth",
	"EthnicityLatest" AS "Ethnicity",
	"EthnicityLatest_Category" AS "EthnicityCategory",
	"IMD_Decile" AS "IMD2019Decile1IsMostDeprived10IsLeastDeprived",
	"SmokingStatus",
	"SmokingConsumption",
	"BMI",
	"BMI_Date" AS "BMIDate",
	"AlcoholStatus",
	"AlcoholConsumption",
TODO DateOfSLEdiagnosis, DateOfLupusNephritisDiagnosis, CKDStage,
	EgfrResult, EgfrDate, CreatinineResult, CreatinineDate, LDLCholesterol
	LDLCholesterolDate, HDLCholesterol, HDLCholesterolDate, Triglycerides, TrigylceridesDate
FROM PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses"
WHERE "GmPseudo" IN (1763539,2926922,182597,1244665,3134799,1544463,5678816,169030,7015182,7089792)
QUALIFY row_number() OVER (PARTITION BY "GmPseudo" ORDER BY "Snapshot" DESC) = 1 -- this brings back the values from the most recent snapshot


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



