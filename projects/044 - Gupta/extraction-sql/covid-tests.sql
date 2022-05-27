--┌────────────────────────────────────┐
--│ Covid Test Outcomes	               │
--└────────────────────────────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------
-- 

-- OUTPUT: Data with the following fields
-- Patient Id
-- TestOutcome (positive/negative/inconclusive)
-- TestDate (DD-MM-YYYY)

-- Set the start date
DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2020-01-01';
SET @EndDate = '2022-05-01';

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


-- load codesets needed for defining cohort


-- define cohort (take this code from patient file)


-- find all covid tests for the  cohort

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
	FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
	AND EventDate <= @EndDate
	and GroupDescription != 'Vaccination' 
	and GroupDescription not in ('Exposed', 'Suspected', 'Tested for immunity')
	and (GroupDescription != 'Unknown' and SubGroupDescription != '')

--bring together for final output
SELECT 
	 PatientId = m.FK_Patient_Link_ID
	,TestOutcome
	,TestDate_Year = YEAR(EventDate)
	,TestDate_Month = MONTH(EventDate)
FROM #covidtests cv
LEFT JOIN #Patients m ON cv.FK_Patient_Link_ID = m.FK_Patient_Link_ID
where m.FK_Patient_Link_ID is not null



