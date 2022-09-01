--+--------------------------------------------------------------------------------+
--¦ All triggers         ¦
--+--------------------------------------------------------------------------------+

-------- RESEARCH DATA ENGINEER CHECK ---------

-- OUTPUT: Data with the following fields
-- Year (YYYY)
-- Month (1-12)
-- CCG (can be an anonymised id for each CCG)
-- GPPracticeId
-- NumberOfPatients (integer)

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2019-01-01';

--Just want the output, not the messages
SET NOCOUNT ON;

-- Create a table with all patients (ID)=========================================================================================================================
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT DISTINCT FK_Patient_Link_ID INTO #Patients FROM [RLS].vw_Patient;


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
SELECT FK_Patient_Link_ID, MIN(GPPracticeCode) as GPPracticeCode INTO #PatientPractice FROM RLS.vw_Patient
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
SELECT FK_Patient_Link_ID, MIN(GPPracticeCode) FROM RLS.vw_Patient
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
SELECT p.FK_Patient_Link_ID, MIN(p.GPPracticeCode) FROM RLS.vw_Patient p
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(HDMModifDate) MostRecentDate FROM RLS.vw_Patient
	WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedPatientsForPracticeCode)
	GROUP BY FK_Patient_Link_ID
) sub ON sub.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND sub.MostRecentDate = p.HDMModifDate
WHERE p.GPPracticeCode IS NOT NULL
GROUP BY p.FK_Patient_Link_ID
HAVING MIN(GPPracticeCode) = MAX(GPPracticeCode);
-- 15

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
FROM RLS.vw_Patient_GP_History;


-- Merge with death date and CCG=========================================================================================================================================================================
IF OBJECT_ID('tempdb..#Table') IS NOT NULL DROP TABLE #Table;
SELECT h.FK_Patient_Link_ID, h.GPPracticeCode, h.StartDate, h.EndDate, l.DeathDate, ccg.CcgName AS CCG
INTO #Table
FROM #GPHistory h
LEFT OUTER JOIN [RLS].[vw_Patient_Link] l ON h.FK_Patient_Link_ID = l.PK_Patient_Link_ID
LEFT OUTER JOIN SharedCare.Reference_GP_Practice gp ON gp.OrganisationCode = h.GPPracticeCode
LEFT OUTER JOIN #CCGLookup ccg ON ccg.CcgId = gp.Commissioner; -- find CCG through GP Practice Code


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
SELECT h.FK_Patient_Link_ID, MAX(GPPracticeCode) AS GPPracticeCode, MAX(CCG) AS CCG, YEAR (DateOfInterest) AS Year, MONTH (DateOfInterest) AS Month, DAY(DateOfInterest) AS Day
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


-- Count============================================================================================================================================================
SELECT Year, Month, CCG, GPPracticeCode AS GPPracticeId, 
	   SUM(CASE WHEN Day IS NOT NULL THEN 1 ELSE 0 END) AS NumberOfPatients
FROM #PatientGPPracticesOnDate
WHERE Year IS NOT NULL AND Month IS NOT NULL AND (CCG IS NOT NULL OR GPPracticeCode IS NOT NULL)
GROUP BY Year, Month, CCG, CCG, GPPracticeCode;

