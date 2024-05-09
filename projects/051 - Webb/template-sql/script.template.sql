--┌────────────────────────────────────────────────────┐
--│ Mental illness diagnoses and self-harm episodes    │
--└────────────────────────────────────────────────────┘

----- RESEARCH DATA ENGINEER CHECK ------
-- 25th August 2022 - George Tilston   --
-----------------------------------------

-- OUTPUT: Data with the following fields
--  - Month (YYYY-MM)
--  - Sex (M/F)
--  - EthnicGroup (White British, Black, South Asian, Other)
--  - AgeCategory (10-17, 18-44, 45-64, 65-79, 80+)
--  - IMDQuintile (1, 2, 3, 4, 5)
--  - FirstRecordedAnxietyAll (int)
--  - FirstRecordedAnxiety2019 (int)
--  - NumberAnxietyEpisodes (int)
--  - FirstRecordedDepressionAll (int)
--  - FirstRecordedDepression2019 (int)
--  - NumberDepressionEpisodes (int)
--  - FirstRecordedADHDAll (int)
--  - FirstRecordedADHD2019 (int)
--  - NumberADHDEpisodes (int)
--  - FirstRecordedASDAll (int)
--  - FirstRecordedASD2019 (int)
--  - NumberASDEpisodes (int)
--  - FirstRecordedEatingDisordersAll (int)
--  - FirstRecordedEatingDisorders2019 (int)
--  - NumberEatingDisordersEpisodes (int)
--  - FirstRecordedSchizophreniaAll (int)
--  - FirstRecordedSchizophrenia2019 (int)
--  - NumberSchizophreniaEpisodes (int)
--  - FirstRecordedBipolarAll (int)
--  - FirstRecordedBipolar2019 (int)
--  - NumberBipolarEpisodes (int)
--  - FirstRecordedSelfharmAll (int)
--  - FirstRecordedSelfharm2019 (int)
--  - NumberSelfharmEpisodes (int)
--  - NumberAllPsychotropicMedication (int)
--  - NumberMAOI (int)
--  - NumberNRI (int)
--  - NumberSARI (int)
--  - NumberSMS (int)
--  - NumberSNRI (int)
--  - NumberSSRI (int)
--  - NumberTricyclicAntidepressants (int)
--  - NumberTetracyclicAntidepressants (int)
--  - NumberOtherAntidepressants (int)
--  - NumberBarbiturate (int)
--  - NumberBenzodiazepines (int)
--  - NumberNBBRA (int)
--  - NumberOtherAnxiolyticsHypnotics (int)
--  - NumberAntipsychotics (int)
--  - NumberAnticonvulsants (int)
--  - NumberLithium (int)
--  - NumberOffLabelMoodStabilisers (int)
--  - NumberADHDMedication (int)


--Just want the output, not the messages
SET NOCOUNT ON;


-- Create a table with all patients (ID)=========================================================================================================================

-- Table of all patients with a GP record
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT DISTINCT FK_Patient_Link_ID
INTO #Patients
FROM SharedCare.Patient
WHERE FK_Reference_Tenancy_ID=2
AND GPPracticeCode NOT LIKE 'ZZZ%';
-- 14s

--> EXECUTE query-patient-year-of-birth.sql
-- 15s

-- Max age is 24 and first year is 2019, so we can exclude everyone born in 1994 and before.
TRUNCATE TABLE #Patients;
INSERT INTO #Patients
SELECT FK_Patient_Link_ID FROM #PatientYearOfBirth WHERE YearOfBirth > 1994;
-- 0s

--> EXECUTE query-patient-sex.sql
-- 10s
--> EXECUTE query-patient-imd.sql
-- 12s
--> EXECUTE query-patient-practice-and-ccg.sql
-- 9s



-- Need to import a code set here to ensure the #AllCode table is available in the next SQL block
--> CODESET anxiety:1

-- Creat a smaller version of GP event table------------------------------------------------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#GPEvents') IS NOT NULL DROP TABLE #GPEvents;
SELECT FK_Patient_Link_ID, CAST(EventDate AS DATE) AS EventDate, SuppliedCode
INTO #GPEvents
FROM SharedCare.GP_Events
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND SuppliedCode IN (SELECT Code FROM #AllCodes);
-- 52s

--> EXECUTE query-build-rq051-gp-events.sql version:1 conditionname:Anxiety condition:anxiety
--> EXECUTE query-build-rq051-gp-events.sql version:1 conditionname:Depression condition:depression
--> EXECUTE query-build-rq051-gp-events.sql version:1 conditionname:Schizophrenia condition:schizophrenia-psychosis
--> EXECUTE query-build-rq051-gp-events.sql version:1 conditionname:Bipolar condition:bipolar
--> EXECUTE query-build-rq051-gp-events.sql version:1 conditionname:EatingDisorders condition:eating-disorders
--> EXECUTE query-build-rq051-gp-events.sql version:1 conditionname:Selfharm condition:selfharm-episodes
--> EXECUTE query-build-rq051-gp-events.sql version:1 conditionname:ADHD condition:attention-deficit-hyperactivity-disorder
--> EXECUTE query-build-rq051-gp-events.sql version:1 conditionname:ASD condition:autism-spectrum-disorder
-- 8s total

-- Creat a smaller version of GP medication table------------------------------------------------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#GPMedications') IS NOT NULL DROP TABLE #GPMedications;
SELECT FK_Patient_Link_ID, CAST(MedicationDate AS DATE) AS MedicationDate, SuppliedCode
INTO #GPMedications
FROM SharedCare.GP_Medications
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND SuppliedCode IN (SELECT Code FROM #AllCodes);
-- 1m16

--> EXECUTE query-build-rq051-gp-medications.sql medication:monoamine-oxidase-inhibitor version:1 medicationname:MAOI
--> EXECUTE query-build-rq051-gp-medications.sql medication:norepinephrine-reuptake-inhibitors version:1 medicationname:NRI
--> EXECUTE query-build-rq051-gp-medications.sql medication:serotonin-antagonist-reuptake-inhibitors version:1 medicationname:SARI
--> EXECUTE query-build-rq051-gp-medications.sql medication:serotonin-modulator-stimulator version:1 medicationname:SMS
--> EXECUTE query-build-rq051-gp-medications.sql medication:serotonin-norepinephrine-reuptake-inhibitors version:1 medicationname:SNRI
--> EXECUTE query-build-rq051-gp-medications.sql medication:selective-serotonin-reuptake-inhibitors version:1 medicationname:SSRI
--> EXECUTE query-build-rq051-gp-medications.sql medication:tricyclic-antidepressants version:1 medicationname:TCA
--> EXECUTE query-build-rq051-gp-medications.sql medication:tetracyclic version:1 medicationname:TECA
--> EXECUTE query-build-rq051-gp-medications.sql medication:other-antidepressants version:1 medicationname:OtherAntidepressants
--> EXECUTE query-build-rq051-gp-medications.sql medication:barbituates version:1 medicationname:Barbituates
--> EXECUTE query-build-rq051-gp-medications.sql medication:benzodiazepines version:2 medicationname:Benzodiazepines
--> EXECUTE query-build-rq051-gp-medications.sql medication:nonbenzodiazepine-benzodiazepine-receptor-agonist version:1 medicationname:NBBRA
--> EXECUTE query-build-rq051-gp-medications.sql medication:other-anxiolytics-and-hypnotics version:1 medicationname:OtherAnxiolyticsHypnotics
--> EXECUTE query-build-rq051-gp-medications.sql medication:antipsychotics version:2 medicationname:Antipsychotics
--> EXECUTE query-build-rq051-gp-medications.sql medication:anticonvulsants version:1 medicationname:Anticonvulsants
--> EXECUTE query-build-rq051-gp-medications.sql medication:lithium version:1 medicationname:Lithium
--> EXECUTE query-build-rq051-gp-medications.sql medication:off-label-mood-stabilisers version:1 medicationname:OffLabelMoodStabilisers
--> EXECUTE query-build-rq051-gp-medications.sql medication:attention-deficit-hyperactivity-disorder-medications version:1 medicationname:ADHDMedication
-- 12s total

-- Create all psychotropic medication tables======================================================================================================================
-- All AllPsychotropicMedication records
IF OBJECT_ID('tempdb..#FirstAllPsychotropicMedicationCounts') IS NOT NULL DROP TABLE #FirstAllPsychotropicMedicationCounts;
SELECT FK_Patient_Link_ID, YEAR(MedicationDate) AS YearOfEpisode, MONTH(MedicationDate) AS MonthOfEpisode, COUNT(*) AS Frequency  --count per person per month
INTO #FirstAllPsychotropicMedicationCounts
FROM #GPMedications
WHERE (
  SuppliedCode IN (SELECT Code FROM #AllCodes WHERE Concept = 'monoamine-oxidase-inhibitor' AND Version = 1) OR
  SuppliedCode IN (SELECT Code FROM #AllCodes WHERE Concept = 'norepinephrine-reuptake-inhibitors' AND Version = 1) OR
  SuppliedCode IN (SELECT Code FROM #AllCodes WHERE Concept = 'serotonin-antagonist-reuptake-inhibitors' AND Version = 1) OR
  SuppliedCode IN (SELECT Code FROM #AllCodes WHERE Concept = 'serotonin-modulator-stimulator' AND Version = 1) OR
  SuppliedCode IN (SELECT Code FROM #AllCodes WHERE Concept = 'serotonin-norepinephrine-reuptake-inhibitors' AND Version = 1) OR
  SuppliedCode IN (SELECT Code FROM #AllCodes WHERE Concept = 'selective-serotonin-reuptake-inhibitors' AND Version = 1) OR
  SuppliedCode IN (SELECT Code FROM #AllCodes WHERE Concept = 'tricyclic-antidepressants' AND Version = 1) OR
  SuppliedCode IN (SELECT Code FROM #AllCodes WHERE Concept = 'tetracyclic' AND Version = 1) OR
  SuppliedCode IN (SELECT Code FROM #AllCodes WHERE Concept = 'other-antidepressants' AND Version = 1) OR
  SuppliedCode IN (SELECT Code FROM #AllCodes WHERE Concept = 'barbituates' AND Version = 1) OR
  SuppliedCode IN (SELECT Code FROM #AllCodes WHERE Concept = 'benzodiazepines' AND Version = 2) OR
  SuppliedCode IN (SELECT Code FROM #AllCodes WHERE Concept = 'nonbenzodiazepine-benzodiazepine-receptor-agonist' AND Version = 1) OR
  SuppliedCode IN (SELECT Code FROM #AllCodes WHERE Concept = 'other-anxiolytics-and-hypnotics' AND Version = 1) OR
  SuppliedCode IN (SELECT Code FROM #AllCodes WHERE Concept = 'antipsychotics' AND Version = 2) OR
  SuppliedCode IN (SELECT Code FROM #AllCodes WHERE Concept = 'anticonvulsants' AND Version = 1) OR
  SuppliedCode IN (SELECT Code FROM #AllCodes WHERE Concept = 'lithium' AND Version = 1) OR
  SuppliedCode IN (SELECT Code FROM #AllCodes WHERE Concept = 'off-label-mood-stabilisers' AND Version = 1) OR
  SuppliedCode IN (SELECT Code FROM #AllCodes WHERE Concept = 'attention-deficit-hyperactivity-disorder-medications' AND Version = 1) 
)
AND MedicationDate >= '2019-01-01' 
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
GROUP BY FK_Patient_Link_ID, YEAR(MedicationDate), MONTH(MedicationDate);
-- 2s

-- Create a table of all IDs of the interested events========================================================================================================
IF OBJECT_ID('tempdb..#IDsAll') IS NOT NULL DROP TABLE #IDsAll;
SELECT FK_Patient_Link_ID INTO #IDsAll FROM #FirstAnxietyCounts
UNION
SELECT FK_Patient_Link_ID FROM #FirstDepressionCounts
UNION
SELECT FK_Patient_Link_ID FROM #FirstSchizophreniaCounts
UNION
SELECT FK_Patient_Link_ID FROM #FirstBipolarCounts
UNION
SELECT FK_Patient_Link_ID FROM #FirstEatingDisordersCounts
UNION
SELECT FK_Patient_Link_ID FROM #FirstSelfharmCounts
UNION
SELECT FK_Patient_Link_ID FROM #FirstADHDCounts
UNION
SELECT FK_Patient_Link_ID FROM #FirstASDCounts
UNION
SELECT FK_Patient_Link_ID FROM #FirstAllPsychotropicMedicationCounts
UNION
SELECT FK_Patient_Link_ID FROM #FirstMAOICounts
UNION
SELECT FK_Patient_Link_ID FROM #FirstNRICounts
UNION
SELECT FK_Patient_Link_ID FROM #FirstSARICounts
UNION
SELECT FK_Patient_Link_ID FROM #FirstSMSCounts
UNION
SELECT FK_Patient_Link_ID FROM #FirstSNRICounts
UNION
SELECT FK_Patient_Link_ID FROM #FirstSSRICounts
UNION
SELECT FK_Patient_Link_ID FROM #FirstTCACounts
UNION
SELECT FK_Patient_Link_ID FROM #FirstTECACounts
UNION
SELECT FK_Patient_Link_ID FROM #FirstOtherAntidepressantsCounts
UNION
SELECT FK_Patient_Link_ID FROM #FirstBarbituatesCounts
UNION
SELECT FK_Patient_Link_ID FROM #FirstBenzodiazepinesCounts
UNION 
SELECT FK_Patient_Link_ID FROM #FirstAnxietyCounts
UNION
SELECT FK_Patient_Link_ID FROM #FirstOtherAnxiolyticsHypnoticsCounts
UNION
SELECT FK_Patient_Link_ID FROM #FirstAntipsychoticsCounts
UNION
SELECT FK_Patient_Link_ID FROM #FirstAnticonvulsantsCounts
UNION
SELECT FK_Patient_Link_ID FROM #FirstLithiumCounts
UNION
SELECT FK_Patient_Link_ID FROM #FirstOffLabelMoodStabilisersCounts
UNION
SELECT FK_Patient_Link_ID FROM #FirstADHDMedicationCounts;
-- 14s

IF OBJECT_ID('tempdb..#IDs') IS NOT NULL DROP TABLE #IDs;
SELECT DISTINCT FK_Patient_Link_ID INTO #IDs FROM #IDsAll;


-- Create all year and month from 2019 til now (need this for calculate age )
IF OBJECT_ID('tempdb..#Dates') IS NOT NULL DROP TABLE #Dates;
CREATE TABLE #Dates (
  [Year] INT,
  [Month] INT,
);

DECLARE @dDate DATE = '2019-01-01'
DECLARE @dEnd DATE = GETDATE()

WHILE ( @dDate < @dEnd )
BEGIN
  INSERT INTO #Dates VALUES(YEAR(@dDate), MONTH(@dDate))
  SELECT @dDate = DATEADD(MONTH, 1, @dDate )
END

-- Merge 2 tables
IF OBJECT_ID('tempdb..#PatientsAll') IS NOT NULL DROP TABLE #PatientsAll;
SELECT *
INTO #PatientsAll
FROM #IDs, #Dates;

-- Create the table of ethnic================================================================================================================================
IF OBJECT_ID('tempdb..#Ethnicities') IS NOT NULL DROP TABLE #Ethnicities;
SELECT 
  PK_Patient_Link_ID AS FK_Patient_Link_ID,
  CASE 
    WHEN EthnicMainGroup IS NULL THEN 'Refused and not stated group'
    ELSE EthnicMainGroup
  END AS Ethnicity
INTO #Ethnicities
FROM SharedCare.Patient_Link
WHERE PK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);



-- Create the table of IDM================================================================================================================================
IF OBJECT_ID('tempdb..#IMDGroup') IS NOT NULL DROP TABLE #IMDGroup;
SELECT FK_Patient_Link_ID, IMDGroup = CASE 
		WHEN IMD2019Decile1IsMostDeprived10IsLeastDeprived IN (1,2) THEN 1 
		WHEN IMD2019Decile1IsMostDeprived10IsLeastDeprived IN (3,4) THEN 2 
		WHEN IMD2019Decile1IsMostDeprived10IsLeastDeprived IN (5,6) THEN 3
		WHEN IMD2019Decile1IsMostDeprived10IsLeastDeprived IN (7,8) THEN 4
		WHEN IMD2019Decile1IsMostDeprived10IsLeastDeprived IN (9,10) THEN 5
		ELSE NULL END
INTO #IMDGroup
FROM #PatientIMDDecile;


-- The counting table========================================================================================================================================
SELECT
  p.Year,
  p.Month,
  Sex,
  Ethnicity,
  (p.Year - YearOfBirth) AS Age,
  IMDGroup,
  CCG,
  SUM(CASE WHEN fafl.FK_Patient_Link_ID IS NOT NULL AND p.Year - yob.YearOfBirth >=6 THEN 1 ELSE 0 END) AS NumberFirstRecordedAnxietyAll,
  SUM(CASE WHEN fafl2019.FK_Patient_Link_ID IS NOT NULL AND p.Year - yob.YearOfBirth >=6 THEN 1 ELSE 0 END) AS NumberFirstRecordedAnxiety2019,
  SUM(CASE WHEN fac.FK_Patient_Link_ID IS NOT NULL AND p.Year - yob.YearOfBirth >=6 THEN fac.Frequency ELSE 0 END) AS NumberAnxietyEpisodes,
  SUM(CASE WHEN fdfl.FK_Patient_Link_ID IS NOT NULL AND p.Year - yob.YearOfBirth >=6 THEN 1 ELSE 0 END) AS NumberFirstRecordedDepressionAll,
  SUM(CASE WHEN fdfl2019.FK_Patient_Link_ID IS NOT NULL AND p.Year - yob.YearOfBirth >=6 THEN 1 ELSE 0 END) AS NumberFirstRecordedDepression2019,
  SUM(CASE WHEN fdc.FK_Patient_Link_ID IS NOT NULL AND p.Year - yob.YearOfBirth >=6 THEN fdc.Frequency ELSE 0 END) AS NumberDepressionEpisodes,
  SUM(CASE WHEN fefl.FK_Patient_Link_ID IS NOT NULL AND p.Year - yob.YearOfBirth >=6 THEN 1 ELSE 0 END) AS NumberFirstRecordedEatingDisordersAll,
  SUM(CASE WHEN fefl2019.FK_Patient_Link_ID IS NOT NULL AND p.Year - yob.YearOfBirth >=6 THEN 1 ELSE 0 END) AS NumberFirstRecordedAEatingDisorders2019,
  SUM(CASE WHEN fec.FK_Patient_Link_ID IS NOT NULL AND p.Year - yob.YearOfBirth >=6 THEN fec.Frequency ELSE 0 END) AS NumberEatingDisordersEpisodes,
  SUM(CASE WHEN fbfl.FK_Patient_Link_ID IS NOT NULL AND p.Year - yob.YearOfBirth >=17 THEN 1 ELSE 0 END) AS NumberFirstRecordedBipolarAll,
  SUM(CASE WHEN fbfl2019.FK_Patient_Link_ID IS NOT NULL AND p.Year - yob.YearOfBirth >=17 THEN 1 ELSE 0 END) AS NumberFirstRecordedBipolar2019,
  SUM(CASE WHEN fbc.FK_Patient_Link_ID IS NOT NULL AND p.Year - yob.YearOfBirth >=17 THEN fbc.Frequency ELSE 0 END) AS NumberBipolarEpisodes,
  SUM(CASE WHEN fsfl.FK_Patient_Link_ID IS NOT NULL AND p.Year - yob.YearOfBirth >=17 THEN 1 ELSE 0 END) AS NumberFirstRecordedSchizophreniaAll,
  SUM(CASE WHEN fsfl2019.FK_Patient_Link_ID IS NOT NULL AND p.Year - yob.YearOfBirth >=17 THEN 1 ELSE 0 END) AS NumberFirstRecordedASchizophrenia2019,
  SUM(CASE WHEN fsc.FK_Patient_Link_ID IS NOT NULL AND p.Year - yob.YearOfBirth >=17 THEN fsc.Frequency ELSE 0 END) AS NumberSchizophreniaEpisodes,
  SUM(CASE WHEN fhfl.FK_Patient_Link_ID IS NOT NULL AND p.Year - yob.YearOfBirth >=10 THEN 1 ELSE 0 END) AS NumberFirstRecordedSelfharmAll,
  SUM(CASE WHEN fhfl2019.FK_Patient_Link_ID IS NOT NULL AND p.Year - yob.YearOfBirth >=10 THEN 1 ELSE 0 END) AS NumberFirstRecordedSelfharm2019,
  SUM(CASE WHEN fhc.FK_Patient_Link_ID IS NOT NULL AND p.Year - yob.YearOfBirth >=10 THEN fhc.Frequency ELSE 0 END) AS NumberSelfharmEpisodes,
  SUM(CASE WHEN fa1fl.FK_Patient_Link_ID IS NOT NULL THEN 1 ELSE 0 END) AS NumberFirstRecordedADHDAll,
  SUM(CASE WHEN fa1fl2019.FK_Patient_Link_ID IS NOT NULL THEN 1 ELSE 0 END) AS NumberFirstRecordedADHD2019pl,
  SUM(CASE WHEN fa1c.FK_Patient_Link_ID IS NOT NULL THEN fa1c.Frequency ELSE 0 END) AS NumberADHDEpisodes,
  SUM(CASE WHEN fa2fl.FK_Patient_Link_ID IS NOT NULL THEN 1 ELSE 0 END) AS NumberFirstRecordedASDAll,
  SUM(CASE WHEN fa2fl2019.FK_Patient_Link_ID IS NOT NULL THEN 1 ELSE 0 END) AS NumberFirstRecordedASD2019,
  SUM(CASE WHEN fa2c.FK_Patient_Link_ID IS NOT NULL THEN fa2c.Frequency ELSE 0 END) AS NumberASDEpisodes,
  SUM(CASE WHEN fm1c.FK_Patient_Link_ID IS NOT NULL THEN fm1c.Frequency ELSE 0 END) AS NumberAllPsychotropicMedication,
  SUM(CASE WHEN fm2c.FK_Patient_Link_ID IS NOT NULL THEN fm2c.Frequency ELSE 0 END) AS NumberMAOI,
  SUM(CASE WHEN fm3c.FK_Patient_Link_ID IS NOT NULL THEN fm3c.Frequency ELSE 0 END) AS NumberNRI,
  SUM(CASE WHEN fm4c.FK_Patient_Link_ID IS NOT NULL THEN fm4c.Frequency ELSE 0 END) AS NumberSARI,
  SUM(CASE WHEN fm5c.FK_Patient_Link_ID IS NOT NULL THEN fm5c.Frequency ELSE 0 END) AS NumberSMS,
  SUM(CASE WHEN fm6c.FK_Patient_Link_ID IS NOT NULL THEN fm6c.Frequency ELSE 0 END) AS NumberSNRI,
  SUM(CASE WHEN fm7c.FK_Patient_Link_ID IS NOT NULL THEN fm7c.Frequency ELSE 0 END) AS NumberSSRI,
  SUM(CASE WHEN fm8c.FK_Patient_Link_ID IS NOT NULL THEN fm8c.Frequency ELSE 0 END) AS NumberTricyclicAntidepressants,
  SUM(CASE WHEN fm9c.FK_Patient_Link_ID IS NOT NULL THEN fm9c.Frequency ELSE 0 END) AS NumberTetracyclicAntidepressants,
  SUM(CASE WHEN fm10c.FK_Patient_Link_ID IS NOT NULL THEN fm10c.Frequency ELSE 0 END) AS NumberOtherAntidepressants,
  SUM(CASE WHEN fm11c.FK_Patient_Link_ID IS NOT NULL THEN fm11c.Frequency ELSE 0 END) AS NumberBarbiturate,
  SUM(CASE WHEN fm12c.FK_Patient_Link_ID IS NOT NULL THEN fm12c.Frequency ELSE 0 END) AS NumberBenzodiazepines,
  SUM(CASE WHEN fm13c.FK_Patient_Link_ID IS NOT NULL THEN fm13c.Frequency ELSE 0 END) AS NumberNBBRA,
  SUM(CASE WHEN fm14c.FK_Patient_Link_ID IS NOT NULL THEN fm14c.Frequency ELSE 0 END) AS NumberOtherAnxiolyticsHypnotics,
  SUM(CASE WHEN fm15c.FK_Patient_Link_ID IS NOT NULL THEN fm15c.Frequency ELSE 0 END) AS NumberAntipsychotics,
  SUM(CASE WHEN fm16c.FK_Patient_Link_ID IS NOT NULL THEN fm16c.Frequency ELSE 0 END) AS NumberAnticonvulsants,
  SUM(CASE WHEN fm17c.FK_Patient_Link_ID IS NOT NULL THEN fm17c.Frequency ELSE 0 END) AS NumberLithium,
  SUM(CASE WHEN fm18c.FK_Patient_Link_ID IS NOT NULL THEN fm18c.Frequency ELSE 0 END) AS NumberOffLabelMoodStabilisers,
  SUM(CASE WHEN fm19c.FK_Patient_Link_ID IS NOT NULL THEN fm19c.Frequency ELSE 0 END) AS NumberADHDMedication
FROM #PatientsAll p
LEFT OUTER JOIN #Ethnicities e ON e.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #IMDGroup imd ON imd.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientPracticeAndCCG gp ON gp.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #FirstAnxietyFullLookback fafl ON fafl.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND YEAR(fafl.FirstOccurrence) = Year AND MONTH(fafl.FirstOccurrence) = Month
LEFT OUTER JOIN #FirstAnxiety2019Lookback fafl2019 ON fafl2019.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND YEAR(fafl2019.FirstOccurrenceFrom2019Onwards) = Year AND MONTH(fafl2019.FirstOccurrenceFrom2019Onwards) = Month
LEFT OUTER JOIN #FirstAnxietyCounts fac ON fac.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND fac.YearOfEpisode = Year AND fac.MonthOfEpisode = Month
LEFT OUTER JOIN #FirstDepressionFullLookback fdfl ON fdfl.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND YEAR(fdfl.FirstOccurrence) = Year AND MONTH(fdfl.FirstOccurrence) = Month
LEFT OUTER JOIN #FirstDepression2019Lookback fdfl2019 ON fdfl2019.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND YEAR(fdfl2019.FirstOccurrenceFrom2019Onwards) = Year AND MONTH(fdfl2019.FirstOccurrenceFrom2019Onwards) = Month
LEFT OUTER JOIN #FirstDepressionCounts fdc ON fdc.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND fdc.YearOfEpisode = Year AND fdc.MonthOfEpisode = Month
LEFT OUTER JOIN #FirstEatingDisordersFullLookback fefl ON fefl.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND YEAR(fefl.FirstOccurrence) = Year AND MONTH(fefl.FirstOccurrence) = Month
LEFT OUTER JOIN #FirstEatingDisorders2019Lookback fefl2019 ON fefl2019.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND YEAR(fefl2019.FirstOccurrenceFrom2019Onwards) = Year AND MONTH(fefl2019.FirstOccurrenceFrom2019Onwards) = Month
LEFT OUTER JOIN #FirstEatingDisordersCounts fec ON fec.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND fec.YearOfEpisode = Year AND fec.MonthOfEpisode = Month
LEFT OUTER JOIN #FirstBipolarFullLookback fbfl ON fbfl.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND YEAR(fbfl.FirstOccurrence) = Year AND MONTH(fbfl.FirstOccurrence) = Month
LEFT OUTER JOIN #FirstBipolar2019Lookback fbfl2019 ON fbfl2019.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND YEAR(fbfl2019.FirstOccurrenceFrom2019Onwards) = Year AND MONTH(fbfl2019.FirstOccurrenceFrom2019Onwards) = Month
LEFT OUTER JOIN #FirstBipolarCounts fbc ON fbc.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND fbc.YearOfEpisode = Year AND fbc.MonthOfEpisode = Month
LEFT OUTER JOIN #FirstSchizophreniaFullLookback fsfl ON fsfl.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND YEAR(fsfl.FirstOccurrence) = Year AND MONTH(fsfl.FirstOccurrence) = Month
LEFT OUTER JOIN #FirstSchizophrenia2019Lookback fsfl2019 ON fsfl2019.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND YEAR(fsfl2019.FirstOccurrenceFrom2019Onwards) = Year AND MONTH(fsfl2019.FirstOccurrenceFrom2019Onwards) = Month
LEFT OUTER JOIN #FirstSchizophreniaCounts fsc ON fsc.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND fsc.YearOfEpisode = Year AND fsc.MonthOfEpisode = Month
LEFT OUTER JOIN #FirstSelfharmFullLookback fhfl ON fhfl.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND YEAR(fhfl.FirstOccurrence) = Year AND MONTH(fhfl.FirstOccurrence) = Month
LEFT OUTER JOIN #FirstSelfharm2019Lookback fhfl2019 ON fhfl2019.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND YEAR(fhfl2019.FirstOccurrenceFrom2019Onwards) = Year AND MONTH(fhfl2019.FirstOccurrenceFrom2019Onwards) = Month
LEFT OUTER JOIN #FirstSelfharmCounts fhc ON fhc.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND fhc.YearOfEpisode = Year AND fhc.MonthOfEpisode = Month
LEFT OUTER JOIN #FirstADHDFullLookback fa1fl ON fa1fl.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND YEAR(fa1fl.FirstOccurrence) = Year AND MONTH(fa1fl.FirstOccurrence) = Month
LEFT OUTER JOIN #FirstADHD2019Lookback fa1fl2019 ON fa1fl2019.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND YEAR(fa1fl2019.FirstOccurrenceFrom2019Onwards) = Year AND MONTH(fa1fl2019.FirstOccurrenceFrom2019Onwards) = Month
LEFT OUTER JOIN #FirstADHDCounts fa1c ON fa1c.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND fa1c.YearOfEpisode = Year AND fa1c.MonthOfEpisode = Month
LEFT OUTER JOIN #FirstASDFullLookback fa2fl ON fa2fl.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND YEAR(fa2fl.FirstOccurrence) = Year AND MONTH(fa2fl.FirstOccurrence) = Month
LEFT OUTER JOIN #FirstASD2019Lookback fa2fl2019 ON fa2fl2019.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND YEAR(fa2fl2019.FirstOccurrenceFrom2019Onwards) = Year AND MONTH(fa2fl2019.FirstOccurrenceFrom2019Onwards) = Month
LEFT OUTER JOIN #FirstASDCounts fa2c ON fa2c.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND fa2c.YearOfEpisode = Year AND fa2c.MonthOfEpisode = Month
LEFT OUTER JOIN #FirstAllPsychotropicMedicationCounts fm1c ON fm1c.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND fm1c.YearOfEpisode = Year AND fm1c.MonthOfEpisode = Month
LEFT OUTER JOIN #FirstMAOICounts fm2c ON fm2c.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND fm2c.YearOfEpisode = Year AND fm2c.MonthOfEpisode = Month
LEFT OUTER JOIN #FirstNRICounts fm3c ON fm3c.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND fm3c.YearOfEpisode = Year AND fm3c.MonthOfEpisode = Month
LEFT OUTER JOIN #FirstSARICounts fm4c ON fm4c.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND fm4c.YearOfEpisode = Year AND fm4c.MonthOfEpisode = Month
LEFT OUTER JOIN #FirstSMSCounts fm5c ON fm5c.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND fm5c.YearOfEpisode = Year AND fm5c.MonthOfEpisode = Month
LEFT OUTER JOIN #FirstSNRICounts fm6c ON fm6c.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND fm6c.YearOfEpisode = Year AND fm6c.MonthOfEpisode = Month
LEFT OUTER JOIN #FirstSSRICounts fm7c ON fm7c.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND fm7c.YearOfEpisode = Year AND fm7c.MonthOfEpisode = Month
LEFT OUTER JOIN #FirstTCACounts fm8c ON fm8c.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND fm8c.YearOfEpisode = Year AND fm8c.MonthOfEpisode = Month
LEFT OUTER JOIN #FirstTECACounts fm9c ON fm9c.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND fm9c.YearOfEpisode = Year AND fm9c.MonthOfEpisode = Month
LEFT OUTER JOIN #FirstOtherAntidepressantsCounts fm10c ON fm10c.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND fm10c.YearOfEpisode = Year AND fm10c.MonthOfEpisode = Month
LEFT OUTER JOIN #FirstBarbituatesCounts fm11c ON fm11c.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND fm11c.YearOfEpisode = Year AND fm11c.MonthOfEpisode = Month
LEFT OUTER JOIN #FirstBenzodiazepinesCounts fm12c ON fm12c.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND fm12c.YearOfEpisode = Year AND fm12c.MonthOfEpisode = Month
LEFT OUTER JOIN #FirstNBBRACounts fm13c ON fm13c.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND fm13c.YearOfEpisode = Year AND fm13c.MonthOfEpisode = Month
LEFT OUTER JOIN #FirstOtherAnxiolyticsHypnoticsCounts fm14c ON fm14c.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND fm14c.YearOfEpisode = Year AND fm14c.MonthOfEpisode = Month
LEFT OUTER JOIN #FirstAntipsychoticsCounts fm15c ON fm15c.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND fm15c.YearOfEpisode = Year AND fm15c.MonthOfEpisode = Month
LEFT OUTER JOIN #FirstAnticonvulsantsCounts fm16c ON fm16c.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND fm16c.YearOfEpisode = Year AND fm16c.MonthOfEpisode = Month
LEFT OUTER JOIN #FirstLithiumCounts fm17c ON fm17c.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND fm17c.YearOfEpisode = Year AND fm17c.MonthOfEpisode = Month
LEFT OUTER JOIN #FirstOffLabelMoodStabilisersCounts fm18c ON fm18c.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND fm18c.YearOfEpisode = Year AND fm18c.MonthOfEpisode = Month
LEFT OUTER JOIN #FirstADHDMedicationCounts fm19c ON fm19c.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND fm19c.YearOfEpisode = Year AND fm19c.MonthOfEpisode = Month
WHERE p.Year - yob.YearOfBirth <= 24 AND p.Year - yob.YearOfBirth >=1 AND Sex !='U'
GROUP BY p.Year, p.Month, Sex, Ethnicity, (p.Year - YearOfBirth), IMDGroup, CCG
ORDER BY p.Year, p.Month;

