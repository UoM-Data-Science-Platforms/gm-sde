--+---------------------------+
--� GMCR population counts    �
--+---------------------------+

-- OBJECTIVE: To provide several counts to understand more about the GMCR population

-- INPUT: No pre-requisites

-- OUTPUT: A table wih these number counts:
--  - All patients in GMCR
--       - All patients in GMCR who registered with a GP
--       - All patients in GMCR who not registered with a GP
--  - Patients registered with a GP
--       - Patients registered with a GP and live inside GM (alive and not opted out, dead, opted out)
--       - Patients registered with a GP and have GP practice inside GM (alive and not opted out, dead, opted out)
--       - Patients registered with a GP and have no GP records
--  - Patients not registered with a GP
--       - Patients not registered with a GP and live inside GM
--       - Patients not registered with a GP and have GP practice inside GM (alive and not opted out, dead, opted out)
--       - Patients not registered with a GP and have no GP records
--  - Updated date

-- Create a table with all patients (ID)=========================================================================================================================
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT DISTINCT FK_Patient_Link_ID INTO #Patients FROM [RLS].vw_Patient;


-- Create a table with all patients registered with a GP (ID, Tenancy_ID)========================================================================================
IF OBJECT_ID('tempdb..#PatientsWithGP') IS NOT NULL DROP TABLE #PatientsWithGP;
SELECT DISTINCT FK_Patient_Link_ID, FK_Reference_Tenancy_ID AS Tenancy_ID 
INTO #PatientsWithGP FROM [RLS].vw_Patient
WHERE FK_Reference_Tenancy_ID = 2;


-- Create a table with LSOA codes and GM areas (ID, LSOA_Code, GM_Area)==========================================================================================
--> EXECUTE query-lsoa-gm-lookup.sql
--> EXECUTE query-patient-lsoa.sql

IF OBJECT_ID('tempdb..#PatientsLSOAGM') IS NOT NULL DROP TABLE #PatientsLSOAGM;
SELECT g.FK_Patient_Link_ID, g.LSOA_Code, l.GM_Area
INTO #PatientsLSOAGM
FROM #LSOALookup l
RIGHT JOIN #PatientLSOA g
ON g.LSOA_Code = l.LSOA_Code;

-- Tidy up - helpful in ensuring the tempdb doesn't run out of space mid-query
DROP TABLE #LSOALookup;
DROP TABLE #PatientLSOA;


-- Find patients who registered with GP outside GM (ID, GP_Code, CCG)==============================================================================================
-- If patients have a tenancy id of 2 we take this as their most likely GP practice code
-- as this is the GP data feed and so most likely to be up to date
IF OBJECT_ID('tempdb..#PatientPractice') IS NOT NULL DROP TABLE #PatientPractice;
SELECT FK_Patient_Link_ID, MIN(GPPracticeCode) as GPPracticeCode INTO #PatientPractice FROM RLS.vw_Patient
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_Tenancy_ID = 2
AND GPPracticeCode IS NOT NULL
GROUP BY FK_Patient_Link_ID
HAVING MIN(GPPracticeCode) = MAX(GPPracticeCode);

-- Find the patients who remain unmatched
IF OBJECT_ID('tempdb..#UnmatchedPatientsForPracticeCode') IS NOT NULL DROP TABLE #UnmatchedPatientsForPracticeCode;
SELECT FK_Patient_Link_ID INTO #UnmatchedPatientsForPracticeCode FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientPractice;

-- If every GPPracticeCode is the same for all their linked patient ids then we use that
INSERT INTO #PatientPractice
SELECT FK_Patient_Link_ID, MIN(GPPracticeCode) FROM RLS.vw_Patient
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedPatientsForPracticeCode)
AND GPPracticeCode IS NOT NULL
GROUP BY FK_Patient_Link_ID
HAVING MIN(GPPracticeCode) = MAX(GPPracticeCode);

-- Find any still unmatched patients
TRUNCATE TABLE #UnmatchedPatientsForPracticeCode;
INSERT INTO #UnmatchedPatientsForPracticeCode
SELECT FK_Patient_Link_ID FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientPractice;

-- If there is a unique most recent GP practice then we use that
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

--> EXECUTE query-ccg-lookup.sql

IF OBJECT_ID('tempdb..#PatientsGPGM') IS NOT NULL DROP TABLE #PatientsGPGM;
SELECT p.FK_Patient_Link_ID, ISNULL(pp.GPPracticeCode,'') AS GP_Code, ISNULL(ccg.CcgName, '') AS CCG
INTO #PatientsGPGM
FROM #Patients p
LEFT OUTER JOIN #PatientPractice pp ON pp.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN SharedCare.Reference_GP_Practice gp ON gp.OrganisationCode = pp.GPPracticeCode
LEFT OUTER JOIN #CCGLookup ccg ON ccg.CcgId = gp.Commissioner;

-- Tidy up - helpful in ensuring the tempdb doesn't run out of space mid-query
DROP TABLE #PatientPractice;
DROP TABLE #UnmatchedPatientsForPracticeCode;
DROP TABLE #CCGLookup;


-- Find patients opt out of data sharing (ID, Opt_Out)==============================================================================================================
-- If patients have a tenancy id of 2 we take this as their most likely opt-out status
-- as this is the GP data feed and so most likely to be up to date
IF OBJECT_ID('tempdb..#PatientsOptOut') IS NOT NULL DROP TABLE #PatientsOptOut;
SELECT FK_Patient_Link_ID, MIN(CodingOptOutFlag) as CodingOptOutFlag INTO #PatientsOptOut FROM RLS.vw_Patient
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_Tenancy_ID = 2
AND CodingOptOutFlag IS NOT NULL
GROUP BY FK_Patient_Link_ID
HAVING MIN(CodingOptOutFlag) = MAX(CodingOptOutFlag);

-- Find the patients who remain unmatched
IF OBJECT_ID('tempdb..#UnmatchedPatientOptOut') IS NOT NULL DROP TABLE #UnmatchedPatientOptOut;
SELECT FK_Patient_Link_ID INTO #UnmatchedPatientOptOut FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientsOptOut;

-- If every CodingOptOutFlag is the same for all their linked patient ids then we use that
INSERT INTO #PatientsOptOut
SELECT FK_Patient_Link_ID, MIN(CodingOptOutFlag) FROM RLS.vw_Patient
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedPatientOptOut)
AND CodingOptOutFlag IS NOT NULL
GROUP BY FK_Patient_Link_ID
HAVING MIN(CodingOptOutFlag) = MAX(CodingOptOutFlag);

-- Find any still unmatched patients
TRUNCATE TABLE #UnmatchedPatientOptOut;
INSERT INTO #UnmatchedPatientOptOut
SELECT FK_Patient_Link_ID FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientsOptOut;

-- If there is a unique most recent update date then we use that
INSERT INTO #PatientsOptOut
SELECT p.FK_Patient_Link_ID, MIN(p.CodingOptOutFlag) FROM RLS.vw_Patient p
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(HDMModifDate) MostRecentDate FROM RLS.vw_Patient
	WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedPatientOptOut)
	GROUP BY FK_Patient_Link_ID
) sub ON sub.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND sub.MostRecentDate = p.HDMModifDate
WHERE p.CodingOptOutFlag IS NOT NULL
GROUP BY p.FK_Patient_Link_ID
HAVING MIN(CodingOptOutFlag) = MAX(CodingOptOutFlag);

-- Tidy up - helpful in ensuring the tempdb doesn't run out of space mid-query
DROP TABLE #UnmatchedPatientOptOut;


-- Find patients who died (ID, Deceased)=====================================================================================================================================
IF OBJECT_ID('tempdb..#PatientsDied') IS NOT NULL DROP TABLE #PatientsDied;
SELECT PK_Patient_Link_ID, Deceased
INTO #PatientsDied
FROM [RLS].[vw_Patient_Link];


-- Find patients who have GP event records (ID, ID_GP_Event)==========================================================================================================================
IF OBJECT_ID('tempdb..#PatientsGPEvent') IS NOT NULL DROP TABLE #PatientsGPEvent;
SELECT DISTINCT FK_Patient_Link_ID AS ID_GP_Event
INTO #PatientsGPEvent
FROM RLS.vw_GP_Events;


-- Find patients who have GP medication records (ID, ID_GP_Medication)==========================================================================================================================
IF OBJECT_ID('tempdb..#PatientsGPMedication') IS NOT NULL DROP TABLE #PatientsGPMedication;
SELECT DISTINCT FK_Patient_Link_ID AS ID_GP_Medication
INTO #PatientsGPMedication
FROM RLS.vw_GP_Medications;


-- Merge all information into 1 table============================================================================================================================
-- Merge into 1 table
IF OBJECT_ID('tempdb..#Population') IS NOT NULL DROP TABLE #Population;
SELECT p.FK_Patient_Link_ID, gp.Tenancy_ID, lsoa.LSOA_Code, lsoa.GM_Area, gpgm.GP_Code, gpgm.CCG, opt.CodingOptOutFlag, die.Deceased, e.ID_GP_Event, m.ID_GP_Medication 
INTO #Population
FROM #Patients p
LEFT OUTER JOIN #PatientsWithGP gp ON gp.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientsLSOAGM lsoa ON lsoa.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientsGPGM gpgm ON gpgm.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientsOptOut opt ON opt.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientsDied die ON die.PK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientsGPEvent e ON e.ID_GP_Event = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientsGPMedication m ON m.ID_GP_Medication = p.FK_Patient_Link_ID;

SELECT TOP (50) *
FROM #Population;

-- Tidy up - helpful in ensuring the tempdb doesn't run out of space mid-query
DROP TABLE #Patients;
DROP TABLE #PatientsWithGP;
DROP TABLE #PatientsLSOAGM;
DROP TABLE #PatientsGPGM;
DROP TABLE #PatientsOptOut;
DROP TABLE #PatientsDied;
DROP TABLE #PatientsGPEvent;
DROP TABLE #PatientsGPMedication;


-- Get information for GMCR population===========================================================================================================================
-- Today date
SELECT FORMAT(GETDATE(), 'yyyy-MM-dd') AS Updated_Date;

-- All patients in GMCR
SELECT COUNT (*) AS Total_Population
FROM #Population;

-- All patients in GMCR who registered with GP
SELECT COUNT (*) AS Patients_With_GP
FROM #Population
WHERE Tenancy_ID = 2;

-- Patients who registered with a GP and had LSOA code inside GM
SELECT COUNT (*) AS Patients_With_GP_Live_In_GM
FROM #Population
WHERE Tenancy_ID = 2 AND GM_Area IS NOT NULL;

-- Patients who registered with a GP and had LSOA code inside GM and alive (no opt-out)
SELECT COUNT (*) AS Patients_With_GP_Live_In_GM_Alive
FROM #Population
WHERE Tenancy_ID = 2 AND GM_Area IS NOT NULL AND Deceased = 'N' AND CodingOptOutFlag = 'N';

-- Patients who registered with a GP and had LSOA code inside GM and dead
SELECT COUNT (*) AS Patients_With_GP_Live_In_GM_Dead
FROM #Population
WHERE Tenancy_ID = 2 AND GM_Area IS NOT NULL AND Deceased = 'Y';

-- Patients who registered with a GP and had LSOA code inside GM and opted out
SELECT COUNT (*) AS Patients_With_GP_Live_In_GM_Opt_Out
FROM #Population
WHERE Tenancy_ID = 2 AND GM_Area IS NOT NULL AND CodingOptOutFlag = 'Y';

-- Patients who registered with a GP and GP inside GM
SELECT COUNT (*) AS Patients_With_GP_Practice_In_GM
FROM #Population
WHERE Tenancy_ID = 2 AND CCG <> '';

-- Patients who registered with a GP and GP inside GM and alive (no opt-out)
SELECT COUNT (*) AS Patients_With_GP_Practice_In_GM_Alive
FROM #Population
WHERE Tenancy_ID = 2 AND CCG <> '' AND Deceased = 'N' AND CodingOptOutFlag = 'N';

-- Patients who registered with a GP and GP inside GM and dead
SELECT COUNT (*) AS Patients_With_GP_Practice_In_GM_Dead
FROM #Population
WHERE Tenancy_ID = 2 AND CCG <> '' AND Deceased = 'Y';

-- Patients who registered with a GP and GP inside GM and opted out
SELECT COUNT (*) AS Patients_With_GP_Practice_In_GM_Opt_Out
FROM #Population
WHERE Tenancy_ID = 2 AND CCG <> '' AND CodingOptOutFlag = 'Y';

-- Patients who registered with a GP and have no GP records
SELECT COUNT (*) AS Patients_With_GP_No_GP_Records
FROM #Population
WHERE Tenancy_ID = 2 AND ID_GP_Event IS NULL AND ID_GP_Medication IS NULL;

-- All patients in GMCR who not registered with GP
SELECT COUNT (*) AS Patients_Without_GP
FROM #Population
WHERE Tenancy_ID IS NULL;

-- Patients in GMCR who not registered with GP and live inside GM
SELECT COUNT (*) AS Patients_Without_GP_Live_In_GM
FROM #Population
WHERE Tenancy_ID IS NULL AND GM_Area IS NOT NULL;

-- Patients in GMCR who not registered with GP and live inside GM and alive (no opt-out)
SELECT COUNT (*) AS Patients_Without_GP_Live_In_GM_Alive
FROM #Population
WHERE Tenancy_ID IS NULL AND GM_Area IS NOT NULL AND Deceased = 'N' AND CodingOptOutFlag = 'N';

-- Patients in GMCR who not registered with GP and live inside GM and dead
SELECT COUNT (*) AS Patients_Without_GP_Live_In_GM_Dead
FROM #Population
WHERE Tenancy_ID IS NULL AND GM_Area IS NOT NULL AND Deceased = 'Y';

-- Patients in GMCR who not registered with GP and live inside GM and opted out
SELECT COUNT (*) AS Patients_Without_GP_Live_In_GM_Opt_Out
FROM #Population
WHERE Tenancy_ID IS NULL AND GM_Area IS NOT NULL AND CodingOptOutFlag = 'Y';

-- Patients in GMCR who not registered with GP and had no GP records
SELECT COUNT (*) AS Patients_Without_GP_No_GP_Records
FROM #Population
WHERE Tenancy_ID IS NULL AND ID_GP_Event IS NULL AND ID_GP_Medication IS NULL;