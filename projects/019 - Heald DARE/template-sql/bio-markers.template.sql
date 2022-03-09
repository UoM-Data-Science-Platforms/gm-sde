--┌────────────┐
--│ HbA1c file │
--└────────────┘

------------------------ RDE CHECK -------------------------

-- Cohort is patients included in the DARE study. The below queries produce the data
-- that is required for each patient. However, a filter needs to be applied to only
-- provide this data for patients in the DARE study. Adrian Heald will provide GraphNet
-- with a list of NHS numbers, then they will execute the below but filtered to the list
-- of NHS numbers.

-- We assume that a temporary table will exist as follows:
-- CREATE TABLE #DAREPatients (NhsNo NVARCHAR(30));

-- For each patient in the DARE cohort, this produces all biomarker readings
-- since 2018-01-01.

-- TODO actually we now want 4 columns, so that we can include all bio readings and not just
-- hbA1c readings. We now also include bmi, hba1c, cholesterol, ldl, hdl etc..

--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2018-01-01';

-- Get link ids of patients
SELECT DISTINCT FK_Patient_Link_ID INTO #Patients
FROM [RLS].vw_Patient p
INNER JOIN #DAREPatients dp ON dp.NhsNo = p.NhsNo;

--> CODESET bmi:2 hba1c:2 cholesterol:2 ldl-cholesterol:1 hdl-cholesterol:1 vitamin-d:1 testosterone:1 sex-hormone-binding-globulin:1 egfr:1

-- Get all biomarker values for the cohort
IF OBJECT_ID('tempdb..#biomarkers') IS NOT NULL DROP TABLE #biomarkers;
CREATE TABLE #biomarkers (
	FK_Patient_Link_ID BIGINT,
	Label VARCHAR(32),
	EventDate DATE,
	[Value] NVARCHAR(128)
);

INSERT INTO #biomarkers
SELECT 
	FK_Patient_Link_ID,
  'bmi' AS Label,
	CAST(EventDate AS DATE) AS EventDate,
	[Value]
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept = 'bmi' AND [Version] = 2)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'bmi' AND [Version] = 2))
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate >= @StartDate
AND [Value] IS NOT NULL
AND [Value] != '0';

INSERT INTO #biomarkers
SELECT 
	FK_Patient_Link_ID,
  'hba1c' AS Label,
	CAST(EventDate AS DATE) AS EventDate,
	[Value]
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept = 'hba1c' AND [Version] = 2)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'hba1c' AND [Version] = 2))
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate >= @StartDate
AND [Value] IS NOT NULL
AND [Value] != '0';

INSERT INTO #biomarkers
SELECT 
	FK_Patient_Link_ID,
  'cholesterol' AS Label,
	CAST(EventDate AS DATE) AS EventDate,
	[Value]
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept = 'cholesterol' AND [Version] = 2)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'cholesterol' AND [Version] = 2))
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate >= @StartDate
AND [Value] IS NOT NULL
AND [Value] != '0';

INSERT INTO #biomarkers
SELECT 
	FK_Patient_Link_ID,
  'ldl' AS Label,
	CAST(EventDate AS DATE) AS EventDate,
	[Value]
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept = 'ldl-cholesterol' AND [Version] = 1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'ldl-cholesterol' AND [Version] = 1))
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate >= @StartDate
AND [Value] IS NOT NULL
AND [Value] != '0';

INSERT INTO #biomarkers
SELECT 
	FK_Patient_Link_ID,
  'hdl' AS Label,
	CAST(EventDate AS DATE) AS EventDate,
	[Value]
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept = 'hdl-cholesterol' AND [Version] = 1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'hdl-cholesterol' AND [Version] = 1))
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate >= @StartDate
AND [Value] IS NOT NULL
AND [Value] != '0';

INSERT INTO #biomarkers
SELECT 
	FK_Patient_Link_ID,
  'vitamin-d' AS Label,
	CAST(EventDate AS DATE) AS EventDate,
	[Value]
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept = 'vitamin-d' AND [Version] = 1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'vitamin-d' AND [Version] = 1))
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate >= @StartDate
AND [Value] IS NOT NULL
AND [Value] != '0';

INSERT INTO #biomarkers
SELECT 
	FK_Patient_Link_ID,
  'testosterone' AS Label,
	CAST(EventDate AS DATE) AS EventDate,
	[Value]
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept = 'testosterone' AND [Version] = 1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'testosterone' AND [Version] = 1))
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate >= @StartDate
AND [Value] IS NOT NULL
AND [Value] != '0';

INSERT INTO #biomarkers
SELECT 
	FK_Patient_Link_ID,
  'sex-hormone-binding-globulin' AS Label,
	CAST(EventDate AS DATE) AS EventDate,
	[Value]
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept = 'sex-hormone-binding-globulin' AND [Version] = 1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'sex-hormone-binding-globulin' AND [Version] = 1))
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate >= @StartDate
AND [Value] IS NOT NULL
AND [Value] != '0';

INSERT INTO #biomarkers
SELECT 
	FK_Patient_Link_ID,
  'egfr' AS Label,
	CAST(EventDate AS DATE) AS EventDate,
	[Value]
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept = 'egfr' AND [Version] = 1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'egfr' AND [Version] = 1))
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate >= @StartDate
AND [Value] IS NOT NULL
AND [Value] != '0';

-- Final output
SELECT * FROM #biomarkers
ORDER BY FK_Patient_Link_ID, EventDate;