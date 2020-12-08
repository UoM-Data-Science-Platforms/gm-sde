-- ┌────────────────────────────┐
-- │ GET LTC Groups per patient │
-- └────────────────────────────┘

-- INPUT: Assumes there exists a temp table as follows:
-- #PatientsWithLTCs (FK_Patient_Link_ID, LTC)
-- Therefore this is run after query-patient-ltcs.sql

-- OUTPUT: A temp table with a row for each patient and ltc group combo
-- #LTCGroups (FK_Patient_Link_ID, LTCGroup)

-- Calculate the LTC groups for each patient
IF OBJECT_ID('tempdb..#LTCGroups') IS NOT NULL DROP TABLE #LTCGroups;
SELECT 
	DISTINCT FK_Patient_Link_ID, 
	CASE 
		WHEN LTC IN ('diabetes', 'ckd') THEN 'diabetes'
		WHEN LTC IN ('hypertension', 'hf') THEN 'cardiovascular'
	END AS LTCGroup INTO #LTCGroups
FROM #PatientsWithLTCs;
