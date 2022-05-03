--┌────────────────┐
--│ Biomarker file │
--└────────────────┘

----------------------- RDE CHECK ---------------------
-- George Tilston  - 7 April 2022 - via pull request --
-------------------------------------------------------

-- Cohort is patients diagnosed with FEP, Schizophrenia, Bipolar affective disorder
-- or psychotic depression. The below queries produce the data that is required for
-- each patient.

-- For each patient, this produces longitudinal readings for antipsycotic medications

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

IF OBJECT_ID('tempdb..#CodeDescriptions') IS NOT NULL DROP TABLE #CodeDescriptions;
select 
	PK_Reference_Coding_ID,
	CASE 
		WHEN FullDescription IS NOT NULL AND FullDescription !='' THEN FullDescription
		WHEN Term198 IS NOT NULL AND Term198 !='' THEN Term198
		WHEN Term60 IS NOT NULL AND Term60 !='' THEN Term60
		WHEN Term30 IS NOT NULL AND Term30 !='' THEN Term30
	END AS Description into #CodeDescriptions
from SharedCare.Reference_Coding where PK_Reference_Coding_ID in (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets);

/*
we don't have any snomed codes in our anti-psych lists so no need for this.

IF OBJECT_ID('tempdb..#SNOMEDCodeDescriptions') IS NOT NULL DROP TABLE #SNOMEDCodeDescriptions;
select PK_Reference_SnomedCT_ID,Term AS Description into #SNOMEDCodeDescriptions
from SharedCare.Reference_SnomedCT where PK_Reference_SnomedCT_ID in (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets);
*/

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
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('amisulpride', 'aripiprazole', 'asenapine', 'chlorpromazine', 'clozapine', 'flupentixol', 'fluphenazine', 'haloperidol', 'levomepromazine', 'loxapine', 'lurasidone', 'olanzapine', 'paliperidone', 'perphenazine', 'pimozide', 'quetiapine', 'risperidone', 'sertindole', 'sulpiride', 'thioridazine', 'trifluoperazine', 'zotepine', 'zuclopenthixol') AND [Version]=1
)
GROUP BY FK_Patient_Link_ID;

-- Table of all patients with SMI or antipsycotic
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT FK_Patient_Link_ID INTO #Patients FROM #SMIPatients
UNION
SELECT FK_Patient_Link_ID FROM #AntipsycoticPatients;

-- First lets get all the measurements in one place to improve query speed later on
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
FROM RLS.vw_GP_Medications m
LEFT OUTER JOIN #CodeDescriptions d on d.PK_Reference_Coding_ID = FK_Reference_Coding_ID
WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND MedicationDate >= @StartDate;

-- Get all medications for the cohort
IF OBJECT_ID('tempdb..#medications') IS NOT NULL DROP TABLE #medications;
CREATE TABLE #medications (
	FK_Patient_Link_ID BIGINT,
	Label VARCHAR(32),
	Description VARCHAR(128),
	Quantity NVARCHAR(10),
	Dosage NVARCHAR(256),
	MedicationDate DATE,
	SuppliedCode NVARCHAR(128)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'amisulpride' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'amisulpride' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'aripiprazole' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'aripiprazole' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'asenapine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'asenapine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'chlorpromazine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'chlorpromazine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'clozapine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'clozapine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'flupentixol' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'flupentixol' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'fluphenazine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'fluphenazine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'haloperidol' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'haloperidol' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'levomepromazine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'levomepromazine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'loxapine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'loxapine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'lurasidone' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'lurasidone' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'olanzapine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'olanzapine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'paliperidone' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'paliperidone' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'perphenazine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'perphenazine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'pimozide' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'pimozide' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'quetiapine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'quetiapine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'risperidone' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'risperidone' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'sertindole' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'sertindole' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'sulpiride' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'sulpiride' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'thioridazine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'thioridazine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'trifluoperazine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'trifluoperazine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'zotepine' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'zotepine' AND [Version] = 1)
);

INSERT INTO #medications
SELECT FK_Patient_Link_ID, 'zuclopenthixol' AS Label, Description, Quantity, Dosage, MedicationDate, SuppliedCode
FROM #allMedications 
WHERE FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept = 'zuclopenthixol' AND [Version] = 1)
);

-- Dosage information *might* contain sensitive information, so let's 
-- restrict to dosage instructions that occur >= 100 times
IF OBJECT_ID('tempdb..#SafeDosages') IS NOT NULL DROP TABLE #SafeDosages;
SELECT Dosage INTO #SafeDosages FROM #medications
group by Dosage
having count(*) >= 100;

-- Final output
SELECT
	FK_Patient_Link_ID AS PatientId, Label, Description, 
	Quantity, ISNULL(#SafeDosages.Dosage, 'REDACTED') AS Dosage, MedicationDate, SuppliedCode
FROM #medications m
LEFT OUTER JOIN #SafeDosages ON m.Dosage = #SafeDosages.Dosage
ORDER BY FK_Patient_Link_ID, MedicationDate;