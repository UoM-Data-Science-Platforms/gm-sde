--┌──────────┐
--│ GET LTCS │
--└──────────┘

-- INPUT: Assumes there exists a temp table as follows:
-- #Patients (FK_Patient_Link_ID)
-- A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: A temp table with a row for each patient and ltc combo
-- #PatientsWithLTCs (FK_Patient_Link_ID, LTC)

-- Get the LTCs that each patient had prior to @StartDate
IF OBJECT_ID('tempdb..#PatientsWithLTCs') IS NOT NULL DROP TABLE #PatientsWithLTCs;
SELECT DISTINCT FK_Patient_Link_ID, CASE 
	WHEN FK_Reference_Coding_ID IN (1,2,3) THEN 'dx1'
	WHEN FK_Reference_Coding_ID IN (248447) THEN 'hypertension' 
	WHEN FK_Reference_Coding_ID IN (239611) THEN 'diabetes'
	END AS LTC INTO #PatientsWithLTCs FROM RLS.vw_GP_Events e
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate < @StartDate
AND FK_Reference_Coding_ID IN (1,2,3,248447,239611);
