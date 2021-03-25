--┌────────────────────────────────┐
--│ Flu vaccine eligibile patients │
--└────────────────────────────────┘

-- OBJECTIVE: To obtain a table with a list of patients who are currently entitled
--            to a flu vaccine.

-- INPUT: No pre-requisites

-- OUTPUT: A temp table as follows:
-- #FluVaccPatients (FK_Patient_Link_ID)
-- 	- FK_Patient_Link_ID - unique patient id

-- Populate temporary table with patients elibigle for a flu vaccine
IF OBJECT_ID('tempdb..#FluVaccPatients') IS NOT NULL DROP TABLE #FluVaccPatients;
SELECT DISTINCT FK_Patient_Link_ID
INTO #FluVaccPatients
FROM [RLS].[vw_Cohort_Patient_Registers]
WHERE FK_Cohort_Register_ID IN (
	SELECT PK_Cohort_Register_ID FROM SharedCare.Cohort_Register
	WHERE FK_Cohort_Category_ID IN (
		SELECT PK_Cohort_Category_ID FROM SharedCare.Cohort_Category
		WHERE CategoryName = 'Flu Immunisation' -- Description is "Registers related to identification of at risk patients requiring Flu Immunisation";
	)
)
