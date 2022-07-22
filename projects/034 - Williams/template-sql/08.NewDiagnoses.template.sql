--+---------------------------------------------------------------------------+
--¦ Patients with a new diagnosis                                             ¦
--+---------------------------------------------------------------------------+

-------- RESEARCH DATA ENGINEER CHECK ---------

-- OUTPUT: Data with the following fields
-- PatientId
-- Date (YYYY/MM/DD) 

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2019-01-01';

--Just want the output, not the messages
SET NOCOUNT ON;

-- Create a table with all patients (ID)=========================================================================================================================
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT DISTINCT FK_Patient_Link_ID INTO #Patients FROM [RLS].vw_Patient;

--> CODESET cancer:1 atrial-fibrillation:1 coronary-heart-disease:1 heart-failure:1 hypertension:1 peripheral-arterial-disease:1 stroke:1 tia:1 
--> CODESET diabetes:1 peptic-ulcer-disease:1 rheumatoid-arthritis:1 epilepsy:1 multiple-sclerosis:1 parkinsons:1 eating-disorders:1 anxiety:1 depression:1 
--> CODESET schizophrenia-psychosis:1 bipolar:1 chronic-kidney-disease:1 asthma:1 copd:1 

-- Create a table for the first diagnosis of cancer===================================================================================================================================
IF OBJECT_ID('tempdb..#CancerAll') IS NOT NULL DROP TABLE #CancerAll;
SELECT FK_Patient_Link_ID, TRY_CONVERT(DATE, EventDate) AS EventDate
INTO #CancerAll
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'cancer' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'cancer' AND Version = 1)
);

IF OBJECT_ID('tempdb..#CancerFirst') IS NOT NULL DROP TABLE #CancerFirst;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate
INTO #CancerFirst
FROM #CancerAll
GROUP BY FK_Patient_Link_ID;

DROP TABLE #CancerAll

-- Create a table for the first diagnosis of AF===================================================================================================================================
IF OBJECT_ID('tempdb..#AFAll') IS NOT NULL DROP TABLE #AFAll;
SELECT FK_Patient_Link_ID, TRY_CONVERT(DATE, EventDate) AS EventDate
INTO #AFAll
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'atrial-fibrillation' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'atrial-fibrillation' AND Version = 1)
);

IF OBJECT_ID('tempdb..#AFFirst') IS NOT NULL DROP TABLE #AFFirst;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate
INTO #AFFirst
FROM #AFAll
GROUP BY FK_Patient_Link_ID;

DROP TABLE #AFAll

-- Create a table for the first diagnosis of CHD===================================================================================================================================
IF OBJECT_ID('tempdb..#CHDAll') IS NOT NULL DROP TABLE #CHDAll;
SELECT FK_Patient_Link_ID, TRY_CONVERT(DATE, EventDate) AS EventDate
INTO #CHDAll
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'coronary-heart-disease' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'coronary-heart-disease' AND Version = 1)
);

IF OBJECT_ID('tempdb..#CHDFirst') IS NOT NULL DROP TABLE #CHDFirst;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate
INTO #CHDFirst
FROM #CHDAll
GROUP BY FK_Patient_Link_ID;

DROP TABLE #CHDAll

-- Create a table for the first diagnosis of HF===================================================================================================================================
IF OBJECT_ID('tempdb..#HFAll') IS NOT NULL DROP TABLE #HFAll;
SELECT FK_Patient_Link_ID, TRY_CONVERT(DATE, EventDate) AS EventDate
INTO #HFAll
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'heart-failure' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'heart-failure' AND Version = 1)
);

IF OBJECT_ID('tempdb..#HFFirst') IS NOT NULL DROP TABLE #HFFirst;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate
INTO #HFFirst
FROM #HFAll
GROUP BY FK_Patient_Link_ID;

DROP TABLE #HFAll


-- Create a table for the first diagnosis of hypertension===================================================================================================================================
IF OBJECT_ID('tempdb..#HypertensionAll') IS NOT NULL DROP TABLE #HypertensionAll;
SELECT FK_Patient_Link_ID, TRY_CONVERT(DATE, EventDate) AS EventDate
INTO #HypertensionAll
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'hypertension' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'hypertension' AND Version = 1)
);

IF OBJECT_ID('tempdb..#HypertensionFirst') IS NOT NULL DROP TABLE #HypertensionFirst;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate
INTO #HypertensionFirst
FROM #HypertensionAll
GROUP BY FK_Patient_Link_ID;

DROP TABLE #HypertensionAll

-- Create a table for the first diagnosis of PAD===================================================================================================================================
IF OBJECT_ID('tempdb..#PADAll') IS NOT NULL DROP TABLE #PADAll;
SELECT FK_Patient_Link_ID, TRY_CONVERT(DATE, EventDate) AS EventDate
INTO #PADAll
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'peripheral-arterial-disease' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'peripheral-arterial-disease' AND Version = 1)
);

IF OBJECT_ID('tempdb..#PADFirst') IS NOT NULL DROP TABLE #PADFirst;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate
INTO #PADFirst
FROM #PADAll
GROUP BY FK_Patient_Link_ID;

DROP TABLE #PADAll


-- Create a table for the first diagnosis of stroke===================================================================================================================================
IF OBJECT_ID('tempdb..#StrokeAll') IS NOT NULL DROP TABLE #StrokeAll;
SELECT FK_Patient_Link_ID, TRY_CONVERT(DATE, EventDate) AS EventDate
INTO #StrokeAll
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'stroke' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'stroke' AND Version = 1)
);

IF OBJECT_ID('tempdb..#StrokeFirst') IS NOT NULL DROP TABLE #StrokeFirst;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate
INTO #StrokeFirst
FROM #StrokeAll
GROUP BY FK_Patient_Link_ID;

DROP TABLE #StrokeAll


-- Create a table for the first diagnosis of TIA===================================================================================================================================
IF OBJECT_ID('tempdb..#TIAAll') IS NOT NULL DROP TABLE #TIAAll;
SELECT FK_Patient_Link_ID, TRY_CONVERT(DATE, EventDate) AS EventDate
INTO #TIAAll
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'tia' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'tia' AND Version = 1)
);

IF OBJECT_ID('tempdb..#TIAFirst') IS NOT NULL DROP TABLE #TIAFirst;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate
INTO #TIAFirst
FROM #TIAAll
GROUP BY FK_Patient_Link_ID;

DROP TABLE #TIAAll


-- Create a table for the first diagnosis of diabetes===================================================================================================================================
IF OBJECT_ID('tempdb..#DiabetesAll') IS NOT NULL DROP TABLE #DiabetesAll;
SELECT FK_Patient_Link_ID, TRY_CONVERT(DATE, EventDate) AS EventDate
INTO #DiabetesAll
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'diabetes' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'diabetes' AND Version = 1)
);

IF OBJECT_ID('tempdb..#DiabetesFirst') IS NOT NULL DROP TABLE #DiabetesFirst;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate
INTO #DiabetesFirst
FROM #DiabetesAll
GROUP BY FK_Patient_Link_ID;

DROP TABLE #DiabetesAll


-- Create a table for the first diagnosis of PUD===================================================================================================================================
IF OBJECT_ID('tempdb..#PUDAll') IS NOT NULL DROP TABLE #PUDAll;
SELECT FK_Patient_Link_ID, TRY_CONVERT(DATE, EventDate) AS EventDate
INTO #PUDAll
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'peptic-ulcer-disease' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'peptic-ulcer-disease' AND Version = 1)
);

IF OBJECT_ID('tempdb..#PUDFirst') IS NOT NULL DROP TABLE #PUDFirst;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate
INTO #PUDFirst
FROM #PUDAll
GROUP BY FK_Patient_Link_ID;

DROP TABLE #PUDAll


-- Create a table for the first diagnosis of RA===================================================================================================================================
IF OBJECT_ID('tempdb..#RAAll') IS NOT NULL DROP TABLE #RAAll;
SELECT FK_Patient_Link_ID, TRY_CONVERT(DATE, EventDate) AS EventDate
INTO #RAAll
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'rheumatoid-arthritis' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'rheumatoid-arthritis' AND Version = 1)
);

IF OBJECT_ID('tempdb..#RAFirst') IS NOT NULL DROP TABLE #RAFirst;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate
INTO #RAFirst
FROM #RAAll
GROUP BY FK_Patient_Link_ID;

DROP TABLE #RAAll


-- Create a table for the first diagnosis of epilepsy===================================================================================================================================
IF OBJECT_ID('tempdb..#EpilepsyAll') IS NOT NULL DROP TABLE #EpilepsyAll;
SELECT FK_Patient_Link_ID, TRY_CONVERT(DATE, EventDate) AS EventDate
INTO #EpilepsyAll
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'epilepsy' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'epilepsy' AND Version = 1)
);

IF OBJECT_ID('tempdb..#EpilepsyFirst') IS NOT NULL DROP TABLE #EpilepsyFirst;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate
INTO #EpilepsyFirst
FROM #EpilepsyAll
GROUP BY FK_Patient_Link_ID;

DROP TABLE #EpilepsyAll


-- Create a table for the first diagnosis of MS===================================================================================================================================
IF OBJECT_ID('tempdb..#MSAll') IS NOT NULL DROP TABLE #MSAll;
SELECT FK_Patient_Link_ID, TRY_CONVERT(DATE, EventDate) AS EventDate
INTO #MSAll
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'multiple-sclerosis' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'multiple-sclerosis' AND Version = 1)
);

IF OBJECT_ID('tempdb..#MSFirst') IS NOT NULL DROP TABLE #MSFirst;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate
INTO #MSFirst
FROM #MSAll
GROUP BY FK_Patient_Link_ID;

DROP TABLE #MSAll


-- Create a table for the first diagnosis of parkinsons===================================================================================================================================
IF OBJECT_ID('tempdb..#ParkinsonsAll') IS NOT NULL DROP TABLE #ParkinsonsAll;
SELECT FK_Patient_Link_ID, TRY_CONVERT(DATE, EventDate) AS EventDate
INTO #ParkinsonsAll
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'parkinsons' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'parkinsons' AND Version = 1)
);

IF OBJECT_ID('tempdb..#ParkinsonsFirst') IS NOT NULL DROP TABLE #ParkinsonsFirst;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate
INTO #ParkinsonsFirst
FROM #ParkinsonsAll
GROUP BY FK_Patient_Link_ID;

DROP TABLE #ParkinsonsAll


-- Create a table for the first diagnosis of eating disorders===================================================================================================================================
IF OBJECT_ID('tempdb..#EatingDisordersAll') IS NOT NULL DROP TABLE #EatingDisordersAll;
SELECT FK_Patient_Link_ID, TRY_CONVERT(DATE, EventDate) AS EventDate
INTO #EatingDisordersAll
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'eating-disorders' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'eating-disorders' AND Version = 1)
);

IF OBJECT_ID('tempdb..#EatingDisordersFirst') IS NOT NULL DROP TABLE #EatingDisordersFirst;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate
INTO #EatingDisordersFirst
FROM #EatingDisordersAll
GROUP BY FK_Patient_Link_ID;

DROP TABLE #EatingDisordersAll


-- Create a table for the first diagnosis of anxiety===================================================================================================================================
IF OBJECT_ID('tempdb..#AnxietyAll') IS NOT NULL DROP TABLE #AnxietyAll;
SELECT FK_Patient_Link_ID, TRY_CONVERT(DATE, EventDate) AS EventDate
INTO #AnxietyAll
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'anxiety' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'anxiety' AND Version = 1)
);

IF OBJECT_ID('tempdb..#AnxietyFirst') IS NOT NULL DROP TABLE #AnxietyFirst;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate
INTO #AnxietyFirst
FROM #AnxietyAll
GROUP BY FK_Patient_Link_ID;

DROP TABLE #AnxietyAll


-- Create a table for the first diagnosis of depression===================================================================================================================================
IF OBJECT_ID('tempdb..#DepressionAll') IS NOT NULL DROP TABLE #DepressionAll;
SELECT FK_Patient_Link_ID, TRY_CONVERT(DATE, EventDate) AS EventDate
INTO #DepressionAll
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'depression' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'depression' AND Version = 1)
);

IF OBJECT_ID('tempdb..#DepressionFirst') IS NOT NULL DROP TABLE #DepressionFirst;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate
INTO #DepressionFirst
FROM #DepressionAll
GROUP BY FK_Patient_Link_ID;

DROP TABLE #DepressionAll


-- Create a table for the first diagnosis of schizophrenia psychosis===================================================================================================================================
IF OBJECT_ID('tempdb..#SchizophreniaAll') IS NOT NULL DROP TABLE #SchizophreniaAll;
SELECT FK_Patient_Link_ID, TRY_CONVERT(DATE, EventDate) AS EventDate
INTO #SchizophreniaAll
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'schizophrenia-psychosis' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'schizophrenia-psychosis' AND Version = 1)
);

IF OBJECT_ID('tempdb..#SchizophreniaFirst') IS NOT NULL DROP TABLE #SchizophreniaFirst;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate
INTO #SchizophreniaFirst
FROM #SchizophreniaAll
GROUP BY FK_Patient_Link_ID;

DROP TABLE #SchizophreniaAll;



-- Create a table for the first diagnosis of bipolar===================================================================================================================================
IF OBJECT_ID('tempdb..#BipolarAll') IS NOT NULL DROP TABLE #BipolarAll;
SELECT FK_Patient_Link_ID, TRY_CONVERT(DATE, EventDate) AS EventDate
INTO #BipolarAll
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'bipolar' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'bipolar' AND Version = 1)
);

IF OBJECT_ID('tempdb..#BipolarFirst') IS NOT NULL DROP TABLE #BipolarFirst;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate
INTO #BipolarFirst
FROM #BipolarAll
GROUP BY FK_Patient_Link_ID;

DROP TABLE #BipolarAll;


-- Create a table for the first diagnosis of CKD===================================================================================================================================
IF OBJECT_ID('tempdb..#CKDAll') IS NOT NULL DROP TABLE #CKDAll;
SELECT FK_Patient_Link_ID, TRY_CONVERT(DATE, EventDate) AS EventDate
INTO #CKDAll
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'chronic-kidney-disease' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'chronic-kidney-disease' AND Version = 1)
);

IF OBJECT_ID('tempdb..#CKDFirst') IS NOT NULL DROP TABLE #CKDFirst;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate
INTO #CKDFirst
FROM #CKDAll
GROUP BY FK_Patient_Link_ID;

DROP TABLE #CKDAll;


-- Create a table for the first diagnosis of asthma===================================================================================================================================
IF OBJECT_ID('tempdb..#AsthmaAll') IS NOT NULL DROP TABLE #AsthmaAll;
SELECT FK_Patient_Link_ID, TRY_CONVERT(DATE, EventDate) AS EventDate
INTO #AsthmaAll
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'asthma' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'asthma' AND Version = 1)
);

IF OBJECT_ID('tempdb..#AsthmaFirst') IS NOT NULL DROP TABLE #AsthmaFirst;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate
INTO #AsthmaFirst
FROM #AsthmaAll
GROUP BY FK_Patient_Link_ID;

DROP TABLE #AsthmaAll;


-- Create a table for the first diagnosis of COPD===================================================================================================================================
IF OBJECT_ID('tempdb..#COPDAll') IS NOT NULL DROP TABLE #COPDAll;
SELECT FK_Patient_Link_ID, TRY_CONVERT(DATE, EventDate) AS EventDate
INTO #COPDAll
FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'copd' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'copd' AND Version = 1)
);

IF OBJECT_ID('tempdb..#COPDFirst') IS NOT NULL DROP TABLE #COPDFirst;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate
INTO #COPDFirst
FROM #COPDAll
GROUP BY FK_Patient_Link_ID;

DROP TABLE #COPDAll;


-- Merge all table=====================================================================================================================================================
IF OBJECT_ID('tempdb..#Table') IS NOT NULL DROP TABLE #Table;
SELECT * INTO #Table FROM #CancerFirst 
UNION
SELECT * FROM #AFFirst
UNION
SELECT * FROM #CHDFirst
UNION
SELECT * FROM #HFFirst
UNION
SELECT * FROM #HypertensionFirst
UNION
SELECT * FROM #PADFirst
UNION
SELECT * FROM #StrokeFirst
UNION
SELECT * FROM #TIAFirst
UNION
SELECT * FROM #DiabetesFirst
UNION
SELECT * FROM #PUDFirst
UNION
SELECT * FROM #RAFirst
UNION
SELECT * FROM #EpilepsyFirst
UNION
SELECT * FROM #MSFirst
UNION
SELECT * FROM #ParkinsonsFirst
UNION
SELECT * FROM #EatingDisordersFirst
UNION
SELECT * FROM #AnxietyFirst
UNION
SELECT * FROM #DepressionFirst
UNION
SELECT * FROM #SchizophreniaFirst
UNION
SELECT * FROM #BipolarFirst
UNION
SELECT * FROM #CKDFirst
UNION
SELECT * FROM #AsthmaFirst
UNION
SELECT * FROM #COPDFirst;


-- Create the final table============================================================================================================================
SELECT DISTINCT FK_Patient_Link_ID AS PatientId, EventDate AS [Date] 
FROM #Table
WHERE YEAR(EventDate) >= 2019;

