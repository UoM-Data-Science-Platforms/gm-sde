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

---- CREATE TABLE OF ALL RELEVANT EPISODES FROM GP_EVENTS, WITH PATIENT INFO APPENDED, AND ROWNUMBER TO IDENTIFY FIRST EPISODES FOR EACH PATIENT

IF OBJECT_ID('tempdb..#SelfHarmEpisodes_all') IS NOT NULL DROP TABLE #SelfHarmEpisodes_all;
SELECT gp.FK_Patient_Link_ID, 
	   EventDate, 
	   EpisodeNumber = ROW_NUMBER() OVER(PARTITION BY gp.FK_Patient_Link_ID ORDER BY EventDate),
	   Dedupe_Flag = ROW_NUMBER() OVER(PARTITION BY gp.FK_Patient_Link_ID, CAST(EventDate AS DATE), SuppliedCode ORDER BY CAST(EventDate AS DATE)),
	   Sex,
	   AgeCategory = 
			CASE WHEN (YEAR(gp.EventDate) - yob.YearOfBirth) BETWEEN 10 AND 17 THEN '10-17'
			WHEN (YEAR(gp.EventDate) - yob.YearOfBirth) BETWEEN 18 AND 44 THEN '18-44'
			WHEN (YEAR(gp.EventDate) - yob.YearOfBirth) BETWEEN 45 AND 64 THEN '45-64'
			WHEN (YEAR(gp.EventDate) - yob.YearOfBirth) BETWEEN 65 AND 79 THEN '65-79'
			WHEN (YEAR(gp.EventDate) - yob.YearOfBirth) >= 80 			  THEN '80+'
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
--256,088 

---REMOVE EPISODES WHERE THE DATE, CODE, AND PATIENT ARE IDENTICAL. THIS ASSUMES THAT IT IS A DUPLICATE RECORD.

DELETE FROM #SelfHarmEpisodes_all
WHERE DEDUPE_FLAG > 1
--13,686

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
HAVING DATEADD(MONTH, DATEDIFF(MONTH, 0, EventDate), 0) BETWEEN '01 JAN 2019' AND GETDATE() --exclude any test records that have a date past 2021
ORDER BY 
	DATEADD(MONTH, DATEDIFF(MONTH, 0, EventDate), 0),
	Sex,
	AgeCategory,
	EthnicMainGroup,
	IMD2019Quintile1IsMostDeprived5IsLeastDeprived
--2,919

-- CREATE A SUBSET TABLE CONTAINING ONLY EPISODES FROM 2019 ONWARDS

IF OBJECT_ID('tempdb..#SelfHarmEpisodes_2019Lookback ') IS NOT NULL DROP TABLE #SelfHarmEpisodes_2019Lookback;
SELECT
	FK_Patient_Link_ID, 
	EventDate, 
	EpisodeNumber = ROW_NUMBER() OVER(PARTITION BY FK_Patient_Link_ID ORDER BY EventDate),
	Sex,
	AgeCategory,
	EthnicMainGroup,
	IMD2019Quintile1IsMostDeprived5IsLeastDeprived
INTO #SelfHarmEpisodes_2019Lookback
FROM #SelfHarmEpisodes_all
WHERE EventDate >= '01 jan 2019'
--32,616

-- SUMMARY TABLE USING SUBSET CREATED ABOVE, USING 2019 ONLY AS THE LOOKBACK PERIOD FOR 2020 ONWARDS

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
HAVING DATEADD(MONTH, DATEDIFF(MONTH, 0, EventDate), 0) BETWEEN '01 JAN 2020' AND GETDATE() --exclude any test records that have a date past 2021
ORDER BY 
	DATEADD(MONTH, DATEDIFF(MONTH, 0, EventDate), 0),
	Sex,
	AgeCategory,
	EthnicMainGroup,
	IMD2019Quintile1IsMostDeprived5IsLeastDeprived
--1,582

--- FINAL OUTPUT

SELECT
	SA.[Month],
	SA.Sex,
	SA.AgeCategory,
	SA.EthnicMainGroup,
	SA.IMD2019Quintile1IsMostDeprived5IsLeastDeprived,
    SA.SelfHarmEpisodes,
    SA.FirstRecordedSelfharmEpisodes_FullLookback,
	FirstRecordedSelfharmEpisodes_2019Lookback = ISNULL(S19.FirstRecordedSelfharmEpisodes_2019Lookback, 0)
FROM #Summary_all SA
LEFT JOIN #Summary_2019Lookback S19 
	ON S19.[Month] = SA.[Month] 
		AND S19.Sex = SA.Sex 
		AND S19.AgeCategory = SA.AgeCategory 
		AND S19.EthnicMainGroup = SA.EthnicMainGroup 
		AND S19.IMD2019Quintile1IsMostDeprived5IsLeastDeprived = SA.IMD2019Quintile1IsMostDeprived5IsLeastDeprived
ORDER BY [Month], Sex, AgeCategory, EthnicMainGroup, IMD2019Quintile1IsMostDeprived5IsLeastDeprived
--2,919