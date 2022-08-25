--┌────────────────────────────────────────────────────┐
--│ Mental illness diagnoses and self-harm episodes    │
--└────────────────────────────────────────────────────┘

-- REVIEW LOG:
--	

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
IF OBJECT_ID('tempdb..#PatientsToInclude') IS NOT NULL DROP TABLE #PatientsToInclude;
SELECT FK_Patient_Link_ID INTO #PatientsToInclude
FROM RLS.vw_Patient_GP_History
GROUP BY FK_Patient_Link_ID
HAVING MIN(StartDate) < '2022-06-01';

IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #Patients 
FROM [PatientsToInclude;


--> CODESET selfharm-episodes:1
--> CODESET anxiety:1
--> CODESET depression:1
--> CODESET eating-disorders:1
--> CODESET bipolar:1
--> CODESET schizophrenia-psychosis:1
--> CODESET attention-deficit-hyperactivity-disorder:1
--> CODESET autism-spectrum-disorder:1

--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-imd.sql
--> EXECUTE query-patient-year-of-birth.sql


-- Create anxiety tables----------------------------------------------------------------------------------------------------------------------------------
-- Reports of anxiety using all historic data
IF OBJECT_ID('tempdb..#AnxietyAll') IS NOT NULL DROP TABLE #AnxietyAll;
SELECT DISTINCT FK_Patient_Link_ID, FORMAT(EventDate, 'yyyy-MM') AS Year_and_month, 
	FirstAnxietyAll = ROW_NUMBER() OVER(PARTITION BY FK_Patient_Link_ID ORDER BY EventDate), EventDate
INTO #AnxietyAll
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'anxiety' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'anxiety' AND Version = 1)
) AND EventDate < '2022-06-01' AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

-- Reports of anxiety using data from 1st Jan 2019
IF OBJECT_ID('tempdb..#Anxiety2019') IS NOT NULL DROP TABLE #Anxiety2019;
SELECT DISTINCT FK_Patient_Link_ID, FORMAT(EventDate, 'yyyy-MM') AS Year_and_month, 
	FirstAnxiety2019 = ROW_NUMBER() OVER(PARTITION BY FK_Patient_Link_ID ORDER BY EventDate), EventDate
INTO #Anxiety2019
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'anxiety' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'anxiety' AND Version = 1)
) AND YEAR(EventDate) >= 2019 AND EventDate < '2022-06-01' AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

-- A table with each row as the first anxiety record for every patients with anxiety (all historic data)
IF OBJECT_ID('tempdb..#NumberFirstAnxietyAll') IS NOT NULL DROP TABLE #NumberFirstAnxietyAll;
SELECT FK_Patient_Link_ID, Year_and_month, FirstAnxietyAll
INTO #NumberFirstAnxietyAll
FROM #AnxietyAll
WHERE FirstAnxietyAll = 1;

-- A table with each row as the first anxiety record for every patients with anxiety (only looking back to 1st Jan 2019)
IF OBJECT_ID('tempdb..#NumberFirstAnxiety2019') IS NOT NULL DROP TABLE #NumberFirstAnxiety2019;
SELECT FK_Patient_Link_ID, Year_and_month, FirstAnxiety2019
INTO #NumberFirstAnxiety2019
FROM #Anxiety2019
WHERE FirstAnxiety2019 = 1;

-- A table with number of anxiety episodes each recorded month for every patients with anxiety
IF OBJECT_ID('tempdb..#NumberAnxietyEpisodes') IS NOT NULL DROP TABLE #NumberAnxietyEpisodes;
SELECT FK_Patient_Link_ID, Year_and_month, COUNT (EventDate) AS NumberAnxietyEpisodes
INTO #NumberAnxietyEpisodes
FROM #AnxietyAll
GROUP BY FK_Patient_Link_ID, Year_and_month;

-- Drop some table
DROP TABLE #AnxietyAll
DROP TABLE #Anxiety2019


-- Create depression tables----------------------------------------------------------------------------------------------------------------------------------
-- Reports of depression using all historic data
IF OBJECT_ID('tempdb..#DepressionAll') IS NOT NULL DROP TABLE #DepressionAll;
SELECT DISTINCT FK_Patient_Link_ID, FORMAT(EventDate, 'yyyy-MM') AS Year_and_month, 
	FirstDepressionAll = ROW_NUMBER() OVER(PARTITION BY FK_Patient_Link_ID ORDER BY EventDate), EventDate
INTO #DepressionAll
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'depression' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'depression' AND Version = 1)
) AND EventDate < '2022-06-01' AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

-- Reports of depression using data from 1st Jan 2019
IF OBJECT_ID('tempdb..#Depression2019') IS NOT NULL DROP TABLE #Depression2019;
SELECT DISTINCT FK_Patient_Link_ID, FORMAT(EventDate, 'yyyy-MM') AS Year_and_month, 
	FirstDepression2019 = ROW_NUMBER() OVER(PARTITION BY FK_Patient_Link_ID ORDER BY EventDate), EventDate
INTO #Depression2019
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'depression' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'depression' AND Version = 1)
) AND YEAR(EventDate) >= 2019 AND EventDate < '2022-06-01' AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

-- A table with each row as the first depression record for every patients with depression (all historic data)
IF OBJECT_ID('tempdb..#NumberFirstDepressionAll') IS NOT NULL DROP TABLE #NumberFirstDepressionAll;
SELECT FK_Patient_Link_ID, Year_and_month, FirstDepressionAll
INTO #NumberFirstDepressionAll
FROM #DepressionAll
WHERE FirstDepressionAll = 1;

-- A table with each row as the first depression record for every patients with depression (only looking back to 1st Jan 2019)
IF OBJECT_ID('tempdb..#NumberFirstDepression2019') IS NOT NULL DROP TABLE #NumberFirstDepression2019;
SELECT FK_Patient_Link_ID, Year_and_month, FirstDepression2019
INTO #NumberFirstDepression2019
FROM #Depression2019
WHERE FirstDepression2019 = 1;

-- A table with number of depression episodes each recorded month for every patients with depression
IF OBJECT_ID('tempdb..#NumberDepressionEpisodes') IS NOT NULL DROP TABLE #NumberDepressionEpisodes;
SELECT FK_Patient_Link_ID, Year_and_month, COUNT (EventDate) AS NumberDepressionEpisodes
INTO #NumberDepressionEpisodes
FROM #DepressionAll
GROUP BY FK_Patient_Link_ID, Year_and_month;

-- Drop some table
DROP TABLE #DepressionAll
DROP TABLE #Depression2019


-- Create schizophrenia tables----------------------------------------------------------------------------------------------------------------------------------
-- Reports of schizophrenia using all historic data
IF OBJECT_ID('tempdb..#SchizophreniaAll') IS NOT NULL DROP TABLE #SchizophreniaAll;
SELECT DISTINCT FK_Patient_Link_ID, FORMAT(EventDate, 'yyyy-MM') AS Year_and_month, 
	FirstSchizophreniaAll = ROW_NUMBER() OVER(PARTITION BY FK_Patient_Link_ID ORDER BY EventDate), EventDate
INTO #SchizophreniaAll
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'schizophrenia' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'schizophrenia' AND Version = 1)
) AND EventDate < '2022-06-01' AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

-- Reports of schizophrenia using data from 1st Jan 2019
IF OBJECT_ID('tempdb..#Schizophrenia2019') IS NOT NULL DROP TABLE #Schizophrenia2019;
SELECT DISTINCT FK_Patient_Link_ID, FORMAT(EventDate, 'yyyy-MM') AS Year_and_month, 
	FirstSchizophrenia2019 = ROW_NUMBER() OVER(PARTITION BY FK_Patient_Link_ID ORDER BY EventDate), EventDate
INTO #Schizophrenia2019
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'schizophrenia' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'schizophrenia' AND Version = 1)
) AND YEAR(EventDate) >= 2019 AND EventDate < '2022-06-01' AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

-- A table with each row as the first schizophrenia record for every patients with schizophrenia (all historic data)
IF OBJECT_ID('tempdb..#NumberFirstSchizophreniaAll') IS NOT NULL DROP TABLE #NumberFirstSchizophreniaAll;
SELECT FK_Patient_Link_ID, Year_and_month, FirstSchizophreniaAll
INTO #NumberFirstSchizophreniaAll
FROM #SchizophreniaAll
WHERE FirstSchizophreniaAll = 1;

-- A table with each row as the first schizophrenia record for every patients with schizophrenia (only looking back to 1st Jan 2019)
IF OBJECT_ID('tempdb..#NumberFirstSchizophrenia2019') IS NOT NULL DROP TABLE #NumberFirstSchizophrenia2019;
SELECT FK_Patient_Link_ID, Year_and_month, FirstSchizophrenia2019
INTO #NumberFirstSchizophrenia2019
FROM #Schizophrenia2019
WHERE FirstSchizophrenia2019 = 1;

-- A table with number of schizophrenia episodes each recorded month for every patients with schizophrenia
IF OBJECT_ID('tempdb..#NumberSchizophreniaEpisodes') IS NOT NULL DROP TABLE #NumberSchizophreniaEpisodes;
SELECT FK_Patient_Link_ID, Year_and_month, COUNT (EventDate) AS NumberSchizophreniaEpisodes
INTO #NumberSchizophreniaEpisodes
FROM #SchizophreniaAll
GROUP BY FK_Patient_Link_ID, Year_and_month;

-- Drop some table
DROP TABLE #SchizophreniaAll
DROP TABLE #Schizophrenia2019


-- Create bipolar tables----------------------------------------------------------------------------------------------------------------------------------
-- Reports of bipolar using all historic data
IF OBJECT_ID('tempdb..#BipolarAll') IS NOT NULL DROP TABLE #BipolarAll;
SELECT DISTINCT FK_Patient_Link_ID, FORMAT(EventDate, 'yyyy-MM') AS Year_and_month, 
	FirstBipolarAll = ROW_NUMBER() OVER(PARTITION BY FK_Patient_Link_ID ORDER BY EventDate), EventDate
INTO #BipolarAll
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'bipolar' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'bipolar' AND Version = 1)
) AND EventDate < '2022-06-01' AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

-- Reports of bipolar using data from 1st Jan 2019
IF OBJECT_ID('tempdb..#Bipolar2019') IS NOT NULL DROP TABLE #Bipolar2019;
SELECT DISTINCT FK_Patient_Link_ID, FORMAT(EventDate, 'yyyy-MM') AS Year_and_month, 
	FirstBipolar2019 = ROW_NUMBER() OVER(PARTITION BY FK_Patient_Link_ID ORDER BY EventDate), EventDate
INTO #Bipolar2019
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'bipolar' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'bipolar' AND Version = 1)
) AND YEAR(EventDate) >= 2019 AND EventDate < '2022-06-01' AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

-- A table with each row as the first bipolar record for every patients with bipolar (all historic data)
IF OBJECT_ID('tempdb..#NumberFirstBipolarAll') IS NOT NULL DROP TABLE #NumberFirstBipolarAll;
SELECT FK_Patient_Link_ID, Year_and_month, FirstBipolarAll
INTO #NumberFirstBipolarAll
FROM #BipolarAll
WHERE FirstBipolarAll = 1;

-- A table with each row as the first bipolar record for every patients with bipolar (only looking back to 1st Jan 2019)
IF OBJECT_ID('tempdb..#NumberFirstBipolar2019') IS NOT NULL DROP TABLE #NumberFirstBipolar2019;
SELECT FK_Patient_Link_ID, Year_and_month, FirstBipolar2019
INTO #NumberFirstBipolar2019
FROM #Bipolar2019
WHERE FirstBipolar2019 = 1;

-- A table with number of bipolar episodes each recorded month for every patients with bipolar
IF OBJECT_ID('tempdb..#NumberBipolarEpisodes') IS NOT NULL DROP TABLE #NumberBipolarEpisodes;
SELECT FK_Patient_Link_ID, Year_and_month, COUNT (EventDate) AS NumberBipolarEpisodes
INTO #NumberBipolarEpisodes
FROM #BipolarAll
GROUP BY FK_Patient_Link_ID, Year_and_month;

-- Drop some table
DROP TABLE #BipolarAll
DROP TABLE #Bipolar2019


-- Create Eating Disorders tables----------------------------------------------------------------------------------------------------------------------------------
-- Reports of Eating Disorders using all historic data
IF OBJECT_ID('tempdb..#EatingDisordersAll') IS NOT NULL DROP TABLE #EatingDisordersAll;
SELECT DISTINCT FK_Patient_Link_ID, FORMAT(EventDate, 'yyyy-MM') AS Year_and_month, 
	FirstEatingDisordersAll = ROW_NUMBER() OVER(PARTITION BY FK_Patient_Link_ID ORDER BY EventDate), EventDate
INTO #EatingDisordersAll
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'eating-disorders' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'eating-disorders' AND Version = 1)
) AND EventDate < '2022-06-01' AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

-- Reports of Eating Disorders using data from 1st Jan 2019
IF OBJECT_ID('tempdb..#EatingDisorders2019') IS NOT NULL DROP TABLE #EatingDisorders2019;
SELECT DISTINCT FK_Patient_Link_ID, FORMAT(EventDate, 'yyyy-MM') AS Year_and_month, 
	FirstEatingDisorders2019 = ROW_NUMBER() OVER(PARTITION BY FK_Patient_Link_ID ORDER BY EventDate), EventDate
INTO #EatingDisorders2019
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'eating-disorders' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'eating-disorders' AND Version = 1)
) AND YEAR(EventDate) >= 2019 AND EventDate < '2022-06-01' AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

-- A table with each row as the first Eating Disorders record for every patients with Eating Disorders (all historic data)
IF OBJECT_ID('tempdb..#NumberFirstEatingDisordersAll') IS NOT NULL DROP TABLE #NumberFirstEatingDisordersAll;
SELECT FK_Patient_Link_ID, Year_and_month, FirstEatingDisordersAll
INTO #NumberFirstEatingDisordersAll
FROM #EatingDisordersAll
WHERE FirstEatingDisordersAll = 1;

-- A table with each row as the first Eating Disorders record for every patients with Eating Disorders (only looking back to 1st Jan 2019)
IF OBJECT_ID('tempdb..#NumberFirstEatingDisorders2019') IS NOT NULL DROP TABLE #NumberFirstEatingDisorders2019;
SELECT FK_Patient_Link_ID, Year_and_month, FirstEatingDisorders2019
INTO #NumberFirstEatingDisorders2019
FROM #EatingDisorders2019
WHERE FirstEatingDisorders2019 = 1;

-- A table with number of Eating Disorders episodes each recorded month for every patients with Eating Disorders
IF OBJECT_ID('tempdb..#NumberEatingDisordersEpisodes') IS NOT NULL DROP TABLE #NumberEatingDisordersEpisodes;
SELECT FK_Patient_Link_ID, Year_and_month, COUNT (EventDate) AS NumberEatingDisordersEpisodes
INTO #NumberEatingDisordersEpisodes
FROM #EatingDisordersAll
GROUP BY FK_Patient_Link_ID, Year_and_month;

-- Drop some table
DROP TABLE #EatingDisordersAll
DROP TABLE #EatingDisorders2019


-- Create self-harm tables----------------------------------------------------------------------------------------------------------------------------------
-- Reports of self-harm using all historic data
IF OBJECT_ID('tempdb..#SelfharmAll') IS NOT NULL DROP TABLE #SelfharmAll;
SELECT DISTINCT FK_Patient_Link_ID, FORMAT(EventDate, 'yyyy-MM') AS Year_and_month, 
	FirstSelfharmAll = ROW_NUMBER() OVER(PARTITION BY FK_Patient_Link_ID ORDER BY EventDate), EventDate
INTO #SelfharmAll
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'selfharm-episodes' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'selfharm-episodes' AND Version = 1)
) AND EventDate < '2022-06-01' AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

-- Reports of self-harm using data from 1st Jan 2019
IF OBJECT_ID('tempdb..#Selfharm2019') IS NOT NULL DROP TABLE #Selfharm2019;
SELECT DISTINCT FK_Patient_Link_ID, FORMAT(EventDate, 'yyyy-MM') AS Year_and_month, 
	FirstSelfharm2019 = ROW_NUMBER() OVER(PARTITION BY FK_Patient_Link_ID ORDER BY EventDate), EventDate
INTO #Selfharm2019
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'selfharm-episodes' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'selfharm-episodes' AND Version = 1)
) AND YEAR(EventDate) >= 2019 AND EventDate < '2022-06-01' AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

-- A table with each row as the first self-harm record for every patients with self-harm (all historic data)
IF OBJECT_ID('tempdb..#NumberFirstSelfharmAll') IS NOT NULL DROP TABLE #NumberFirstSelfharmAll;
SELECT FK_Patient_Link_ID, Year_and_month, FirstSelfharmAll
INTO #NumberFirstSelfharmAll
FROM #SelfharmAll
WHERE FirstSelfharmAll = 1;

-- A table with each row as the first self-harm record for every patients with self-harm (only looking back to 1st Jan 2019)
IF OBJECT_ID('tempdb..#NumberFirstSelfharm2019') IS NOT NULL DROP TABLE #NumberFirstSelfharm2019;
SELECT FK_Patient_Link_ID, Year_and_month, FirstSelfharm2019
INTO #NumberFirstSelfharm2019
FROM #Selfharm2019
WHERE FirstSelfharm2019 = 1;

-- A table with number of self-harm episodes each recorded month for every patients with self-harm
IF OBJECT_ID('tempdb..#NumberSelfharmEpisodes') IS NOT NULL DROP TABLE #NumberSelfharmEpisodes;
SELECT FK_Patient_Link_ID, Year_and_month, COUNT (EventDate) AS NumberSelfharmEpisodes
INTO #NumberSelfharmEpisodes
FROM #SelfharmAll
GROUP BY FK_Patient_Link_ID, Year_and_month;

-- Drop some table
DROP TABLE #SelfharmAll
DROP TABLE #Selfharm2019


-- Create ADHD tables------------------------------------------------------------------------------------------------------------------------------------------
-- Reports of ADHD using all historic data
IF OBJECT_ID('tempdb..#ADHDAll') IS NOT NULL DROP TABLE #ADHDAll;
SELECT DISTINCT FK_Patient_Link_ID, FORMAT(EventDate, 'yyyy-MM') AS Year_and_month, 
	FirstADHDAll = ROW_NUMBER() OVER(PARTITION BY FK_Patient_Link_ID ORDER BY EventDate), EventDate
INTO #ADHDAll
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'attention-deficit-hyperactivity-disorder' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'attention-deficit-hyperactivity-disorder' AND Version = 1)
) AND EventDate < '2022-06-01' AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

-- Reports of ADHD using data from 1st Jan 2019
IF OBJECT_ID('tempdb..#ADHD2019') IS NOT NULL DROP TABLE #ADHD2019;
SELECT DISTINCT FK_Patient_Link_ID, FORMAT(EventDate, 'yyyy-MM') AS Year_and_month, 
	FirstADHD2019 = ROW_NUMBER() OVER(PARTITION BY FK_Patient_Link_ID ORDER BY EventDate), EventDate
INTO #ADHD2019
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'attention-deficit-hyperactivity-disorder' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'attention-deficit-hyperactivity-disorder' AND Version = 1)
) AND YEAR(EventDate) >= 2019 AND EventDate < '2022-06-01' AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

-- A table with each row as the first ADHD record for every patients with ADHD (all historic data)
IF OBJECT_ID('tempdb..#NumberFirstADHDAll') IS NOT NULL DROP TABLE #NumberFirstADHDAll;
SELECT FK_Patient_Link_ID, Year_and_month, FirstADHDAll
INTO #NumberFirstADHDAll
FROM #ADHDAll
WHERE FirstADHDAll = 1;

-- A table with each row as the first ADHD record for every patients with ADHD (only looking back to 1st Jan 2019)
IF OBJECT_ID('tempdb..#NumberFirstADHD2019') IS NOT NULL DROP TABLE #NumberFirstADHD2019;
SELECT FK_Patient_Link_ID, Year_and_month, FirstADHD2019
INTO #NumberFirstADHD2019
FROM #ADHD2019
WHERE FirstADHD2019 = 1;

-- A table with number of ADHD episodes each recorded month for every patients with ADHD
IF OBJECT_ID('tempdb..#NumberADHDEpisodes') IS NOT NULL DROP TABLE #NumberADHDEpisodes;
SELECT FK_Patient_Link_ID, Year_and_month, COUNT (EventDate) AS NumberADHDEpisodes
INTO #NumberADHDEpisodes
FROM #ADHDAll
GROUP BY FK_Patient_Link_ID, Year_and_month;

-- Drop some table
DROP TABLE #ADHDAll
DROP TABLE #ADHD2019


-- Create ASD tables------------------------------------------------------------------------------------------------------------------------------------------
-- Reports of ASD using all historic data
IF OBJECT_ID('tempdb..#ASDAll') IS NOT NULL DROP TABLE #ASDAll;
SELECT DISTINCT FK_Patient_Link_ID, FORMAT(EventDate, 'yyyy-MM') AS Year_and_month, 
	FirstASDAll = ROW_NUMBER() OVER(PARTITION BY FK_Patient_Link_ID ORDER BY EventDate), EventDate
INTO #ASDAll
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'autism-spectrum-disorder' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'autism-spectrum-disorder' AND Version = 1)
) AND EventDate < '2022-06-01' AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

-- Reports of ASD using data from 1st Jan 2019
IF OBJECT_ID('tempdb..#ASD2019') IS NOT NULL DROP TABLE #ASD2019;
SELECT DISTINCT FK_Patient_Link_ID, FORMAT(EventDate, 'yyyy-MM') AS Year_and_month, 
	FirstASD2019 = ROW_NUMBER() OVER(PARTITION BY FK_Patient_Link_ID ORDER BY EventDate), EventDate
INTO #ASD2019
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'autism-spectrum-disorder' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'autism-spectrum-disorder' AND Version = 1)
) AND YEAR(EventDate) >= 2019 AND EventDate < '2022-06-01' AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

-- A table with each row as the first ASD record for every patients with ASD (all historic data)
IF OBJECT_ID('tempdb..#NumberFirstASDAll') IS NOT NULL DROP TABLE #NumberFirstASDAll;
SELECT FK_Patient_Link_ID, Year_and_month, FirstASDAll
INTO #NumberFirstASDAll
FROM #ASDAll
WHERE FirstASDAll = 1;

-- A table with each row as the first ASD record for every patients with ASD (only looking back to 1st Jan 2019)
IF OBJECT_ID('tempdb..#NumberFirstASD2019') IS NOT NULL DROP TABLE #NumberFirstASD2019;
SELECT FK_Patient_Link_ID, Year_and_month, FirstASD2019
INTO #NumberFirstASD2019
FROM #ASD2019
WHERE FirstASD2019 = 1;

-- A table with number of ASD episodes each recorded month for every patients with ASD
IF OBJECT_ID('tempdb..#NumberASDEpisodes') IS NOT NULL DROP TABLE #NumberASDEpisodes;
SELECT FK_Patient_Link_ID, Year_and_month, COUNT (EventDate) AS NumberASDEpisodes
INTO #NumberASDEpisodes
FROM #ASDAll
GROUP BY FK_Patient_Link_ID, Year_and_month;

-- Drop some table
DROP TABLE #ASDAll
DROP TABLE #ASD2019


-- Create all psychotropic medication tables======================================================================================================================
-- All AllPsychotropicMedication records
IF OBJECT_ID('tempdb..#AllPsychotropicMedicationAll') IS NOT NULL DROP TABLE #AllPsychotropicMedicationAll;
SELECT DISTINCT FK_Patient_Link_ID, FORMAT(MedicationDate, 'yyyy-MM') AS Year_and_month, MedicationDate
INTO #AllPsychotropicMedicationAll
FROM [RLS].[vw_GP_Medications]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'monoamine-oxidase-inhibitor' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'monoamine-oxidase-inhibitor' AND Version = 1) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'norepinephrine-reuptake-inhibitors' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'norepinephrine-reuptake-inhibitors' AND Version = 1) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'serotonin-antagonist-reuptake-inhibitors' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'serotonin-antagonist-reuptake-inhibitors' AND Version = 1) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'serotonin-modulator-stimulator' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'serotonin-modulator-stimulator' AND Version = 1) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'serotonin-norepinephrine-reuptake-inhibitors' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'serotonin-norepinephrine-reuptake-inhibitors' AND Version = 1) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'selective-serotonin-reuptake-inhibitors' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'selective-serotonin-reuptake-inhibitors' AND Version = 1) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'tricyclic-antidepressants' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'tricyclic-antidepressants' AND Version = 1) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'tetracyclic' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'tetracyclic' AND Version = 1) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'other-antidepressants' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'other-antidepressants' AND Version = 1) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'barbituates' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'barbituates' AND Version = 1) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'benzodiazepines' AND Version = 2) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'benzodiazepines' AND Version = 2) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'nonbenzodiazepine-benzodiazepine-receptor-agonist' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'nonbenzodiazepine-benzodiazepine-receptor-agonist' AND Version = 1) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'other-anxiolytics-and-hypnotics' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'other-anxiolytics-and-hypnotics' AND Version = 1) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'antipsychotics' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'antipsychotics' AND Version = 1) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'Anticonvulsants' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'Anticonvulsants' AND Version = 1) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'lithium' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'lithium' AND Version = 1) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'off-label-mood-stabilisers' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'off-label-mood-stabilisers' AND Version = 1) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'attention-deficit-hyperactivity-disorder-medications' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'attention-deficit-hyperactivity-disorder-medications' AND Version = 1)
)
AND MedicationDate < '2022-06-01' AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

-- Count the number of all psychotropic medication for each recorded month
IF OBJECT_ID('tempdb..#AllPsychotropicMedication') IS NOT NULL DROP TABLE #AllPsychotropicMedication;
SELECT FK_Patient_Link_ID, Year_and_month, COUNT(Medicationdate) AS NumberAllPsychotropicMedication
INTO #AllPsychotropicMedication
FROM #AllPsychotropicMedicationAll
GROUP BY FK_Patient_Link_ID, Year_and_month;

--Drop the first table
DROP TABLE #AllPsychotropicMedicationAll


-- Create MOAI medication tables======================================================================================================================
-- All MOAI records
IF OBJECT_ID('tempdb..#MOAIAll') IS NOT NULL DROP TABLE #MOAIAll;
SELECT DISTINCT FK_Patient_Link_ID, FORMAT(MedicationDate, 'yyyy-MM') AS Year_and_month, MedicationDate
INTO #MOAIAll
FROM [RLS].[vw_GP_Medications]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'monoamine-oxidase-inhibitor' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'monoamine-oxidase-inhibitor' AND Version = 1)
)
AND MedicationDate < '2022-06-01' AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

-- Count the number of MOAI medications for each recorded month
IF OBJECT_ID('tempdb..#MOAI') IS NOT NULL DROP TABLE #MOAI;
SELECT FK_Patient_Link_ID, Year_and_month, COUNT(Medicationdate) AS NumberMOAI
INTO #MOAI
FROM #MOAIAll
GROUP BY FK_Patient_Link_ID, Year_and_month;

--Drop the first table
DROP TABLE #MOAIAll


-- Create NRI medication tables======================================================================================================================
-- All NRI records
IF OBJECT_ID('tempdb..#NRIAll') IS NOT NULL DROP TABLE #NRIAll;
SELECT DISTINCT FK_Patient_Link_ID, FORMAT(MedicationDate, 'yyyy-MM') AS Year_and_month, MedicationDate
INTO #NRIAll
FROM [RLS].[vw_GP_Medications]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'norepinephrine-reuptake-inhibitors' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'norepinephrine-reuptake-inhibitors' AND Version = 1)
)
AND MedicationDate < '2022-06-01' AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

-- Count the number of NRI medications for each recorded month
IF OBJECT_ID('tempdb..#NRI') IS NOT NULL DROP TABLE #NRI;
SELECT FK_Patient_Link_ID, Year_and_month, COUNT(Medicationdate) AS NumberNRI
INTO #NRI
FROM #NRIAll
GROUP BY FK_Patient_Link_ID, Year_and_month;

--Drop the first table
DROP TABLE #NRIAll


-- Create SARI medication tables======================================================================================================================
-- All SARI records
IF OBJECT_ID('tempdb..#SARIAll') IS NOT NULL DROP TABLE #SARIAll;
SELECT DISTINCT FK_Patient_Link_ID, FORMAT(MedicationDate, 'yyyy-MM') AS Year_and_month, MedicationDate
INTO #SARIAll
FROM [RLS].[vw_GP_Medications]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'serotonin-antagonist-reuptake-inhibitors' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'serotonin-antagonist-reuptake-inhibitors' AND Version = 1)
)
AND MedicationDate < '2022-06-01' AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

-- Count the number of SARI medications for each recorded month
IF OBJECT_ID('tempdb..#SARI') IS NOT NULL DROP TABLE #SARI;
SELECT FK_Patient_Link_ID, Year_and_month, COUNT(Medicationdate) AS NumberSARI
INTO #SARI
FROM #SARIAll
GROUP BY FK_Patient_Link_ID, Year_and_month;

--Drop the first table
DROP TABLE #SARIAll


-- Create SMS medication tables======================================================================================================================
-- All SMS records
IF OBJECT_ID('tempdb..#SMSAll') IS NOT NULL DROP TABLE #SMSAll;
SELECT DISTINCT FK_Patient_Link_ID, FORMAT(MedicationDate, 'yyyy-MM') AS Year_and_month, MedicationDate
INTO #SMSAll
FROM [RLS].[vw_GP_Medications]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'serotonin-modulator-stimulator' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'serotonin-modulator-stimulator' AND Version = 1)
)
AND MedicationDate < '2022-06-01' AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

-- Count the number of SMS medications for each recorded month
IF OBJECT_ID('tempdb..#SMS') IS NOT NULL DROP TABLE #SMS;
SELECT FK_Patient_Link_ID, Year_and_month, COUNT(Medicationdate) AS NumberSMS
INTO #SMS
FROM #SMSAll
GROUP BY FK_Patient_Link_ID, Year_and_month;

--Drop the first table
DROP TABLE #SMSAll


-- Create SNRI medication tables======================================================================================================================
-- All SNRI records
IF OBJECT_ID('tempdb..#SNRIAll') IS NOT NULL DROP TABLE #SNRIAll;
SELECT DISTINCT FK_Patient_Link_ID, FORMAT(MedicationDate, 'yyyy-MM') AS Year_and_month, MedicationDate
INTO #SNRIAll
FROM [RLS].[vw_GP_Medications]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'serotonin-norepinephrine-reuptake-inhibitors' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'serotonin-norepinephrine-reuptake-inhibitors' AND Version = 1)
)
AND MedicationDate < '2022-06-01' AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

-- Count the number of SNRI medications for each recorded month
IF OBJECT_ID('tempdb..#SNRI') IS NOT NULL DROP TABLE #SNRI;
SELECT FK_Patient_Link_ID, Year_and_month, COUNT(Medicationdate) AS NumberSNRI
INTO #SNRI
FROM #SNRIAll
GROUP BY FK_Patient_Link_ID, Year_and_month;

--Drop the first table
DROP TABLE #SNRIAll


-- Create SSRI medication tables======================================================================================================================
-- All SSRI records
IF OBJECT_ID('tempdb..#SSRIAll') IS NOT NULL DROP TABLE #SSRIAll;
SELECT DISTINCT FK_Patient_Link_ID, FORMAT(MedicationDate, 'yyyy-MM') AS Year_and_month, MedicationDate
INTO #SSRIAll
FROM [RLS].[vw_GP_Medications]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'selective-serotonin-reuptake-inhibitors' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'selective-serotonin-reuptake-inhibitors' AND Version = 1)
)
AND MedicationDate < '2022-06-01' AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

-- Count the number of SSRI medications for each recorded month
IF OBJECT_ID('tempdb..#SSRI') IS NOT NULL DROP TABLE #SSRI;
SELECT FK_Patient_Link_ID, Year_and_month, COUNT(Medicationdate) AS NumberSSRI
INTO #SSRI
FROM #SSRIAll
GROUP BY FK_Patient_Link_ID, Year_and_month;

--Drop the first table
DROP TABLE #SSRIAll


-- Create TCA medication tables======================================================================================================================
-- All TCA records
IF OBJECT_ID('tempdb..#TCAAll') IS NOT NULL DROP TABLE #TCAAll;
SELECT DISTINCT FK_Patient_Link_ID, FORMAT(MedicationDate, 'yyyy-MM') AS Year_and_month, MedicationDate
INTO #TCAAll
FROM [RLS].[vw_GP_Medications]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'tricyclic-antidepressants' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'tricyclic-antidepressants' AND Version = 1)
)
AND MedicationDate < '2022-06-01' AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

-- Count the number of TCA medications for each recorded month
IF OBJECT_ID('tempdb..#TCA') IS NOT NULL DROP TABLE #TCA;
SELECT FK_Patient_Link_ID, Year_and_month, COUNT(Medicationdate) AS NumberTCA
INTO #TCA
FROM #TCAAll
GROUP BY FK_Patient_Link_ID, Year_and_month;

--Drop the first table
DROP TABLE #TCAAll


-- Create TECA medication tables======================================================================================================================
-- All TECA records
IF OBJECT_ID('tempdb..#TECAAll') IS NOT NULL DROP TABLE #TECAAll;
SELECT DISTINCT FK_Patient_Link_ID, FORMAT(MedicationDate, 'yyyy-MM') AS Year_and_month, MedicationDate
INTO #TECAAll
FROM [RLS].[vw_GP_Medications]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'tetracyclic' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'tetracyclic' AND Version = 1)
)
AND MedicationDate < '2022-06-01' AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

-- Count the number of TECA medications for each recorded month
IF OBJECT_ID('tempdb..#TECA') IS NOT NULL DROP TABLE #TECA;
SELECT FK_Patient_Link_ID, Year_and_month, COUNT(Medicationdate) AS NumberTECA
INTO #TECA
FROM #TECAAll
GROUP BY FK_Patient_Link_ID, Year_and_month;

--Drop the first table
DROP TABLE #TECAAll


-- Create other antidepressants medication tables======================================================================================================================
-- All OtherAntidepressants records
IF OBJECT_ID('tempdb..#OtherAntidepressantsAll') IS NOT NULL DROP TABLE #OtherAntidepressantsAll;
SELECT DISTINCT FK_Patient_Link_ID, FORMAT(MedicationDate, 'yyyy-MM') AS Year_and_month, MedicationDate
INTO #OtherAntidepressantsAll
FROM [RLS].[vw_GP_Medications]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'other-antidepressants' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'other-antidepressants' AND Version = 1)
)
AND MedicationDate < '2022-06-01' AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

-- Count the number of other antidepressants medications for each recorded month
IF OBJECT_ID('tempdb..#OtherAntidepressants') IS NOT NULL DROP TABLE #OtherAntidepressants;
SELECT FK_Patient_Link_ID, Year_and_month, COUNT(Medicationdate) AS NumberOtherAntidepressants
INTO #OtherAntidepressants
FROM #OtherAntidepressantsAll
GROUP BY FK_Patient_Link_ID, Year_and_month;

--Drop the first table
DROP TABLE #OtherAntidepressantsAll


-- Create Barbiturate medication tables======================================================================================================================
-- All Barbiturate records
IF OBJECT_ID('tempdb..#BarbiturateAll') IS NOT NULL DROP TABLE #BarbiturateAll;
SELECT DISTINCT FK_Patient_Link_ID, FORMAT(MedicationDate, 'yyyy-MM') AS Year_and_month, MedicationDate
INTO #BarbiturateAll
FROM [RLS].[vw_GP_Medications]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'barbituates' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'barbituates' AND Version = 1)
)
AND MedicationDate < '2022-06-01' AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

-- Count the number of Barbiturate medications for each recorded month
IF OBJECT_ID('tempdb..#Barbiturate') IS NOT NULL DROP TABLE #Barbiturate;
SELECT FK_Patient_Link_ID, Year_and_month, COUNT(Medicationdate) AS NumberBarbiturate
INTO #Barbiturate
FROM #BarbiturateAll
GROUP BY FK_Patient_Link_ID, Year_and_month;

--Drop the first table
DROP TABLE #BarbiturateAll


-- Create Benzodiazepine medication tables======================================================================================================================
-- All Benzodiazepine records
IF OBJECT_ID('tempdb..#BenzodiazepineAll') IS NOT NULL DROP TABLE #BenzodiazepineAll;
SELECT DISTINCT FK_Patient_Link_ID, FORMAT(MedicationDate, 'yyyy-MM') AS Year_and_month, MedicationDate
INTO #BenzodiazepineAll
FROM [RLS].[vw_GP_Medications]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'benzodiazepines' AND Version = 2) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'benzodiazepines' AND Version = 2)
)
AND MedicationDate < '2022-06-01' AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

-- Count the number of Benzodiazepine medications for each recorded month
IF OBJECT_ID('tempdb..#Benzodiazepine') IS NOT NULL DROP TABLE #Benzodiazepine;
SELECT FK_Patient_Link_ID, Year_and_month, COUNT(Medicationdate) AS NumberBenzodiazepine
INTO #Benzodiazepine
FROM #BenzodiazepineAll
GROUP BY FK_Patient_Link_ID, Year_and_month;

--Drop the first table
DROP TABLE #BenzodiazepineAll


-- Create NBBRA medication tables======================================================================================================================
-- All NBBRA records
IF OBJECT_ID('tempdb..#NBBRAAll') IS NOT NULL DROP TABLE #NBBRAAll;
SELECT DISTINCT FK_Patient_Link_ID, FORMAT(MedicationDate, 'yyyy-MM') AS Year_and_month, MedicationDate
INTO #NBBRAAll
FROM [RLS].[vw_GP_Medications]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'nonbenzodiazepine-benzodiazepine-receptor-agonist' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'nonbenzodiazepine-benzodiazepine-receptor-agonist' AND Version = 1)
)
AND MedicationDate < '2022-06-01' AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

-- Count the number of NBBRA medications for each recorded month
IF OBJECT_ID('tempdb..#NBBRA') IS NOT NULL DROP TABLE #NBBRA;
SELECT FK_Patient_Link_ID, Year_and_month, COUNT(Medicationdate) AS NumberNBBRA
INTO #NBBRA
FROM #NBBRAAll
GROUP BY FK_Patient_Link_ID, Year_and_month;

--Drop the first table
DROP TABLE #NBBRAAll


-- Create other anxiolytics and hypnotics tables======================================================================================================================
-- All OtherAnxiolyticsHypnotics records
IF OBJECT_ID('tempdb..#OtherAnxiolyticsHypnoticsAll') IS NOT NULL DROP TABLE #OtherAnxiolyticsHypnoticsAll;
SELECT DISTINCT FK_Patient_Link_ID, FORMAT(MedicationDate, 'yyyy-MM') AS Year_and_month, MedicationDate
INTO #OtherAnxiolyticsHypnoticsAll
FROM [RLS].[vw_GP_Medications]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'other-anxiolytics-and-hypnotics' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'other-anxiolytics-and-hypnotics' AND Version = 1)
)
AND MedicationDate < '2022-06-01' AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

-- Count the number of other anxiolytics and hypnotics for each recorded month
IF OBJECT_ID('tempdb..#OtherAnxiolyticsHypnotics') IS NOT NULL DROP TABLE #OtherAnxiolyticsHypnotics;
SELECT FK_Patient_Link_ID, Year_and_month, COUNT(Medicationdate) AS NumberOtherAnxiolyticsHypnotics
INTO #OtherAnxiolyticsHypnotics
FROM #OtherAnxiolyticsHypnoticsAll
GROUP BY FK_Patient_Link_ID, Year_and_month;

--Drop the first table
DROP TABLE #OtherAnxiolyticsHypnoticsAll


-- Create antipsychotics medication tables======================================================================================================================
-- All antipsychotics records
IF OBJECT_ID('tempdb..#AntipsychoticsAll') IS NOT NULL DROP TABLE #AntipsychoticsAll;
SELECT DISTINCT FK_Patient_Link_ID, FORMAT(MedicationDate, 'yyyy-MM') AS Year_and_month, MedicationDate
INTO #AntipsychoticsAll
FROM [RLS].[vw_GP_Medications]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'antipsychotics' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'antipsychotics' AND Version = 1)
)
AND MedicationDate < '2022-06-01' AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

-- Count the number of antipsychotics medications for each recorded month
IF OBJECT_ID('tempdb..#Antipsychotics') IS NOT NULL DROP TABLE #Antipsychotics;
SELECT FK_Patient_Link_ID, Year_and_month, COUNT(Medicationdate) AS NumberAntipsychotics
INTO #Antipsychotics
FROM #AntipsychoticsAll
GROUP BY FK_Patient_Link_ID, Year_and_month;

--Drop the first table
DROP TABLE #AntipsychoticsAll


-- Create anticonvulsants medication tables======================================================================================================================
-- All Anticonvulsants records
IF OBJECT_ID('tempdb..#AnticonvulsantsAll') IS NOT NULL DROP TABLE #AnticonvulsantsAll;
SELECT DISTINCT FK_Patient_Link_ID, FORMAT(MedicationDate, 'yyyy-MM') AS Year_and_month, MedicationDate
INTO #AnticonvulsantsAll
FROM [RLS].[vw_GP_Medications]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'anticonvulsants' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'anticonvulsants' AND Version = 1)
)
AND MedicationDate < '2022-06-01' AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

-- Count the number of Anticonvulsants medications for each recorded month
IF OBJECT_ID('tempdb..#Anticonvulsants') IS NOT NULL DROP TABLE #Anticonvulsants;
SELECT FK_Patient_Link_ID, Year_and_month, COUNT(Medicationdate) AS NumberAnticonvulsants
INTO #Anticonvulsants
FROM #AnticonvulsantsAll
GROUP BY FK_Patient_Link_ID, Year_and_month;

--Drop the first table
DROP TABLE #AnticonvulsantsAll


-- Create lithium medication tables======================================================================================================================
-- All Lithium records
IF OBJECT_ID('tempdb..#LithiumAll') IS NOT NULL DROP TABLE #LithiumAll;
SELECT DISTINCT FK_Patient_Link_ID, FORMAT(MedicationDate, 'yyyy-MM') AS Year_and_month, MedicationDate
INTO #LithiumAll
FROM [RLS].[vw_GP_Medications]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'lithium' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'lithium' AND Version = 1)
)
AND MedicationDate < '2022-06-01' AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

-- Count the number of Lithium medications for each recorded month
IF OBJECT_ID('tempdb..#Lithium') IS NOT NULL DROP TABLE #Lithium;
SELECT FK_Patient_Link_ID, Year_and_month, COUNT(Medicationdate) AS NumberLithium
INTO #Lithium
FROM #LithiumAll
GROUP BY FK_Patient_Link_ID, Year_and_month;

--Drop the first table
DROP TABLE #LithiumAll


-- Create Off Label Mood Stabilisers medication tables======================================================================================================================
-- All OffLabelMoodStabilisers  records
IF OBJECT_ID('tempdb..#OffLabelMoodStabilisers All') IS NOT NULL DROP TABLE #OffLabelMoodStabilisers All;
SELECT DISTINCT FK_Patient_Link_ID, FORMAT(MedicationDate, 'yyyy-MM') AS Year_and_month, MedicationDate
INTO #OffLabelMoodStabilisers All
FROM [RLS].[vw_GP_Medications]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'off-label-mood-stabilisers' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'off-label-mood-stabilisers' AND Version = 1)
)
AND MedicationDate < '2022-06-01' AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

-- Count the number of Label Mood Stabilisers medications for each recorded month
IF OBJECT_ID('tempdb..#OffLabelMoodStabilisers ') IS NOT NULL DROP TABLE #OffLabelMoodStabilisers ;
SELECT FK_Patient_Link_ID, Year_and_month, COUNT(Medicationdate) AS NumberOffLabelMoodStabilisers 
INTO #OffLabelMoodStabilisers 
FROM #OffLabelMoodStabilisers All
GROUP BY FK_Patient_Link_ID, Year_and_month;

--Drop the first table
DROP TABLE #OffLabelMoodStabilisers All


-- Create ADHD medication tables======================================================================================================================
-- All ADHDMedication records
IF OBJECT_ID('tempdb..#ADHDMedicationAll') IS NOT NULL DROP TABLE #ADHDMedicationAll;
SELECT DISTINCT FK_Patient_Link_ID, FORMAT(MedicationDate, 'yyyy-MM') AS Year_and_month, MedicationDate
INTO #ADHDMedicationAll
FROM [RLS].[vw_GP_Medications]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'attention-deficit-hyperactivity-disorder-medications' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'attention-deficit-hyperactivity-disorder-medications' AND Version = 1)
)
AND MedicationDate < '2022-06-01' AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

-- Count the number of ADHD medications for each recorded month
IF OBJECT_ID('tempdb..#ADHDMedication') IS NOT NULL DROP TABLE #ADHDMedication;
SELECT FK_Patient_Link_ID, Year_and_month, COUNT(Medicationdate) AS NumberADHDMedication
INTO #ADHDMedication
FROM #ADHDMedicationAll
GROUP BY FK_Patient_Link_ID, Year_and_month;

--Drop the first table
DROP TABLE #ADHDMedicationAll


-- Create a table of all year-month of the studied events========================================================================================================
IF OBJECT_ID('tempdb..#TimeAll') IS NOT NULL DROP TABLE #TimeAll;
SELECT Year_and_month INTO #TimeAll FROM #NumberAnxietyEpisodes
UNION
SELECT Year_and_month FROM #NumberDepressionEpisodes
UNION
SELECT Year_and_month FROM #NumberSchizophreniaEpisodes
UNION
SELECT Year_and_month FROM #NumberBipolarEpisodes
UNION
SELECT Year_and_month FROM #NumberEatingDisordersEpisodes
UNION
SELECT Year_and_month FROM #NumberSelfharmEpisodes
UNION
SELECT Year_and_month FROM #NumberADHDEpisodes
UNION
SELECT Year_and_month FROM #NumberASDEpisodes
UNION
SELECT Year_and_month FROM #AllPsychotropicMedication
UNION
SELECT Year_and_month FROM #MAOI
UNION
SELECT Year_and_month FROM #NRI
UNION
SELECT Year_and_month FROM #SARI
UNION
SELECT Year_and_month FROM #SMS
UNION
SELECT Year_and_month FROM #SNRI
UNION
SELECT Year_and_month FROM #SSRI
UNION
SELECT Year_and_month FROM #TricyclicAntidepressants
UNION
SELECT Year_and_month FROM #TetracyclicAntidepressants
UNION
SELECT Year_and_month FROM #OtherAntidepressants
UNION
SELECT Year_and_month FROM #Barbiturate
UNION
SELECT Year_and_month FROM #Benzodiazepines
UNION
SELECT Year_and_month FROM #NBBRA
UNION
SELECT Year_and_month FROM #OtherAnxiolyticsHypnotics
UNION
SELECT Year_and_month FROM #Antipsychotics
UNION
SELECT Year_and_month FROM #Anticonvulsants
UNION
SELECT Year_and_month FROM #Lithium
UNION
SELECT Year_and_month FROM #OffLabelMoodStabilisers
UNION
SELECT Year_and_month FROM #ADHDMedication

IF OBJECT_ID('tempdb..#Time') IS NOT NULL DROP TABLE #Time;
SELECT DISTINCT Year_and_month INTO #Time FROM #TimeAll;

-- Create the table of patients' IDs and time====================================================================================================================
IF OBJECT_ID('tempdb..#PatientsTime') IS NOT NULL DROP TABLE #PatientsTime;
SELECT *
INTO #PatientsTime
FROM #Patients, #Time;


-- Create the table of ethnic================================================================================================================================
IF OBJECT_ID('tempdb..#Ethnic') IS NOT NULL DROP TABLE #Ethnic;
SELECT PK_Patient_Link_ID AS FK_Patient_Link_ID, EthnicMainGroup AS Ethnic
INTO #Ethnic
FROM RLS.vw_Patient_Link;


-- The final table===========================================================================================================================================
IF OBJECT_ID('tempdb..#Table') IS NOT NULL DROP TABLE #Table;
SELECT  p.FK_Patient_Link_ID,
	p.Year_and_month,
	Ethnic,	
	Sex,
	Age = YEAR(p.Year_and_month) - yob.YearOfBirth,
	IMD2019Quintile1IsMostDeprived5IsLeastDeprived = CASE WHEN IMD2019Decile1IsMostDeprived10IsLeastDeprived IN (1,2) THEN 1 
		WHEN IMD2019Decile1IsMostDeprived10IsLeastDeprived IN (3,4) THEN 2 
		WHEN IMD2019Decile1IsMostDeprived10IsLeastDeprived IN (5,6) THEN 3
		WHEN IMD2019Decile1IsMostDeprived10IsLeastDeprived IN (7,8) THEN 4
		WHEN IMD2019Decile1IsMostDeprived10IsLeastDeprived IN (9,10) THEN 5
			ELSE NULL END,
	n1.FirstAnxietyAll,
	n2.FirstAnxiety2019,
	n3.NumberAnxietyEpisodes,
	n4.FirstDepressionAll,
	n5.FirstDepression2019,
	n6.NumberDepressionEpisodes,
	n7.FirstSchizophreniaAll,
	n8.FirstSchizophrenia2019,
	n9.NumberSchizophreniaEpisodes,
	n10.FirstBipolarAll,
	n11.FirstBipolar2019,
	n12.NumberBipolarEpisodes, 
	n13.FirstEatingDisordersAll,
	n14.FirstEatingDisorders2019,
	n15.NumberEatingDisordersEpisodes,
	n16.FirstSelfharmAll,
	n17.FirstSelfharm2019,
	n18.NumberSelfharmEpisodes,
	n19.FirstADHDAll,
	n20.FirstADHD2019,
	n21.NumberADHDEpisodes,
	n22.FirstASDAll,
	n23.FirstASD2019,
	n24.NumberASDEpisodes,
	n25.NumberAllPsychotropicMedication,
	n26.NumberMAOI,
	n27.NumberNRI,
	n28.NumberSARI,
	n29.NumberSMS,
	n30.NumberSNRI,
	n31.NumberSSRI,
	n32.NumberTricyclicAntidepressants,
	n33.NumberTetracyclicAntidepressants,
	n34.NumberOtherAntidepressants,
	n35.NumberBarbiturate,
	n36.NumberBenzodiazepines,
	n37.NumberNBBRA,
	n38.NumberOtherAnxiolyticsHypnotics,
	n39.NumberAntipsychotics,
	n40.NumberAnticonvulsants,
	n41.NumberLithium,
	n42.NumberOffLabelMoodStabilisers,
	n43.NumberADHDMedication
INTO #Table
FROM #PatientsTime p
LEFT OUTER JOIN #Ethnic e ON e.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientIMDDecile imd ON imd.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #NumberFirstAnxietyAll n1 ON n1.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n1.Year_and_month = p.Year_and_month
LEFT OUTER JOIN #NumberFirstAnxiety2019 n2 ON n2.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n2.Year_and_month = p.Year_and_month
LEFT OUTER JOIN #NumberAnxietyEpisodes n3 ON n3.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n3.Year_and_month = p.Year_and_month
LEFT OUTER JOIN #NumberFirstDepressionAll n4 ON n4.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n4.Year_and_month = p.Year_and_month
LEFT OUTER JOIN #NumberFirstDepression2019 n5 ON n5.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n5.Year_and_month = p.Year_and_month
LEFT OUTER JOIN #NumberDepressionEpisodes n6 ON n6.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n6.Year_and_month = p.Year_and_month
LEFT OUTER JOIN #NumberFirstSchizophreniaAll n7 ON n7.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n7.Year_and_month = p.Year_and_month
LEFT OUTER JOIN #NumberFirstSchizophrenia2019 n8 ON n8.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n8.Year_and_month = p.Year_and_month
LEFT OUTER JOIN #NumberSchizophreniaEpisodes n9 ON n9.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n9.Year_and_month = p.Year_and_month
LEFT OUTER JOIN #NumberFirstBipolarAll n10 ON n10.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n10.Year_and_month = p.Year_and_month
LEFT OUTER JOIN #NumberFirstBipolar2019 n11 ON n11.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n11.Year_and_month = p.Year_and_month
LEFT OUTER JOIN #NumberBipolarEpisodes n12 ON n12.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n12.Year_and_month = p.Year_and_month
LEFT OUTER JOIN #NumberFirstEatingDisordersAll n13 ON n13.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n13.Year_and_month = p.Year_and_month
LEFT OUTER JOIN #NumberFirstEatingDisorders2019 n14 ON n14.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n14.Year_and_month = p.Year_and_month
LEFT OUTER JOIN #NumberEatingDisordersEpisodes n15 ON n15.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n15.Year_and_month = p.Year_and_month
LEFT OUTER JOIN #NumberFirstSelfharmAll n16 ON n16.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n16.Year_and_month = p.Year_and_month
LEFT OUTER JOIN #NumberFirstSelfharm2019 n17 ON n17.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n17.Year_and_month = p.Year_and_month
LEFT OUTER JOIN #NumberSelfharmEpisodes n18 ON n18.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n18.Year_and_month = p.Year_and_month
LEFT OUTER JOIN #NumberFirstADHDAll n19 ON n19.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n19.Year_and_month = p.Year_and_month
LEFT OUTER JOIN #NumberFirstADHD2019 n20 ON n20.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n20.Year_and_month = p.Year_and_month
LEFT OUTER JOIN #NumberADHDEpisodes n21 ON n21.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n21.Year_and_month = p.Year_and_month
LEFT OUTER JOIN #NumberFirstASDAll n22 ON n22.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n22.Year_and_month = p.Year_and_month
LEFT OUTER JOIN #NumberFirstASD2019 n23 ON n23.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n23.Year_and_month = p.Year_and_month
LEFT OUTER JOIN #NumberASDEpisodes n24 ON n24.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n24.Year_and_month = p.Year_and_month
LEFT OUTER JOIN #AllPsychotropicMedication n25 ON n25.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n25.Year_and_month = p.Year_and_month
LEFT OUTER JOIN #MAOI n26 ON n26.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n26.Year_and_month = p.Year_and_month
LEFT OUTER JOIN #NRI n27 ON n27.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n27.Year_and_month = p.Year_and_month
LEFT OUTER JOIN #SARI n28 ON n28.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n28.Year_and_month = p.Year_and_month
LEFT OUTER JOIN #SMS n29 ON n29.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n29.Year_and_month = p.Year_and_month
LEFT OUTER JOIN #SNRI n30 ON n30.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n30.Year_and_month = p.Year_and_month
LEFT OUTER JOIN #SSRI n31 ON n31.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n31.Year_and_month = p.Year_and_month
LEFT OUTER JOIN #TricyclicAntidepressants n32 ON n32.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n32.Year_and_month = p.Year_and_month
LEFT OUTER JOIN #TetracyclicAntidepressants n33 ON n33.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n33.Year_and_month = p.Year_and_month
LEFT OUTER JOIN #OtherAntidepressants n34 ON n34.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n34.Year_and_month = p.Year_and_month
LEFT OUTER JOIN #Barbiturate n35 ON n35.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n35.Year_and_month = p.Year_and_month
LEFT OUTER JOIN #Benzodiazepines n36 ON n36.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n36.Year_and_month = p.Year_and_month
LEFT OUTER JOIN #NBBRA n37 ON n37.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n37.Year_and_month = p.Year_and_month
LEFT OUTER JOIN #OtherAnxiolyticsHypnotics n38 ON n38.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n38.Year_and_month = p.Year_and_month
LEFT OUTER JOIN #Antipsychotics n39 ON n39.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n39.Year_and_month = p.Year_and_month
LEFT OUTER JOIN #Anticonvulsants n40 ON n40.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n40.Year_and_month = p.Year_and_month
LEFT OUTER JOIN #Lithium n41 ON n41.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n41.Year_and_month = p.Year_and_month
LEFT OUTER JOIN #OffLabelMoodStabilisers n42 ON n42.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n42.Year_and_month = p.Year_and_month
LEFT OUTER JOIN #ADHDMedication n43 ON n43.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND n43.Year_and_month = p.Year_and_month;


