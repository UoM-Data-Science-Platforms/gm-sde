--┌───────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
--│ Define Cohort for RQ062: all individuals registered with a GP who were aged 50 years or older on September 1 2013 │
--└───────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

-- NEED TO DO!!!: CHANGE YEAR AND MONTH OF BIRTH INTO WEEK OF BIRTH LATER WHEN THE WEEK OF BIRTH DATA IS AVAILABLE

-- OBJECTIVE: To build the cohort of patients needed for RQ062. This reduces duplication of code in the template scripts.

-- COHORT: All individuals who registered with a GP, and were aged 50 years or older on September 1 2013 (the start of the herpes zoster vaccine programme in the UK)

-- OUTPUT: Temp tables as follows:
-- #Patients (FK_Patient_Link_ID)
-- A distinct list of FK_Patient_Link_IDs for each patient in the cohort


-- Set the start date
DECLARE @StudyStartDate datetime;
SET @StudyStartDate = '2013-09-01';

--> EXECUTE query-get-possible-patients.sql
--> EXECUTE query-patient-practice-and-ccg.sql
--> EXECUTE query-patient-year-and-quarter-month-of-birth.sql


-- Merge information========================================================================================================================================================
IF OBJECT_ID('tempdb..#Cohort') IS NOT NULL DROP TABLE #Cohort;
SELECT
  p.FK_Patient_Link_ID as PatientId, 
  gp.GPPracticeCode, 
  yob.YearAndQuarterMonthOfBirth, DATEDIFF(year, yob.YearAndQuarterMonthOfBirth, '2013-09-01') AS [Time]
INTO #Cohort
FROM #Patients p
LEFT OUTER JOIN #PatientPractice gp ON gp.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearAndQuarterMonthOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE gp.GPPracticeCode IS NOT NULL AND YearAndQuarterMonthOfBirth < '1963-09-01'

-- Reduce #Patients table to just the cohort patients========================================================================================================================
DELETE FROM #Patients
WHERE FK_Patient_Link_ID NOT IN (SELECT PatientId FROM #Cohort)
