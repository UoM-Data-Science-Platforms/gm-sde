--┌───────────────────────────────────────────────────────────────────┐
--│ Define Cohort for LH003: patients that had a dementia diagnosis   │
--└───────────────────────────────────────────────────────────────────┘

-- OBJECTIVE: To build the cohort of patients needed for LH003. This reduces duplication of code in the template scripts.

-- COHORT: Any patient with a dementia diagnosis between start and end date.

-- INPUT: assumes there exists one temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: Temp tables as follows:
-- #Cohort

TODO need to know schema where we can write this to

types are:

GmPseudo NUMBER(38,0)
FirstDementiaDate DATE

SELECT "GmPseudo", MIN("Dementia_DiagnosisDate") AS FirstDementiaDate
FROM PRESENTATION.GP_RECORD."LongTermConditionRegister_SecondaryUses"
WHERE "Dementia_DiagnosisDate" IS NOT NULL
AND "Age" >= 18
GROUP BY "GmPseudo"