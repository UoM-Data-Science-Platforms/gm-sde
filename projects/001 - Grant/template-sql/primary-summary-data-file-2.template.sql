--┌──────────────────────────┐
--│ Primary summary file 2 │
--└──────────────────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------
-- GEORGE TILSTON  DATE: 11/08/21

-- OBJECTIVE: To provide a denominator population when working with the primary data files. This
--						file gives counts per CCG, imd and the number of LTCs

-- OUTPUT: Data with the following fields
-- 	•	CCG
-- 	•	IMD2019Decile1IsMostDeprived10IsLeastDeprived
-- 	•	NumberOfLTCs
-- 	•	Number

--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2019-12-23';

-- Populate a table with all the GM registered patients
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT DISTINCT FK_Patient_Link_ID INTO #Patients FROM RLS.vw_Patient
WHERE FK_Reference_Tenancy_ID=2
AND GPPracticeCode NOT LIKE 'ZZZ%'; -- exclude out of area patients

--> EXECUTE query-patient-ltcs.sql

--> EXECUTE query-patient-ltcs-number-of.sql

--> EXECUTE query-patient-imd.sql

--> EXECUTE query-patient-lsoa.sql

--> EXECUTE query-patient-practice-and-ccg.sql

SELECT 
	CCG,
	ISNULL(IMD2019Decile1IsMostDeprived10IsLeastDeprived, 0) AS IMD2019Decile1IsMostDeprived10IsLeastDeprived, 
	ISNULL(NumberOfLTCs,0) AS NumberOfLTCs,
	COUNT(*) AS Number
FROM #Patients p
	LEFT OUTER JOIN #PatientIMDDecile imd ON imd.FK_Patient_Link_ID = p.FK_Patient_Link_ID
	LEFT OUTER JOIN #NumLTCs ltc ON ltc.FK_Patient_Link_ID = p.FK_Patient_Link_ID
	LEFT OUTER JOIN #PatientLSOA lsoa ON lsoa.FK_Patient_Link_ID = p.FK_Patient_Link_ID
	LEFT OUTER JOIN #PatientPracticeAndCCG ppc ON ppc.FK_Patient_Link_ID = p.FK_Patient_Link_ID
GROUP BY CCG, IMD2019Decile1IsMostDeprived10IsLeastDeprived, NumberOfLTCs
ORDER BY CCG, IMD2019Decile1IsMostDeprived10IsLeastDeprived, NumberOfLTCs;

