--┌──────────────────────────┐
--│ GET No. LTCS per patient │
--└──────────────────────────┘

-- INPUT: Assumes there exists a temp table as follows:
-- #PatientsWithLTCs (FK_Patient_Link_ID, LTC)
-- Therefore this is run after query-patient-ltcs.sql

-- OUTPUT: A temp table with a row for each patient with the number of LTCs they have
-- #NumLTCs (FK_Patient_Link_ID, NumberOfLTCs)

-- Calculate the number of LTCs for each patient
IF OBJECT_ID('tempdb..#NumLTCs') IS NOT NULL DROP TABLE #NumLTCs;
SELECT 
  FK_Patient_Link_ID, 
  CASE
    WHEN NumberOfLTCs > 2 THEN 2 
    ELSE NumberOfLTCs
  END AS NumberOfLTCs
INTO #NumLTCs
FROM (
  SELECT FK_Patient_Link_ID, COUNT(*) AS NumberOfLTCs FROM #PatientsWithLTCs
  GROUP BY FK_Patient_Link_ID
) subquery;
