--┌────────────────────────────────────┐
--│ Patients Information               │
--└────────────────────────────────────┘

-- OBJECTIVE: To find patients' information (1 row for each ID)

-- INPUT: assumes there exists one temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: Data with the following fields
-- PatientId
-- Sex
-- YearOfBirth
-- Ethnic
-- Religion
-- BMI
-- LSOA
-- IMD
-- DeathTime
-- GPRegister
-- IsCareHomeResident
-- Cancer
-- Asthma
-- Anxiety
-- LongCovid
-- SevereMental


--Just want the output, not the messages
SET NOCOUNT ON;


-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2019-01-01';


-- Create a table with all patients (ID)=========================================================================================================================
IF OBJECT_ID('tempdb..#PatientsToInclude') IS NOT NULL DROP TABLE #PatientsToInclude;
SELECT FK_Patient_Link_ID INTO #PatientsToInclude
FROM RLS.vw_Patient_GP_History
GROUP BY FK_Patient_Link_ID
HAVING MIN(StartDate) < '2022-06-01';

IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #Patients 
FROM #PatientsToInclude;


--> CODESET cancer:1
--> CODESET asthma:1
--> CODESET anxiety:1
--> CODESET long-covid:1
--> CODESET severe-mental-illness:1

--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-year-of-birth.sql
--> EXECUTE query-patient-imd.sql
--> EXECUTE query-patient-lsoa.sql
--> EXECUTE query-patient-care-home-resident.sql


-- Creat a smaller version of GP event table===========================================================================================================
IF OBJECT_ID('tempdb..#GPEvents') IS NOT NULL DROP TABLE #GPEvents;
SELECT FK_Patient_Link_ID, EventDate, FK_Reference_Coding_ID, FK_Reference_SnomedCT_ID
INTO #GPEvents
FROM [RLS].[vw_GP_Events]
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);


-- Create cancer table==================================================================================================================================
IF OBJECT_ID('tempdb..#Cancer') IS NOT NULL DROP TABLE #Cancer;
SELECT DISTINCT FK_Patient_Link_ID, 'Y' AS Cancer
INTO #Cancer
FROM #GPEvents
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'cancer' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'cancer' AND Version = 1)
);

-- Create asthma table==================================================================================================================================
IF OBJECT_ID('tempdb..#Asthma') IS NOT NULL DROP TABLE #Asthma;
SELECT DISTINCT FK_Patient_Link_ID, 'Y' AS Asthma
INTO #Asthma
FROM #GPEvents
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'asthma' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'asthma' AND Version = 1)
);

-- Create anxiety table==================================================================================================================================
IF OBJECT_ID('tempdb..#Anxiety') IS NOT NULL DROP TABLE #Anxiety;
SELECT DISTINCT FK_Patient_Link_ID, 'Y' AS Anxiety
INTO #Anxiety
FROM #GPEvents
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'anxiety' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'anxiety' AND Version = 1)
);

-- Create long Covid table==================================================================================================================================
IF OBJECT_ID('tempdb..#LongCovid') IS NOT NULL DROP TABLE #LongCovid;
SELECT DISTINCT FK_Patient_Link_ID, 'Y' AS LongCovid
INTO #LongCovid
FROM #GPEvents
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'long-covid' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'long-covid' AND Version = 1)
);

-- Create severe mental illness table==================================================================================================================================
IF OBJECT_ID('tempdb..#SevereMental') IS NOT NULL DROP TABLE #SevereMental;
SELECT DISTINCT FK_Patient_Link_ID, 'Y' AS SevereMentall
INTO #SevereMental
FROM #GPEvents
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'severe-mental-illness' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'severe-mental-illness' AND Version = 1)
);

-- Select ethnicity and death date from PatientLink table================================================================================================================================
IF OBJECT_ID('tempdb..#PatientLinkTable') IS NOT NULL DROP TABLE #PatientLinkTable;
SELECT PK_Patient_Link_ID AS FK_Patient_Link_ID, EthnicMainGroup AS Ethnic, DeathDate
INTO #PatientLinkTable
FROM RLS.vw_Patient_Link;


-- Create a table with all patients registered with a GP (ID, Tenancy_ID)========================================================================================
IF OBJECT_ID('tempdb..#PatientsWithGP') IS NOT NULL DROP TABLE #PatientsWithGP;
SELECT DISTINCT FK_Patient_Link_ID, FK_Reference_Tenancy_ID AS Tenancy_ID
INTO #PatientsWithGP FROM [RLS].vw_Patient
WHERE FK_Reference_Tenancy_ID = 2;


-- The final table==========================================================================
SELECT
  p.FK_Patient_Link_ID AS PatientId,
  Sex,
  Ethnic,
  YearOfBirth,
  IMD2019Decile1IsMostDeprived10IsLeastDeprived AS IMD,
  BMI,
  FORMAT (l.DeathDate , 'MMyyyy') AS DeathTime,
  LSOA_Code AS LSOA,
  IsCareHomeResident,
  CASE WHEN FK_Reference_Tenancy_ID = 2 THEN 'Y' ELSE 'N' END AS GPRegister
FROM #Patients p
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #IMDGroup imd ON imd.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientLinkTable l ON l.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientLSOA lsoa ON lsoa.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientCareHomeStatus care ON care.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientsWithGP gp ON gp.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #Cancer c1 ON c1.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #Anxiety c2 ON c2.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #Asthma c3 ON c3.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #LongCovid c4 ON c4.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #SevereMental c5 ON c5.FK_Patient_Link_ID = p.FK_Patient_Link_ID
