{if:verbose}
--┌──────────────────────────────────────────────┐
--│ Find the most recent value for a given code  │
--└──────────────────────────────────────────────┘

-- OBJECTIVE: For a given code set, find the most recent value

-- INPUT: A variable:
--  - min-value: number - the smallest permitted value. Values lower than this will be disregarded.
--  - max-value: number - the largest permitted value. Values higher than this will be disregarded.
--  - unit: string - if a particular unit is required can enter it here. If any then use '%'
--  -	all-patients: boolean - (true/false) if true, then all patients are included, otherwise only those in the pre-existing #Patients table.
--  - gp-events-table: string - (table name) the name of the table containing the GP events. Usually is "SharedCare.GP_Events" but can be anything with the columns: FK_Patient_Link_ID, EventDate, and SuppliedCode
--  - code-set: string - the name of the code set to be used. Must be one from the repository.
--  - version: number - the code set version
--  - max-or-min: string (max/min) if two or more values on the same day should we choose the max or min
--  - temp-table-name: string - the name of the temp table that this will produce

-- OUTPUT: Temp table `temp-table-name` with columns:
--  - FK_Patient_Link_ID - unique patient id
--  - MostRecentDate - date (YYYY/MM/DD) - date of the most recent value
--  - MostRecentValue - float - the most recent value
{endif:verbose}

--> CODESET {param:code-set}:{param:version}
IF OBJECT_ID('tempdb..{param:temp-table-name}temp1') IS NOT NULL DROP TABLE {param:temp-table-name}temp1;
SELECT FK_Patient_Link_ID, MAX(EventDate) AS MostRecentDate
INTO {param:temp-table-name}temp1
FROM {param:gp-events-table} p
WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = '{param:code-set}' AND Version = {param:version})
AND [Value] IS NOT NULL
AND [Value] >= {param:min-value}
AND [Value] <= {param:max-value}
AND Units LIKE '{param:unit}'
AND EventDate IS NOT NULL
{if:all-patients=false}
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
{endif:all-patients}
GROUP BY FK_Patient_Link_ID;

IF OBJECT_ID('tempdb..{param:temp-table-name}temp2') IS NOT NULL DROP TABLE {param:temp-table-name}temp2;
SELECT FK_Patient_Link_ID, MAX(EventDate) AS MostRecentDate
INTO {param:temp-table-name}temp2
FROM {param:gp-events-table} p
WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = '{param:code-set}' AND Version = {param:version})
AND [Value] IS NOT NULL
AND [Value] >= {param:min-value}
AND [Value] <= {param:max-value}
AND Units LIKE '{param:unit}'
AND EventDate IS NOT NULL
{if:all-patients=false}
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
{endif:all-patients}
GROUP BY FK_Patient_Link_ID;

IF OBJECT_ID('tempdb..{param:temp-table-name}temp3') IS NOT NULL DROP TABLE {param:temp-table-name}temp3;
SELECT 
  CASE WHEN t1.FK_Patient_Link_ID IS NULL THEN t2.FK_Patient_Link_ID ELSE t1.FK_Patient_Link_ID END AS FK_Patient_Link_ID,
	CASE
		WHEN t1.MostRecentDate IS NULL THEN t2.MostRecentDate
		WHEN t2.MostRecentDate IS NULL THEN t1.MostRecentDate
		WHEN t1.MostRecentDate < t2.MostRecentDate THEN t2.MostRecentDate
		ELSE t1.MostRecentDate
	END AS MostRecentDate
INTO {param:temp-table-name}temp3
FROM {param:temp-table-name}temp1 t1	
FULL JOIN {param:temp-table-name}temp2 t2 on t1.FK_Patient_Link_ID = t2.FK_Patient_Link_ID;

IF OBJECT_ID('tempdb..{param:temp-table-name}') IS NOT NULL DROP TABLE {param:temp-table-name};
SELECT
  t3.FK_Patient_Link_ID,
  MAX(t3.MostRecentDate) AS MostRecentDate,
{if:max-or-min=max}
  MAX([Value]) AS MostRecentValue
{endif:max-or-min}
{if:max-or-min=min}
  MIN([Value]) AS MostRecentValue
{endif:max-or-min}
INTO {param:temp-table-name}
FROM {param:temp-table-name}temp3 t3
LEFT OUTER JOIN {param:gp-events-table} gp ON gp.FK_Patient_Link_ID = t3.FK_Patient_Link_ID AND gp.EventDate = t3.MostRecentDate
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = '{param:code-set}' AND Version = {param:version}) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = '{param:code-set}' AND Version = {param:version})
)
AND [Value] IS NOT NULL
AND [Value] >= {param:min-value}
AND [Value] <= {param:max-value}
AND Units LIKE '{param:unit}'
GROUP BY t3.FK_Patient_Link_ID;
