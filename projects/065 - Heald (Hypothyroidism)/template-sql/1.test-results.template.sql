--┌───────────────────────────┐
--│ Longitudinal test results │
--└───────────────────────────┘

-- Get every thyroid function test (TFT) results and BMI results for each member of the cohort
-- OUTPUT:
--   Patient ID
--   Date of test results
--   Type of test (TSH/FT4/FT3) + TPO Antibody titre (ie we do not need anyone without a TFT result)
--   Test Result Value
--   Measurement Units

-- Just want the output, not the messages
SET NOCOUNT ON;

-- Get the cohort of patients
--> EXECUTE query-build-rq065-cohort.sql
-- 2m43
--> EXECUTE query-build-rq065-cohort-events.sql
-- 4m25

--> CODESET tsh:1 t3:1 t4:1 tpo-antibody:1 bmi:2

IF OBJECT_ID('tempdb..#Measurements') IS NOT NULL DROP TABLE #Measurements;
CREATE TABLE #Measurements (
	FK_Patient_Link_ID bigint,
	MeasurementDate DATE,
	MeasurementLabel VARCHAR(50),
	MeasurementValue FLOAT,
	MeasurementUnit NVARCHAR(64)
);

-- tsh
INSERT INTO #Measurements
SELECT FK_Patient_Link_ID, EventDate AS MeasurementDate, 'tsh' AS MeasurementLabel, [Value] AS MeasurementValue, Units AS MeasurementUnit
FROM #PatientEventData
WHERE SuppliedCode IN (SELECT [Code] FROM #AllCodes WHERE [Concept] = 'tsh' AND [Version] = 1)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND [Value] IS NOT NULL
AND [Value] != 0;
-- 10s

-- t3
INSERT INTO #Measurements
SELECT FK_Patient_Link_ID, EventDate AS MeasurementDate, 't3' AS MeasurementLabel, [Value] AS MeasurementValue, Units AS MeasurementUnit
FROM #PatientEventData
WHERE SuppliedCode IN (SELECT [Code] FROM #AllCodes WHERE [Concept] = 't3' AND [Version] = 1)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND [Value] IS NOT NULL
AND [Value] != 0;
-- 0s

-- t4
INSERT INTO #Measurements
SELECT FK_Patient_Link_ID, EventDate AS MeasurementDate, 't4' AS MeasurementLabel, [Value] AS MeasurementValue, Units AS MeasurementUnit
FROM #PatientEventData
WHERE SuppliedCode IN (SELECT [Code] FROM #AllCodes WHERE [Concept] = 't4' AND [Version] = 1)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND [Value] IS NOT NULL
AND [Value] != 0;
-- 18s

-- tpo-antibody
INSERT INTO #Measurements
SELECT FK_Patient_Link_ID, EventDate AS MeasurementDate, 'tpo-antibody' AS MeasurementLabel, [Value] AS MeasurementValue, Units AS MeasurementUnit
FROM #PatientEventData
WHERE SuppliedCode IN (SELECT [Code] FROM #AllCodes WHERE [Concept] = 'tpo-antibody' AND [Version] = 1)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND [Value] IS NOT NULL
AND [Value] != 0;
-- 0s

-- bmi
INSERT INTO #Measurements
SELECT FK_Patient_Link_ID, EventDate AS MeasurementDate, 'bmi' AS MeasurementLabel, [Value] AS MeasurementValue, Units AS MeasurementUnit
FROM #PatientEventData
WHERE SuppliedCode IN (SELECT [Code] FROM #AllCodes WHERE [Concept] = 'bmi' AND [Version] = 2)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND [Value] IS NOT NULL
AND [Value] != 0;
-- 14s

SELECT 
  FK_Patient_Link_ID AS PatientId,
  MeasurementDate,
  MeasurementLabel,
  MeasurementValue,
  MeasurementUnit
FROM #Measurements;