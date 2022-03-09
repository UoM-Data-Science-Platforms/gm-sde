--┌───────────────┐
--│ Frailty score │
--└───────────────┘

-- OBJECTIVE: To get the frailty score for each patient.

-- INPUT: Assumes there exists a temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: A temp table as follows:
-- #PatientFrailtyScore (FK_Patient_Link_ID, FrailtyScore)
-- 	- FK_Patient_Link_ID - unique patient id
--	- FrailtyScore - FLOAT

-- ASSUMPTIONS:
--	- Patient data is obtained from multiple sources. Where patients have multiple frailty scores we determine the frailty score as follows:
--	-	If every frailty score is the same for a patient (ignoring nulls) then we use that
--	-	If there is a single most recently updated frailty score in the database then we use that
--	-	Otherwise we take the highest frailty score for the patient on the basis that frailty is unlikely to revers

-- Get all patients year of birth for the cohort
IF OBJECT_ID('tempdb..#AllPatientFrailtyScores') IS NOT NULL DROP TABLE #AllPatientFrailtyScores;
SELECT 
	FK_Patient_Link_ID,
	FK_Reference_Tenancy_ID,
	HDMModifDate,
	FrailtyScore
INTO #AllPatientFrailtyScores
FROM RLS.vw_Patient p
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FrailtyScore IS NOT NULL;

-- If every fraitly score is the same for all their linked patient ids then we use that
IF OBJECT_ID('tempdb..#PatientFrailtyScore') IS NOT NULL DROP TABLE #PatientFrailtyScore;
SELECT FK_Patient_Link_ID, MIN(FrailtyScore) AS FrailtyScore INTO #PatientFrailtyScore
FROM #AllPatientFrailtyScores
GROUP BY FK_Patient_Link_ID
HAVING MIN(FrailtyScore) = MAX(FrailtyScore);

-- Find the patients who remain unmatched
IF OBJECT_ID('tempdb..#UnmatchedFrailtyScorePatients') IS NOT NULL DROP TABLE #UnmatchedFrailtyScorePatients;
SELECT FK_Patient_Link_ID INTO #UnmatchedFrailtyScorePatients FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientFrailtyScore;

-- If there is a unique most recent frailty score then use that
INSERT INTO #PatientFrailtyScore
SELECT p.FK_Patient_Link_ID, MIN(p.FrailtyScore) FROM #AllPatientFrailtyScores p
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(HDMModifDate) MostRecentDate FROM #AllPatientFrailtyScores
	WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedFrailtyScorePatients)
	GROUP BY FK_Patient_Link_ID
) sub ON sub.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND sub.MostRecentDate = p.HDMModifDate
GROUP BY p.FK_Patient_Link_ID
HAVING MIN(FrailtyScore) = MAX(FrailtyScore);

-- Find any still unmatched patients
TRUNCATE TABLE #UnmatchedFrailtyScorePatients;
INSERT INTO #UnmatchedFrailtyScorePatients
SELECT FK_Patient_Link_ID FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientFrailtyScore;

-- Otherwise just use the highest value (with the exception that can't be in the future)
INSERT INTO #PatientFrailtyScore
SELECT FK_Patient_Link_ID, MAX(FrailtyScore) FROM #AllPatientFrailtyScores
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedFrailtyScorePatients)
GROUP BY FK_Patient_Link_ID;

-- Tidy up - helpful in ensuring the tempdb doesn't run out of space mid-query
DROP TABLE #AllPatientFrailtyScores;
DROP TABLE #UnmatchedFrailtyScorePatients;