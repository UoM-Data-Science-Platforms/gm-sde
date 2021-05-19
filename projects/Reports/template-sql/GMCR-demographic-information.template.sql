--┌───────────────────┐
--│ GMCR demographics │
--└───────────────────┘

-- OBJECTIVE: Attempts to provide a demographic breakdown of all patients
--						in the GMCR. This is useful for papers that require summary
--						data about their patient population. This provides the demographics
--						for the population of living patients registered with a GM GP.
--						This might not be suitable for all papers. There are other tables
--            containing patient ids which can be substituted into the final 
--            SELECT statement. The only caveat is that if you pick a population
--            that includes dead people, you will need to change the age calculation
--            as it assumes that patients are alive today.

-- INPUT: No pre-requisites

-- OUTPUT: A table containing key demographic information.

--Just want the output, not the messages
SET NOCOUNT ON;

--> EXECUTE query-practice-systems-lookup.sql

-- Every unique person in the GMCR database
IF OBJECT_ID('tempdb..#AllGMCRPatients') IS NOT NULL DROP TABLE #AllGMCRPatients;
SELECT PK_Patient_Link_ID AS FK_Patient_Link_ID INTO #AllGMCRPatients FROM RLS.vw_Patient_Link;
-- 5464180

-- Populate patient table to get other demographic info
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT FK_Patient_Link_ID INTO #Patients FROM #AllGMCRPatients;

--> EXECUTE query-patient-imd.sql
--> EXECUTE query-patient-lsoa.sql
--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-year-of-birth.sql

-- Every living unique person in the GMCR database
IF OBJECT_ID('tempdb..#AllLivingGMCRPatients') IS NOT NULL DROP TABLE #AllLivingGMCRPatients;
SELECT PK_Patient_Link_ID AS FK_Patient_Link_ID INTO #AllLivingGMCRPatients FROM RLS.vw_Patient_Link WHERE Deceased='N';
-- 5238741

-- Every unique person in the GMCR database who now or previously was registered with a GM GP
IF OBJECT_ID('tempdb..#GMCRPatientsWithGPFeed') IS NOT NULL DROP TABLE #GMCRPatientsWithGPFeed;
SELECT distinct FK_Patient_Link_ID INTO #GMCRPatientsWithGPFeed FROM RLS.vw_Patient WHERE FK_Reference_Tenancy_ID=2;
-- 3487444

-- Every unique living person in the GMCR database who now or previously was registered with a GM GP
IF OBJECT_ID('tempdb..#GMCRLivingPatientsWithGPFeed') IS NOT NULL DROP TABLE #GMCRLivingPatientsWithGPFeed;
SELECT FK_Patient_Link_ID INTO #GMCRLivingPatientsWithGPFeed FROM #GMCRPatientsWithGPFeed
INTERSECT
SELECT FK_Patient_Link_ID FROM #AllLivingGMCRPatients;
-- 3391988

-- Every unique person in the GMCR database who is currently registered with a GM GP (includes dead people who died while registered at a GM GP)
IF OBJECT_ID('tempdb..#GMCRPatientsWithGMGP') IS NOT NULL DROP TABLE #GMCRPatientsWithGMGP;
SELECT DISTINCT FK_Patient_Link_ID INTO #GMCRPatientsWithGMGP FROM RLS.vw_Patient
WHERE GPPracticeCode NOT LIKE 'ZZ%'
AND FK_Reference_Tenancy_ID=2;
-- 3246326

-- Every unique living person in the GMCR database who is currently registered with a GM GP
IF OBJECT_ID('tempdb..#GMCRLivingPatientsWithGMGP') IS NOT NULL DROP TABLE #GMCRLivingPatientsWithGMGP;
SELECT FK_Patient_Link_ID INTO #GMCRLivingPatientsWithGMGP FROM #GMCRPatientsWithGMGP
INTERSECT
SELECT FK_Patient_Link_ID FROM #AllLivingGMCRPatients;
-- 3153135

SELECT '1. Number of patients' AS Demographic, count(*) FROM #GMCRLivingPatientsWithGMGP
UNION
SELECT '2. SEX: ' + CASE WHEN Sex IS NULL THEN 'U' ELSE Sex END, count(*) FROM #GMCRLivingPatientsWithGMGP p
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
GROUP BY Sex
UNION
SELECT '3. AGE: MEAN', AVG(CAST(YEAR(GETDATE()) - YearOfBirth AS FLOAT)) from #GMCRLivingPatientsWithGMGP p
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
union
SELECT '3. AGE: SD', STDEV(YEAR(GETDATE()) - YearOfBirth) from #GMCRLivingPatientsWithGMGP p
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
UNION
SELECT  CASE
			WHEN quartile = 1 THEN '3. AGE: LQ'
			WHEN quartile = 2 THEN '3. AGE: MEDIAN'
			WHEN quartile = 3 THEN '3. AGE: UQ'
			WHEN quartile = 4 THEN '3. AGE: MAX'
		END, max(Age) as [my_column]
FROM    (SELECT YEAR(GETDATE()) - YearOfBirth AS Age, ntile(4) OVER (ORDER BY YEAR(GETDATE()) - YearOfBirth) AS [quartile]
         FROM    #GMCRLivingPatientsWithGMGP p
	LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID) i
GROUP BY quartile
UNION
SELECT '4. IMD: ' + CASE WHEN IMD2019Decile1IsMostDeprived10IsLeastDeprived IS NULL THEN 'UNKNOWN' ELSE CAST(IMD2019Decile1IsMostDeprived10IsLeastDeprived AS NVARCHAR) END, count(*) from #GMCRLivingPatientsWithGMGP p
LEFT OUTER JOIN #PatientIMDDecile imd ON imd.FK_Patient_Link_ID = p.FK_Patient_Link_ID
GROUP BY IMD2019Decile1IsMostDeprived10IsLeastDeprived
ORDER BY Demographic