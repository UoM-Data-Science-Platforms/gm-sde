--┌────────────────────────────────────┐
--│ Covid Test Outcomes	               │
--└────────────────────────────────────┘

-- REVIEW LOG:

-- OUTPUT: Data with the following fields
-- Patient Id
-- TestOutcome (positive/negative/inconclusive)
-- TestDate (DD-MM-YYYY)
-- TestLocation (hospital/elsewhere)

--COHORT: PATIENTS WITH SMI DIAGNOSES AS OF 31.01.20

IF OBJECT_ID('tempdb..#Patients_1') IS NOT NULL DROP TABLE #Patients_1;
SELECT distinct gp.FK_Patient_Link_ID 
INTO #Patients_1
FROM [RLS].[vw_GP_Events] gp
LEFT OUTER JOIN #Patients p ON p.PK_Patient_ID = gp.FK_Patient_ID
WHERE SuppliedCode IN (
	SELECT [Code] FROM #AllCodes WHERE [Concept] IN ('severe-mental-illness') AND [Version] = 1
)
	AND (gp.EventDate) <= '2020-01-31'

DROP TABLE #covidtests
SELECT 
      [FK_Patient_Link_ID]
      ,[EventDate]
      ,[DeathDate]
      ,[DeceasedFlag]
      ,[MainCode]
      ,[CodeDescription]
      ,[GroupDescription]
      ,[SubGroupDescription]
      ,[DeathWithin28Days]
	  ,TestOutcome = CASE WHEN SubGroupDescription = 'Post complication' and GroupDescription = 'Confirmed'						then 'Positive'
			WHEN GroupDescription = 'Confirmed'																		then 'Positive'
			WHEN SubGroupDescription = 'Post complication' and  GroupDescription = 'Confirmed'						then 'Positive'
			WHEN SubGroupDescription = 'Organism' and  GroupDescription = 'Confirmed'								then 'Positive'
			WHEN SubGroupDescription = '' and GroupDescription = 'Excluded'											then 'Negative'
			WHEN SubGroupDescription = '' and GroupDescription = 'Tested' and CodeDescription like '%not detected%' then 'Negative'
			WHEN SubGroupDescription = 'Offered' and GroupDescription = 'Tested'									then 'Unknown/Inconclusive'
			WHEN SubGroupDescription = 'Unknown' 																	then 'Unknown/Inconclusive'
			WHEN SubGroupDescription = '' and GroupDescription = 'Tested' and CodeDescription not like '%detected%' 
							and CodeDescription not like '%positive%' and CodeDescription not like '%negative%'		then 'Unknown/Inconclusive'
			WHEN SubGroupDescription != ''																			then SubGroupDescription
			WHEN SubGroupDescription = '' and CodeDescription like '%reslt unknow%'									then 'Inconclusive'
							ELSE 'CHECK' END
  INTO #covidtests
  FROM [RLS].[vw_COVID19]
  WHERE 
	FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
	and GroupDescription != 'Vaccination' 
	and GroupDescription not in ('Exposed', 'Suspected', 'Tested for immunity')
	and (GroupDescription != 'Unknown' and SubGroupDescription != '')
