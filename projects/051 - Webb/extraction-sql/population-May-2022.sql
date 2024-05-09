--+--------------------------------------------------------------------------------+
--¦ GP population counts in May 2022     					   ¦
--+--------------------------------------------------------------------------------+

-------- RESEARCH DATA ENGINEER CHECK ---------

-- OUTPUT: Data with the following fields
-- Year (YYYY)
-- Month (1-12)
-- CCG (can be an anonymised id for each CCG)
-- GPPracticeId
-- Age
-- Sex
-- Ethnic
-- IMDGroup
-- NumberOfPatients (integer)

--Just want the output, not the messages
SET NOCOUNT ON;

-- Create a table with all patients (ID)=========================================================================================================================
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT DISTINCT FK_Patient_Link_ID
INTO #Patients
FROM SharedCare.Patient
WHERE FK_Reference_Tenancy_ID=2
AND GPPracticeCode NOT LIKE 'ZZZ%';


--┌──────────────────┐
--│ CCG lookup table │
--└──────────────────┘

-- OBJECTIVE: To provide lookup table for CCG names. The GMCR provides the CCG id (e.g. '00T', '01G') but not 
--            the CCG name. This table can be used in other queries when the output is required to be a ccg 
--            name rather than an id.

-- INPUT: No pre-requisites

-- OUTPUT: A temp table as follows:
-- #CCGLookup (CcgId, CcgName)
-- 	- CcgId - Nationally recognised ccg id
--	- CcgName - Bolton, Stockport etc..

IF OBJECT_ID('tempdb..#CCGLookup') IS NOT NULL DROP TABLE #CCGLookup;
CREATE TABLE #CCGLookup (CcgId nchar(3), CcgName nvarchar(20));
INSERT INTO #CCGLookup VALUES ('01G', 'Salford'); 
INSERT INTO #CCGLookup VALUES ('00T', 'Bolton'); 
INSERT INTO #CCGLookup VALUES ('01D', 'HMR'); 
INSERT INTO #CCGLookup VALUES ('02A', 'Trafford'); 
INSERT INTO #CCGLookup VALUES ('01W', 'Stockport');
INSERT INTO #CCGLookup VALUES ('00Y', 'Oldham'); 
INSERT INTO #CCGLookup VALUES ('02H', 'Wigan'); 
INSERT INTO #CCGLookup VALUES ('00V', 'Bury'); 
INSERT INTO #CCGLookup VALUES ('14L', 'Manchester'); 
INSERT INTO #CCGLookup VALUES ('01Y', 'Tameside Glossop'); 
--┌─────┐
--│ Sex │
--└─────┘

-- OBJECTIVE: To get the Sex for each patient.

-- INPUT: Assumes there exists a temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: A temp table as follows:
-- #PatientSex (FK_Patient_Link_ID, Sex)
-- 	- FK_Patient_Link_ID - unique patient id
--	- Sex - M/F

-- ASSUMPTIONS:
--	- Patient data is obtained from multiple sources. Where patients have multiple sexes we determine the sex as follows:
--	-	If the patients has a sex in their primary care data feed we use that as most likely to be up to date
--	-	If every sex for a patient is the same, then we use that
--	-	If there is a single most recently updated sex in the database then we use that
--	-	Otherwise the patient's sex is considered unknown

-- Get all patients sex for the cohort
IF OBJECT_ID('tempdb..#AllPatientSexs') IS NOT NULL DROP TABLE #AllPatientSexs;
SELECT 
	FK_Patient_Link_ID,
	FK_Reference_Tenancy_ID,
	HDMModifDate,
	Sex
INTO #AllPatientSexs
FROM SharedCare.Patient p
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND Sex IS NOT NULL;


-- If patients have a tenancy id of 2 we take this as their most likely Sex
-- as this is the GP data feed and so most likely to be up to date
IF OBJECT_ID('tempdb..#PatientSex') IS NOT NULL DROP TABLE #PatientSex;
SELECT FK_Patient_Link_ID, MIN(Sex) as Sex INTO #PatientSex FROM #AllPatientSexs
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_Tenancy_ID = 2
GROUP BY FK_Patient_Link_ID
HAVING MIN(Sex) = MAX(Sex);

-- Find the patients who remain unmatched
IF OBJECT_ID('tempdb..#UnmatchedSexPatients') IS NOT NULL DROP TABLE #UnmatchedSexPatients;
SELECT FK_Patient_Link_ID INTO #UnmatchedSexPatients FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientSex;

-- If every Sex is the same for all their linked patient ids then we use that
INSERT INTO #PatientSex
SELECT FK_Patient_Link_ID, MIN(Sex) FROM #AllPatientSexs
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedSexPatients)
GROUP BY FK_Patient_Link_ID
HAVING MIN(Sex) = MAX(Sex);

-- Find any still unmatched patients
TRUNCATE TABLE #UnmatchedSexPatients;
INSERT INTO #UnmatchedSexPatients
SELECT FK_Patient_Link_ID FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientSex;

-- If there is a unique most recent Sex then use that
INSERT INTO #PatientSex
SELECT p.FK_Patient_Link_ID, MIN(p.Sex) FROM #AllPatientSexs p
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(HDMModifDate) MostRecentDate FROM #AllPatientSexs
	WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedSexPatients)
	GROUP BY FK_Patient_Link_ID
) sub ON sub.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND sub.MostRecentDate = p.HDMModifDate
GROUP BY p.FK_Patient_Link_ID
HAVING MIN(Sex) = MAX(Sex);

-- Tidy up - helpful in ensuring the tempdb doesn't run out of space mid-query
DROP TABLE #AllPatientSexs;
DROP TABLE #UnmatchedSexPatients;
--┌────────────────────────────┐
--│ Index Multiple Deprivation │
--└────────────────────────────┘

-- OBJECTIVE: To get the 2019 Index of Multiple Deprivation (IMD) decile for each patient.

-- INPUT: Assumes there exists a temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: A temp table as follows:
-- #PatientIMDDecile (FK_Patient_Link_ID, IMD2019Decile1IsMostDeprived10IsLeastDeprived)
-- 	- FK_Patient_Link_ID - unique patient id
--	- IMD2019Decile1IsMostDeprived10IsLeastDeprived - number 1 to 10 inclusive

-- Get all patients IMD_Score (which is a rank) for the cohort and map to decile
-- (Data on mapping thresholds at: https://www.gov.uk/government/statistics/english-indices-of-deprivation-2019
IF OBJECT_ID('tempdb..#AllPatientIMDDeciles') IS NOT NULL DROP TABLE #AllPatientIMDDeciles;
SELECT 
	FK_Patient_Link_ID,
	FK_Reference_Tenancy_ID,
	HDMModifDate,
	CASE 
		WHEN IMD_Score <= 3284 THEN 1
		WHEN IMD_Score <= 6568 THEN 2
		WHEN IMD_Score <= 9853 THEN 3
		WHEN IMD_Score <= 13137 THEN 4
		WHEN IMD_Score <= 16422 THEN 5
		WHEN IMD_Score <= 19706 THEN 6
		WHEN IMD_Score <= 22990 THEN 7
		WHEN IMD_Score <= 26275 THEN 8
		WHEN IMD_Score <= 29559 THEN 9
		ELSE 10
	END AS IMD2019Decile1IsMostDeprived10IsLeastDeprived 
INTO #AllPatientIMDDeciles
FROM SharedCare.Patient p
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND IMD_Score IS NOT NULL
AND IMD_Score != -1;
-- 972479 rows
-- 00:00:11

-- If patients have a tenancy id of 2 we take this as their most likely IMD_Score
-- as this is the GP data feed and so most likely to be up to date
IF OBJECT_ID('tempdb..#PatientIMDDecile') IS NOT NULL DROP TABLE #PatientIMDDecile;
SELECT FK_Patient_Link_ID, MIN(IMD2019Decile1IsMostDeprived10IsLeastDeprived) as IMD2019Decile1IsMostDeprived10IsLeastDeprived INTO #PatientIMDDecile FROM #AllPatientIMDDeciles
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_Tenancy_ID = 2
GROUP BY FK_Patient_Link_ID;
-- 247377 rows
-- 00:00:00

-- Find the patients who remain unmatched
IF OBJECT_ID('tempdb..#UnmatchedImdPatients') IS NOT NULL DROP TABLE #UnmatchedImdPatients;
SELECT FK_Patient_Link_ID INTO #UnmatchedImdPatients FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientIMDDecile;
-- 38710 rows
-- 00:00:00

-- If every IMD_Score is the same for all their linked patient ids then we use that
INSERT INTO #PatientIMDDecile
SELECT FK_Patient_Link_ID, MIN(IMD2019Decile1IsMostDeprived10IsLeastDeprived) FROM #AllPatientIMDDeciles
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedImdPatients)
GROUP BY FK_Patient_Link_ID
HAVING MIN(IMD2019Decile1IsMostDeprived10IsLeastDeprived) = MAX(IMD2019Decile1IsMostDeprived10IsLeastDeprived);
-- 36656
-- 00:00:00

-- Find any still unmatched patients
TRUNCATE TABLE #UnmatchedImdPatients;
INSERT INTO #UnmatchedImdPatients
SELECT FK_Patient_Link_ID FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientIMDDecile;
-- 2054 rows
-- 00:00:00

-- If there is a unique most recent imd decile then use that
INSERT INTO #PatientIMDDecile
SELECT p.FK_Patient_Link_ID, MIN(p.IMD2019Decile1IsMostDeprived10IsLeastDeprived) FROM #AllPatientIMDDeciles p
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(HDMModifDate) MostRecentDate FROM #AllPatientIMDDeciles
	WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedImdPatients)
	GROUP BY FK_Patient_Link_ID
) sub ON sub.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND sub.MostRecentDate = p.HDMModifDate
GROUP BY p.FK_Patient_Link_ID
HAVING MIN(IMD2019Decile1IsMostDeprived10IsLeastDeprived) = MAX(IMD2019Decile1IsMostDeprived10IsLeastDeprived);
-- 489
-- 00:00:00
--┌───────────────┐
--│ Year of birth │
--└───────────────┘

-- OBJECTIVE: To get the year of birth for each patient.

-- INPUT: Assumes there exists a temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: A temp table as follows:
-- #PatientYearOfBirth (FK_Patient_Link_ID, YearOfBirth)
-- 	- FK_Patient_Link_ID - unique patient id
--	- YearOfBirth - INT

-- ASSUMPTIONS:
--	- Patient data is obtained from multiple sources. Where patients have multiple YOBs we determine the YOB as follows:
--	-	If the patients has a YOB in their primary care data feed we use that as most likely to be up to date
--	-	If every YOB for a patient is the same, then we use that
--	-	If there is a single most recently updated YOB in the database then we use that
--	-	Otherwise we take the highest YOB for the patient that is not in the future

-- Get all patients year of birth for the cohort
IF OBJECT_ID('tempdb..#AllPatientYearOfBirths') IS NOT NULL DROP TABLE #AllPatientYearOfBirths;
SELECT 
	FK_Patient_Link_ID,
	FK_Reference_Tenancy_ID,
	HDMModifDate,
	YEAR(Dob) AS YearOfBirth
INTO #AllPatientYearOfBirths
FROM SharedCare.Patient p
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND Dob IS NOT NULL;


-- If patients have a tenancy id of 2 we take this as their most likely YOB
-- as this is the GP data feed and so most likely to be up to date
IF OBJECT_ID('tempdb..#PatientYearOfBirth') IS NOT NULL DROP TABLE #PatientYearOfBirth;
SELECT FK_Patient_Link_ID, MIN(YearOfBirth) as YearOfBirth INTO #PatientYearOfBirth FROM #AllPatientYearOfBirths
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_Tenancy_ID = 2
GROUP BY FK_Patient_Link_ID
HAVING MIN(YearOfBirth) = MAX(YearOfBirth);

-- Find the patients who remain unmatched
IF OBJECT_ID('tempdb..#UnmatchedYobPatients') IS NOT NULL DROP TABLE #UnmatchedYobPatients;
SELECT FK_Patient_Link_ID INTO #UnmatchedYobPatients FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientYearOfBirth;

-- If every YOB is the same for all their linked patient ids then we use that
INSERT INTO #PatientYearOfBirth
SELECT FK_Patient_Link_ID, MIN(YearOfBirth) FROM #AllPatientYearOfBirths
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedYobPatients)
GROUP BY FK_Patient_Link_ID
HAVING MIN(YearOfBirth) = MAX(YearOfBirth);

-- Find any still unmatched patients
TRUNCATE TABLE #UnmatchedYobPatients;
INSERT INTO #UnmatchedYobPatients
SELECT FK_Patient_Link_ID FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientYearOfBirth;

-- If there is a unique most recent YOB then use that
INSERT INTO #PatientYearOfBirth
SELECT p.FK_Patient_Link_ID, MIN(p.YearOfBirth) FROM #AllPatientYearOfBirths p
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(HDMModifDate) MostRecentDate FROM #AllPatientYearOfBirths
	WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedYobPatients)
	GROUP BY FK_Patient_Link_ID
) sub ON sub.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND sub.MostRecentDate = p.HDMModifDate
GROUP BY p.FK_Patient_Link_ID
HAVING MIN(YearOfBirth) = MAX(YearOfBirth);

-- Find any still unmatched patients
TRUNCATE TABLE #UnmatchedYobPatients;
INSERT INTO #UnmatchedYobPatients
SELECT FK_Patient_Link_ID FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientYearOfBirth;

-- Otherwise just use the highest value (with the exception that can't be in the future)
INSERT INTO #PatientYearOfBirth
SELECT FK_Patient_Link_ID, MAX(YearOfBirth) FROM #AllPatientYearOfBirths
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedYobPatients)
GROUP BY FK_Patient_Link_ID
HAVING MAX(YearOfBirth) <= YEAR(GETDATE());

-- Tidy up - helpful in ensuring the tempdb doesn't run out of space mid-query
DROP TABLE #AllPatientYearOfBirths;
DROP TABLE #UnmatchedYobPatients;
--┌───────────────────────────────────────┐
--│ GET practice and ccg for each patient │
--└───────────────────────────────────────┘

-- OBJECTIVE:	For each patient to get the practice id that they are registered to, and 
--						the CCG name that the practice belongs to.

-- INPUT: Assumes there exists a temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: Two temp tables as follows:
-- #PatientPractice (FK_Patient_Link_ID, GPPracticeCode)
--	- FK_Patient_Link_ID - unique patient id
--	- GPPracticeCode - the nationally recognised practice id for the patient
-- #PatientPracticeAndCCG (FK_Patient_Link_ID, GPPracticeCode, CCG)
--	- FK_Patient_Link_ID - unique patient id
--	- GPPracticeCode - the nationally recognised practice id for the patient
--	- CCG - the name of the patient's CCG

-- If patients have a tenancy id of 2 we take this as their most likely GP practice
-- as this is the GP data feed and so most likely to be up to date
IF OBJECT_ID('tempdb..#PatientPractice') IS NOT NULL DROP TABLE #PatientPractice;
SELECT FK_Patient_Link_ID, MIN(GPPracticeCode) as GPPracticeCode INTO #PatientPractice FROM SharedCare.Patient
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_Tenancy_ID = 2
AND GPPracticeCode IS NOT NULL
GROUP BY FK_Patient_Link_ID;
-- 1298467 rows
-- 00:00:11

-- Find the patients who remain unmatched
IF OBJECT_ID('tempdb..#UnmatchedPatientsForPracticeCode') IS NOT NULL DROP TABLE #UnmatchedPatientsForPracticeCode;
SELECT FK_Patient_Link_ID INTO #UnmatchedPatientsForPracticeCode FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientPractice;
-- 12702 rows
-- 00:00:00

-- If every GPPracticeCode is the same for all their linked patient ids then we use that
INSERT INTO #PatientPractice
SELECT FK_Patient_Link_ID, MIN(GPPracticeCode) FROM SharedCare.Patient
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedPatientsForPracticeCode)
AND GPPracticeCode IS NOT NULL
GROUP BY FK_Patient_Link_ID
HAVING MIN(GPPracticeCode) = MAX(GPPracticeCode);
-- 12141
-- 00:00:00

-- Find any still unmatched patients
TRUNCATE TABLE #UnmatchedPatientsForPracticeCode;
INSERT INTO #UnmatchedPatientsForPracticeCode
SELECT FK_Patient_Link_ID FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientPractice;
-- 561 rows
-- 00:00:00

-- If there is a unique most recent gp practice then we use that
INSERT INTO #PatientPractice
SELECT p.FK_Patient_Link_ID, MIN(p.GPPracticeCode) FROM SharedCare.Patient p
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(HDMModifDate) MostRecentDate FROM SharedCare.Patient
	WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedPatientsForPracticeCode)
	GROUP BY FK_Patient_Link_ID
) sub ON sub.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND sub.MostRecentDate = p.HDMModifDate
WHERE p.GPPracticeCode IS NOT NULL
GROUP BY p.FK_Patient_Link_ID
HAVING MIN(GPPracticeCode) = MAX(GPPracticeCode);
-- 15

-- >>> Ignoring following query as already injected: query-ccg-lookup.sql

IF OBJECT_ID('tempdb..#PatientPracticeAndCCG') IS NOT NULL DROP TABLE #PatientPracticeAndCCG;
SELECT p.FK_Patient_Link_ID, ISNULL(pp.GPPracticeCode,'') AS GPPracticeCode, ISNULL(ccg.CcgName, '') AS CCG
INTO #PatientPracticeAndCCG
FROM #Patients p
LEFT OUTER JOIN #PatientPractice pp ON pp.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN SharedCare.Reference_GP_Practice gp ON gp.OrganisationCode = pp.GPPracticeCode
LEFT OUTER JOIN #CCGLookup ccg ON ccg.CcgId = gp.Commissioner;

/*

This is the logic we apply to the GP_History table to find which practice a patient was most likely
registered at on a given date - DateOfInterest.

-      Find all practices where the patient’s start date <=DateOfInterest, and end date is NULL or >=DateOfInterest
-      Where registration periods overlap they use the one with the most recent start date
-      If there are several with the same start date they use the longest one (i.e. with the latest end date).

*/


-- Create a table populated with the time points that we want to find the GP population for
IF OBJECT_ID('tempdb..#DatesOfInterest') IS NOT NULL DROP TABLE #DatesOfInterest;
CREATE TABLE #DatesOfInterest (
       [DateOfInterest] DATE
);

INSERT INTO #DatesOfInterest
VALUES ('2019-01-15'), ('2019-02-15'), ('2019-03-15'), ('2019-04-15'), ('2019-05-15'), ('2019-06-15'),
	   ('2019-07-15'), ('2019-08-15'), ('2019-09-15'), ('2019-10-15'), ('2019-11-15'), ('2019-12-15'),
	   ('2020-01-15'), ('2020-02-15'), ('2020-03-15'), ('2020-04-15'), ('2020-05-15'), ('2020-06-15'),
	   ('2020-07-15'), ('2020-08-15'), ('2020-09-15'), ('2020-10-15'), ('2020-11-15'), ('2020-12-15'),
	   ('2021-01-15'), ('2021-02-15'), ('2021-03-15'), ('2021-04-15'), ('2021-05-15'), ('2021-06-15'),
	   ('2021-07-15'), ('2021-08-15'), ('2021-09-15'), ('2021-10-15'), ('2021-11-15'), ('2021-12-15'),
	   ('2022-01-15'), ('2022-02-15'), ('2022-03-15'), ('2022-04-15'), ('2022-05-15');


-- Create a table of all patients with start date and end date in GP history table================================================================================================================
IF OBJECT_ID('tempdb..#GPHistory') IS NOT NULL DROP TABLE #GPHistory;
SELECT FK_Patient_Link_ID, StartDate, EndDate, GPPracticeCode
INTO #GPHistory
FROM SharedCare.Patient_GP_History
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);


-- Merge with death date=========================================================================================================================================================================
IF OBJECT_ID('tempdb..#Table') IS NOT NULL DROP TABLE #Table;
SELECT h.FK_Patient_Link_ID, h.GPPracticeCode, h.StartDate, h.EndDate, l.DeathDate
INTO #Table
FROM #GPHistory h
LEFT OUTER JOIN [RLS].[vw_Patient_Link] l ON h.FK_Patient_Link_ID = l.PK_Patient_Link_ID;


-- Update the table with death date information===========================================================================================================
UPDATE
#Table
SET
EndDate = DeathDate
WHERE
EndDate IS NULL OR DeathDate < EndDate;


UPDATE
#Table
SET
StartDate = DeathDate
WHERE
DeathDate < StartDate;


-- For each patient with a matching registration period for each date of interest, we find
-- the most recent start date (NB this can match multiple rows for each patient and each date of interest)
IF OBJECT_ID('tempdb..#MostRecentStartDates') IS NOT NULL DROP TABLE #MostRecentStartDates;
SELECT FK_Patient_Link_ID, DateOfInterest, MAX(StartDate) AS LatestStartDate INTO #MostRecentStartDates
FROM #Table h
INNER JOIN #DatesOfInterest d ON CAST(StartDate AS DATE) <= d.DateOfInterest AND (EndDate IS NULL OR CAST(EndDate AS DATE) >= d.DateOfInterest)
WHERE GPPracticeCode IS NOT NULL
GROUP BY FK_Patient_Link_ID, DateOfInterest;
-- 3m29


-- We now link the patient ids and start dates back to the GP_History table, so that for cases
-- where a patient has multiple startdates, we can pick the one with the furthest end date. (NB
-- this can still lead to multiple rows for each patient and each date of interest)
IF OBJECT_ID('tempdb..#FurthestEndDates') IS NOT NULL DROP TABLE #FurthestEndDates;
SELECT h.FK_Patient_Link_ID, DateOfInterest, StartDate, MAX(CASE WHEN EndDate IS NULL THEN '2100-01-01' ELSE EndDate END) AS LatestEndDate INTO #FurthestEndDates
FROM #Table h
INNER JOIN #MostRecentStartDates m 
       ON m.FK_Patient_Link_ID = h.FK_Patient_Link_ID
       AND m.LatestStartDate = StartDate
       AND (EndDate IS NULL OR CAST(EndDate AS DATE) >= DateOfInterest)
GROUP BY h.FK_Patient_Link_ID, DateOfInterest, StartDate;
-- 2m23


-- Bring it all together into a table that shows which practice each person was at
-- for each date of interest
IF OBJECT_ID('tempdb..#PatientGPPracticesOnDate') IS NOT NULL DROP TABLE #PatientGPPracticesOnDate;
SELECT h.FK_Patient_Link_ID, MAX(GPPracticeCode) AS GPPracticeCode, YEAR (DateOfInterest) AS Year, MONTH (DateOfInterest) AS Month, DAY(DateOfInterest) AS Day
INTO #PatientGPPracticesOnDate
FROM #Table h
INNER JOIN #FurthestEndDates f
       ON f.FK_Patient_Link_ID = h.FK_Patient_Link_ID
       AND f.StartDate = h.StartDate
       AND (
             f.LatestEndDate = h.EndDate 
             OR (h.EndDate IS NULL AND f.LatestEndDate='2100-01-01')
       )
WHERE GPPracticeCode IS NOT NULL
GROUP BY h.FK_Patient_Link_ID, DateOfInterest;


-- Create the table of ethnic================================================================================================================================
IF OBJECT_ID('tempdb..#Ethnic') IS NOT NULL DROP TABLE #Ethnic;
SELECT PK_Patient_Link_ID AS FK_Patient_Link_ID, EthnicMainGroup AS Ethnic
INTO #Ethnic
FROM SharedCare.Patient_Link;


-- Create the table of IDM================================================================================================================================
IF OBJECT_ID('tempdb..#IMDGroup') IS NOT NULL DROP TABLE #IMDGroup;
SELECT FK_Patient_Link_ID, IMDGroup = CASE 
		WHEN IMD2019Decile1IsMostDeprived10IsLeastDeprived IN (1,2) THEN 1 
		WHEN IMD2019Decile1IsMostDeprived10IsLeastDeprived IN (3,4) THEN 2 
		WHEN IMD2019Decile1IsMostDeprived10IsLeastDeprived IN (5,6) THEN 3
		WHEN IMD2019Decile1IsMostDeprived10IsLeastDeprived IN (7,8) THEN 4
		WHEN IMD2019Decile1IsMostDeprived10IsLeastDeprived IN (9,10) THEN 5
		ELSE NULL END
INTO #IMDGroup
FROM #PatientIMDDecile;


-- Merge CCG information============================================================================================================================================
IF OBJECT_ID('tempdb..#FinalTable') IS NOT NULL DROP TABLE #FinalTable;
SELECT p.FK_Patient_Link_ID, 
	p.GPPracticeCode, 
	p.Year, 
	p.Month,
	p.Day,
	ISNULL(ccg.CcgName, '') AS CCG, 
	Sex,
	Ethnic,
	(p.Year - YearOfBirth) AS Age,
  	IMDGroup
INTO #FinalTable
FROM #PatientGPPracticesOnDate p
LEFT OUTER JOIN SharedCare.Reference_GP_Practice gp ON gp.OrganisationCode = p.GPPracticeCode
LEFT OUTER JOIN #CCGLookup ccg ON ccg.CcgId = gp.Commissioner
LEFT OUTER JOIN #Ethnic e ON e.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #IMDGroup imd ON imd.FK_Patient_Link_ID = p.FK_Patient_Link_ID;


-- Count============================================================================================================================================================
SELECT Year, Month, Sex, Age, Ethnic, IMDGroup, CCG, GPPracticeCode AS GPPracticeId, 
	   SUM(CASE WHEN Day IS NOT NULL THEN 1 ELSE 0 END) AS NumberOfPatients
FROM #FinalTable
WHERE Year = 2022 AND Month = 5
GROUP BY Year, Month, Age, Sex, Ethnic, IMDGroup, GPPracticeCode, CCG
ORDER BY Year, Month, Age, Sex, Ethnic, IMDGroup, GPPracticeCode, CCG;

