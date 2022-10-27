{if:verbose}
--┌───────────────────────────────────┐
--│ Electronic Frailty Index subquery │
--└───────────────────────────────────┘

-- OBJECTIVE: Subquery for the EFI calculation to ensure consistency. This allows a code with a value
--            within a range to be counted towards a deficit

-- INPUT: Assumes there exists a temp table #EfiEvents(FK_Patient_Link_ID, Deficit, EventDate) and 
--        a temp table #EfiValueData(FK_Patient_Link_ID, EventDate, SuppliedCode, Value)
--  ALso takes three parameters
--  - efi-category: string - e.g. "activity-limitation" to match the "efi-activity-limitation" code set
--	-	all-patients: boolean - (true/false) if false, then only those in the pre-existing #Patients table are included, otherwise everyone.
--	-	patients: temp table name - OPTIONAL - e.g. "#Patients" allows filtering to just some patients
--	- supplied-codes: string - (of form 'code','code2',...,'coden') the codes to include
--  - min-value: int - OPTIONAL - The minimum value to count. Strict inequality so "0" would become >0
--  - max-value: int - OPTIONAL - The maximum value to count. Strict inequality so "0" would become <0
-- OUTPUT: None. This populates the pre-existing #EfiEvents table with the first time the patient experienced the deficit specified by the efi-category.
{endif:verbose}

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, '{param:efi-category}' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #EfiValueData
WHERE SuppliedCode IN ({param:supplied-codes})
{if:min-value}
AND [Value] > {param:min-value}
{endif:min-value}
{if:max-value}
AND [Value] < {param:max-value}
{endif:max-value}
{if:patients}
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM {param:patients})
{endif:patients}
{if:all-patients=false}
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
{endif:all-patients}
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;