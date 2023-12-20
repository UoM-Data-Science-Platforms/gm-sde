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
--> EXECUTE query-patient-bmi.sql gp-events-table:SharedCare.GP_Events
--> EXECUTE query-patient-alcohol-intake.sql gp-events-table:SharedCare.GP_Events
--> EXECUTE query-patient-smoking-status.sql gp-events-table:SharedCare.GP_Events
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
	[concept] = CASE WHEN s.[concept] IS NOT NULL THEN s.[concept] ELSE c.[concept] END
INTO #ckd
FROM SharedCare.GP_Events gp
LEFT OUTER JOIN #VersionedSnomedSets s ON s.FK_Reference_SnomedCT_ID = gp.FK_Reference_SnomedCT_ID
LEFT OUTER JOIN #VersionedCodeSets c ON c.FK_Reference_Coding_ID = gp.FK_Reference_Coding_ID
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort) 
	AND (
		gp.FK_Reference_Coding_ID in (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept  IN ('chronic-kidney-disease', 'ckd-stage-1', 'ckd-stage-2', 'ckd-stage-3', 'ckd-stage-4', 'ckd-stage-5'))
		OR gp.FK_Reference_SnomedCT_ID in (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept  IN ('chronic-kidney-disease', 'ckd-stage-1', 'ckd-stage-2', 'ckd-stage-3', 'ckd-stage-4', 'ckd-stage-5'))
	)

SELECT FK_Patient_Link_ID,
		CKDStage = CASE WHEN concept = 'ckd-stage-1' then 1
			WHEN concept = 'ckd-stage-2' then 2
			WHEN concept = 'ckd-stage-3' then 3
			WHEN concept = 'ckd-stage-4' then 4
			WHEN concept = 'ckd-stage-5' then 5
				ELSE 0 END
INTO #ckd_stages
FROM #ckd

SELECT FK_Patient_Link_ID, 
		CKDStageMax = MAX(CKDStage)
INTO #CKDStage
FROM #ckd_stages
GROUP BY FK_Patient_Link_ID

----------- GET MOST RECENT EGFR AND CREATININE MEASUREMENT FOR EACH PATIENT

-- GET VALUES FOR OBSERVATIONS OF INTEREST

IF OBJECT_ID('tempdb..#egfr_creat') IS NOT NULL DROP TABLE #egfr_creat;
SELECT 
	FK_Patient_Link_ID,
	CAST(EventDate AS DATE) AS EventDate,
	Concept = CASE WHEN sn.Concept IS NOT NULL THEN sn.Concept ELSE co.Concept END,
	[Version] =  CASE WHEN sn.[Version] IS NOT NULL THEN sn.[Version] ELSE co.[Version] END,
	[Value],
	[Units]
INTO #egfr_creat
FROM SharedCare.GP_Events gp
LEFT JOIN #VersionedSnomedSets sn ON sn.FK_Reference_SnomedCT_ID = gp.FK_Reference_SnomedCT_ID
LEFT JOIN #VersionedCodeSets co ON co.FK_Reference_Coding_ID = gp.FK_Reference_Coding_ID
WHERE
	(
	 gp.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('egfr', 'creatinine')) ) OR
     gp.FK_Reference_Coding_ID   IN (SELECT FK_Reference_Coding_ID   FROM #VersionedCodeSets WHERE (Concept IN ('egfr', 'creatinine'))  ) 
	 )
AND gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort)
AND EventDate BETWEEN @MinDate and @IndexDate
AND Value <> ''

-- For Egfr and Creatinine we want closest prior to index date
IF OBJECT_ID('tempdb..#TempCurrentEgfr') IS NOT NULL DROP TABLE #TempCurrentEgfr;
SELECT 
	a.FK_Patient_Link_ID, 
	a.Concept,
	Max([Value]) as [Value],
	Max(EventDate) as EventDate
INTO #TempCurrentEgfr
FROM #egfr_creat a
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(EventDate) AS MostRecentDate 
	FROM #egfr_creat
	WHERE Concept = 'egfr'
	GROUP BY FK_Patient_Link_ID
) sub ON sub.MostRecentDate = a.EventDate and sub.FK_Patient_Link_ID = a.FK_Patient_Link_ID
GROUP BY a.FK_Patient_Link_ID, a.Concept;

IF OBJECT_ID('tempdb..#TempCurrentCreatinine') IS NOT NULL DROP TABLE #TempCurrentCreatinine;
SELECT 
	a.FK_Patient_Link_ID, 
	a.Concept,
	Max([Value]) as [Value],
	Max(EventDate) as EventDate
INTO #TempCurrentCreatinine
FROM #egfr_creat a
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(EventDate) AS MostRecentDate 
	FROM #egfr_creat
	WHERE Concept = 'creatinine'
	GROUP BY FK_Patient_Link_ID
) sub ON sub.MostRecentDate = a.EventDate and sub.FK_Patient_Link_ID = a.FK_Patient_Link_ID
GROUP BY a.FK_Patient_Link_ID, a.Concept;

-- bring together in a table that can be joined to
IF OBJECT_ID('tempdb..#PatientEgfrCreatinine') IS NOT NULL DROP TABLE #PatientEgfrCreatinine;
SELECT 
	p.FK_Patient_Link_ID,
	Egfr = MAX(CASE WHEN e.Concept = 'Egfr' THEN TRY_CONVERT(NUMERIC(16,5), e.[Value]) ELSE NULL END),
	Egfr_dt = MAX(CASE WHEN e.Concept = 'Egfr' THEN e.EventDate ELSE NULL END),
	Creatinine = MAX(CASE WHEN c.Concept = 'Creatinine' THEN TRY_CONVERT(NUMERIC(16,5), c.[Value]) ELSE NULL END),
	Creatinine_dt = MAX(CASE WHEN c.Concept = 'Creatinine' THEN c.EventDate ELSE NULL END)
INTO #PatientEgfrCreatinine
FROM #Cohort p
LEFT OUTER JOIN #TempCurrentEgfr e on e.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #TempCurrentCreatinine c on c.FK_Patient_Link_ID = p.FK_Patient_Link_ID
GROUP BY p.FK_Patient_Link_ID


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
		,Egfr
		,Egfr_dt
		,Creatinine
		,Creatinine_dt
FROM #Cohort m
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientLSOA lsoa ON lsoa.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientIMDDecile imd ON imd.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSmokingStatus smok ON smok.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientBMI bmi ON bmi.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientAlcoholIntake alc ON alc.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #SLEFirstDiagnosis sle ON sle.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #CKDStage ckd ON ckd.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientEgfrCreatinine ec ON ec.FK_Patient_Link_ID = m.FK_Patient_Link_ID



