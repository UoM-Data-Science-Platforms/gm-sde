--┌──────────────────────────────────────┐
--│ CREATE RANDOM PATIENT IDs FOR COHORT │
--└──────────────────────────────────────┘

-- OBJECTIVE: To produce a list of random unique patient IDs for a single study. These will be different to all other studies


-- OUTPUT: A temp table as follows:
-- #random_patient_ids_patient_id (Random_Patient_ID)
--  - PK_Patient_Link_ID - Original PatientID
--  - Random_Patient_ID - A random, unique identifier for the patient

SET NOCOUNT ON

IF OBJECT_ID('tempdb..#patients') IS NOT NULL DROP TABLE #patients;
SELECT PK_Patient_Link_ID
INTO #PATIENTS
FROM RLS.vw_Patient_Link 

IF OBJECT_ID('tempdb..#random_patient_ids') IS NOT NULL DROP TABLE #random_patient_ids;
SELECT PK_Patient_Link_ID, 
	Random_Patient_ID = ROW_NUMBER() OVER (ORDER BY PK_Patient_Link_ID)
INTO #random_patient_ids
FROM #PATIENTS
ORDER BY NEWID()

-- FINAL OUTPUT STATEMENT
PRINT 'PATIENT_LINK_ID, RANDOM_PATIENT_ID'
select * from #random_patient_ids order by newid()