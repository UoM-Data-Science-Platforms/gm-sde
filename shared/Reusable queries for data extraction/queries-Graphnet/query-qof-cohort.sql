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

IF OBJECT_ID('tempdb..#{param:outputtable}') IS NOT NULL DROP TABLE #{param:outputtable};
SELECT DISTINCT FK_Patient_Link_ID
INTO #{param:outputtable}
FROM [RLS].[vw_Cohort_Patient_Registers]
WHERE FK_Cohort_Register_ID IN (
	SELECT PK_Cohort_Register_ID FROM SharedCare.Cohort_Register
	WHERE FK_Cohort_Category_ID IN (
		SELECT PK_Cohort_Category_ID FROM SharedCare.Cohort_Category
		WHERE CategoryName = '{param:condition}'
	)
);