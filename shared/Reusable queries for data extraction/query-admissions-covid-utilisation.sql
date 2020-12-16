--┌─────────────────────────────────────────────────┐
--│ GET COVID utilisation from secondary admissions │
--└─────────────────────────────────────────────────┘

-- OBJECTIVE: To classify every admission to secondary care based on whether it is a COVID or non-COVID related. 
--						A COVID-related admission is classed as an admission within 4 weeks after, or up to 2 weeks before
--						a positive test.

-- INPUT: Assumes there exists two temp tables as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort
-- #Admissions (FK_Patient_Link_ID, AdmissionDate, AcuteProvider)
--  A distinct list of the admissions for each patient in the cohort

-- OUTPUT: A temp table as follows:
-- #COVIDUtilisationAdmissions (FK_Patient_Link_ID, AdmissionDate, AcuteProvider, CovidHealthcareUtilisation)
-- 	- FK_Patient_Link_ID - unique patient id
--	- AdmissionDate - date of discharge (YYYY-MM-DD)
--	- AcuteProvider - Bolton, SRFT, Stockport etc..
--  - CovidHealthcareUtilisation - 'TRUE' if admission within 4 weeks after, or up to 14 days before, a positive test

-- Get first positive covid test for each patient
IF OBJECT_ID('tempdb..#CovidCases') IS NOT NULL DROP TABLE #CovidCases;
SELECT FK_Patient_Link_ID, MIN(CONVERT(DATE, [EventDate])) AS CovidPositiveDate INTO #CovidCases
FROM [RLS].[vw_COVID19]
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND GroupDescription = 'Confirmed'
GROUP BY FK_Patient_Link_ID;


IF OBJECT_ID('tempdb..#COVIDUtilisationAdmissions') IS NOT NULL DROP TABLE #COVIDUtilisationAdmissions;
SELECT 
	a.*, 
	CASE
		WHEN c.FK_Patient_Link_ID IS NOT NULL THEN 'TRUE'
		ELSE 'FALSE'
	END AS CovidHealthcareUtilisation
INTO #COVIDUtilisationAdmissions 
FROM #Admissions a
LEFT OUTER join #CovidCases c ON 
	a.FK_Patient_Link_ID = c.FK_Patient_Link_ID 
	AND a.AdmissionDate <= DATEADD(WEEK, 4, c.CovidPositiveDate)
	AND a.AdmissionDate >= DATEADD(DAY, -14, c.CovidPositiveDate);