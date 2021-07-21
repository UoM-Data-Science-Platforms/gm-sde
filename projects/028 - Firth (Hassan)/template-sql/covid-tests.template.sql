--┌────────────────────────────────────┐
--│ Covid Test Outcomes	               │
--└────────────────────────────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------
-- RICHARD WILLIAMS |	DATE: 20/07/21

-- OUTPUT: Data with the following fields
-- Patient Id
-- TestOutcome (positive/negative/inconclusive)
-- TestDate (DD-MM-YYYY)
-- TestLocation (hospital/elsewhere) - NOT AVAILABLE

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2020-01-31';

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

--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-year-of-birth.sql

--> CODESET recurrent-depressive:1 schizophrenia-psychosis:1 bipolar:1 depression:1


-- cohort of patients with depression

IF OBJECT_ID('tempdb..#depression_cohort') IS NOT NULL DROP TABLE #depression_cohort;
SELECT DISTINCT gp.FK_Patient_Link_ID
INTO #depression_cohort
FROM [RLS].[vw_GP_Events] gp
WHERE SuppliedCode IN 
	(SELECT [Code] FROM #AllCodes WHERE [Concept] IN ('depression') AND [Version] = 1)
    AND gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
	AND (gp.EventDate) <= '2020-01-31'
--655,657

-- take a 10 percent sample of depression patients (as requested by PI), to add to SMI cohort later on

SELECT TOP 10 PERCENT *
INTO #depression_cohort_sample
FROM #depression_cohort
ORDER BY FK_Patient_Link_ID --not ideal to order by this but need it to be the same across files
--65,566

-- SMI episodes to identify cohort

IF OBJECT_ID('tempdb..#SMI_Episodes') IS NOT NULL DROP TABLE #SMI_Episodes;
SELECT gp.FK_Patient_Link_ID, 
		YearOfBirth, 
		Sex
INTO #SMI_Episodes
FROM [RLS].[vw_GP_Events] gp
LEFT OUTER JOIN #Patients p ON p.FK_Patient_link_ID = gp.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE ((SuppliedCode IN 
	(SELECT [Code] FROM #AllCodes WHERE [Concept] IN ('recurrent-depressive', 'bipolar', 'schizophrenia-psychosis') AND [Version] = 1)) 
	OR 
	(gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #depression_cohort_sample)))
    AND gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
	AND (gp.EventDate) <= '2020-01-31'

-- Define the main cohort to be matched

IF OBJECT_ID('tempdb..#MainCohort') IS NOT NULL DROP TABLE #MainCohort;
SELECT DISTINCT FK_Patient_Link_ID, 
		YearOfBirth, 
		Sex
INTO #MainCohort
FROM #SMI_Episodes
--51,082

-- Define the population of potential matches for the cohort
IF OBJECT_ID('tempdb..#PotentialMatches') IS NOT NULL DROP TABLE #PotentialMatches;
SELECT p.FK_Patient_Link_ID, Sex, YearOfBirth
INTO #PotentialMatches
FROM #Patients p
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
EXCEPT
SELECT FK_Patient_Link_ID, Sex, YearOfBirth FROM #MainCohort;
-- 3,378,730

--> EXECUTE query-cohort-matching-yob-sex-alt.sql yob-flex:1 num-matches:4

-- Get the matched cohort detail - same as main cohort
IF OBJECT_ID('tempdb..#MatchedCohort') IS NOT NULL DROP TABLE #MatchedCohort;
SELECT 
  c.MatchingPatientId AS FK_Patient_Link_ID,
  Sex,
  MatchingYearOfBirth,
  PatientId AS PatientWhoIsMatched
INTO #MatchedCohort
FROM #CohortStore c
WHERE c.PatientId IN (SELECT FK_Patient_Link_ID FROM #Patients);

-- Define a table with all the patient ids for the main cohort and the matched cohort
IF OBJECT_ID('tempdb..#PatientIds') IS NOT NULL DROP TABLE #PatientIds;
SELECT PatientId AS FK_Patient_Link_ID INTO #PatientIds FROM #CohortStore
UNION
SELECT MatchingPatientId FROM #CohortStore;


-- find all covid tests for the main and matched cohort
IF OBJECT_ID('tempdb..#covidtests') IS NOT NULL DROP TABLE #covidtests;
SELECT 
      [FK_Patient_Link_ID]
      ,[EventDate]
      ,[MainCode]
      ,[CodeDescription]
      ,[GroupDescription]
      ,[SubGroupDescription]
	  ,TestOutcome = CASE WHEN GroupDescription = 'Confirmed'														then 'Positive'
			WHEN SubGroupDescription = '' and GroupDescription = 'Excluded'											then 'Negative'
			WHEN SubGroupDescription = '' and GroupDescription = 'Tested' and CodeDescription like '%not detected%' then 'Negative'
			WHEN SubGroupDescription = 'Offered' and GroupDescription = 'Tested'									then 'Unknown/Inconclusive'
			WHEN SubGroupDescription = 'Unknown' 																	then 'Unknown/Inconclusive'
			WHEN SubGroupDescription = '' and GroupDescription = 'Tested' and CodeDescription not like '%detected%' 
							and CodeDescription not like '%positive%' and CodeDescription not like '%negative%'		then 'Unknown/Inconclusive'
			WHEN SubGroupDescription != ''																			then SubGroupDescription
			WHEN SubGroupDescription = '' and CodeDescription like '%reslt unknow%'									then 'Unknown/Inconclusive'
							ELSE 'CHECK' END
INTO #covidtests
FROM [RLS].[vw_COVID19]
WHERE 
	(FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #MainCohort) OR FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #MatchedCohort))
	and GroupDescription != 'Vaccination' 
	and GroupDescription not in ('Exposed', 'Suspected', 'Tested for immunity')
	and (GroupDescription != 'Unknown' and SubGroupDescription != '')

--bring together for final output
--patients in main cohort
SELECT 
	 PatientId = m.FK_Patient_Link_ID
	,NULL AS MainCohortMatchedPatientId
	,TestOutcome
	,TestDate_Year = YEAR(EventDate)
	,TestDate_Month = MONTH(EventDate)
FROM #covidtests cv
LEFT JOIN #MainCohort m ON cv.FK_Patient_Link_ID = m.FK_Patient_Link_ID
where m.FK_Patient_Link_ID is not null
UNION 
--patients in matched cohort
SELECT 
	 PatientId = m.FK_Patient_Link_ID
	,PatientWhoIsMatched AS MainCohortMatchedPatientId
	,TestOutcome
	,TestDate_Year = YEAR(EventDate)
	,TestDate_Month = MONTH(EventDate)
FROM #covidtests cv
LEFT JOIN #MatchedCohort m ON cv.FK_Patient_Link_ID = m.FK_Patient_Link_ID
where m.FK_Patient_Link_ID is not null

