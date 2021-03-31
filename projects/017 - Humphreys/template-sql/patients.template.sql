--┌─────────────────────────────┐
--│ Patient cohort demographics │
--└─────────────────────────────┘

-- OUTPUT: Data with the following fields
-- 	- PatientId (int)
-- 	- Sex (M/F/U)
--  - YearOfBirht (int) 
--  - GPPracticeCode

--Just want the output, not the messages
SET NOCOUNT ON;

-- For now let's use the in-built QOF rule for the RA cohort. We can refine this over time
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT DISTINCT FK_Patient_Link_ID
INTO #Patients
FROM [RLS].[vw_Cohort_Patient_Registers]
WHERE FK_Cohort_Register_ID IN (
	SELECT PK_Cohort_Register_ID FROM SharedCare.Cohort_Register
	WHERE FK_Cohort_Category_ID IN (
		SELECT PK_Cohort_Category_ID FROM SharedCare.Cohort_Category
		WHERE CategoryName = 'Rheumatoid Arthritis'
	)
);

--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-year-of-birth.sql
--> EXECUTE query-patient-practice-and-ccg.sql

SELECT p.FK_Patient_Link_ID AS PatientId, Sex, YearOfBirth, GPPracticeCode FROM #Patients p
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientPractice pp ON pp.FK_Patient_Link_ID = p.FK_Patient_Link_ID;
