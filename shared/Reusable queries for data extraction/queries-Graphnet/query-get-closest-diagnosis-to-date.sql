{if:verbose}
--┌───────────────────────────────────────────────────┐
--│ Find the closest diagnosis to a particular date   │
--└───────────────────────────────────────────────────┘

-- OBJECTIVE: To find the closest diagnosis for a particular disease and a given date.

-- INPUT: A variable:
--  - date: date - (YYYY-MM-DD) the date to look around
--  - comparison: inequality sign (>, <, >= or <=) e.g. if '>' then will look for the first value strictly after the date
--	-	all-patients: boolean - (true/false) if true, then all patients are included, otherwise only those in the pre-existing #Patients table.
--	- gp-events-table: string - (table name) the name of the table containing the GP events. Usually is "SharedCare.GP_Events" but can be anything with the columns: FK_Patient_Link_ID, EventDate, and SuppliedCode
--  - code-set: string - the name of the code set to be used. Must be one from the repository.
--  - version: number - the code set version
--  - temp-table-name: string - the name of the temp table that this will produce

-- OUTPUT: Temp tables as follows:
-- (temp table name specified in parameter) FK_Patient_Link_ID, EventDate
{endif:verbose}

--> CODESET {param:code-set}:{param:version}

-- First we get the date of the nearest {param:code-set} diagnosis before/after the specified date

IF OBJECT_ID('tempdb..{param:temp-table-name}') IS NOT NULL DROP TABLE {param:temp-table-name};
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
INTO {param:temp-table-name}
FROM {param:gp-events-table}
WHERE SuppliedCode IN (SELECT code FROM #AllCodes WHERE Concept = '{param:code-set}' AND Version = {param:version}) 
AND EventDate {param:comparison} '{param:date}'
{if:patients}
AND p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM {param:patients})
{endif:patients}
{if:all-patients=false}
AND p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
{endif:all-patients}
GROUP BY FK_Patient_Link_ID;
