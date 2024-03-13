{if:verbose}
--┌──────────────────────────┐
--│ Gets a patient's height  │
--└──────────────────────────┘

-- OBJECTIVE: Gets the most recent measurement of a person's height

-- INPUT: A variable:
--  -   date: date - (yyyy-mm-dd) the date for which you want to find the most recent measurement 
--  -	all-patients: boolean - (true/false) if true, then all patients are included, otherwise only those in the pre-existing #Patients table.
--  -	gp-events-table: string - (table name) the name of the table containing the GP events. Usually is "SharedCare.GP_Events" but can be anything with the columns: FK_Patient_Link_ID, EventDate, and SuppliedCode

-- OUTPUT: Temp table called #PatientHeight with columns:
--	-	FK_Patient_Link_ID - unique patient id
--	-   HeightInCentimetres - int - the most recent height measurement before the specified date, in cm
--	-	HeightDate - date (YYYY/MM/DD) - the date of the most recent height measurement before the specified date
{endif:verbose}

-- Height is almost always recorded in either metres or centimetres, so
-- first we get the most recent value for height where the unit is 'm'
--> EXECUTE query-get-closest-value-to-date.sql all-patients:false min-value:0.01 max-value:2.5 unit:m date:{param:date} comparison:<= gp-events-table:{param:gp-events-table} code-set:height version:1 temp-table-name:#PatientHeightInMetres

-- Now we do the same but for 'cm'
--> EXECUTE query-get-closest-value-to-date.sql all-patients:false min-value:10 max-value:250 unit:cm date:{param:date} comparison:<= gp-events-table:{param:gp-events-table} code-set:height version:1 temp-table-name:#PatientHeightInCentimetres
-- NB the units are standardised so 'm' and 'cm' dominate. You do not get units like 'metres'.

-- now include records that don't have a unit value but have a height recording (there are only useful records with NULL for unit, not a blank value)

IF OBJECT_ID('tempdb..#PatientHeightNoUnitsTEMP1') IS NOT NULL DROP TABLE #PatientHeightNoUnitsTEMP1;
SELECT  FK_Patient_Link_ID, MAX(EventDate) AS EventDate
INTO #PatientHeightNoUnitsTEMP1
FROM {param:gp-events-table} 
WHERE Units IS NULL 
	AND Value IS NOT NULL
	AND Value <> ''
	AND TRY_CONVERT(DECIMAL(10,3), stuff([Value], 1, patindex('%[0-9]%', [Value])-1, '')) != 0
	AND EventDate <= '{param:date}'
	AND SuppliedCode IN (SELECT code FROM #AllCodes WHERE Concept = 'height' AND Version = 1) 
{if:all-patients=false}
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
{endif:all-patients}
GROUP BY FK_Patient_Link_ID

IF OBJECT_ID('tempdb..#PatientHeightNoUnits') IS NOT NULL DROP TABLE #PatientHeightNoUnits;
SELECT p.FK_Patient_Link_ID, p.EventDate AS DateOfFirstValue, MAX(p.Value) AS [Value]
INTO #PatientHeightNoUnits
FROM {param:gp-events-table} p
INNER JOIN #PatientHeightNoUnitsTEMP1 sub ON sub.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND sub.EventDate = p.EventDate
WHERE SuppliedCode IN (SELECT code FROM #AllCodes WHERE Concept = 'height' AND Version = 1) 
{if:patients}
AND p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM {param:patients})
{endif:patients}
{if:all-patients=false}
AND p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
{endif:all-patients}
GROUP BY p.FK_Patient_Link_ID, p.EventDate;

-- Create the output PatientHeight temp table. We combine the m and cm tables from above
-- to find the most recent height for each person. We multiply the height in metres by 100
-- to standardise the output to centimetres.
IF OBJECT_ID('tempdb..#PatientHeight') IS NOT NULL DROP TABLE #PatientHeight;
SELECT 
	CASE WHEN hm.FK_Patient_Link_ID IS NULL THEN hcm.FK_Patient_Link_ID ELSE hm.FK_Patient_Link_ID END AS FK_Patient_Link_ID,
	CASE
		WHEN hm.FK_Patient_Link_ID IS NULL THEN TRY_CONVERT(DECIMAL(10,3), stuff(hcm.[Value], 1, patindex('%[0-9]%', hcm.[Value])-1, ''))
		WHEN hcm.FK_Patient_Link_ID IS NULL THEN TRY_CONVERT(DECIMAL(10,3), stuff(hm.[Value], 1, patindex('%[0-9]%', hm.[Value])-1, '')) * 100
		WHEN hm.DateOfFirstValue > hcm.DateOfFirstValue THEN TRY_CONVERT(DECIMAL(10,3), stuff(hm.[Value], 1, patindex('%[0-9]%', hm.[Value])-1, '')) * 100
		ELSE TRY_CONVERT(DECIMAL(10,3), stuff(hcm.[Value], 1, patindex('%[0-9]%', hcm.[Value])-1, ''))
	END AS HeightInCentimetres,
	CASE
		WHEN hm.FK_Patient_Link_ID IS NULL THEN hcm.DateOfFirstValue
		WHEN hcm.FK_Patient_Link_ID IS NULL THEN hm.DateOfFirstValue
		WHEN hm.DateOfFirstValue > hcm.DateOfFirstValue THEN hm.DateOfFirstValue
		ELSE hcm.DateOfFirstValue
	END AS HeightDate
INTO #PatientHeight
FROM #PatientHeightInCentimetres hcm
FULL JOIN #PatientHeightInMetres hm ON hm.FK_Patient_Link_ID = hcm.FK_Patient_Link_ID
UNION ALL
SELECT 
	hno.FK_Patient_Link_ID,
	CASE WHEN (TRY_CONVERT(DECIMAL(10,3), stuff([Value], 1, patindex('%[0-9]%', [Value])-1, ''))) BETWEEN 0.01 AND 2.5 
	THEN (TRY_CONVERT(DECIMAL(10,3), stuff([Value], 1, patindex('%[0-9]%', [Value])-1, ''))) * 100 
		ELSE (TRY_CONVERT(DECIMAL(10,3), stuff([Value], 1, patindex('%[0-9]%', [Value])-1, '')))
		END,
	HeightDate = DateOfFirstValue
FROM #PatientHeightNoUnits hno