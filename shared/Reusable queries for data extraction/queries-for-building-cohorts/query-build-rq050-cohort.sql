--┌──────────────────────────┐
--│ Define Cohort for RQ050  │
--└──────────────────────────┘

-- OBJECTIVE: To build the cohort of patients needed for RQ050. This reduces duplication of code in the template scripts.

-- COHORT: All patients that had a pregnancy related code in their GP record, or a maternity admission, between 2012 and 2022  

-- INPUT: assumes there exists one temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: Temp tables as follows:
-- #MainCohort
-- #MatchedCohort
-- #PatientEventData

------------------------------------------------------------------------------------------------------------------------------------------------------------

--> EXECUTE query-get-possible-patients.sql

--> CODESET pregnancy-preterm:1 pregnancy-postterm:1 pregnancy-third-trimester:1
--> CODESET pregnancy-antenatal:1 pregnancy-postdel-antenatal:1 pregnancy-lmp:1 pregnancy-edc:1 pregnancy-edd:1 pregnancy-delivery:1 pregnancy-postnatal-8wk:1 pregnancy-stillbirth:1
--> CODESET pregnancy-multiple:1 pregnancy-ectopic:1 pregnancy-miscarriage:1 pregnancy-top:1 pregnancy-top-probable:1 pregnancy-molar:1 pregnancy-blighted-ovum:1
--> CODESET pregnancy-loss-unspecified:1 pregnancy-postnatal-other:1 pregnancy-late-preg:1 pregnancy-preg-related:1

-- table of all pregnancy codes within the study period

IF OBJECT_ID('tempdb..#PregnancyPatientsGP') IS NOT NULL DROP TABLE #PregnancyPatientsGP;
SELECT 
	FK_Patient_Link_ID,
	SuppliedCode,
	EventDate
INTO #PregnancyPatientsGP
FROM [SharedCare].[GP_Events]
WHERE 
    SuppliedCode IN (SELECT [Code] FROM #AllCodes WHERE [Concept] LIKE 'pregnancy%' AND [Version] = 1)
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

--> EXECUTE query-patient-year-of-birth.sql
--> EXECUTE query-patient-sex.sql

-- COMBINE (FROM PRIMARY AND SECONDARY CARE DATA) PATIENTS IDENTIFIED AS HAVING A PREGNANCY DURING STUDY PERIOD 

IF OBJECT_ID('tempdb..#Cohort') IS NOT NULL DROP TABLE #Cohort;
SELECT DISTINCT ph.FK_Patient_Link_ID, Sex, YearOfBirth
INTO #Cohort
FROM #PregnancyPatientsHosp ph
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = ph.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = ph.FK_Patient_Link_ID
WHERE YEAR(@StartDate) - YearOfBirth BETWEEN 14 AND 49 -- OVER 18s ONLY
	AND Sex <> 'M'

UNION ALL 
SELECT DISTINCT pp.FK_Patient_Link_ID, Sex, YearOfBirth
FROM #PregnancyPatientsGP pp
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = pp.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = pp.FK_Patient_Link_ID
WHERE YEAR(@StartDate) - YearOfBirth BETWEEN 14 AND 49 -- OVER 18s ONLY
	AND Sex <> 'M'


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
FROM [SharedCare].GP_Events
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort);

--Outputs from this reusable query:
-- #Cohort
-- #PatientEventData

---------------------------------------------------------------------------------------------------------------
