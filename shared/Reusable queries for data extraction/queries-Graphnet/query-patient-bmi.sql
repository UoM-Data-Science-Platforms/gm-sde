--┌─────┐
--│ BMI │
--└─────┘

-- OBJECTIVE: To get the BMI for each patient in a cohort.

-- INPUT: Assumes there exists a temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort
-- Also takes one parameter:
--	- gp-events-table: string - (table name) the name of the table containing the GP events. Usually is "RLS.vw_GP_Events" but can be anything with the columns: FK_Patient_Link_ID, EventDate, FK_Reference_Coding_ID, and FK_Reference_SnomedCT_ID
-- Also assumes there is an @IndexDate defined - The index date of the study


-- OUTPUT: A temp table as follows:
-- #PatientBMI (FK_Patient_Link_ID, BMI, DateOfBMIMeasurement)
--	- FK_Patient_Link_ID - unique patient id
--  - BMI
--  - DateOfBMIMeasurement

-- ASSUMPTIONS:
--	- We take the measurement closest to @IndexDate to be correct

--> CODESET bmi:2

-- Get all BMI measurements 

IF OBJECT_ID('tempdb..#AllPatientBMI') IS NOT NULL DROP TABLE #AllPatientBMI;
SELECT 
	FK_Patient_Link_ID,
	CAST(EventDate AS DATE) AS EventDate,
	FK_Reference_Coding_ID,
	FK_Reference_SnomedCT_ID,
	[Value]
INTO #AllPatientBMI
FROM {param:gp-events-table}
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
	AND FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'bmi'AND [Version]=2) 
	AND EventDate <= @IndexDate
	AND TRY_CONVERT(NUMERIC(16,5), [Value]) BETWEEN 5 AND 100

UNION
SELECT 
	FK_Patient_Link_ID,
	CAST(EventDate AS DATE) AS EventDate,
	FK_Reference_Coding_ID,
	FK_Reference_SnomedCT_ID,
	[Value]
FROM {param:gp-events-table}
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
	AND FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'bmi' AND [Version]=2)
	AND EventDate <= @IndexDate
	AND TRY_CONVERT(NUMERIC(16,5), [Value]) BETWEEN 5 AND 100


-- For closest BMI prior to index date
IF OBJECT_ID('tempdb..#TempCurrentBMI') IS NOT NULL DROP TABLE #TempCurrentBMI;
SELECT 
	a.FK_Patient_Link_ID, 
	Max([Value]) as [Value],
	Max(EventDate) as EventDate
INTO #TempCurrentBMI
FROM #AllPatientBMI a
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(EventDate) AS MostRecentDate 
	FROM #AllPatientBMI
	GROUP BY FK_Patient_Link_ID
) sub ON sub.MostRecentDate = a.EventDate and sub.FK_Patient_Link_ID = a.FK_Patient_Link_ID
GROUP BY a.FK_Patient_Link_ID;

-- Bring all together in final table
IF OBJECT_ID('tempdb..#PatientBMI') IS NOT NULL DROP TABLE #PatientBMI;
SELECT 
	p.FK_Patient_Link_ID,
	BMI = TRY_CONVERT(NUMERIC(16,5), [Value]),
	EventDate AS DateOfBMIMeasurement
INTO #PatientBMI 
FROM #Patients p
LEFT OUTER JOIN #TempCurrentBMI c on c.FK_Patient_Link_ID = p.FK_Patient_Link_ID