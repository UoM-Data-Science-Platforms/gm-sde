{if:verbose}
--┌───────────────────────────────────┐
--│ Electronic Frailty Index subquery │
--└───────────────────────────────────┘

-- OBJECTIVE: Subquery for the EFI calculation to ensure consistency instead of copy/pasting the same code 35 times.

-- INPUT: Assumes there exists a temp table #EfiEvents(FK_Patient_Link_ID, Deficit, EventDate)
--  ALso takes three parameters
--  - efi-category: string - e.g. "activity-limitation" to match the "efi-activity-limitation" code set
--	- gp-events-table: string - (table name) the name of the table containing the GP events. Usually is "SharedCare.GP_Events" but can be anything with the columns: FK_Patient_Link_ID, EventDate, and SuppliedCode

-- OUTPUT: None. This populates the pre-existing #EfiEvents table with the first time the patient experienced the deficit specified by the efi-category.
{endif:verbose}

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, '{param:efi-category}' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM {param:gp-events-table}
WHERE SuppliedCode IN (
  select Code from #AllCodes 
  where Concept = 'efi-{param:efi-category}'
  AND Version = 1
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;