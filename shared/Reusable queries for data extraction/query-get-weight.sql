{if:verbose}
--┌──────────────────────────┐
--│ Gets a patient's Weight  │
--└──────────────────────────┘

-- OBJECTIVE: Gets the most recent measurement of a person's Weight, in kilograms

-- INPUT: A variable:
--  -   date: date - (yyyy-mm-dd) the date for which you want to find the most recent measurement 
--  -	all-patients: boolean - (true/false) if true, then all patients are included, otherwise only those in the pre-existing #Patients table.
--  -	gp-events-table: string - (table name) the name of the table containing the GP events. Usually is "SharedCare.GP_Events" but can be anything with the columns: FK_Patient_Link_ID, EventDate, and SuppliedCode

-- OUTPUT: Temp table called #PatientWeight with columns:
--	-	FK_Patient_Link_ID - unique patient id
--	-   WeightInKilograms - int - the most recent Weight measurement before the specified date, in kg
--	-	WeightDate - date (YYYY/MM/DD) - the date of the most recent Weight measurement before the specified date
{endif:verbose}

--> CODESET weight:1 
-- this code set also gets added in lines 32 and 35, but doing it here allows us to create the #GPEvents table directly below

-- Create a smaller version of GP event table===========================================================================================================
IF OBJECT_ID('tempdb..#GPEvents') IS NOT NULL DROP TABLE #GPEvents;
SELECT gp.FK_Patient_Link_ID, EventDate, SuppliedCode, FK_Reference_Coding_ID, FK_Reference_SnomedCT_ID, [Value], Units
INTO #GPEvents
FROM SharedCare.GP_Events gp
	WHERE SuppliedCode IN (SELECT code FROM #AllCodes WHERE Concept = 'weight' AND Version = 1) 
	AND gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)


-- Weight is almost always recorded in kilograms, so
-- first we get the most recent value for Weight where the unit is 'kg'
--> EXECUTE query-get-closest-value-to-date.sql all-patients:false min-value:0.1 max-value:500 unit:kg date:{param:date} comparison:<= gp-events-table:{param:gp-events-table} code-set:weight version:1 temp-table-name:#PatientWeightInKilograms

-- NB the units are standardised so 'kg' dominates. You do not get units like 'kilograms'.

-- now include records that don't have a unit value but have a Weight recording (there are only useful records with NULL for unit, not a blank value)

IF OBJECT_ID('tempdb..#PatientWeightNoUnitsTEMP1') IS NOT NULL DROP TABLE #PatientWeightNoUnitsTEMP1;
SELECT  FK_Patient_Link_ID, MAX(EventDate) AS EventDate
INTO #PatientWeightNoUnitsTEMP1
FROM {param:gp-events-table} 
WHERE Units IS NULL 
	AND Value IS NOT NULL
	AND Value <> ''
	AND TRY_CONVERT(DECIMAL(10,3), stuff([Value], 1, patindex('%[0-9]%', [Value])-1, '')) BETWEEN 0.1 AND 500
	AND TRY_CONVERT(DECIMAL(10,3), stuff([Value], 1, patindex('%[0-9]%', [Value])-1, '')) != 0
	AND EventDate <= '{param:date}'
	AND SuppliedCode IN (SELECT code FROM #AllCodes WHERE Concept = 'weight' AND Version = 1) 
{if:all-patients=false}
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
{endif:all-patients}
GROUP BY FK_Patient_Link_ID

IF OBJECT_ID('tempdb..#PatientWeightNoUnits') IS NOT NULL DROP TABLE #PatientWeightNoUnits;
SELECT p.FK_Patient_Link_ID, p.EventDate AS DateOfFirstValue, MAX(p.Value) AS [Value]
INTO #PatientWeightNoUnits
FROM {param:gp-events-table} p
INNER JOIN #PatientWeightNoUnitsTEMP1 sub ON sub.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND sub.EventDate = p.EventDate
WHERE SuppliedCode IN (SELECT code FROM #AllCodes WHERE Concept = 'weight' AND Version = 1) 
{if:patients}
AND p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM {param:patients})
{endif:patients}
{if:all-patients=false}
AND p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
{endif:all-patients}
GROUP BY p.FK_Patient_Link_ID, p.EventDate;

-- Create the output PatientWeight temp table. We combine the m and cm tables from above
-- to find the most recent Weight for each person. We multiply the Weight in metres by 100
-- to standardise the output to Kilograms.
IF OBJECT_ID('tempdb..#PatientWeight') IS NOT NULL DROP TABLE #PatientWeight;
SELECT 
	wkg.FK_Patient_Link_ID,
	WeightInKilograms = TRY_CONVERT(DECIMAL(10,3), stuff(wkg.[Value], 1, patindex('%[0-9]%', wkg.[Value])-1, '')),
	WeightDate = wkg.DateOfFirstValue 
INTO #PatientWeight
FROM #PatientWeightInKilograms wkg
UNION ALL
SELECT 
	wno.FK_Patient_Link_ID,
	WeightInKilograms = TRY_CONVERT(DECIMAL(10,3), stuff([Value], 1, patindex('%[0-9]%', [Value])-1, '')),
	WeightDate = DateOfFirstValue
FROM #PatientWeightNoUnits wno