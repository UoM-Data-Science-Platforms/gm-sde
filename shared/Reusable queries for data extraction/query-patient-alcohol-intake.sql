--┌────────────────┐
--│ Alcohol Intake │
--└────────────────┘

-- OBJECTIVE: To get the alcohol status for each patient in a cohort.

-- INPUT: Assumes there exists a temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort
-- Also takes one parameter:
--	- gp-events-table: string - (table name) the name of the table containing the GP events. Usually is "RLS.vw_GP_Events" but can be anything with the columns: FK_Patient_Link_ID, EventDate, FK_Reference_Coding_ID, and FK_Reference_SnomedCT_ID

-- OUTPUT: A temp table as follows:
-- #PatientAlcoholIntake (FK_Patient_Link_ID, CurrentAlcoholIntake)
--	- FK_Patient_Link_ID - unique patient id
--  - WorstAlcoholIntake - [heavy drinker/moderate drinker/light drinker/non-drinker] - worst code
--	- CurrentAlcoholIntake - [heavy drinker/moderate drinker/light drinker/non-drinker] - most recent code

-- ASSUMPTIONS:
--	- We take the most recent alcohol intake code in a patient's record to be correct

--> CODESET alcohol-non-drinker:1 alcohol-light-drinker:1 alcohol-moderate-drinker:1 alcohol-heavy-drinker:1 alcohol-weekly-intake:1

-- Get all patients year of birth for the cohort
IF OBJECT_ID('tempdb..#AllPatientAlcoholIntakeCodes') IS NOT NULL DROP TABLE #AllPatientAlcoholIntakeCodes;
SELECT 
	FK_Patient_Link_ID,
	CAST(EventDate AS DATE) AS EventDate,
	FK_Reference_Coding_ID,
	FK_Reference_SnomedCT_ID,
	[Value]
INTO #AllPatientAlcoholIntakeCodes
FROM {param:gp-events-table}
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_SnomedCT_ID IN (
	SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets 
	WHERE Concept IN (
	'alcohol-non-drinker', 
	'alcohol-light-drinker',
	'alcohol-moderate-drinker',
	'alcohol-heavy-drinker',
	'alcohol-weekly-intake'
	)
	AND [Version]=1
) 
UNION
SELECT 
	FK_Patient_Link_ID,
	CAST(EventDate AS DATE) AS EventDate,
	FK_Reference_Coding_ID,
	FK_Reference_SnomedCT_ID,
	[Value]
FROM {param:gp-events-table}
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets 
	WHERE Concept IN (
	'alcohol-non-drinker', 
	'alcohol-light-drinker',
	'alcohol-moderate-drinker',
	'alcohol-heavy-drinker',
	'alcohol-weekly-intake'
	)
	AND [Version]=1
);

IF OBJECT_ID('tempdb..#AllPatientAlcoholIntakeConcept') IS NOT NULL DROP TABLE #AllPatientAlcoholIntakeConcept;
SELECT 
	a.FK_Patient_Link_ID,
	EventDate,
	CASE WHEN c.Concept IS NULL THEN s.Concept ELSE c.Concept END AS Concept,
	-1 AS Severity,
	[Value]
INTO #AllPatientAlcoholIntakeConcept
FROM #AllPatientAlcoholIntakeCodes a
LEFT OUTER JOIN #VersionedCodeSets c on c.FK_Reference_Coding_ID = a.FK_Reference_Coding_ID
LEFT OUTER JOIN #VersionedSnomedSets s on s.FK_Reference_SnomedCT_ID = a.FK_Reference_SnomedCT_ID;

UPDATE #AllPatientAlcoholIntakeConcept
SET Severity = 3
WHERE Concept = 'alcohol-heavy-drinker' OR (Concept = 'alcohol-weekly-intake' AND TRY_CONVERT(NUMERIC(16,5), [Value]) > 14) ;
UPDATE #AllPatientAlcoholIntakeConcept
SET Severity = 2
WHERE Concept = 'alcohol-moderate-drinker' OR (Concept = 'alcohol-weekly-intake' AND TRY_CONVERT(NUMERIC(16,5), [Value]) BETWEEN 7 AND 14);
UPDATE #AllPatientAlcoholIntakeConcept
SET Severity = 1
WHERE Concept = 'alcohol-light-drinker' OR (Concept = 'alcohol-weekly-intake' AND TRY_CONVERT(NUMERIC(16,5), [Value]) BETWEEN 0 AND 7);
UPDATE #AllPatientAlcoholIntakeConcept
SET Severity = 0
WHERE Concept = 'alcohol-non-drinker' OR (Concept = 'alcohol-weekly-intake' AND TRY_CONVERT(NUMERIC(16,5), [Value]) = 0 );

-- For "worst" alcohol intake
IF OBJECT_ID('tempdb..#TempWorstAlc') IS NOT NULL DROP TABLE #TempWorstAlc;
SELECT 
	FK_Patient_Link_ID, 
	CASE 
		WHEN MAX(Severity) = 3 THEN 'heavy drinker'
		WHEN MAX(Severity) = 2 THEN 'moderate drinker'
		WHEN MAX(Severity) = 1 THEN 'light drinker'
		WHEN MAX(Severity) = 0 THEN 'non-drinker'
	END AS [Status]
INTO #TempWorstAlc
FROM #AllPatientAlcoholIntakeConcept
WHERE Severity >= 0
GROUP BY FK_Patient_Link_ID;

-- For "current" alcohol intake
IF OBJECT_ID('tempdb..#TempCurrentAlc') IS NOT NULL DROP TABLE #TempCurrentAlc;
SELECT 
	a.FK_Patient_Link_ID, 
	CASE 
		WHEN MAX(Severity) = 3 THEN 'heavy drinker'
		WHEN MAX(Severity) = 2 THEN 'moderate drinker'
		WHEN MAX(Severity) = 1 THEN 'light drinker'
		WHEN MAX(Severity) = 0 THEN 'non-drinker'
	END AS [Status]
INTO #TempCurrentAlc
FROM #AllPatientAlcoholIntakeConcept a
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(EventDate) AS MostRecentDate FROM #AllPatientAlcoholIntakeConcept
	WHERE Severity >= 0
	GROUP BY FK_Patient_Link_ID
) sub ON sub.MostRecentDate = a.EventDate and sub.FK_Patient_Link_ID = a.FK_Patient_Link_ID
GROUP BY a.FK_Patient_Link_ID;

-- Bring all together in final table
IF OBJECT_ID('tempdb..#PatientAlcoholIntake') IS NOT NULL DROP TABLE #PatientAlcoholIntake;
SELECT 
	p.FK_Patient_Link_ID,
	CASE WHEN w.[Status] IS NULL THEN 'non-drinker' ELSE w.[Status] END AS WorstAlcoholIntake,
	CASE WHEN c.[Status] IS NULL THEN 'non-drinker' ELSE c.[Status] END AS CurrentAlcoholIntake
INTO #PatientAlcoholIntake FROM #Patients p
LEFT OUTER JOIN #TempWorstAlc w on w.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #TempCurrentAlc c on c.FK_Patient_Link_ID = p.FK_Patient_Link_ID;