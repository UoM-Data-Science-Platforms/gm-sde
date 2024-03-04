{if:verbose}
--┌──────────────────────────────────────────────────┐
--│ height and weight, standardised in centimetres   │
--└──────────────────────────────────────────────────┘

-- OBJECTIVE: To find the height and weight for every patient, closest to the date provided, standardised in centimetres.

-- INPUT: A variable:
--  - date: date - (YYYY-MM-DD) the date to look around
--  - comparison: inequality sign (>, <, >= or <=) e.g. if '>' then will look for the first value strictly after the date
--	- all-patients: boolean - (true/false) if true, then all patients are included, otherwise only those in the pre-existing #Patients table.
--	- gp-events-table: string - (table name) the name of the table containing the GP events. Usually is "SharedCare.GP_Events" but can be anything with the columns: FK_Patient_Link_ID, EventDate, and SuppliedCode

-- OUTPUT: Temp tables as follows:
-- #PatientHeightStandardised (FK_Patient_Link_ID, DateOfFirstValue, Value, HeightInCm)
-- #PatientWeight (FK_Patient_Link_ID, DateOfFirstValue, Value)
{endif:verbose}

--> CODESET height:1 

-- First we get the date of the nearest height measurement before/after the index date

IF OBJECT_ID('tempdb..#HEIGHT_TEMP1') IS NOT NULL DROP TABLE #HEIGHT_TEMP1;
{if:comparison=>}
  SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate
{endif:comparison}
{if:comparison=>=}
  SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate
{endif:comparison}
{if:comparison=<}
  SELECT FK_Patient_Link_ID, MAX(EventDate) AS EventDate
{endif:comparison}
{if:comparison=<=}
  SELECT FK_Patient_Link_ID, MAX(EventDate) AS EventDate
{endif:comparison}
INTO #HEIGHT_TEMP1
FROM {param:gp-events-table}
WHERE SuppliedCode IN (SELECT code FROM #AllCodes WHERE Concept = 'height' AND Version = 1) 
AND EventDate {param:comparison} '{param:date}'
AND [Value] IS NOT NULL
AND [Value] != '0'
GROUP BY FK_Patient_Link_ID;

-- Then we join to that table in order to get the value of that measurement
IF OBJECT_ID('tempdb..#PatientHeight') IS NOT NULL DROP TABLE #PatientHeight;
SELECT p.FK_Patient_Link_ID, p.EventDate AS DateOfFirstValue, MAX(p.Value) AS [Value]
INTO #PatientHeight 
FROM {param:gp-events-table} p
INNER JOIN #HEIGHT_TEMP1 sub ON sub.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND sub.EventDate = p.EventDate
WHERE SuppliedCode IN (SELECT code FROM #AllCodes WHERE Concept = 'height' AND Version = 1) 
{if:patients}
AND p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM {param:patients})
{endif:patients}
{if:all-patients=false}
AND p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
{endif:all-patients}
GROUP BY p.FK_Patient_Link_ID, p.EventDate;


-- standardise height values by converting to numeric, then converting to CM where the measurement is in M
IF OBJECT_ID('tempdb..#PatientHeightStandardised') IS NOT NULL DROP TABLE #PatientHeightStandardised;
SELECT p.FK_Patient_Link_ID, h.DateOfFirstValue, h.[Value],
	HeightInCm = CASE WHEN (TRY_CONVERT(DECIMAL(10,3), stuff([Value], 1, patindex('%[0-9]%', [Value])-1, ''))) BETWEEN 0.1 AND 3 
		THEN (TRY_CONVERT(DECIMAL(10,3), stuff([Value], 1, patindex('%[0-9]%', [Value])-1, ''))) * 100 
		ELSE (TRY_CONVERT(DECIMAL(10,3), stuff([Value], 1, patindex('%[0-9]%', [Value])-1, '')))
		END
INTO #PatientHeightStandardised 
FROM #Cohort p
LEFT OUTER JOIN #PatientHeight h ON h.FK_Patient_Link_ID = p.FK_Patient_Link_ID 
WHERE (TRY_CONVERT(DECIMAL(10,3), stuff([Value], 1, patindex('%[0-9]%', [Value])-1, ''))) BETWEEN 0.1 AND 300 -- filter out unreasonable values

-- repeat all of the above but for weight (no need for the standardisation, as always in KG)

--> CODESET weight:1 

IF OBJECT_ID('tempdb..#WEIGHT_TEMP1') IS NOT NULL DROP TABLE #WEIGHT_TEMP1;
{if:comparison=>}
  SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate
{endif:comparison}
{if:comparison=>=}
  SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate
{endif:comparison}
{if:comparison=<}
  SELECT FK_Patient_Link_ID, MAX(EventDate) AS EventDate
{endif:comparison}
{if:comparison=<=}
  SELECT FK_Patient_Link_ID, MAX(EventDate) AS EventDate
{endif:comparison}
INTO #WEIGHT_TEMP1
FROM {param:gp-events-table}
WHERE SuppliedCode IN (SELECT code FROM #AllCodes WHERE Concept = 'weight' AND Version = 1) 
AND EventDate {param:comparison} '{param:date}'
AND [Value] IS NOT NULL
AND [Value] != '0'
GROUP BY FK_Patient_Link_ID;

-- Then we join to that table in order to get the value of that measurement
IF OBJECT_ID('tempdb..#PatientWeight') IS NOT NULL DROP TABLE #PatientWeight;
SELECT p.FK_Patient_Link_ID, p.EventDate AS DateOfFirstValue, MAX(p.Value) AS [Value]
INTO #PatientWeight 
FROM {param:gp-events-table} p
INNER JOIN #WEIGHT_TEMP1 sub ON sub.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND sub.EventDate = p.EventDate
WHERE SuppliedCode IN (SELECT code FROM #AllCodes WHERE Concept = 'weight' AND Version = 1) 
{if:patients}
AND p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM {param:patients})
{endif:patients}
{if:all-patients=false}
AND p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
{endif:all-patients}
GROUP BY p.FK_Patient_Link_ID, p.EventDate;
