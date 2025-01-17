{if:verbose}
--┌───────────────────────────────────────────────┐
--│ Find the closest value to a particular date   │
--└───────────────────────────────────────────────┘

-- OBJECTIVE: To find the closest value for a particular test to a given date.

-- INPUT: A variable:
--  - min-value: number - the smallest permitted value. Values lower than this will be disregarded.
--  - max-value: number - the largest permitted value. Values higher than this will be disregarded.
--  - unit: string - if a particular unit is required can enter it here. If any then use '%'
--  - date: date - (YYYY-MM-DD) the date to look around
--  - comparison: inequality sign (>, <, >= or <=) e.g. if '>' then will look for the first value strictly after the date
--	-	all-patients: boolean - (true/false) if true, then all patients are included, otherwise only those in the pre-existing #Patients table.
--	- gp-events-table: string - (table name) the name of the table containing the GP events. Usually is "SharedCare.GP_Events" but can be anything with the columns: FK_Patient_Link_ID, EventDate, and SuppliedCode
--  - code-set: string - the name of the code set to be used. Must be one from the repository.
--  - version: number - the code set version
--  - temp-table-name: string - the name of the temp table that this will produce

-- OUTPUT: Temp tables as follows:
-- #Patients - list of patient ids of the cohort
{endif:verbose}

--> CODESET {param:code-set}:{param:version}

-- First we get the date of the nearest {param:code-set} measurement before/after
-- the index date
IF OBJECT_ID('tempdb..{param:temp-table-name}TEMP1') IS NOT NULL DROP TABLE {param:temp-table-name}TEMP1;
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
INTO {param:temp-table-name}TEMP1
FROM {param:gp-events-table}
WHERE SuppliedCode IN (SELECT code FROM #AllCodes WHERE Concept = '{param:code-set}' AND Version = {param:version}) 
AND EventDate {param:comparison} '{param:date}'
AND [Value] IS NOT NULL
AND [Value] != '0'
AND Units LIKE '{param:unit}'
-- as these are all tests, we can ignore values values outside the specified range
AND TRY_CONVERT(DECIMAL(10,3), [Value]) >= {param:min-value}
AND TRY_CONVERT(DECIMAL(10,3), [Value]) <= {param:max-value}
GROUP BY FK_Patient_Link_ID;

-- Then we join to that table in order to get the value of that measurement
IF OBJECT_ID('tempdb..{param:temp-table-name}') IS NOT NULL DROP TABLE {param:temp-table-name};
SELECT p.FK_Patient_Link_ID, p.EventDate AS DateOfFirstValue, MAX(p.Value) AS [Value]
INTO {param:temp-table-name}
FROM {param:gp-events-table} p
INNER JOIN {param:temp-table-name}TEMP1 sub ON sub.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND sub.EventDate = p.EventDate
WHERE SuppliedCode IN (SELECT code FROM #AllCodes WHERE Concept = '{param:code-set}' AND Version = {param:version}) 
{if:patients}
AND p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM {param:patients})
{endif:patients}
{if:all-patients=false}
AND p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
{endif:all-patients}
GROUP BY p.FK_Patient_Link_ID, p.EventDate;