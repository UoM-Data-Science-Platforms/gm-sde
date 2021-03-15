
--┌──────────────────────────────────────┐
--│ CREATE RANDOM PATIENT IDs FOR COHORT │
--└──────────────────────────────────────┘

-- OBJECTIVE: To produce a list of random unique patient IDs for a single study. These will be different to all other studies


-- INPUT: Assumes there exists a temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort


-- OUTPUT: A temp table as follows:
-- #new_patient_id (Random_Patient_ID)
--  - Random_Patient_ID - A random, unique identifier for the patient

IF OBJECT_ID('tempdb..#patients') IS NOT NULL DROP TABLE #patients;
SELECT PK_Patient_Link_ID
INTO #PATIENTS
FROM RLS.vw_Patient_Link 


-- THE BELOW TABLE '#random_patient_ids' CONTAINS THE ORIGINAL PATIENT_LINK_ID ALONGSIDE THE NEW RANDOM UNIQUE ID

IF OBJECT_ID('tempdb..#random_patient_ids') IS NOT NULL DROP TABLE #random_patient_ids;
SELECT PK_Patient_Link_ID, 
	Random_Patient_ID = ROW_NUMBER() OVER (ORDER BY PK_Patient_Link_ID)
INTO #random_patient_ids
FROM #PATIENTS
ORDER BY NEWID()


-- THE BELOW TABLE '#new_patient_id' CONTAINS ONLY THE NEW ID

IF OBJECT_ID('tempdb..#new_patient_id') IS NOT NULL DROP TABLE #new_patient_id;
SELECT 
	Random_Patient_ID
INTO #new_patient_id
FROM #random_patient_ids
ORDER BY NEWID()


select * from #random_patient_ids order by newid()
--select * from #new_patient_id order by newid()
