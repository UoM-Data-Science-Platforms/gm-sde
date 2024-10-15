--┌──────────────────────────────────────────┐
--│ Patient medication data splitter for EFI │
--└──────────────────────────────────────────┘

-- OBJECTIVE: Split the medication data into chunks to improve performance

-- First get the medication data for this chunk of patients
IF OBJECT_ID('tempdb..#PatientMedicationData{param:n}') IS NOT NULL DROP TABLE [#PatientMedicationData{param:n}];
SELECT 
  FK_Patient_Link_ID,
  CAST(MedicationDate AS DATE) AS MedicationDate,
  SuppliedCode
INTO [#PatientMedicationData{param:n}]
FROM [SharedCare].GP_Medications
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND ABS(FK_Patient_Link_ID) % 10 = {param:n}
AND MedicationDate < '2022-06-01'; --TODO TEMP POST COPI FIX

-- Improve performance later with an index
DROP INDEX IF EXISTS [medData{param:n}] ON [#PatientMedicationData{param:n}];
CREATE INDEX [medData{param:n}] ON [#PatientMedicationData{param:n}] (FK_Patient_Link_ID, MedicationDate) INCLUDE (SuppliedCode);

IF OBJECT_ID('tempdb..#PatientMedDataTempTable{param:n}') IS NOT NULL DROP TABLE [#PatientMedDataTempTable{param:n}];
SELECT
  FK_Patient_Link_ID,
  SuppliedCode, 
  LAG(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS PreviousDate,
  MedicationDate, 
  LEAD(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS NextDate,
  ROW_NUMBER() OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS rn
INTO [#PatientMedDataTempTable{param:n}]
FROM [#PatientMedicationData{param:n}];
-- 56s

DELETE FROM [#PatientMedDataTempTable{param:n}]
WHERE DATEDIFF(YEAR, PreviousDate, NextDate) = 0
AND rn % 2 = 0;
--25s

DECLARE @LastDeletedNumber{param:n} INT; 
SET @LastDeletedNumber{param:n}=10001;
WHILE ( @LastDeletedNumber{param:n} > 10000)
BEGIN
  IF OBJECT_ID('tempdb..#PatientMedDataTempTableHolding{param:n}') IS NOT NULL DROP TABLE [#PatientMedDataTempTableHolding{param:n}];
  SELECT FK_Patient_Link_ID, SuppliedCode, 
        LAG(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS PreviousDate  ,MedicationDate, 
      LEAD(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS NextDate ,
      ROW_NUMBER() OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS rn
  INTO [#PatientMedDataTempTableHolding{param:n}]
  FROM [#PatientMedDataTempTable{param:n}];

  DELETE FROM [#PatientMedDataTempTableHolding{param:n}]
  WHERE DATEDIFF(YEAR, PreviousDate, NextDate) = 0
  AND rn % 2 = 0;

  TRUNCATE TABLE #PatientMedDataTempTable{param:n};
  INSERT INTO #PatientMedDataTempTable{param:n}
  SELECT FK_Patient_Link_ID, SuppliedCode, 
        LAG(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS PreviousDate  ,MedicationDate, 
      LEAD(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS NextDate ,
      ROW_NUMBER() OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS rn
  FROM [#PatientMedDataTempTableHolding{param:n}];

  DELETE FROM [#PatientMedDataTempTable{param:n}]
  WHERE DATEDIFF(YEAR, PreviousDate, NextDate) = 0
  AND rn % 2 = 0;

  SELECT @LastDeletedNumber{param:n}=@@ROWCOUNT;
END

-- Improve performance later with an index
DROP INDEX IF EXISTS [xx{param:n}] ON [#PatientMedDataTempTable{param:n}];
CREATE INDEX [xx{param:n}] ON [#PatientMedDataTempTable{param:n}] (FK_Patient_Link_ID, MedicationDate) INCLUDE (SuppliedCode);

IF OBJECT_ID('tempdb..#PolypharmDates5InLastYear{param:n}') IS NOT NULL DROP TABLE #PolypharmDates5InLastYear{param:n};
SELECT m1.FK_Patient_Link_ID, m1.[MedicationDate] AS PotentialPolypharmStartDate
INTO #PolypharmDates5InLastYear{param:n}
FROM [#PatientMedDataTempTable{param:n}] m1
LEFT OUTER JOIN [#PatientMedDataTempTable{param:n}] m2
	ON m1.FK_Patient_Link_ID = m2.FK_Patient_Link_ID
	AND m1.[MedicationDate] >= m2.[MedicationDate]
	AND m1.[MedicationDate] < DATEADD(year, 1, m2.[MedicationDate])
GROUP BY m1.FK_Patient_Link_ID, m1.[MedicationDate]
HAVING COUNT(DISTINCT m2.SuppliedCode) >= 5;

-- Next is a look forward from the day after a medication. This will deal with the stop events
IF OBJECT_ID('tempdb..#PolypharmStopDates5InLastYear{param:n}') IS NOT NULL DROP TABLE #PolypharmStopDates5InLastYear{param:n};
SELECT m1.FK_Patient_Link_ID, DATEADD(year, 1, m1.[MedicationDate]) AS PotentialPolypharmEndDate
INTO #PolypharmStopDates5InLastYear{param:n}
FROM [#PatientMedDataTempTable{param:n}] m1
LEFT OUTER JOIN [#PatientMedDataTempTable{param:n}] m2
	ON m1.FK_Patient_Link_ID = m2.FK_Patient_Link_ID
	AND DATEADD(year, 1, m1.[MedicationDate]) >= m2.[MedicationDate]
	AND DATEADD(year, 1, m1.[MedicationDate]) < DATEADD(year, 1, m2.[MedicationDate])
GROUP BY m1.FK_Patient_Link_ID, DATEADD(year, 1, m1.[MedicationDate])
HAVING COUNT(DISTINCT m2.SuppliedCode) < 5;