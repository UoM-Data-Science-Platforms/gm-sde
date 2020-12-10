--
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
    WHEN LTC IN ('atrial fibrillation','heart failure') THEN 'Cardiovascular'
		WHEN LTC IN ('') THEN 'Endocrine'
		WHEN LTC IN ('peptic ulcer disease') THEN 'Gastrointestinal'
		WHEN LTC IN ('') THEN 'Musculoskeletal or Skin'
		WHEN LTC IN ('') THEN 'Neurological'
		WHEN LTC IN ('') THEN 'Psychiatric'
		WHEN LTC IN ('') THEN 'Renal or Urological'
		WHEN LTC IN ('asthma') THEN 'Respiratory'
		WHEN LTC IN ('') THEN 'Sensory Impairment or Learning Disability'
		WHEN LTC IN ('') THEN 'Substance Abuse'
  END AS LTCGroup INTO #LTCGroups
FROM #PatientsWithLTCs;
