{if:verbose}
--┌─────────────────────────────────────────────┐
--│ Find the first prescription of a medication │
--└─────────────────────────────────────────────┘

-- OBJECTIVE: To find the first prescription of a particular medication for each patient

-- INPUT: A variable:
--  -	all-patients: boolean - (true/false) if true, then all patients are included, otherwise only those in the pre-existing #Patients table.
--  - gp-medications-table: string - (table name) the name of the table containing the GP medications. Usually is "SharedCare.GP_Medications" but can be anything with the columns: FK_Patient_Link_ID, MedicationDate, and SuppliedCode
--  - code-set: string - the name of the code set to be used. Must be one from the repository.
--  - version: number - the code set version
--  - temp-table-name: string - the name of the temp table that this will produce

-- OUTPUT: Temp table `temp-table-name`
--	- FK_Patient_Link_ID - unique patient id
--	- FirstPrescriptionDate - date (YYYY-MM-DD) date of first prescription
{endif:verbose}

--> CODESET {param:code-set}:{param:version}
IF OBJECT_ID('tempdb..{param:temp-table-name}') IS NOT NULL DROP TABLE {param:temp-table-name};
SELECT FK_Patient_Link_ID, MIN(CAST(MedicationDate AS DATE)) AS FirstPrescriptionDate
INTO {param:temp-table-name}
FROM {param:gp-medications-table}
WHERE SuppliedCode IN (
	SELECT [Code] FROM #AllCodes WHERE [Concept] = '{param:code-set}' AND [Version] = {param:version}
)
{if:all-patients=false}
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
{endif:all-patients}
GROUP BY FK_Patient_Link_ID;
