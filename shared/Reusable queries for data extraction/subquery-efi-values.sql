--┌───────────────────────────────────┐
--│ Electronic Frailty Index subquery │
--└───────────────────────────────────┘

-- OBJECTIVE: Subquery for the EFI calculation to ensure consistency. This allows a code with a value
--            within a range to be counted towards a deficit

-- INPUT: Assumes there exists a temp table #EfiEvents(FK_Patient_Link_ID, Deficit, EventDate) and 
--        a temp table #EfiValueData(FK_Patient_Link_ID, EventDate, SuppliedCode, Value)
--  ALso takes three parameters
--  - efi-category: string - e.g. "activity-limitation" to match the "efi-activity-limitation" code set
--	-	all-patients: boolean - (true/false) if true, then all patients are included, otherwise only those in the pre-existing #Patients table.
--	- supplied-codes: string - (of form 'code','code2',...,'coden') the codes to include
--  - min-value: int - The minimum value to count. Strict inequality so "0" would become >0
--  - max-value: int - The maximum value to count. Strict inequality so "0" would become <0
-- OUTPUT: None. This populates the pre-existing #EfiEvents table with the first time the patient experienced the deficit specified by the efi-category.

BEGIN
  IF '{param:all-patients}'='true'
    INSERT INTO #EfiEvents
    SELECT FK_Patient_Link_ID, '{param:efi-category}' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
    FROM #EfiValueData
    WHERE SuppliedCode IN ({param:supplied-codes})
		AND [Value] > {param:min-value}
    AND [Value] < {param:max-value}
    AND EventDate <= GETDATE()
    GROUP BY FK_Patient_Link_ID;
  ELSE
    INSERT INTO #EfiEvents
    SELECT FK_Patient_Link_ID, '{param:efi-category}' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
    FROM #EfiValueData
    WHERE SuppliedCode IN ({param:supplied-codes})
		AND [Value] > {param:min-value}
    AND [Value] < {param:max-value}
    AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
    AND EventDate <= GETDATE()
    GROUP BY FK_Patient_Link_ID;
  END
END