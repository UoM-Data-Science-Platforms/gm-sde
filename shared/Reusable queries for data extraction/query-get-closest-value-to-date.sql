{if:verbose}
--┌───────────────────────────────────────────────┐
--│ Find the closest value to a particular date   │
--└───────────────────────────────────────────────┘

-- OBJECTIVE: To find the first diagnosis for a particular disease for every patient.

-- INPUT: A variable:
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
SELECT p.FK_Patient_Link_ID, p.EventDate AS DateOfFirstValue, MAX(p.Value) AS [Value]
INTO {param:temp-table-name}
FROM {param:gp-events-table} p
INNER JOIN (
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
  FROM {param:gp-events-table}
  WHERE (
    FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = '{param:code-set}' AND Version = {param:version}) OR
    FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = '{param:code-set}' AND Version = {param:version})
  )
  AND EventDate {param:comparison} '{param:date}'
  AND [Value] IS NOT NULL
  AND [Value] != '0'
  GROUP BY FK_Patient_Link_ID
) sub ON sub.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND sub.EventDate = p.EventDate
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = '{param:code-set}' AND Version = {param:version}) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = '{param:code-set}' AND Version = {param:version})
)
{if:patients}
AND p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM {param:patients})
{endif:patients}
{if:all-patients=false}
AND p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
{endif:all-patients}
GROUP BY p.FK_Patient_Link_ID, p.EventDate;