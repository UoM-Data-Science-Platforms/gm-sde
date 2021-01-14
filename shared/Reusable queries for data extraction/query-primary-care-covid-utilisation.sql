--┌──────────────────────────────────────────┐
--│ COVID utilisation from primary care data │
--└──────────────────────────────────────────┘

-- OBJECTIVE:	Classifies a list of events as COVID or non-COVID. An event is classified as
--						"COVID" if the date of the event is within 4 weeks after, or up to 14 days 
--						before, a positive COVID test.

-- INPUT: Assumes there exists two temp tables as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort
-- #PatientDates (FK_Patient_Link_ID, EventDate)
-- 	- FK_Patient_Link_ID - unique patient id
--	- EventDate - date of the event to classify as COVID/non-COVID
--  A distinct list of the dates of the event for each patient in the cohort

-- OUTPUT: A temp table as follows:
-- #COVIDUtilisationPrimaryCare (FK_Patient_Link_ID, AdmissionDate, AcuteProvider, CovidHealthcareUtilisation)
-- 	- FK_Patient_Link_ID - unique patient id
--	- EventDate - date of the event to classify as COVID/non-COVID
--  - CovidHealthcareUtilisation - 'TRUE' if event within 4 weeks after, or up to 14 days before, a positive test

-- Get first positive covid test for each patient
IF OBJECT_ID('tempdb..#CovidCases') IS NOT NULL DROP TABLE #CovidCases;
SELECT FK_Patient_Link_ID, MIN(CONVERT(DATE, [EventDate])) AS CovidPositiveDate INTO #CovidCases
FROM [RLS].[vw_COVID19]
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND GroupDescription = 'Confirmed'
GROUP BY FK_Patient_Link_ID;

IF OBJECT_ID('tempdb..#COVIDUtilisationPrimaryCare') IS NOT NULL DROP TABLE #COVIDUtilisationPrimaryCare;
SELECT 
	pd.*, 
	CASE
		WHEN c.FK_Patient_Link_ID IS NOT NULL THEN 'TRUE'
		ELSE 'FALSE'
	END AS CovidHealthcareUtilisation
INTO #COVIDUtilisationPrimaryCare 
FROM #PatientDates pd
LEFT OUTER join #CovidCases c ON 
	pd.FK_Patient_Link_ID = c.FK_Patient_Link_ID 
	AND pd.EventDate <= DATEADD(WEEK, 4, c.CovidPositiveDate)
	AND pd.EventDate >= DATEADD(DAY, -14, c.CovidPositiveDate);