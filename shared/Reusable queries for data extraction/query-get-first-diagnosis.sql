{if:verbose}
--┌────────────────────────────────────────────────────┐
--│ Find the first diagnosis of a particular disease   │
--└────────────────────────────────────────────────────┘

-- OBJECTIVE: To find the first diagnosis for a particular disease for every patient.

-- INPUT: A variable:
--	-	all-patients: boolean - (true/false) if true, then all patients are included, otherwise only those in the pre-existing #Patients table.
--	- gp-events-table: string - (table name) the name of the table containing the GP events. Usually is "SharedCare.GP_Events" but can be anything with the columns: FK_Patient_Link_ID, EventDate, and SuppliedCode
--  - code-set: string - the name of the code set to be used. Must be one from the repository.
--  - version: number - the code set version
--  - temp-table-name: string - the name of the temp table that this will produce

-- OUTPUT: Temp table with the name of the provided parameter `temp-table-name` with columns:
--	-	FK_Patient_Link_ID - unique patient id
--	-	DateOfFirstDiagnosis - date (YYY/MM/DD) - the date of the first diagnosis
{endif:verbose}

--> CODESET {param:code-set}:{param:version}
-- We find the first occurrence of the relevant code for each patient. For performance reasons
-- we first search by FK_Reference_Coding_ID, and then later, separately, for FK_Reference_SnomedCT_ID.
-- Combining these into an OR statement in a WHERE clause in a single query is substantially slower than
-- searching for each individually and then combining.
IF OBJECT_ID('tempdb..{param:temp-table-name}temppart1') IS NOT NULL DROP TABLE {param:temp-table-name}temppart1;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS DateOfFirstDiagnosis
INTO {param:temp-table-name}temppart1
FROM {param:gp-events-table}
WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = '{param:code-set}' AND Version = {param:version})
{if:all-patients=false}
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
{endif:all-patients}
GROUP BY FK_Patient_Link_ID;

-- As per above now we find the first instance of the code based on the FK_Reference_SnomedCT_ID
IF OBJECT_ID('tempdb..{param:temp-table-name}temppart2') IS NOT NULL DROP TABLE {param:temp-table-name}temppart2;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS DateOfFirstDiagnosis
INTO {param:temp-table-name}temppart2
FROM {param:gp-events-table}
WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = '{param:code-set}' AND Version = {param:version})
{if:patients}
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM {param:patients})
{endif:patients}
{if:all-patients=false}
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
{endif:all-patients}
GROUP BY FK_Patient_Link_ID;

-- We now join the two tables above. By doing a FULL JOIN we include all records from both tables.
-- In each row, at least one of the DateOfFirstDiagnosis will be non NULL. Therefore if one field
-- is NULL, then we use the other. If both are non NULL, then we take the earliest as the goal is
-- to get the first occurrence of the code for each patient.
IF OBJECT_ID('tempdb..{param:temp-table-name}') IS NOT NULL DROP TABLE {param:temp-table-name};
SELECT
	CASE WHEN p1.FK_Patient_Link_ID IS NULL THEN p2.FK_Patient_Link_ID ELSE p1.FK_Patient_Link_ID END AS FK_Patient_Link_ID,
	CASE
		WHEN p1.DateOfFirstDiagnosis IS NULL THEN p2.DateOfFirstDiagnosis
		WHEN p2.DateOfFirstDiagnosis IS NULL THEN p1.DateOfFirstDiagnosis
		WHEN p1.DateOfFirstDiagnosis < p2.DateOfFirstDiagnosis THEN p1.DateOfFirstDiagnosis
		ELSE p2.DateOfFirstDiagnosis
	END AS DateOfFirstDiagnosis
INTO {param:temp-table-name}
FROM {param:temp-table-name}temppart1 p1
FULL JOIN {param:temp-table-name}temppart2 p2 on p1.FK_Patient_Link_ID = p2.FK_Patient_Link_ID
