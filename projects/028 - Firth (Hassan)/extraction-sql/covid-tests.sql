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

