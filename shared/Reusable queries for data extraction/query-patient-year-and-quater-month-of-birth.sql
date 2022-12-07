--┌────────────────────────────────┐
--│ Year and quater month of birth │
--└────────────────────────────────┘

-- OBJECTIVE: To get the year of birth for each patient.

-- INPUT: Assumes there exists a temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: A temp table as follows:
-- #PatientYearAndQuaterMonthOfBirth (FK_Patient_Link_ID, YearAndQuaterMonthOfBirth)
-- 	- FK_Patient_Link_ID - unique patient id
--	- YearAndQuaterMonthOfBirth - (YYYY-MM-01)

-- ASSUMPTIONS:
--	- Patient data is obtained from multiple sources. Where patients have multiple YearAndQuaterMonthOfBirths we determine the YearAndQuaterMonthOfBirth as follows:
--	-	If the patients has a YearAndQuaterMonthOfBirth in their primary care data feed we use that as most likely to be up to date
--	-	If every YearAndQuaterMonthOfBirth for a patient is the same, then we use that
--	-	If there is a single most recently updated YearAndQuaterMonthOfBirth in the database then we use that
--	-	Otherwise we take the highest YearAndQuaterMonthOfBirth for the patient that is not in the future

-- Get all patients year and quater month of birth for the cohort
IF OBJECT_ID('tempdb..#AllPatientYearAndQuaterMonthOfBirths') IS NOT NULL DROP TABLE #AllPatientYearAndQuaterMonthOfBirths;
SELECT 
	FK_Patient_Link_ID,
	FK_Reference_Tenancy_ID,
	HDMModifDate,
	CONVERT(date, Dob) AS YearAndQuaterMonthOfBirth
INTO #AllPatientYearAndQuaterMonthOfBirths
FROM SharedCare.Patient p
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND Dob IS NOT NULL;


-- If patients have a tenancy id of 2 we take this as their most likely YearAndQuaterMonthOfBirth
-- as this is the GP data feed and so most likely to be up to date
IF OBJECT_ID('tempdb..#PatientYearAndQuaterMonthOfBirth') IS NOT NULL DROP TABLE #PatientYearAndQuaterMonthOfBirth;
SELECT FK_Patient_Link_ID, MIN(YearAndQuaterMonthOfBirth) as YearAndQuaterMonthOfBirth INTO #PatientYearAndQuaterMonthOfBirth FROM #AllPatientYearAndQuaterMonthOfBirths
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_Tenancy_ID = 2
GROUP BY FK_Patient_Link_ID
HAVING MIN(YearAndQuaterMonthOfBirth) = MAX(YearAndQuaterMonthOfBirth);

-- Find the patients who remain unmatched
IF OBJECT_ID('tempdb..#UnmatchedYobPatients') IS NOT NULL DROP TABLE #UnmatchedYobPatients;
SELECT FK_Patient_Link_ID INTO #UnmatchedYobPatients FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientYearAndQuaterMonthOfBirth;

-- If every YearAndQuaterMonthOfBirth is the same for all their linked patient ids then we use that
INSERT INTO #PatientYearAndQuaterMonthOfBirth
SELECT FK_Patient_Link_ID, MIN(YearAndQuaterMonthOfBirth) FROM #AllPatientYearAndQuaterMonthOfBirths
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedYobPatients)
GROUP BY FK_Patient_Link_ID
HAVING MIN(YearAndQuaterMonthOfBirth) = MAX(YearAndQuaterMonthOfBirth);

-- Find any still unmatched patients
TRUNCATE TABLE #UnmatchedYobPatients;
INSERT INTO #UnmatchedYobPatients
SELECT FK_Patient_Link_ID FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientYearAndQuaterMonthOfBirth;

-- If there is a unique most recent YearAndQuaterMonthOfBirth then use that
INSERT INTO #PatientYearAndQuaterMonthOfBirth
SELECT p.FK_Patient_Link_ID, MIN(p.YearAndQuaterMonthOfBirth) FROM #AllPatientYearAndQuaterMonthOfBirths p
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(HDMModifDate) MostRecentDate FROM #AllPatientYearAndQuaterMonthOfBirths
	WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedYobPatients)
	GROUP BY FK_Patient_Link_ID
) sub ON sub.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND sub.MostRecentDate = p.HDMModifDate
GROUP BY p.FK_Patient_Link_ID
HAVING MIN(YearAndQuaterMonthOfBirth) = MAX(YearAndQuaterMonthOfBirth);

-- Find any still unmatched patients
TRUNCATE TABLE #UnmatchedYobPatients;
INSERT INTO #UnmatchedYobPatients
SELECT FK_Patient_Link_ID FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientYearAndQuaterMonthOfBirth;

-- Otherwise just use the highest value (with the exception that can't be in the future)
INSERT INTO #PatientYearAndQuaterMonthOfBirth
SELECT FK_Patient_Link_ID, MAX(YearAndQuaterMonthOfBirth) FROM #AllPatientYearAndQuaterMonthOfBirths
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedYobPatients)
GROUP BY FK_Patient_Link_ID
HAVING MAX(YearAndQuaterMonthOfBirth) <= GETDATE();

-- Tidy up - helpful in ensuring the tempdb doesn't run out of space mid-query
DROP TABLE #AllPatientYearAndQuaterMonthOfBirths;
DROP TABLE #UnmatchedYobPatients;