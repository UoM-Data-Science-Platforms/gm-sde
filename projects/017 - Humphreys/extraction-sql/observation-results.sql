--┌─────────────────────┐
--│ Observation results │
--└─────────────────────┘

----------------------- RDE CHECK -----------------------
--RDE Name: George Tilston, Date of check: 06/05/21

-- OUTPUT: Data with the following fields
-- 	- PatientId (int)
--	-	ResultType
--	-	ResultCode
--	-	ResultDescription
--	-	SourceDate
--	-	TestDescription
--	-	ResultMinimumValue (Currently redacted)
--	-	ResultMaximumValue(Currently redacted)
--	-	ResultFlag
--	-	ResultStatus
--	-	ResultValue	(Currently redacted)
--	-	ResultUnit

--Just want the output, not the messages
SET NOCOUNT ON;

-- For now let's use the in-built QOF rule for the RA cohort. We can refine this over time
--┌──────────────────────────────────────────────────────┐
--│ Create a cohort of patients based on QOF definitions │
--└──────────────────────────────────────────────────────┘

-- OBJECTIVE: To obtain a cohort of patients defined by a particular QOF condition.

-- INPUT: Takes two parameters
--  - condition: string - the name of the QOF condition as recorded in the SharedCare.Cohort_Category table
--  - outputtable: string - the name of the temp table that will be created to store the cohort

-- OUTPUT: A temp table as follows:
-- #[outputtable] (FK_Patient_Link_ID)
--  - FK_Patient_Link_ID - unique patient id for cohort patient

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

SELECT 
	ord.FK_Patient_Link_ID AS PatientId, 
	ord.ResultType,
	ord.ResultCode,
	ord.ResultDescription,
	ord.SourceDate,
	res.TestDescription,
	res.ResultMinimumValue,
	res.ResultMaximumValue,
	res.ResultFlag,
	res.ResultStatus,
	res.ResultValue,
	res.ResultUnit
FROM RLS.vw_Orders ord
LEFT OUTER JOIN RLS.vw_Observation_Results res ON res.FK_Order_ID = ord.PK_Order_ID
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);
