--┌───────────────────────┐
--│ Recorded measurements │
--└───────────────────────┘

-- OBJECTIVE: To get the recorded measurements for the cohort

-- OUTPUT: Data with the following fields
--  - FK_Patient_Link_ID
--  - MeasurementLabel (eGFR/UACR/Serum creatinine/body mass index/weight/systolic blood pressure/diastolic blood pressure)
--  - MeasurementValue
--  - MeasurementUnit
--  - MeasurementDate (YYYY-MM-DD)

--Just want the output, not the messages
SET NOCOUNT ON;

--> EXECUTE query-build-industry-001-cohort.sql extraction-date:2023-09-19

--> CODESET egfr:1 urinary-albumin-creatinine-ratio:1 creatinine:1 bmi:2 weight:1 systolic-blood-pressure:1 diastolic-blood-pressure:1

IF OBJECT_ID('tempdb..#Measurements') IS NOT NULL DROP TABLE #Measurements;
CREATE TABLE #Measurements (
	FK_Patient_Link_ID bigint,
	MeasurementLabel VARCHAR(50),
	MeasurementValue FLOAT,
	MeasurementUnit NVARCHAR(64),
	MeasurementDate DATE
);

INSERT INTO #Measurements
SELECT FK_Patient_Link_ID, 'egfr' AS MeasurementLabel, [Value] AS MeasurementValue, Units AS MeasurementUnit, EventDate AS MeasurementDate
FROM #PatientEventData
WHERE SuppliedCode IN (SELECT [Code] FROM #AllCodes WHERE [Concept] = 'egfr' AND [Version] = 1)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND [Value] IS NOT NULL
AND [Value] != 0;

INSERT INTO #Measurements
SELECT FK_Patient_Link_ID, 'urinary-albumin-creatinine-ratio' AS MeasurementLabel, [Value] AS MeasurementValue, Units AS MeasurementUnit, EventDate AS MeasurementDate
FROM #PatientEventData
WHERE SuppliedCode IN (SELECT [Code] FROM #AllCodes WHERE [Concept] = 'urinary-albumin-creatinine-ratio' AND [Version] = 1)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND [Value] IS NOT NULL
AND [Value] != 0;

INSERT INTO #Measurements
SELECT FK_Patient_Link_ID, 'creatinine' AS MeasurementLabel, [Value] AS MeasurementValue, Units AS MeasurementUnit, EventDate AS MeasurementDate
FROM #PatientEventData
WHERE SuppliedCode IN (SELECT [Code] FROM #AllCodes WHERE [Concept] = 'creatinine' AND [Version] = 1)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND [Value] IS NOT NULL
AND [Value] != 0;

INSERT INTO #Measurements
SELECT FK_Patient_Link_ID, 'bmi' AS MeasurementLabel, [Value] AS MeasurementValue, Units AS MeasurementUnit, EventDate AS MeasurementDate
FROM #PatientEventData
WHERE SuppliedCode IN (SELECT [Code] FROM #AllCodes WHERE [Concept] = 'bmi' AND [Version] = 2)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND [Value] IS NOT NULL
AND [Value] != 0;

INSERT INTO #Measurements
SELECT FK_Patient_Link_ID, 'weight' AS MeasurementLabel, [Value] AS MeasurementValue, Units AS MeasurementUnit, EventDate AS MeasurementDate
FROM #PatientEventData
WHERE SuppliedCode IN (SELECT [Code] FROM #AllCodes WHERE [Concept] = 'weight' AND [Version] = 1)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND [Value] IS NOT NULL
AND [Value] != 0;

INSERT INTO #Measurements
SELECT FK_Patient_Link_ID, 'systolic-blood-pressure' AS MeasurementLabel, [Value] AS MeasurementValue, Units AS MeasurementUnit, EventDate AS MeasurementDate
FROM #PatientEventData
WHERE SuppliedCode IN (SELECT [Code] FROM #AllCodes WHERE [Concept] = 'systolic-blood-pressure' AND [Version] = 1)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND [Value] IS NOT NULL
AND [Value] != 0;

INSERT INTO #Measurements
SELECT FK_Patient_Link_ID, 'diastolic-blood-pressure' AS MeasurementLabel, [Value] AS MeasurementValue, Units AS MeasurementUnit, EventDate AS MeasurementDate
FROM #PatientEventData
WHERE SuppliedCode IN (SELECT [Code] FROM #AllCodes WHERE [Concept] = 'diastolic-blood-pressure' AND [Version] = 1)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND [Value] IS NOT NULL
AND [Value] != 0;

SELECT 
  FK_Patient_Link_ID AS PatientId,
  MeasurementLabel,
  MeasurementValue,
  MeasurementUnit,
  MeasurementDate
FROM #Measurements;