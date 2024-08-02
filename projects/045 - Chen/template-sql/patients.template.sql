--┌────────────────────────────────────┐
--│ Patients Information               │
--└────────────────────────────────────┘

-- OBJECTIVE: To find patients' information (1 row for each ID)

-- OUTPUT: Data with the following fields
-- PatientId
-- Sex
-- YearOfBirth
-- Ethnicity
-- BMI
-- Height
-- Weight
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

--> EXECUTE query-build-rq045-cohort.sql
--> EXECUTE query-patient-imd.sql
--> EXECUTE query-patient-care-home-resident.sql

--> CODESET height:1 weight:1
--> CODESET cancer:1 asthma:1 anxiety:1 long-covid:1 severe-mental-illness:1


DECLARE @MinDate datetime;
SET @MinDate = '1900-01-01';
DECLARE @IndexDate datetime;
SET @IndexDate = '2023-12-31';

-- Create a smaller version of GP event table===========================================================================================================
IF OBJECT_ID('tempdb..#GPEvents') IS NOT NULL DROP TABLE #GPEvents;
SELECT gp.FK_Patient_Link_ID, EventDate, SuppliedCode, FK_Reference_Coding_ID, FK_Reference_SnomedCT_ID, [Value], Units
INTO #GPEvents
FROM SharedCare.GP_Events gp
WHERE gp.SuppliedCode IN (SELECT Code FROM #AllCodes)
AND gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate BETWEEN @MinDate and @IndexDate

-- Create cancer table==================================================================================================================================
IF OBJECT_ID('tempdb..#Cancer') IS NOT NULL DROP TABLE #Cancer;
SELECT DISTINCT FK_Patient_Link_ID, 1 AS Cancer
INTO #Cancer
FROM #GPEvents
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'cancer' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'cancer' AND Version = 1)
);

-- Create asthma table==================================================================================================================================
IF OBJECT_ID('tempdb..#Asthma') IS NOT NULL DROP TABLE #Asthma;
SELECT DISTINCT FK_Patient_Link_ID, 1 AS Asthma
INTO #Asthma
FROM #GPEvents
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'asthma' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'asthma' AND Version = 1)
);

-- Create anxiety table==================================================================================================================================
IF OBJECT_ID('tempdb..#Anxiety') IS NOT NULL DROP TABLE #Anxiety;
SELECT DISTINCT FK_Patient_Link_ID, 1 AS Anxiety
INTO #Anxiety
FROM #GPEvents
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'anxiety' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'anxiety' AND Version = 1)
);


-- Create long Covid table==================================================================================================================================
IF OBJECT_ID('tempdb..#LongCovid') IS NOT NULL DROP TABLE #LongCovid;
SELECT DISTINCT FK_Patient_Link_ID, 1 AS LongCovid
INTO #LongCovid
FROM #GPEvents
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'long-covid' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'long-covid' AND Version = 1)
);

-- Create severe mental illness table==================================================================================================================================
IF OBJECT_ID('tempdb..#SevereMental') IS NOT NULL DROP TABLE #SevereMental;
SELECT DISTINCT FK_Patient_Link_ID, 1 AS SevereMental
INTO #SevereMental
FROM #GPEvents
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'severe-mental-illness' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'severe-mental-illness' AND Version = 1)
);


--> EXECUTE query-get-height.sql date:2023-12-31 all-patients:false gp-events-table:#GPEvents
--> EXECUTE query-get-weight.sql date:2023-12-31 all-patients:false gp-events-table:#GPEvents
--> EXECUTE query-patient-bmi.sql gp-events-table:#GPEvents

-- The final table==========================================================================
SELECT
  p.FK_Patient_Link_ID as PatientId,
  p.Sex,
  p.Ethnicity,
  p.YearOfBirth,
  IMD2019Decile1IsMostDeprived10IsLeastDeprived,
  DeathYearAndMonth = FORMAT (p.DeathDate , 'MM-yyyy'),
  LSOA = p.LSOA_Code,
  IsCareHomeResident,
  HO_Cancer = ISNULL(c1.Cancer,0),
  HO_Anxiety = ISNULL(c2.Anxiety,0),
  HO_Asthma = ISNULL(c3.Asthma,0),
  HO_LongCovid = ISNULL(c4.LongCovid,0),
  HO_SevereMentalIllness = ISNULL(c5.SevereMental,0),
  h.HeightInCentimetres,
  DateOfHeightMeasurement = h.HeightDate,
  WeightInKilograms,
  DateOfWeightMeasurement = w.WeightDate,
  BMI,
  DateOfBMIMeasurement
FROM #Cohort p
LEFT OUTER JOIN #PatientIMDDecile imd ON imd.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientCareHomeStatus care ON care.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #Cancer c1 ON c1.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #Anxiety c2 ON c2.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #Asthma c3 ON c3.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #LongCovid c4 ON c4.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #SevereMental c5 ON c5.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientHeight h ON h.FK_Patient_Link_ID = p.FK_Patient_Link_ID 
LEFT OUTER JOIN #PatientWeight w ON w.FK_Patient_Link_ID = p.FK_Patient_Link_ID 
LEFT OUTER JOIN #PatientBMI b ON b.FK_Patient_Link_ID = p.FK_Patient_Link_ID 
