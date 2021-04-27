--┌──────────────────────────┐
--│ Secondary summary file 1 │
--└──────────────────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------
-- GEORGE TILSTON	DATE: 23/04/21

-- OBJECTIVE: To provide a denominator population when working with the secondary data files. This
--						file gives counts per hospital, imd and the LTC group.

-- OUTPUT: Data with the following fields
-- 	•	MostLikelyHospitalFromLSOA
-- 	•	IMD2019Decile1IsMostDeprived10IsLeastDeprived
-- 	•	LTCGroup
-- 	•	Number

--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2020-01-01';

-- Populate a table with all the GM registered patients
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT DISTINCT FK_Patient_Link_ID INTO #Patients FROM RLS.vw_Patient
WHERE FK_Reference_Tenancy_ID=2;

--> EXECUTE query-patient-ltcs.sql

--> EXECUTE query-patient-ltcs-group.sql

--> EXECUTE query-patient-imd.sql

--> EXECUTE query-patient-lsoa.sql

--> EXECUTE query-patient-lsoa-likely-hospital.sql

--> EXECUTE query-patient-practice-and-ccg.sql

SELECT 
	ISNULL(LikelyLSOAHospital, 'UnknownLSOA') AS MostLikelyHospitalFromLSOA,
	CASE WHEN CCG = 'Manchester' THEN 'Y' ELSE 'N' END AS IsManchesterCCGResident,
	ISNULL(IMD2019Decile1IsMostDeprived10IsLeastDeprived, 0) AS IMD2019Decile1IsMostDeprived10IsLeastDeprived, 
	ISNULL(LTCGroup, 'None') AS LTCGroup,
	COUNT(*) AS Number
FROM #Patients p
	LEFT OUTER JOIN #PatientIMDDecile imd ON imd.FK_Patient_Link_ID = p.FK_Patient_Link_ID
	LEFT OUTER JOIN #LTCGroups ltc ON ltc.FK_Patient_Link_ID = p.FK_Patient_Link_ID
	LEFT OUTER JOIN #PatientLSOA lsoa ON lsoa.FK_Patient_Link_ID = p.FK_Patient_Link_ID
	LEFT OUTER JOIN #LikelyLSOAHospital hosp ON hosp.LSOA = lsoa.LSOA_Code
	LEFT OUTER JOIN #PatientPracticeAndCCG ppc ON ppc.FK_Patient_Link_ID = p.FK_Patient_Link_ID
GROUP BY LikelyLSOAHospital, CASE WHEN CCG = 'Manchester' THEN 'Y' ELSE 'N' END, IMD2019Decile1IsMostDeprived10IsLeastDeprived, LTCGroup
ORDER BY LikelyLSOAHospital, CASE WHEN CCG = 'Manchester' THEN 'Y' ELSE 'N' END, IMD2019Decile1IsMostDeprived10IsLeastDeprived, LTCGroup;