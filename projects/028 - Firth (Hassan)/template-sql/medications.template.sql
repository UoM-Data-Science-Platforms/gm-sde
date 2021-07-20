--┌─────────────┐
--│ Medications │
--└─────────────┘

-- All prescriptions of: antipsychotic medication.

-- OUTPUT: Data with the following fields
-- 	-   PatientId (int)
--	-	MedicationDescription
--	-	MostRecentPrescriptionDate (YYYY-MM-DD)

--Just want the output, not the messages
SET NOCOUNT ON;

DECLARE @StartDate datetime;
SET @StartDate = '2020-01-31';


-- Find all patients alive at start date
IF OBJECT_ID('tempdb..#PossiblePatients') IS NOT NULL DROP TABLE #PossiblePatients;
SELECT PK_Patient_Link_ID as FK_Patient_Link_ID, EthnicMainGroup, DeathDate INTO #PossiblePatients FROM [RLS].vw_Patient_Link
WHERE (DeathDate IS NULL OR DeathDate >= @StartDate);

-- Find all patients registered with a GP
IF OBJECT_ID('tempdb..#PatientsWithGP') IS NOT NULL DROP TABLE #PatientsWithGP;
SELECT DISTINCT FK_Patient_Link_ID INTO #PatientsWithGP FROM [RLS].vw_Patient
where FK_Reference_Tenancy_ID = 2;

-- Make cohort from patients alive at start date and registered with a GP
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT pp.* INTO #Patients FROM #PossiblePatients pp
INNER JOIN #PatientsWithGP gp on gp.FK_Patient_Link_ID = pp.FK_Patient_Link_ID;


--> CODESET recurrent-depressive:1 schizophrenia-psychosis:1 bipolar:1
--> CODESET antipsychotics:1

-- cohort of patients with depression

IF OBJECT_ID('tempdb..#depression_cohort') IS NOT NULL DROP TABLE #depression_cohort;
SELECT DISTINCT gp.FK_Patient_Link_ID
INTO #depression_cohort
FROM [RLS].[vw_GP_Events] gp
WHERE SuppliedCode IN 
	(SELECT [Code] FROM #AllCodes WHERE [Concept] IN ('depression') AND [Version] = 1)
    AND gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
	AND (gp.EventDate) <= '2020-01-31'
--655,657

-- take a 10 percent sample of depression patients (as requested by PI), to add to SMI cohort later on
IF OBJECT_ID('tempdb..#depression_cohort_sample') IS NOT NULL DROP TABLE #depression_cohort_sample;
SELECT TOP 10 PERCENT *
INTO #depression_cohort_sample
FROM #depression_cohort
ORDER BY FK_Patient_Link_ID --not ideal to order by this but need it to be the same across files
--65,566

--FIND PATIENTS THAT HAVE AN SMI DIAGNOSIS AS OF 31.01.20

IF OBJECT_ID('tempdb..#SMI_patients') IS NOT NULL DROP TABLE #SMI_patients;
SELECT 
	distinct gp.FK_Patient_Link_ID
INTO #SMI_patients
FROM [RLS].[vw_GP_Events] gp
WHERE ((SuppliedCode IN 
	(SELECT [Code] FROM #AllCodes WHERE [Concept] IN ('recurrent-depressive', 'bipolar', 'schizophrenia-psychosis') AND [Version] = 1)) 
	OR 
	(gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #depression_cohort_sample)))
	AND gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
	AND (gp.EventDate) <= '2020-01-31'


-- SMI PATIENTS WITH RX OF PSYCHOTROPIC MEDS SINCE 31.07.19

IF OBJECT_ID('tempdb..#SMI_antipsychotics') IS NOT NULL DROP TABLE #SMI_antipsychotics;
SELECT 
	 m.FK_Patient_Link_ID,
		CAST(MedicationDate AS DATE) as PrescriptionDate,
		[description] = CASE WHEN s.[description] IS NOT NULL THEN s.[description] ELSE c.[description] END
INTO #SMI_antipsychotics
FROM RLS.vw_GP_Medications m
LEFT OUTER JOIN #VersionedSnomedSets s ON s.FK_Reference_SnomedCT_ID = m.FK_Reference_SnomedCT_ID
LEFT OUTER JOIN #VersionedCodeSets c ON c.FK_Reference_Coding_ID = m.FK_Reference_Coding_ID
WHERE m.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #SMI_patients)
AND m.MedicationDate > '2019-07-31' 
AND (
	m.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('antipsychotics') AND [Version]=1) OR
    m.FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('antipsychotics') AND [Version]=1)
);


-- CREATE TABLE OF ALL ANTIPSYCHOTIC RX FOR THE SMI COHORT, WITH THE MAIN INGREDIENT AND PRESCRIPTION DATE

drop table #antipsychotics_rx
SELECT 
	PatientId = FK_Patient_Link_ID,
	PrescriptionDate,
	ActiveIngredient = CASE WHEN UPPER([description]) like '%ABILIFY%' THEN 'abilify'
	WHEN UPPER([description]) like '%AMISULPRIDE%' THEN 'amisulpride'
	WHEN UPPER([description]) like '%ANQUIL%' THEN 'anquil'
	WHEN UPPER([description]) like '%ARIPIPRAZOLE%' THEN 'aripiprazole'
	WHEN UPPER([description]) like '%ASENAPINE%' THEN 'asenapine'
	WHEN UPPER([description]) like '%BENPERIDOL%' THEN 'benperidol'
	WHEN UPPER([description]) like '%BENQUIL%' THEN 'benquil'
	WHEN UPPER([description]) like '%CHLORACTIL%' THEN 'chloractil'
	WHEN UPPER([description]) like '%CHLORPROMAZ%' THEN 'chlorpromazine'
	WHEN UPPER([description]) like '%CHLORPROTHIXENE%' THEN 'chlorprothixene'
	WHEN UPPER([description]) like '%CLOPIXOL%' THEN 'clopixol'
	WHEN UPPER([description]) like '%CLOZAPINE%' THEN 'clozapine'
	WHEN UPPER([description]) like '%CLOZARIL%' THEN 'clozaril'
	WHEN UPPER([description]) like '%DENZAPINE%' THEN 'denzapine'
	WHEN UPPER([description]) like '%DEPIXOL%' THEN 'depixol'
	WHEN UPPER([description]) like '%DOLMATIL%' THEN 'dolmatil'
	WHEN UPPER([description]) like '%DOZIC%' THEN 'dozic'
	WHEN UPPER([description]) like '%DROLEPTAN%' THEN 'droleptan'
	WHEN UPPER([description]) like '%Droperidol%' THEN 'droperidol'
	WHEN UPPER([description]) like '%FENTAZIN%' THEN 'fentazin'
	WHEN (UPPER([description]) like '%FLUPENTIXOL%' OR UPPER([description]) like '%FLUPENTHIXOL%') THEN 'flupentixol'
	WHEN UPPER([description]) like '%FLUPHENAZ%' THEN 'fluphenazine'
	WHEN UPPER([description]) like '%HALDOL%' THEN 'haldol'
	WHEN UPPER([description]) like '%HALOPERIDOL%' THEN 'haloperidol'
	WHEN UPPER([description]) like '%INTEGRIN%' THEN 'integrin'
	WHEN UPPER([description]) like '%INVEGA%' THEN 'invega'
	WHEN UPPER([description]) like '%LARGACTIL%' THEN 'largactil'
	WHEN UPPER([description]) like '%LEVINAN%' THEN 'levinan'
	WHEN UPPER([description]) like '%LEVOMEPROMAZINE%' THEN 'Levomepromazine'
	WHEN UPPER([description]) like '%Modecate%' THEN 'modecate'
	WHEN UPPER([description]) like '%MODITEN%' THEN 'moditen'
	WHEN UPPER([description]) like '%NEULACTIL%' THEN 'neulactil'
	WHEN UPPER([description]) like '%NOZINAN%' THEN 'nozinan'
	WHEN UPPER([description]) like '%OLANZAPINE%' THEN 'olanzapine'
	WHEN UPPER([description]) like 'ORAP %' THEN 'orap'
	WHEN UPPER([description]) like '%PALIPERIDON%' THEN 'paliperidone'
	WHEN UPPER([description]) like '%PARSTELIN%' THEN 'parstelin'
	WHEN UPPER([description]) like '%PERICYAZINE%' THEN 'pericyazine'
	WHEN UPPER([description]) like '%PERPHENAZINE%' THEN 'perphenazine'
	WHEN UPPER([description]) like '%PIMOZIDE%' THEN 'pimozide'
	WHEN UPPER([description]) like '%PIPORTIL%' THEN 'piportil'
	WHEN (UPPER([description]) like '%PIPOTIAZINE%' OR UPPER([description]) like '%PIPOTHIAZINE%') THEN 'pipotiazine'
	WHEN (UPPER([description]) like '%PROMAZINE%' AND UPPER([description]) NOT like '%CHLORPROMAZINE%') THEN 'promazine'
	WHEN UPPER([description]) like '%PSYTIXOL%' THEN 'psytixol'
	WHEN UPPER([description]) like '%QUETIAPINE%' THEN 'quetiapine'
	WHEN UPPER([description]) like '%REMOXIPRIDE%' THEN 'remoxipride'
	WHEN UPPER([description]) like '%RISPERDAL%' THEN 'risperdal'
	WHEN UPPER([description]) like '%RISPERIDONE%' THEN 'risperidone'
	WHEN UPPER([description]) like '%ROXIAM%' THEN 'roxiam'
	WHEN UPPER([description]) like '%SERDOLECT%' THEN 'serdolect'
	WHEN UPPER([description]) like '%SERENACE%' THEN 'serenace'
	WHEN UPPER([description]) like '%SEROQUEL%' THEN 'seroquel'
	WHEN UPPER([description]) like '%SERTINDOLE%' THEN 'sertindole'
	WHEN UPPER([description]) like '%SOLIAN%' THEN 'solian'
	WHEN UPPER([description]) like '%SONDATE%' THEN 'sondate'
	WHEN UPPER([description]) like '%SPARINE%' THEN 'sparine'
	WHEN UPPER([description]) like '%STELABID%' THEN 'stelabid'
	WHEN UPPER([description]) like '%STELAZINE%' THEN 'stelazine'
	WHEN UPPER([description]) like '%SULPAREX%' THEN 'sulparex'
	WHEN UPPER([description]) like '%SULPIRIDE%' THEN 'sulpiride'
	WHEN UPPER([description]) like '%SULPITIL%' THEN 'sulpitil'
	WHEN UPPER([description]) like '%SULPOR%' THEN 'sulpor'
	WHEN UPPER([description]) like '%TARACTAN%' THEN 'taractan'
	WHEN UPPER([description]) like '%TENPROLIDE%' THEN 'tenprolide'
	WHEN UPPER([description]) like '%THIORIDAZINE%' THEN 'thioridazine'
	WHEN UPPER([description]) like '%TRANYLCYPROMINE%' THEN 'tranylcypromine'
	WHEN UPPER([description]) like '%TRIFLUOPERAZ%' THEN 'trifluoperazine'
	WHEN UPPER([description]) like '%TRIFLUPERIDOL%' THEN 'trifluperidol'
	WHEN UPPER([description]) like '%TRIPERIDOL%' THEN 'triperidol'
	WHEN UPPER([description]) like '%TRIPTAFEN%' THEN 'triptafen'
	WHEN UPPER([description]) like '%VERACTIL%' THEN 'veractil'
	WHEN UPPER([description]) like '%XEPLION%' THEN 'xeplion'
	WHEN UPPER([description]) like '%ZALASTA%' THEN 'zalasta'
	WHEN UPPER([description]) like '%ZAPONEX%' THEN 'zaponex'
	WHEN UPPER([description]) like '%ZOLEPTIL%' THEN 'zoleptil'
	WHEN UPPER([description]) like '%ZOTEPINE%' THEN 'zotepine'
	WHEN UPPER([description]) like '%ZUCLOPENTHIX%' THEN 'zuclopenthixol'
	WHEN UPPER([description]) like '%ZYPADHERA%' THEN 'zypadhera'
	WHEN UPPER([description]) like '%ZYPREXA%'  THEN 'zyprexa'
		ELSE NULL END
INTO #antipsychotics_rx
FROM #SMI_antipsychotics 

-- Produce final table of most recent antipsychotic prescriptions for SMI patients

SELECT PatientId, 
	ActiveIngredient, 
	MostRecentPrescriptionDate = MAX(PrescriptionDate)
FROM #antipsychotics_rx
GROUP BY PatientId, 
	ActiveIngredient
ORDER BY PatientId,
	ActiveIngredient


