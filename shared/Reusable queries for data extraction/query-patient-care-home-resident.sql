--┌──────────────────┐
--│ Care home status │
--└──────────────────┘

-- OBJECTIVE: To get the care home status for each patient.

-- INPUT: Assumes there exists a temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: A temp table as follows:
-- #PatientCareHomeStatus (FK_Patient_Link_ID, IsCareHomeResident)
-- 	- FK_Patient_Link_ID - unique patient id
--	- IsCareHomeResident - Y/N

-- ASSUMPTIONS:
--	-	If any of the patient records suggests the patients lives in a care home we will assume that they do

-- Get the care home status for each patient
IF OBJECT_ID('tempdb..#PatientCareHomeStatus') IS NOT NULL DROP TABLE #PatientCareHomeStatus;
SELECT 
	FK_Patient_Link_ID,
	MAX(NursingCareHomeFlag) AS IsCareHomeResident -- max as Y > N > NULL
INTO #PatientCareHomeStatus
FROM RLS.vw_Patient p
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND NursingCareHomeFlag IS NOT NULL
GROUP BY FK_Patient_Link_ID;
