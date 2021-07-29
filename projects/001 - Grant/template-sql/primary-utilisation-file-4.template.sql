--┌─────────────────────────────────┐
--│ Primary care utilisation file 4 │
--└─────────────────────────────────┘

-- OUTPUT: Data with the following fields
-- 	•	Date (YYYY-MM-DD) 
-- 	•	CCG (Bolton/Salford/HMR/etc.)
-- 	•	Practice (P27001/P27001/etc..)
-- 	•	CovidHealthcareUtilisation (TRUE/FALSE)
-- 	•	2019IMDDecile (integer 1-10)
-- 	•	LTCGroup  (none/respiratory/mental health/cardiovascular/ etc.) 
-- 	•	NumberFirstPrescriptions (integer) 

--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2019-12-23';

--> EXECUTE query-first-prescribing-of-medication.sql

-- Populate a table with all the patients so in the future we can get their LTCs and deprivation score etc.
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT DISTINCT FK_Patient_Link_ID INTO #Patients FROM #FirstMedications;

-- Populate a table with all the patients and the event dates for use later classifying as COVID/non-COVID
IF OBJECT_ID('tempdb..#PatientDates') IS NOT NULL DROP TABLE #PatientDates;
SELECT DISTINCT FK_Patient_Link_ID, FirstMedDate as EventDate INTO #PatientDates FROM #FirstMedications;

--> EXECUTE query-patient-ltcs.sql

--> EXECUTE query-patient-ltcs-group.sql

--> EXECUTE query-patient-imd.sql

--> EXECUTE query-primary-care-covid-utilisation.sql start-date:2019-12-23

--> EXECUTE query-patient-practice-and-ccg.sql

-- We need to remove the main COVID vaccine codes from the medications as they cause
-- spikes which we're not interested in
IF OBJECT_ID('tempdb..#COVIDVaccMedCodes') IS NOT NULL DROP TABLE #COVIDVaccMedCodes;
SELECT 'S'+CONVERT(VARCHAR,FK_Reference_SnomedCT_ID) AS Code INTO #COVIDVaccMedCodes
FROM SharedCare.Reference_Local_Code
WHERE LocalCode IN ('COCO138186NEMIS','CODI138564NEMIS','TASO138184NEMIS')
AND FK_Reference_SnomedCT_ID != -1
UNION
SELECT 'F'+CONVERT(VARCHAR,FK_Reference_Coding_ID) FROM SharedCare.Reference_Local_Code
WHERE LocalCode IN ('COCO138186NEMIS','CODI138564NEMIS','TASO138184NEMIS')
AND FK_Reference_Coding_ID != -1;

-- Bring it all together for output
-- PRINT 'FirstMedDate,CCG,GPPracticeCode,IMD2019Decile1IsMostDeprived10IsLeastDeprived,LTCGroup,CovidHealthcareUtilisation,NumberFirstPrescriptions';
SELECT 
	fm.FirstMedDate,	
	'Y' AS IsCovidVaccine,
	CCG, GPPracticeCode, 
	ISNULL(IMD2019Decile1IsMostDeprived10IsLeastDeprived, 0) AS IMD2019Decile1IsMostDeprived10IsLeastDeprived, 
	ISNULL(LTCGroup, 'None') AS LTCGroup, CovidHealthcareUtilisation, count(*) AS NumberFirstPrescriptions  
FROM #FirstMedications fm
LEFT OUTER JOIN #COVIDUtilisationPrimaryCare c ON c.FK_Patient_Link_ID = fm.FK_Patient_Link_ID AND c.EventDate = fm.FirstMedDate
LEFT OUTER JOIN #LTCGroups ltc ON ltc.FK_Patient_Link_ID = fm.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientIMDDecile imd ON imd.FK_Patient_Link_ID = fm.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientPracticeAndCCG pc ON pc.FK_Patient_Link_ID = fm.FK_Patient_Link_ID
WHERE fm.Code IN (SELECT Code FROM #COVIDVaccMedCodes)
GROUP BY FirstMedDate, CCG, GPPracticeCode,IMD2019Decile1IsMostDeprived10IsLeastDeprived, LTCGroup, CovidHealthcareUtilisation
UNION
SELECT 
	fm.FirstMedDate,	
	'N' AS IsCovidVaccine,
	CCG, GPPracticeCode, 
	ISNULL(IMD2019Decile1IsMostDeprived10IsLeastDeprived, 0) AS IMD2019Decile1IsMostDeprived10IsLeastDeprived, 
	ISNULL(LTCGroup, 'None') AS LTCGroup, CovidHealthcareUtilisation, count(*) AS NumberFirstPrescriptions  
FROM #FirstMedications fm
LEFT OUTER JOIN #COVIDUtilisationPrimaryCare c ON c.FK_Patient_Link_ID = fm.FK_Patient_Link_ID AND c.EventDate = fm.FirstMedDate
LEFT OUTER JOIN #LTCGroups ltc ON ltc.FK_Patient_Link_ID = fm.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientIMDDecile imd ON imd.FK_Patient_Link_ID = fm.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientPracticeAndCCG pc ON pc.FK_Patient_Link_ID = fm.FK_Patient_Link_ID
WHERE fm.Code NOT IN (SELECT Code FROM #COVIDVaccMedCodes)
GROUP BY FirstMedDate, CCG, GPPracticeCode,IMD2019Decile1IsMostDeprived10IsLeastDeprived, LTCGroup, CovidHealthcareUtilisation
ORDER BY FirstMedDate, IsCovidVaccine, CCG, GPPracticeCode,IMD2019Decile1IsMostDeprived10IsLeastDeprived, LTCGroup, CovidHealthcareUtilisation;
