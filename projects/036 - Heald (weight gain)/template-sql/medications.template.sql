--┌─────────────────┐
--│ Medication file │
--└─────────────────┘

----------------------- RDE CHECK ---------------------
-- George Tilston  - 7 April 2022 - via pull request --
-------------------------------------------------------

-- Cohort is patients diagnosed with FEP, Schizophrenia, Bipolar affective disorder
-- or psychotic depression. The below queries produce the data that is required for
-- each patient.

-- For each patient, this produces longitudinal readings for antipsycotic medications

-- since 2018-01-01.
-- UPDATE 15 June 2022 - PI has requested to go back as far as possible

--Just want the output, not the messages
SET NOCOUNT ON;

-- Only include patients who were first registered at a GP practice prior
-- to June 2022. This is 1 month before COPI expired and so acts as a buffer.
-- If we only looked at patients who first registered before July 2022, then
-- there is a chance that their data was processed after COPI expired.
IF OBJECT_ID('tempdb..#PatientsToInclude') IS NOT NULL DROP TABLE #PatientsToInclude;
SELECT FK_Patient_Link_ID INTO #PatientsToInclude
FROM SharedCare.Patient_GP_History
GROUP BY FK_Patient_Link_ID
HAVING MIN(StartDate) < '2022-06-01';

--> CODESET bipolar:2 schizophrenia-psychosis:2 history-of-bipolar:1 antipsychotics:1

IF OBJECT_ID('tempdb..#CodeDescriptions') IS NOT NULL DROP TABLE #CodeDescriptions;
select 
	PK_Reference_Coding_ID,
	CASE 
		WHEN FullDescription IS NOT NULL AND FullDescription !='' THEN FullDescription COLLATE Latin1_General_CS_AS
		WHEN Term198 IS NOT NULL AND Term198 !='' THEN Term198 COLLATE Latin1_General_CS_AS
		WHEN Term60 IS NOT NULL AND Term60 !='' THEN Term60 COLLATE Latin1_General_CS_AS
		WHEN Term30 IS NOT NULL AND Term30 !='' THEN Term30 COLLATE Latin1_General_CS_AS
	END AS Description into #CodeDescriptions
from SharedCare.Reference_Coding where PK_Reference_Coding_ID in (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets);

/*
we don't have any snomed codes in our anti-psych lists so no need for this.

IF OBJECT_ID('tempdb..#SNOMEDCodeDescriptions') IS NOT NULL DROP TABLE #SNOMEDCodeDescriptions;
select PK_Reference_SnomedCT_ID,Term AS Description into #SNOMEDCodeDescriptions
from SharedCare.Reference_SnomedCT where PK_Reference_SnomedCT_ID in (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets);
*/

-- First get all the SMI patients and the date of first diagnosis
--> CODESET history-of-psychosis-or-schizophrenia:1
--> CODESET amisulpride:1 aripiprazole:1 asenapine:1 chlorpromazine:1 clozapine:1 flupentixol:1 fluphenazine:1
--> CODESET haloperidol:1 levomepromazine:1 loxapine:1 lurasidone:1 olanzapine:1 paliperidone:1 perphenazine:1
--> CODESET pimozide:1 quetiapine:1 risperidone:1 sertindole:1 sulpiride:1 thioridazine:1 trifluoperazine:1
--> CODESET zotepine:1 zuclopenthixol:1
IF OBJECT_ID('tempdb..#BipolarPatients') IS NOT NULL DROP TABLE #BipolarPatients;
SELECT FK_Patient_Link_ID, MIN(CAST(EventDate AS DATE)) AS FirstBipolarDate INTO #BipolarPatients
FROM SharedCare.GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('bipolar') AND [Version]=2) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('bipolar') AND [Version]=2)
)
AND EventDate IS NOT NULL
AND EventDate < '2022-06-01'
GROUP BY FK_Patient_Link_ID;

IF OBJECT_ID('tempdb..#PsychosisSchizoPatients') IS NOT NULL DROP TABLE #PsychosisSchizoPatients;
SELECT FK_Patient_Link_ID, MIN(CAST(EventDate AS DATE)) AS FirstPsychosisSchizophreniaDate INTO #PsychosisSchizoPatients
FROM SharedCare.GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('schizophrenia-psychosis') AND [Version]=2) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('schizophrenia-psychosis') AND [Version]=2)
)
AND EventDate IS NOT NULL
AND EventDate < '2022-06-01'
GROUP BY FK_Patient_Link_ID;

IF OBJECT_ID('tempdb..#BipolarHistoryPatients') IS NOT NULL DROP TABLE #BipolarHistoryPatients;
SELECT FK_Patient_Link_ID, MIN(CAST(EventDate AS DATE)) AS FirstBipolarHistoryCode INTO #BipolarHistoryPatients
FROM SharedCare.GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('history-of-bipolar') AND [Version]=1) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('history-of-bipolar') AND [Version]=1)
)
AND EventDate IS NOT NULL
AND EventDate < '2022-06-01'
GROUP BY FK_Patient_Link_ID;

IF OBJECT_ID('tempdb..#PsychSchizoHistoryPatients') IS NOT NULL DROP TABLE #PsychSchizoHistoryPatients;
SELECT FK_Patient_Link_ID, MIN(CAST(EventDate AS DATE)) AS FirstPsychosisSchizophreniaHistoryCode INTO #PsychSchizoHistoryPatients
FROM SharedCare.GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('history-of-psychosis-or-schizophrenia') AND [Version]=1) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('history-of-psychosis-or-schizophrenia') AND [Version]=1)
)
AND EventDate IS NOT NULL
AND EventDate < '2022-06-01'
GROUP BY FK_Patient_Link_ID;


IF OBJECT_ID('tempdb..#AntipsycoticPatients') IS NOT NULL DROP TABLE #AntipsycoticPatients;
SELECT FK_Patient_Link_ID, MIN(CAST(MedicationDate AS DATE)) AS FirstAntipsycoticDate INTO #AntipsycoticPatients
FROM SharedCare.GP_Medications
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('amisulpride', 'aripiprazole', 'asenapine', 'chlorpromazine', 'clozapine', 'flupentixol', 'fluphenazine', 'haloperidol', 'levomepromazine', 'loxapine', 'lurasidone', 'olanzapine', 'paliperidone', 'perphenazine', 'pimozide', 'quetiapine', 'risperidone', 'sertindole', 'sulpiride', 'thioridazine', 'trifluoperazine', 'zotepine', 'zuclopenthixol') AND [Version]=1) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('amisulpride', 'aripiprazole', 'asenapine', 'chlorpromazine', 'clozapine', 'flupentixol', 'fluphenazine', 'haloperidol', 'levomepromazine', 'loxapine', 'lurasidone', 'olanzapine', 'paliperidone', 'perphenazine', 'pimozide', 'quetiapine', 'risperidone', 'sertindole', 'sulpiride', 'thioridazine', 'trifluoperazine', 'zotepine', 'zuclopenthixol') AND [Version]=1)
)
AND MedicationDate IS NOT NULL
AND MedicationDate < '2022-06-01'
GROUP BY FK_Patient_Link_ID;

-- Table of all patients with SMI or antipsycotic
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
(
  SELECT FK_Patient_Link_ID INTO #Patients FROM #BipolarPatients
  UNION
  SELECT FK_Patient_Link_ID FROM #BipolarHistoryPatients
  UNION
  SELECT FK_Patient_Link_ID FROM #PsychosisSchizoPatients
  UNION
  SELECT FK_Patient_Link_ID FROM #PsychSchizoHistoryPatients
  UNION
  SELECT FK_Patient_Link_ID FROM #AntipsycoticPatients
)
INTERSECT
SELECT FK_Patient_Link_ID FROM #PatientsToInclude;

-- First lets get all the medications in one place to improve query speed later on
IF OBJECT_ID('tempdb..#allMedications') IS NOT NULL DROP TABLE #allMedications;
SELECT 
	FK_Patient_Link_ID,
	CAST(MedicationDate AS DATE) AS MedicationDate,
  SuppliedCode,
	Description,
	Quantity,
	Dosage,
	FK_Reference_Coding_ID
INTO #allMedications
FROM SharedCare.GP_Medications m
LEFT OUTER JOIN #CodeDescriptions d on d.PK_Reference_Coding_ID = FK_Reference_Coding_ID
WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets)
AND MedicationDate < '2022-06-01'
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);

-- Get all medications for the cohort
IF OBJECT_ID('tempdb..#medications') IS NOT NULL DROP TABLE #medications;
CREATE TABLE #medications (
	FK_Patient_Link_ID BIGINT,
	Category VARCHAR(32),
	Label VARCHAR(32),
	Description VARCHAR(128),
	Quantity NVARCHAR(10),
	Dosage NVARCHAR(256),
	MedicationDate DATE,
	SuppliedCode NVARCHAR(128)
);

-- Antipsycotics
INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antipsychotic', 'amisulpride' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'amisulpride' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antipsychotic', 'aripiprazole' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'aripiprazole' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antipsychotic', 'asenapine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'asenapine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antipsychotic', 'chlorpromazine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'chlorpromazine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antipsychotic', 'clozapine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'clozapine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antipsychotic', 'flupentixol' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'flupentixol' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antipsychotic', 'fluphenazine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'fluphenazine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antipsychotic', 'haloperidol' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'haloperidol' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antipsychotic', 'levomepromazine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'levomepromazine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antipsychotic', 'loxapine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'loxapine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antipsychotic', 'lurasidone' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'lurasidone' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antipsychotic', 'olanzapine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'olanzapine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antipsychotic', 'paliperidone' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'paliperidone' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antipsychotic', 'perphenazine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'perphenazine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antipsychotic', 'pimozide' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'pimozide' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antipsychotic', 'quetiapine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'quetiapine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antipsychotic', 'risperidone' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'risperidone' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antipsychotic', 'sertindole' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'sertindole' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antipsychotic', 'sulpiride' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'sulpiride' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antipsychotic', 'thioridazine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'thioridazine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antipsychotic', 'trifluoperazine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'trifluoperazine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antipsychotic', 'zotepine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'zotepine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antipsychotic', 'zuclopenthixol' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'zuclopenthixol' AND [Version] = 1)
);

-- Antidepressants
--> CODESET amitriptyline:1 aripiprazole:1 buspirone:1 clomipramine:1 dosulepin:1 doxepin:1 duloxetine:1 escitalopram:1
--> CODESET flupentixol:1 imipramine:1 isocarboxazid:1 lofepramine:1 mianserin:1 mirtazapine:1 moclobemide:1 nortriptyline:1
--> CODESET olanzapine:1 paroxetine:1 phenelzine:1 pregabalin:1 quetiapine:1 reboxetine:1 risperidone:1 sertraline:1
--> CODESET tranylcypromine:1 trazodone-hydrochloride:1 trimipramine:1 venlafaxine:1 vortioxetine:1

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidepressant', 'amitriptyline' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications
WHERE FK_Reference_Coding_ID IN (
  SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'amitriptyline' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidepressant', 'aripiprazole' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications
WHERE FK_Reference_Coding_ID IN (
  SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'aripiprazole' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidepressant', 'buspirone' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications
WHERE FK_Reference_Coding_ID IN (
  SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'buspirone' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidepressant', 'clomipramine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications
WHERE FK_Reference_Coding_ID IN (
  SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'clomipramine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidepressant', 'dosulepin' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications
WHERE FK_Reference_Coding_ID IN (
  SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'dosulepin' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidepressant', 'doxepin' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications
WHERE FK_Reference_Coding_ID IN (
  SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'doxepin' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidepressant', 'duloxetine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications
WHERE FK_Reference_Coding_ID IN (
  SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'duloxetine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidepressant', 'escitalopram' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications
WHERE FK_Reference_Coding_ID IN (
  SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'escitalopram' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidepressant', 'flupentixol' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications
WHERE FK_Reference_Coding_ID IN (
  SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'flupentixol' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidepressant', 'imipramine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications
WHERE FK_Reference_Coding_ID IN (
  SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'imipramine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidepressant', 'isocarboxazid' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications
WHERE FK_Reference_Coding_ID IN (
  SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'isocarboxazid' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidepressant', 'lofepramine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications
WHERE FK_Reference_Coding_ID IN (
  SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'lofepramine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidepressant', 'mianserin' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications
WHERE FK_Reference_Coding_ID IN (
  SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'mianserin' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidepressant', 'mirtazapine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications
WHERE FK_Reference_Coding_ID IN (
  SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'mirtazapine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidepressant', 'moclobemide' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications
WHERE FK_Reference_Coding_ID IN (
  SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'moclobemide' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidepressant', 'nortriptyline' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications
WHERE FK_Reference_Coding_ID IN (
  SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'nortriptyline' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidepressant', 'olanzapine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications
WHERE FK_Reference_Coding_ID IN (
  SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'olanzapine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidepressant', 'paroxetine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications
WHERE FK_Reference_Coding_ID IN (
  SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'paroxetine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidepressant', 'phenelzine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications
WHERE FK_Reference_Coding_ID IN (
  SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'phenelzine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidepressant', 'pregabalin' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications
WHERE FK_Reference_Coding_ID IN (
  SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'pregabalin' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidepressant', 'quetiapine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications
WHERE FK_Reference_Coding_ID IN (
  SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'quetiapine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidepressant', 'reboxetine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications
WHERE FK_Reference_Coding_ID IN (
  SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'reboxetine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidepressant', 'risperidone' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications
WHERE FK_Reference_Coding_ID IN (
  SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'risperidone' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidepressant', 'sertraline' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications
WHERE FK_Reference_Coding_ID IN (
  SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'sertraline' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidepressant', 'tranylcypromine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications
WHERE FK_Reference_Coding_ID IN (
  SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'tranylcypromine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidepressant', 'trazodone-hydrochloride' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications
WHERE FK_Reference_Coding_ID IN (
  SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'trazodone-hydrochloride' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidepressant', 'trimipramine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications
WHERE FK_Reference_Coding_ID IN (
  SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'trimipramine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidepressant', 'venlafaxine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications
WHERE FK_Reference_Coding_ID IN (
  SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'venlafaxine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidepressant', 'vortioxetine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications
WHERE FK_Reference_Coding_ID IN (
  SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'vortioxetine' AND [Version] = 1)
);

-- Mood stabilizers
--> CODESET carbamazepine:1 lithium:1 valproic-acid:1 sodium-valproate:1 valproate-semisodium:1

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'mood-stabilizer', 'carbamazepine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'carbamazepine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'mood-stabilizer', 'lithium' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'lithium' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'mood-stabilizer', 'valproic-acid' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'valproic-acid' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'mood-stabilizer', 'sodium-valproate' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'sodium-valproate' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'mood-stabilizer', 'valproate-semisodium' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'valproate-semisodium' AND [Version] = 1)
);

-- Antihistamines
--> CODESET cetirizine-hydrochloride:1 chlorphenamine:1 cinnarizine:1 cyclizine:1 desloratadine:1 fexofenadine:1 
--> CODESET icatibant:1 ipratropium-bromide:1 levocetirizine:1 loratadine:1 mizolastine:1 promethazine:1 salbutamol:1 

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antihistamine','cetirizine-hydrochloride' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'cetirizine-hydrochloride' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antihistamine','chlorphenamine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'chlorphenamine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antihistamine','cinnarizine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'cinnarizine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antihistamine','cyclizine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'cyclizine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antihistamine','desloratadine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'desloratadine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antihistamine','fexofenadine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'fexofenadine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antihistamine','hydrochloride' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'hydrochloride' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antihistamine','icatibant' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'icatibant' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antihistamine','ipratropium-bromide' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'ipratropium-bromide' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antihistamine','levocetirizine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'levocetirizine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antihistamine','loratadine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'loratadine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antihistamine','mizolastine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'mizolastine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antihistamine','promethazine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'promethazine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antihistamine','salbutamol' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'salbutamol' AND [Version] = 1)
);

-- Steroids
--> CODESET betamethasone:1 dexamethasone:1 fludrocortisone-acetate:1 hydrocortisone:1 prednisolone:1
--> CODESET beclometasone:1 budesonide:1 deflazacort:1 fludrocortisone-acetate:1 methylprednisolone:1 
INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'steroid','betamethasone' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'betamethasone' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'steroid','dexamethasone' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'dexamethasone' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'steroid','fludrocortisone-acetate' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'fludrocortisone-acetate' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'steroid','hydrocortisone' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'hydrocortisone' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'steroid','prednisolone' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'prednisolone' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'steroid','beclometasone' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'beclometasone' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'steroid','budesonide' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'budesonide' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'steroid','deflazacort' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'deflazacort' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'steroid','fludrocortisone-acetate' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'fludrocortisone-acetate' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'steroid','methylprednisolone' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'methylprednisolone' AND [Version] = 1)
);

-- Contraceptive hormones
--> CODESET desogestrel:1 etonogestrel:1 levonorgestrel:1 medroxyprogesterone:1 norethisterone:1 
INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'contraceptive hormone', 'desogestrel' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'desogestrel' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'contraceptive hormone', 'etonogestrel' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'etonogestrel' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'contraceptive hormone', 'levonorgestrel' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'levonorgestrel' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'contraceptive hormone', 'medroxyprogesterone' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'medroxyprogesterone' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'contraceptive hormone', 'norethisterone' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'norethisterone' AND [Version] = 1)
);

-- Antidiabetics
--> CODESET insulin:1 acarbose:1 alogliptin:1 canagliflozin:1 dapagliflozin:1 dulaglutide:1 empagliflozin:1
--> CODESET exenatide:1 gliclazide:1 glimepiride:1 glipizide:1 linagliptin:1 liraglutide:1 lixisenatide:1
--> CODESET metformin:1 pioglitazone:1 repaglinide:1 saxagliptin:1 sitagliptin:1 tolbutamide:1 vildagliptin:1 
INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidiabetic','insulin' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'insulin' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidiabetic','acarbose' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'acarbose' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidiabetic','alogliptin' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'alogliptin' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidiabetic','canagliflozin' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'canagliflozin' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidiabetic','dapagliflozin' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'dapagliflozin' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidiabetic','dulaglutide' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'dulaglutide' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidiabetic','empagliflozin' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'empagliflozin' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidiabetic','exenatide' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'exenatide' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidiabetic','gliclazide' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'gliclazide' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidiabetic','glimepiride' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'glimepiride' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidiabetic','glipizide' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'glipizide' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidiabetic','linagliptin' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'linagliptin' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidiabetic','liraglutide' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'liraglutide' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidiabetic','lixisenatide' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'lixisenatide' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidiabetic','metformin' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'metformin' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidiabetic','pioglitazone' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'pioglitazone' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidiabetic','repaglinide' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'repaglinide' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidiabetic','saxagliptin' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'saxagliptin' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidiabetic','sitagliptin' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'sitagliptin' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidiabetic','tolbutamide' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'tolbutamide' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'antidiabetic','vildagliptin' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'vildagliptin' AND [Version] = 1)
);

-- Dosage information *might* contain sensitive information, so let's 
-- restrict to dosage instructions that occur >= 100 times
IF OBJECT_ID('tempdb..#SafeDosages') IS NOT NULL DROP TABLE #SafeDosages;
SELECT Dosage INTO #SafeDosages FROM #medications
group by Dosage
having count(*) >= 100;

-- Final output
SELECT
	FK_Patient_Link_ID AS PatientId,
	Category,
	Label,
	REPLACE(Description, ',',' ') AS Description,
	Quantity,
	LEFT(REPLACE(REPLACE(REPLACE(ISNULL(#SafeDosages.Dosage, 'REDACTED'),',',' '),CHAR(13),' '),CHAR(10),' '),50) AS Dosage,
	MedicationDate,
	SuppliedCode
FROM #medications m
LEFT OUTER JOIN #SafeDosages ON m.Dosage = #SafeDosages.Dosage
ORDER BY FK_Patient_Link_ID, MedicationDate;