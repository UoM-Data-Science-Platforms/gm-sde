--┌─────────────────────────────────────────────────────────────────────────┐
--│ Secondary admissions and length of stay following each of n COVID tests │
--└─────────────────────────────────────────────────────────────────────────┘

-- OBJECTIVE: To obtain tables with the first secondary care admission, and length of
--						stay, following the nth COVID test.

-- INPUT: One parameter
--	-	all-patients: boolean - (true/false) if true, then all patients are included, otherwise only those in the pre-existing #Patients table.

-- OUTPUT: Two temp table as follows:
-- #PatientsAdmissionsPostTest
-- 	- FK_Patient_Link_ID - unique patient id
--	- FirstAdmissionPost1stCOVIDTest - date of first admission following 1st covid postivie test (YYYY-MM-DD)
--	-	FirstAdmissionPost2ndCOVIDTest
--	-	FirstAdmissionPost3rdCOVIDTest
--	-	FirstAdmissionPost4thCOVIDTest
--	-	FirstAdmissionPost5thCOVIDTest
--  (Limited to one admission per person per hospital per day, because if a patient has 2 admissions 
--   on the same day to the same hopsital then it's most likely data duplication rather than two short
--   hospital stays)
-- #PatientsLOSPostTest
-- 	- FK_Patient_Link_ID - unique patient id
--	-	LengthOfStay1stAdmission1stCOVIDTest - length of stay for first admission following 1st positive covid test
--	-	LengthOfStay1stAdmission2ndCOVIDTest - length of stay for first admission following 2nd positive covid test
--	-	LengthOfStay1stAdmission3rdCOVIDTest - length of stay for first admission following 3rd positive covid test
--	-	LengthOfStay1stAdmission4thCOVIDTest - length of stay for first admission following 4th positive covid test
--	-	LengthOfStay1stAdmission5thCOVIDTest - length of stay for first admission following 5th positive covid test

--> EXECUTE query-get-admissions-and-length-of-stay.sql all-patients:{param:all-patients}

-- Now find hospital admission following each of up to 5 covid positive tests
IF OBJECT_ID('tempdb..#PatientsAdmissionsPostTest') IS NOT NULL DROP TABLE #PatientsAdmissionsPostTest;
CREATE TABLE #PatientsAdmissionsPostTest (
  FK_Patient_Link_ID BIGINT,
  [FirstAdmissionPost1stCOVIDTest] DATE,
  [FirstAdmissionPost2ndCOVIDTest] DATE,
  [FirstAdmissionPost3rdCOVIDTest] DATE,
  [FirstAdmissionPost4thCOVIDTest] DATE,
  [FirstAdmissionPost5thCOVIDTest] DATE
);

-- Populate table with patient IDs
INSERT INTO #PatientsAdmissionsPostTest (FK_Patient_Link_ID)
SELECT FK_Patient_Link_ID FROM #Patients;

IF OBJECT_ID('tempdb..#CovidPatientsMultipleDiagnosesFiltered') IS NOT NULL DROP TABLE #CovidPatientsMultipleDiagnosesFiltered;
SELECT * INTO #CovidPatientsMultipleDiagnosesFiltered
FROM #CovidPatientsMultipleDiagnoses
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);

-- Find 1st hospital stay following 1st COVID positive test (but before 2nd)
UPDATE t1
SET t1.[FirstAdmissionPost1stCOVIDTest] = NextAdmissionDate
FROM #PatientsAdmissionsPostTest AS t1
INNER JOIN (
SELECT cp.FK_Patient_Link_ID, MIN(los.AdmissionDate) AS NextAdmissionDate FROM #CovidPatientsMultipleDiagnosesFiltered cp
INNER JOIN #LengthOfStay los ON cp.FK_Patient_Link_ID = los.FK_Patient_Link_ID 
	AND los.AdmissionDate >= DATEADD(day, -2, FirstCovidPositiveDate) -- hospital AFTER COVID test
	AND (los.AdmissionDate < SecondCovidPositiveDate OR SecondCovidPositiveDate IS NULL) --hospital BEFORE next COVID test
GROUP BY cp.FK_Patient_Link_ID) AS sub ON sub.FK_Patient_Link_ID = t1.FK_Patient_Link_ID;

-- Find 1st hospital stay following 2nd COVID positive test (but before 3rd)
UPDATE t1
SET t1.[FirstAdmissionPost2ndCOVIDTest] = NextAdmissionDate
FROM #PatientsAdmissionsPostTest AS t1
INNER JOIN (
SELECT cp.FK_Patient_Link_ID, MIN(los.AdmissionDate) AS NextAdmissionDate FROM #CovidPatientsMultipleDiagnosesFiltered cp
INNER JOIN #LengthOfStay los ON cp.FK_Patient_Link_ID = los.FK_Patient_Link_ID 
	AND los.AdmissionDate >= DATEADD(day, -2, SecondCovidPositiveDate) -- hospital AFTER COVID test
	AND (los.AdmissionDate < ThirdCovidPositiveDate OR ThirdCovidPositiveDate IS NULL)  --hospital BEFORE next COVID test
GROUP BY cp.FK_Patient_Link_ID) AS sub ON sub.FK_Patient_Link_ID = t1.FK_Patient_Link_ID;

-- Find 1st hospital stay following 3rd COVID positive test (but before 4th)
UPDATE t1
SET t1.[FirstAdmissionPost3rdCOVIDTest] = NextAdmissionDate
FROM #PatientsAdmissionsPostTest AS t1
INNER JOIN (
SELECT cp.FK_Patient_Link_ID, MIN(los.AdmissionDate) AS NextAdmissionDate FROM #CovidPatientsMultipleDiagnosesFiltered cp
INNER JOIN #LengthOfStay los ON cp.FK_Patient_Link_ID = los.FK_Patient_Link_ID 
	AND los.AdmissionDate >= DATEADD(day, -2, ThirdCovidPositiveDate) -- hospital AFTER COVID test
	AND (los.AdmissionDate < FourthCovidPositiveDate OR FourthCovidPositiveDate IS NULL)  --hospital BEFORE next COVID test
GROUP BY cp.FK_Patient_Link_ID) AS sub ON sub.FK_Patient_Link_ID = t1.FK_Patient_Link_ID;

-- Find 1st hospital stay following 4th COVID positive test (but before 5th)
UPDATE t1
SET t1.[FirstAdmissionPost4thCOVIDTest] = NextAdmissionDate
FROM #PatientsAdmissionsPostTest AS t1
INNER JOIN (
SELECT cp.FK_Patient_Link_ID, MIN(los.AdmissionDate) AS NextAdmissionDate FROM #CovidPatientsMultipleDiagnosesFiltered cp
INNER JOIN #LengthOfStay los ON cp.FK_Patient_Link_ID = los.FK_Patient_Link_ID 
	AND los.AdmissionDate >= DATEADD(day, -2, FourthCovidPositiveDate) -- hospital AFTER COVID test
	AND (los.AdmissionDate < FifthCovidPositiveDate OR FifthCovidPositiveDate IS NULL)  --hospital BEFORE next COVID test
GROUP BY cp.FK_Patient_Link_ID) AS sub ON sub.FK_Patient_Link_ID = t1.FK_Patient_Link_ID;

-- Find 1st hospital stay following 5th COVID positive test
UPDATE t1
SET t1.[FirstAdmissionPost5thCOVIDTest] = NextAdmissionDate
FROM #PatientsAdmissionsPostTest AS t1
INNER JOIN (
SELECT cp.FK_Patient_Link_ID, MIN(los.AdmissionDate) AS NextAdmissionDate FROM #CovidPatientsMultipleDiagnosesFiltered cp
INNER JOIN #LengthOfStay los ON cp.FK_Patient_Link_ID = los.FK_Patient_Link_ID 
	AND los.AdmissionDate >= DATEADD(day, -2, FifthCovidPositiveDate) -- hospital AFTER COVID test
GROUP BY cp.FK_Patient_Link_ID) AS sub ON sub.FK_Patient_Link_ID = t1.FK_Patient_Link_ID;

-- Get length of stay for each admission just calculated
IF OBJECT_ID('tempdb..#PatientsLOSPostTest') IS NOT NULL DROP TABLE #PatientsLOSPostTest;
SELECT p.FK_Patient_Link_ID, 
		MAX(l1.LengthOfStay) AS LengthOfStay1stAdmission1stCOVIDTest,
		MAX(l2.LengthOfStay) AS LengthOfStay1stAdmission2ndCOVIDTest,
		MAX(l3.LengthOfStay) AS LengthOfStay1stAdmission3rdCOVIDTest,
		MAX(l4.LengthOfStay) AS LengthOfStay1stAdmission4thCOVIDTest,
		MAX(l5.LengthOfStay) AS LengthOfStay1stAdmission5thCOVIDTest
INTO #PatientsLOSPostTest
FROM #PatientsAdmissionsPostTest p
	LEFT OUTER JOIN #LengthOfStay l1 ON p.FK_Patient_Link_ID = l1.FK_Patient_Link_ID AND p.[FirstAdmissionPost1stCOVIDTest] = l1.AdmissionDate
	LEFT OUTER JOIN #LengthOfStay l2 ON p.FK_Patient_Link_ID = l2.FK_Patient_Link_ID AND p.[FirstAdmissionPost2ndCOVIDTest] = l2.AdmissionDate
	LEFT OUTER JOIN #LengthOfStay l3 ON p.FK_Patient_Link_ID = l3.FK_Patient_Link_ID AND p.[FirstAdmissionPost3rdCOVIDTest] = l3.AdmissionDate
	LEFT OUTER JOIN #LengthOfStay l4 ON p.FK_Patient_Link_ID = l4.FK_Patient_Link_ID AND p.[FirstAdmissionPost4thCOVIDTest] = l4.AdmissionDate
	LEFT OUTER JOIN #LengthOfStay l5 ON p.FK_Patient_Link_ID = l5.FK_Patient_Link_ID AND p.[FirstAdmissionPost5thCOVIDTest] = l5.AdmissionDate
GROUP BY p.FK_Patient_Link_ID;