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

-- Set the start date
DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2019-01-01';
SET @EndDate = '2022-06-01';

--Just want the output, not the messages
SET NOCOUNT ON;

-- Create a table with all patients (ID)=========================================================================================================================
IF OBJECT_ID('tempdb..#PatientsToInclude') IS NOT NULL DROP TABLE #PatientsToInclude;
SELECT FK_Patient_Link_ID INTO #PatientsToInclude
FROM SharedCare.Patient_GP_History
GROUP BY FK_Patient_Link_ID
HAVING MIN(StartDate) < '2022-06-01';

IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #Patients 
FROM #PatientsToInclude;


--> EXECUTE query-ccg-lookup.sql
--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-imd.sql
--> EXECUTE query-patient-year-of-birth.sql
--> EXECUTE query-patient-practice-and-ccg.sql

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

