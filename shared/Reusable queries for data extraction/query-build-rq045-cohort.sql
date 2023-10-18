--┌──────────────────────────────────────────────────────────────────────┐
--│ Define Cohort for RQ045: COVID-19 vaccine hesitancy and acceptance   │
--└──────────────────────────────────────────────────────────────────────┘

-- OBJECTIVE: To build the cohort of patients needed for RQ045. This reduces
--						duplication of code in the template scripts. The cohort is any
--						patient who have no missing data for YOB, sex, LSOA and ethnicity.

-- INPUT: assumes there exists one temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: Temp tables as follows:
-- #Cohort - list of patient ids of the cohort

--==========================================================================================================================
--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-year-of-birth.sql
--> EXECUTE query-patient-lsoa.sql


-- Create the table of ethnic================================================================================================================================
IF OBJECT_ID('tempdb..#Ethnic') IS NOT NULL DROP TABLE #Ethnic;
SELECT PK_Patient_Link_ID AS FK_Patient_Link_ID, EthnicCategoryDescription AS Ethnicity
INTO #Ethnic
FROM SharedCare.Patient_Link;

-- The final table========================================================================================================================================
SELECT
  p.FK_Patient_Link_ID as PatientId,
  YearAndQuarterMonthOfBirth,
  Sex,
  Ethnicity,
  IMDGroup,
  LSOA_Code AS LSOA,
  FORMAT(link.DeathDate, 'yyyy-MM') AS YearAndMonthOfDeath
FROM #Patients p
LEFT OUTER JOIN #Ethnic e ON e.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearAndQuarterMonthOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #IMDGroup imd ON imd.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientLSOA l ON l.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN [SharedCare].[Patient_Link] link ON p.FK_Patient_Link_ID = link.PK_Patient_Link_ID;