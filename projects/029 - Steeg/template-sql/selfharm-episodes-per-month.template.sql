--┌────────────────────────────────────┐
--│ Self-harm episodes per month	   │
--└────────────────────────────────────┘

-- OUTPUT: Data with the following fields
-- 	- Month (YYYY-MM)
--  - Sex (M/F)
--  - EthnicGroup ()
--  - AgeCategory ()
--  - IMDQuintile (int)
--  - FirstRecordedSelfharmEpisodes (int)
--  - SelfharmEpisodes (int)
--  - FirstRecordedSelfharmEpisodes_2019Lookback (int)
--  - FirstRecordedSelfharmEpisodes_fullLookback (int)

--Just want the output, not the messages
SET NOCOUNT ON;

-- *************** INTERIM WORKAROUND DUE TO MISSING PATIENT_LINK_ID'S ***************************
-- find patient_id for all patients, this will be used to link the gp_events table to patient_link
-- ***********************************************************************************************

IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT P.PK_Patient_ID, PL.PK_Patient_Link_ID AS FK_Patient_Link_ID, PL.EthnicMainGroup
INTO #Patients 
FROM [RLS].vw_Patient P
LEFT JOIN [RLS].vw_Patient_Link PL ON P.FK_Patient_Link_ID = PL.PK_Patient_Link_ID

--> EXECUTE load-code-sets.sql
--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-imd.sql
--> EXECUTE query-patient-year-of-birth.sql

-- CREATE TABLE OF ALL RELEVANT EPISODES FROM GP_EVENTS, WITH PATIENT INFO APPENDED, AND ROWNUMBER TO IDENTIFY FIRST EPISODES FOR EACH PATIENT

IF OBJECT_ID('tempdb..#SelfHarmEpisodes_all') IS NOT NULL DROP TABLE #SelfHarmEpisodes_all;
SELECT gp.FK_Patient_Link_ID, 
	   EventDate, 
	   EpisodeNumber = ROW_NUMBER() OVER(PARTITION BY gp.FK_Patient_Link_ID ORDER BY EventDate),
	   Sex,
	   AgeCategory = CASE WHEN (YEAR(gp.EventDate) - yob.YearOfBirth) BETWEEN 0 AND 9 THEN '0-9'
			WHEN (YEAR(gp.EventDate) - yob.YearOfBirth) BETWEEN 10 AND 19 THEN '10-19'
			WHEN (YEAR(gp.EventDate) - yob.YearOfBirth) BETWEEN 20 AND 29 THEN '20-29'
			WHEN (YEAR(gp.EventDate) - yob.YearOfBirth) BETWEEN 30 AND 39 THEN '30-39'
			WHEN (YEAR(gp.EventDate) - yob.YearOfBirth) BETWEEN 40 AND 49 THEN '40-49'
			WHEN (YEAR(gp.EventDate) - yob.YearOfBirth) BETWEEN 50 AND 59 THEN '50-59'
			WHEN (YEAR(gp.EventDate) - yob.YearOfBirth) BETWEEN 60 AND 69 THEN '60-69'
			WHEN (YEAR(gp.EventDate) - yob.YearOfBirth) BETWEEN 70 AND 79 THEN '70-79'
			WHEN (YEAR(gp.EventDate) - yob.YearOfBirth) BETWEEN 80 AND 89 THEN '80-89'
			WHEN (YEAR(gp.EventDate) - yob.YearOfBirth) >= 90			   THEN '90+'
					ELSE NULL END,
	EthnicMainGroup,
	IMD2019Quintile1IsMostDeprived5IsLeastDeprived = CASE WHEN IMD2019Decile1IsMostDeprived10IsLeastDeprived IN (1,2) THEN 1 
		WHEN IMD2019Decile1IsMostDeprived10IsLeastDeprived IN (3,4) THEN 2 
		WHEN IMD2019Decile1IsMostDeprived10IsLeastDeprived IN (5,6) THEN 3
		WHEN IMD2019Decile1IsMostDeprived10IsLeastDeprived IN (7,8) THEN 4
		WHEN IMD2019Decile1IsMostDeprived10IsLeastDeprived IN (9,10) THEN 5
			ELSE NULL END 
INTO #SelfHarmEpisodes_all 
FROM [RLS].[vw_GP_Events] gp
LEFT OUTER JOIN #Patients p ON p.PK_Patient_ID = gp.FK_Patient_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientIMDDecile imd ON imd.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE SuppliedCode IN (
	SELECT [Code] FROM #AllCodes WHERE [Concept] IN ('selfharm-episodes') AND [Version] = 1
)
	AND (YEAR(gp.EventDate) - yob.YearOfBirth) >= 10
--237,931
--238,040 with new patient_id workaround


-- CREATE SUMMARY TABLE AT MONTH LEVEL

IF OBJECT_ID('tempdb..#Summary_all') IS NOT NULL DROP TABLE #Summary_all;
SELECT 
	[Month] = DATEADD(MONTH, DATEDIFF(MONTH, 0, EventDate), 0),
	Sex,
	AgeCategory,
	EthnicMainGroup,
	IMD2019Quintile1IsMostDeprived5IsLeastDeprived,
	SelfHarmEpisodes = COUNT(*),
	FirstRecordedSelfharmEpisodes_FullLookback = SUM(CASE WHEN EpisodeNumber = 1 THEN 1 ELSE 0 END)
INTO #Summary_all
FROM #SelfHarmEpisodes_all
GROUP BY 
	DATEADD(MONTH, DATEDIFF(MONTH, 0, EventDate), 0),
	Sex,
	AgeCategory,
	EthnicMainGroup,
	IMD2019Quintile1IsMostDeprived5IsLeastDeprived
HAVING DATEADD(MONTH, DATEDIFF(MONTH, 0, EventDate), 0) BETWEEN '01 JAN 2019' AND '30 APR 2021'
ORDER BY 
	DATEADD(MONTH, DATEDIFF(MONTH, 0, EventDate), 0),
	Sex,
	AgeCategory,
	EthnicMainGroup,
	IMD2019Quintile1IsMostDeprived5IsLeastDeprived
--4003

-- REPEAT THE ABOVE BUT ONLY GOING BACK TO 2019

IF OBJECT_ID('tempdb..#SelfHarmEpisodes_2019Lookback ') IS NOT NULL DROP TABLE #SelfHarmEpisodes_2019Lookback;
SELECT gp.FK_Patient_Link_ID, 
	   EventDate, 
	   EpisodeNumber = ROW_NUMBER() OVER(PARTITION BY gp.FK_Patient_Link_ID ORDER BY EventDate),
	   Sex,
	   AgeCategory = CASE WHEN (YEAR(gp.EventDate) - yob.YearOfBirth) BETWEEN 0 AND 9 THEN '0-9'
			WHEN (YEAR(gp.EventDate) - yob.YearOfBirth) BETWEEN 10 AND 19 THEN '10-19'
			WHEN (YEAR(gp.EventDate) - yob.YearOfBirth) BETWEEN 20 AND 29 THEN '20-29'
			WHEN (YEAR(gp.EventDate) - yob.YearOfBirth) BETWEEN 30 AND 39 THEN '30-39'
			WHEN (YEAR(gp.EventDate) - yob.YearOfBirth) BETWEEN 40 AND 49 THEN '40-49'
			WHEN (YEAR(gp.EventDate) - yob.YearOfBirth) BETWEEN 50 AND 59 THEN '50-59'
			WHEN (YEAR(gp.EventDate) - yob.YearOfBirth) BETWEEN 60 AND 69 THEN '60-69'
			WHEN (YEAR(gp.EventDate) - yob.YearOfBirth) BETWEEN 70 AND 79 THEN '70-79'
			WHEN (YEAR(gp.EventDate) - yob.YearOfBirth) BETWEEN 80 AND 89 THEN '80-89'
			WHEN (YEAR(gp.EventDate) - yob.YearOfBirth) >= 90			   THEN '90+'
					ELSE NULL END,
	EthnicMainGroup,
	IMD2019Quintile1IsMostDeprived5IsLeastDeprived = CASE WHEN IMD2019Decile1IsMostDeprived10IsLeastDeprived IN (1,2) THEN 1 
		WHEN IMD2019Decile1IsMostDeprived10IsLeastDeprived IN (3,4) THEN 2 
		WHEN IMD2019Decile1IsMostDeprived10IsLeastDeprived IN (5,6) THEN 3
		WHEN IMD2019Decile1IsMostDeprived10IsLeastDeprived IN (7,8) THEN 4
		WHEN IMD2019Decile1IsMostDeprived10IsLeastDeprived IN (9,10) THEN 5
			ELSE NULL END 
INTO #SelfHarmEpisodes_2019Lookback 
FROM [RLS].[vw_GP_Events] gp
LEFT OUTER JOIN #Patients p ON p.FK_Patient_Link_ID = gp.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = gp.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = gp.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientIMDDecile imd ON imd.FK_Patient_Link_ID = gp.FK_Patient_Link_ID
WHERE SuppliedCode IN (
	SELECT [Code] FROM #AllCodes WHERE [Concept] IN ('selfharm-episodes') AND [Version] = 1
)
	AND EventDate >= '01 jan 2019'
	AND (YEAR(gp.EventDate) - yob.YearOfBirth) >= 10
--29958

IF OBJECT_ID('tempdb..#Summary_2019Lookback') IS NOT NULL DROP TABLE #Summary_2019Lookback;
SELECT 
	[Month] = DATEADD(MONTH, DATEDIFF(MONTH, 0, EventDate), 0),
	Sex,
	AgeCategory,
	EthnicMainGroup,
	IMD2019Quintile1IsMostDeprived5IsLeastDeprived,
	SelfHarmEpisodes = COUNT(*),
	FirstRecordedSelfharmEpisodes_2019Lookback = SUM(CASE WHEN EpisodeNumber = 1 THEN 1 ELSE 0 END)
INTO #Summary_2019Lookback
FROM #SelfHarmEpisodes_2019Lookback
GROUP BY 
	DATEADD(MONTH, DATEDIFF(MONTH, 0, EventDate), 0),
	Sex,
	AgeCategory,
	EthnicMainGroup,
	IMD2019Quintile1IsMostDeprived5IsLeastDeprived
HAVING DATEADD(MONTH, DATEDIFF(MONTH, 0, EventDate), 0) BETWEEN '01 JAN 2020' AND '30 APR 2021'
ORDER BY 
	DATEADD(MONTH, DATEDIFF(MONTH, 0, EventDate), 0),
	Sex,
	AgeCategory,
	EthnicMainGroup,
	IMD2019Quintile1IsMostDeprived5IsLeastDeprived
--2127


--- FINAL OUTPUT

PRINT('Month, Sex, AgeCategory, EthnicMainGroup, IMD2019Quintile1IsMostDeprived5IsLeastDeprived, SelfHarmEpisodes, FirstRecordedSelfharmEpisodes_FullLookback, FirstRecordedSelfharmEpisodes_2019Lookback')
SELECT
	SA.[Month],
	SA.Sex,
	SA.AgeCategory,
	SA.EthnicMainGroup,
	SA.IMD2019Quintile1IsMostDeprived5IsLeastDeprived,
    SA.SelfHarmEpisodes,
    SA.FirstRecordedSelfharmEpisodes_FullLookback,
	S19.FirstRecordedSelfharmEpisodes_2019Lookback
FROM #Summary_all SA
LEFT JOIN #Summary_2019Lookback S19 
	ON S19.[Month] = SA.[Month] 
		AND S19.Sex = SA.Sex 
		AND S19.AgeCategory = SA.AgeCategory 
		AND S19.EthnicMainGroup = SA.EthnicMainGroup 
		AND S19.IMD2019Quintile1IsMostDeprived5IsLeastDeprived = SA.IMD2019Quintile1IsMostDeprived5IsLeastDeprived
UNION
SELECT
	SA.[Month],
	SA.Sex,
	SA.AgeCategory,
	SA.EthnicMainGroup,
	SA.IMD2019Quintile1IsMostDeprived5IsLeastDeprived,
    SA.SelfHarmEpisodes,
    SA.FirstRecordedSelfharmEpisodes_FullLookback,
	S19.FirstRecordedSelfharmEpisodes_2019Lookback
FROM #Summary_all SA
RIGHT JOIN #Summary_2019Lookback S19 
	ON S19.[Month] = SA.[Month] 
		AND S19.Sex = SA.Sex 
		AND S19.AgeCategory = SA.AgeCategory 
		AND S19.EthnicMainGroup = SA.EthnicMainGroup 
		AND S19.IMD2019Quintile1IsMostDeprived5IsLeastDeprived = SA.IMD2019Quintile1IsMostDeprived5IsLeastDeprived
ORDER BY [Month], Sex, AgeCategory, EthnicMainGroup, IMD2019Quintile1IsMostDeprived5IsLeastDeprived