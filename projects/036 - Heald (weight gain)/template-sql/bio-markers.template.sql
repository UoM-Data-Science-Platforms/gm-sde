--┌────────────────┐
--│ Biomarker file │
--└────────────────┘

----------------------- RDE CHECK ---------------------
-- George Tilston  - 7 April 2022 - via pull request --
-------------------------------------------------------

-- Cohort is patients diagnosed with FEP, Schizophrenia, Bipolar affective disorder
-- or psychotic depression. The below queries produce the data that is required for
-- each patient.

-- For each patient, this produces longitudinal readings for
-- BMI, HbA1c, Cholesterol, LDL-cholesterol, HDL-cholesterol, Vitamin D, Testosterone, SHBG, eGFR,

-- All blood glucose, , Bone profile,
--  LH, FSH, T4, TSH, Prolactin, Creatinine, weight, 
-- systolic blood pressure, diastolic blood pressure

-- since 2018-01-01.

--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2018-01-01';


-- First get all the SMI patients and the date of first diagnosis
--> CODESET severe-mental-illness:1 antipsychotics:1
--> CODESET amisulpride:1 aripiprazole:1 asenapine:1 chlorpromazine:1 clozapine:1 flupentixol:1 fluphenazine:1
--> CODESET haloperidol:1 levomepromazine:1 loxapine:1 lurasidone:1 olanzapine:1 paliperidone:1 perphenazine:1
--> CODESET pimozide:1 quetiapine:1 risperidone:1 sertindole:1 sulpiride:1 thioridazine:1 trifluoperazine:1
--> CODESET zotepine:1 zuclopenthixol:1
IF OBJECT_ID('tempdb..#SMIPatients') IS NOT NULL DROP TABLE #SMIPatients;
SELECT FK_Patient_Link_ID, MIN(CAST(EventDate AS DATE)) AS FirstDiagnosisDate INTO #SMIPatients
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('severe-mental-illness') AND [Version]=1) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('severe-mental-illness') AND [Version]=1)
)
GROUP BY FK_Patient_Link_ID;

IF OBJECT_ID('tempdb..#AntipsycoticPatients') IS NOT NULL DROP TABLE #AntipsycoticPatients;
SELECT FK_Patient_Link_ID, MIN(CAST(MedicationDate AS DATE)) AS FirstPrescriptionDate INTO #AntipsycoticPatients
FROM RLS.vw_GP_Medications
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('amisulpride', 'aripiprazole', 'asenapine', 'chlorpromazine', 'clozapine', 'flupentixol', 'fluphenazine', 'haloperidol', 'levomepromazine', 'loxapine', 'lurasidone', 'olanzapine', 'paliperidone', 'perphenazine', 'pimozide', 'quetiapine', 'risperidone', 'sertindole', 'sulpiride', 'thioridazine', 'trifluoperazine', 'zotepine', 'zuclopenthixol') AND [Version]=1) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('amisulpride', 'aripiprazole', 'asenapine', 'chlorpromazine', 'clozapine', 'flupentixol', 'fluphenazine', 'haloperidol', 'levomepromazine', 'loxapine', 'lurasidone', 'olanzapine', 'paliperidone', 'perphenazine', 'pimozide', 'quetiapine', 'risperidone', 'sertindole', 'sulpiride', 'thioridazine', 'trifluoperazine', 'zotepine', 'zuclopenthixol') AND [Version]=1)
)
GROUP BY FK_Patient_Link_ID;

-- Table of all patients with SMI or antipsycotic
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT FK_Patient_Link_ID INTO #Patients FROM #SMIPatients
UNION
SELECT FK_Patient_Link_ID FROM #AntipsycoticPatients;

--> CODESET bmi:2 hba1c:2 cholesterol:2 ldl-cholesterol:1 hdl-cholesterol:1 vitamin-d:1 testosterone:1 sex-hormone-binding-globulin:1 egfr:1
--> CODESET weight:1 systolic-blood-pressure:1 diastolic-blood-pressure:1

-- First lets get all the measurements in one place to improve query speed later on
IF OBJECT_ID('tempdb..#biomarkerValues') IS NOT NULL DROP TABLE #biomarkerValues;
SELECT 
	FK_Patient_Link_ID,
	CAST(EventDate AS DATE) AS EventDate,
	FK_Reference_Coding_ID,
	FK_Reference_SnomedCT_ID,
	[Value]
INTO #biomarkerValues
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets)
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate >= @StartDate
AND UPPER([Value]) NOT LIKE '%[A-Z]%' -- Remove any value that contains text. The only valid character is "e" in scientific notation e.g. 2e17 - but none of these values will be in that range
AND [Value] IS NOT NULL
AND [Value] != '0'; -- In theory none of these markers should have a 0 value so this is a sensible default to exclude

-- Get all biomarker values for the cohort
IF OBJECT_ID('tempdb..#biomarkers') IS NOT NULL DROP TABLE #biomarkers;
CREATE TABLE #biomarkers (
	FK_Patient_Link_ID BIGINT,
	Label VARCHAR(32),
	EventDate DATE,
	[Value] NVARCHAR(128)
);

INSERT INTO #biomarkers
SELECT FK_Patient_Link_ID, 'bmi' AS Label, EventDate, [Value]
FROM #biomarkerValues
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept = 'bmi' AND [Version] = 2)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'bmi' AND [Version] = 2))
);

INSERT INTO #biomarkers
SELECT FK_Patient_Link_ID, 'hba1c' AS Label, EventDate, [Value]
FROM #biomarkerValues
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept = 'hba1c' AND [Version] = 2)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'hba1c' AND [Version] = 2))
);

INSERT INTO #biomarkers
SELECT FK_Patient_Link_ID, 'cholesterol' AS Label, EventDate, [Value]
FROM #biomarkerValues
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept = 'cholesterol' AND [Version] = 2)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'cholesterol' AND [Version] = 2))
);

INSERT INTO #biomarkers
SELECT FK_Patient_Link_ID, 'ldl-cholesterol' AS Label, EventDate, [Value]
FROM #biomarkerValues
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept = 'ldl-cholesterol' AND [Version] = 1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'ldl-cholesterol' AND [Version] = 1))
);

INSERT INTO #biomarkers
SELECT FK_Patient_Link_ID, 'hdl-cholesterol' AS Label, EventDate, [Value]
FROM #biomarkerValues
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept = 'hdl-cholesterol' AND [Version] = 1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'hdl-cholesterol' AND [Version] = 1))
);

INSERT INTO #biomarkers
SELECT FK_Patient_Link_ID, 'vitamin-d' AS Label, EventDate, [Value]
FROM #biomarkerValues
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept = 'vitamin-d' AND [Version] = 1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'vitamin-d' AND [Version] = 1))
);

INSERT INTO #biomarkers
SELECT FK_Patient_Link_ID, 'testosterone' AS Label, EventDate, [Value]
FROM #biomarkerValues
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept = 'testosterone' AND [Version] = 1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'testosterone' AND [Version] = 1))
);

INSERT INTO #biomarkers
SELECT FK_Patient_Link_ID, 'sex-hormone-binding-globulin' AS Label, EventDate, [Value]
FROM #biomarkerValues
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept = 'sex-hormone-binding-globulin' AND [Version] = 1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'sex-hormone-binding-globulin' AND [Version] = 1))
);

INSERT INTO #biomarkers
SELECT FK_Patient_Link_ID, 'egfr' AS Label, EventDate, [Value]
FROM #biomarkerValues
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept = 'egfr' AND [Version] = 1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'egfr' AND [Version] = 1))
);

INSERT INTO #biomarkers
SELECT FK_Patient_Link_ID, 'weight' AS Label, EventDate, [Value]
FROM #biomarkerValues
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept = 'weight' AND [Version] = 1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'weight' AND [Version] = 1))
);

INSERT INTO #biomarkers
SELECT FK_Patient_Link_ID, 'systolic-blood-pressure' AS Label, EventDate, [Value]
FROM #biomarkerValues
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept = 'systolic-blood-pressure' AND [Version] = 1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'systolic-blood-pressure' AND [Version] = 1))
);

INSERT INTO #biomarkers
SELECT FK_Patient_Link_ID, 'diastolic-blood-pressure' AS Label, EventDate, [Value]
FROM #biomarkerValues
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept = 'diastolic-blood-pressure' AND [Version] = 1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'diastolic-blood-pressure' AND [Version] = 1))
);

-- Final output
SELECT FK_Patient_Link_ID AS PatientId, Label, EventDate, [Value]
FROM #biomarkers
ORDER BY FK_Patient_Link_ID, EventDate;