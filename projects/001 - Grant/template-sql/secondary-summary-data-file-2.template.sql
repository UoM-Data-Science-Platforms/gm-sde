--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2020-01-01';

--> EXECUTE query-classify-secondary-admissions.sql

-- Populate a table with all the patients so in the future we can get their LTCs and deprivation score etc.
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT DISTINCT FK_Patient_Link_ID INTO #Patients FROM #AdmissionTypes;
-- 286087 rows
-- 00:00:01

--> EXECUTE query-patient-ltcs.sql

--> EXECUTE query-patient-ltcs-number-of.sql

--> EXECUTE query-patient-imd.sql

-- Generate cohort so at most one patient per acute provider
IF OBJECT_ID('tempdb..#FinalCohort') IS NOT NULL DROP TABLE #FinalCohort;
SELECT DISTINCT FK_Patient_Link_ID, AcuteProvider INTO #FinalCohort FROM #AdmissionTypes;

PRINT 'AcuteProvider,IMD2019Decile1IsMostDeprived10IsLeastDeprived,NumberOfLTCs,Number';
SELECT 
	p.AcuteProvider, ISNULL(IMD2019Decile1IsMostDeprived10IsLeastDeprived, 0) AS IMD2019Decile1IsMostDeprived10IsLeastDeprived, 
	ISNULL(NumberOfLTCs,0) AS NumberOfLTCs, count(*)
FROM #FinalCohort p
	LEFT OUTER JOIN #NumLTCs ltc ON ltc.FK_Patient_Link_ID = p.FK_Patient_Link_ID
	LEFT OUTER JOIN #PatientIMDDecile imd ON imd.FK_Patient_Link_ID = p.FK_Patient_Link_ID
GROUP BY p.AcuteProvider,IMD2019Decile1IsMostDeprived10IsLeastDeprived, NumberOfLTCs
ORDER BY p.AcuteProvider,IMD2019Decile1IsMostDeprived10IsLeastDeprived, NumberOfLTCs
