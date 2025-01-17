--┌─────────────────────────────────┐
--│ Primary care utilisation file 5 │
--└─────────────────────────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------
-- GEORGE TILSTON	DATE: 23/04/21

-- OUTPUT: Data with the following fields
-- 	•	Date (YYYY-MM-DD) 
-- 	•	CCG (Bolton/Salford/HMR/etc.)
-- 	•	Practice (P27001/P27001/etc..)
-- 	•	2019IMDDecile (integer 1-10)
-- 	•	NumberOfLTCs (integer 0,1,2) – where 2 represents 2 or more
-- 	•	NumberBP (integer) 
-- 	•	NumberBMI (integer) 
-- 	•	NumberCholesterol (integer) 
-- 	•	NumberHbA1c (integer) 
-- 	•	NumberSmokingStatus (integer) 

--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2019-12-23';

--> CODESET bmi:1 smoking-status:1 blood-pressure:1 cholesterol:1 hba1c:1
IF OBJECT_ID('tempdb..#KeyEvents') IS NOT NULL DROP TABLE #KeyEvents;
SELECT CAST(EventDate AS DATE) AS EventDate, FK_Reference_Coding_ID, FK_Reference_SnomedCT_ID, FK_Patient_Link_ID
INTO #KeyEvents
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('bmi','smoking-status','blood-pressure','cholesterol','hba1c') AND [Version]=1) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('bmi','smoking-status','blood-pressure','cholesterol','hba1c') AND [Version]=1)
)
AND EventDate >= @StartDate;

IF OBJECT_ID('tempdb..#KeyEventsPerPatient') IS NOT NULL DROP TABLE #KeyEventsPerPatient;
select FK_Patient_Link_ID, EventDate, CASE WHEN s.Concept IS NULL THEN c.Concept ELSE s.Concept END AS Concept
INTO #KeyEventsPerPatient
FROM #KeyEvents k
LEFT OUTER JOIN #VersionedSnomedSets s ON s.FK_Reference_SnomedCT_ID = k.FK_Reference_SnomedCT_ID
LEFT OUTER JOIN #VersionedCodeSets c ON c.FK_Reference_Coding_ID = k.FK_Reference_Coding_ID
GROUP BY FK_Patient_Link_ID, EventDate, CASE WHEN s.Concept IS NULL THEN c.Concept ELSE s.Concept END;

-- Populate a table with all the patients so in the future we can get their LTCs and deprivation score etc.
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT DISTINCT FK_Patient_Link_ID INTO #Patients FROM #KeyEventsPerPatient;

--> EXECUTE query-patient-ltcs.sql

--> EXECUTE query-patient-ltcs-number-of.sql

--> EXECUTE query-patient-imd.sql

--> EXECUTE query-patient-practice-and-ccg.sql

-- Bring it all together for output
-- PRINT 'EventDate,CCG,GPPracticeCode,IMD2019Decile1IsMostDeprived10IsLeastDeprived,NumberOfLTCs,NumberBP,NumberBMI,NumberCholesterol,NumberHbA1c,NumberSmokingStatus';
SELECT 
	EventDate, CCG, GPPracticeCode, 
	ISNULL(IMD2019Decile1IsMostDeprived10IsLeastDeprived, 0) AS IMD2019Decile1IsMostDeprived10IsLeastDeprived, 
	ISNULL(NumberOfLTCs,0) AS NumberOfLTCs, 
	SUM(CASE WHEN Concept = 'blood-pressure' THEN 1 ELSE 0 END) AS NumberBP,
	SUM(CASE WHEN Concept = 'bmi' THEN 1 ELSE 0 END) AS NumberBMI,
	SUM(CASE WHEN Concept = 'cholesterol' THEN 1 ELSE 0 END) AS NumberCholesterol,
	SUM(CASE WHEN Concept = 'hba1c' THEN 1 ELSE 0 END) AS NumberHbA1c,
	SUM(CASE WHEN Concept = 'smoking-status' THEN 1 ELSE 0 END) AS NumberSmokingStatus
FROM #KeyEventsPerPatient kepp
LEFT OUTER JOIN #NumLTCs ltc ON ltc.FK_Patient_Link_ID = kepp.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientIMDDecile imd ON imd.FK_Patient_Link_ID = kepp.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientPracticeAndCCG pc ON pc.FK_Patient_Link_ID = kepp.FK_Patient_Link_ID
GROUP BY EventDate, CCG, GPPracticeCode,IMD2019Decile1IsMostDeprived10IsLeastDeprived, NumberOfLTCs
ORDER BY EventDate, CCG, GPPracticeCode,IMD2019Decile1IsMostDeprived10IsLeastDeprived, NumberOfLTCs;