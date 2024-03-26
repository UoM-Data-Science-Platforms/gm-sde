--┌────────────────────────────────┐
--│ Year, month and week of birth  │
--└────────────────────────────────┘

-- OBJECTIVE: To get the week of birth for each patient.

-- INPUT: Assumes there exists a temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: A temp table as follows:
-- #PatientWeekOfBirth (FK_Patient_Link_ID, WeekOfBirth)
-- 	- FK_Patient_Link_ID - unique patient id
--	- WeekOfBirth (Number of the week within a year, e.g. from 1 to 52)
--  - MonthOfBirth (mm)
--  - YearOfBirth (yyyy)

-- ASSUMPTIONS:
--	- Patient data is obtained from multiple sources. Where patients have multiple WeekOfBirths we determine the WeekOfBirth as follows:
--	-	If the patients has a WeekOfBirth in their primary care data feed we use that as most likely to be up to date
--	-	If every WeekOfBirth for a patient is the same, then we use that
--	-	If there is a single most recently updated WeekOfBirth in the database then we use that
--	-	Otherwise we take the highest WeekOfBirth for the patient that is not in the future

-- Get all patients year and quarter month of birth for the cohort
IF OBJECT_ID('tempdb..#AllPatientDateOfBirths') IS NOT NULL DROP TABLE #AllPatientDateOfBirths;
SELECT 
	FK_Patient_Link_ID,
	FK_Reference_Tenancy_ID,
	HDMModifDate,
	CONVERT(date, Dob) AS DateOfBirth
INTO #AllPatientDateOfBirths
FROM SharedCare.Patient p
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND Dob IS NOT NULL;


-- If patients have a tenancy id of 2 we take this as their most likely DateOfBirth
-- as this is the GP data feed and so most likely to be up to date
IF OBJECT_ID('tempdb..#PatientDateOfBirth') IS NOT NULL DROP TABLE #PatientDateOfBirth;
SELECT FK_Patient_Link_ID, MIN(DateOfBirth) as DateOfBirthPID INTO #PatientDateOfBirth FROM #AllPatientDateOfBirths
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_Tenancy_ID = 2
GROUP BY FK_Patient_Link_ID
HAVING MIN(DateOfBirth) = MAX(DateOfBirth);

-- Find the patients who remain unmatched
IF OBJECT_ID('tempdb..#UnmatchedYobPatients') IS NOT NULL DROP TABLE #UnmatchedYobPatients;
SELECT FK_Patient_Link_ID INTO #UnmatchedYobPatients FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientDateOfBirth;

-- If every DateOfBirth is the same for all their linked patient ids then we use that
INSERT INTO #PatientDateOfBirth
SELECT FK_Patient_Link_ID, MIN(DateOfBirth) FROM #AllPatientDateOfBirths
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedYobPatients)
GROUP BY FK_Patient_Link_ID
HAVING MIN(DateOfBirth) = MAX(DateOfBirth);

-- Find any still unmatched patients
TRUNCATE TABLE #UnmatchedYobPatients;
INSERT INTO #UnmatchedYobPatients
SELECT FK_Patient_Link_ID FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientDateOfBirth;

-- If there is a unique most recent DateOfBirth then use that
INSERT INTO #PatientDateOfBirth
SELECT p.FK_Patient_Link_ID, MIN(p.DateOfBirth) FROM #AllPatientDateOfBirths p
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(HDMModifDate) MostRecentDate FROM #AllPatientDateOfBirths
	WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedYobPatients)
	GROUP BY FK_Patient_Link_ID
) sub ON sub.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND sub.MostRecentDate = p.HDMModifDate
GROUP BY p.FK_Patient_Link_ID
HAVING MIN(DateOfBirth) = MAX(DateOfBirth);

-- Find any still unmatched patients
TRUNCATE TABLE #UnmatchedYobPatients;
INSERT INTO #UnmatchedYobPatients
SELECT FK_Patient_Link_ID FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientDateOfBirth;

-- Otherwise just use the highest value (with the exception that can't be in the future)
INSERT INTO #PatientDateOfBirth
SELECT FK_Patient_Link_ID, MAX(DateOfBirth) FROM #AllPatientDateOfBirths
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedYobPatients)
GROUP BY FK_Patient_Link_ID
HAVING MAX(DateOfBirth) <= GETDATE();

-- Tidy up - helpful in ensuring the tempdb doesn't run out of space mid-query
DROP TABLE #AllPatientDateOfBirths;
DROP TABLE #UnmatchedYobPatients;

-- Mask 'day' in date of birth by converting to week of birth

IF OBJECT_ID('tempdb..#PatientWeekOfBirth') IS NOT NULL DROP TABLE #PatientWeekOfBirth;
SELECT FK_Patient_Link_ID,
	DateOfBirthPID, -- this is included in this table incase it is needed (e.g. to calculate an accurate age)
	WeekOfBirth = DATEPART(Week,DateOfBirthPID),
    MonthOfBirth = DATEPART(Month,DateOfBirthPID),
    YearOfBirth = DATEPART(Year,DateOfBirthPID) 
INTO #PatientWeekOfBirth
FROM #PatientDateOfBirth