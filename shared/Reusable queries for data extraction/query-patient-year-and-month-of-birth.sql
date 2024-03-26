--┌────────────────────────────────┐
--│ Year and month of birth        │
--└────────────────────────────────┘

-- OBJECTIVE: To get the year of birth for each patient.

-- INPUT: Assumes there exists a temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: A temp table as follows:
-- #PatientYearAndMonthOfBirth (FK_Patient_Link_ID, YearAndMonthOfBirth)
-- 	- FK_Patient_Link_ID - unique patient id
--	- YearAndMonthOfBirth - (YYYY-MM-01)

-- ASSUMPTIONS:
--	- Patient data is obtained from multiple sources. Where patients have multiple YearAndMonthOfBirths we determine the YearAndMonthOfBirth as follows:
--	-	If the patients has a YearAndMonthOfBirth in their primary care data feed we use that as most likely to be up to date
--	-	If every YearAndMonthOfBirth for a patient is the same, then we use that
--	-	If there is a single most recently updated YearAndMonthOfBirth in the database then we use that
--	-	Otherwise we take the highest YearAndMonthOfBirth for the patient that is not in the future

-- Get all patients year and quarter month of birth for the cohort
IF OBJECT_ID('tempdb..#AllPatientYearAndMonthOfBirths') IS NOT NULL DROP TABLE #AllPatientYearAndMonthOfBirths;
SELECT 
	FK_Patient_Link_ID,
	FK_Reference_Tenancy_ID,
	HDMModifDate,
	CONVERT(Date, DateAdd(Month, DateDiff(Month, 0, DOB), 0)) AS YearAndMonthOfBirth -- set day to '01' to mask
INTO #AllPatientYearAndMonthOfBirths
FROM SharedCare.Patient p
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND Dob IS NOT NULL;


-- If patients have a tenancy id of 2 we take this as their most likely YearAndMonthOfBirth
-- as this is the GP data feed and so most likely to be up to date
IF OBJECT_ID('tempdb..#PatientYearAndMonthOfBirth') IS NOT NULL DROP TABLE #PatientYearAndMonthOfBirth;
SELECT FK_Patient_Link_ID, MIN(YearAndMonthOfBirth) as YearAndMonthOfBirth INTO #PatientYearAndMonthOfBirth FROM #AllPatientYearAndMonthOfBirths
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_Tenancy_ID = 2
GROUP BY FK_Patient_Link_ID
HAVING MIN(YearAndMonthOfBirth) = MAX(YearAndMonthOfBirth);

-- Find the patients who remain unmatched
IF OBJECT_ID('tempdb..#UnmatchedYobPatients') IS NOT NULL DROP TABLE #UnmatchedYobPatients;
SELECT FK_Patient_Link_ID INTO #UnmatchedYobPatients FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientYearAndMonthOfBirth;

-- If every YearAndMonthOfBirth is the same for all their linked patient ids then we use that
INSERT INTO #PatientYearAndMonthOfBirth
SELECT FK_Patient_Link_ID, MIN(YearAndMonthOfBirth) FROM #AllPatientYearAndMonthOfBirths
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedYobPatients)
GROUP BY FK_Patient_Link_ID
HAVING MIN(YearAndMonthOfBirth) = MAX(YearAndMonthOfBirth);

-- Find any still unmatched patients
TRUNCATE TABLE #UnmatchedYobPatients;
INSERT INTO #UnmatchedYobPatients
SELECT FK_Patient_Link_ID FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientYearAndMonthOfBirth;

-- If there is a unique most recent YearAndMonthOfBirth then use that
INSERT INTO #PatientYearAndMonthOfBirth
SELECT p.FK_Patient_Link_ID, MIN(p.YearAndMonthOfBirth) FROM #AllPatientYearAndMonthOfBirths p
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(HDMModifDate) MostRecentDate FROM #AllPatientYearAndMonthOfBirths
	WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedYobPatients)
	GROUP BY FK_Patient_Link_ID
) sub ON sub.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND sub.MostRecentDate = p.HDMModifDate
GROUP BY p.FK_Patient_Link_ID
HAVING MIN(YearAndMonthOfBirth) = MAX(YearAndMonthOfBirth);

-- Find any still unmatched patients
TRUNCATE TABLE #UnmatchedYobPatients;
INSERT INTO #UnmatchedYobPatients
SELECT FK_Patient_Link_ID FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientYearAndMonthOfBirth;

-- Otherwise just use the highest value (with the exception that can't be in the future)
INSERT INTO #PatientYearAndMonthOfBirth
SELECT FK_Patient_Link_ID, MAX(YearAndMonthOfBirth) FROM #AllPatientYearAndMonthOfBirths
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedYobPatients)
GROUP BY FK_Patient_Link_ID
HAVING MAX(YearAndMonthOfBirth) <= GETDATE();

-- Tidy up - helpful in ensuring the tempdb doesn't run out of space mid-query
DROP TABLE #AllPatientYearAndMonthOfBirths;
DROP TABLE #UnmatchedYobPatients;