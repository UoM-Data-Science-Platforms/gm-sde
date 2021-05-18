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

--> CODESET severe-mental-illness
--> CODESET antipsychotics

-- Define medication cohort -- 

--FIND PATIENTS THAT HAVE AN SMI DIAGNOSIS AS OF 31.01.20

IF OBJECT_ID('tempdb..#Patients_1') IS NOT NULL DROP TABLE #Patients_1;
SELECT distinct gp.FK_Patient_Link_ID 
INTO #Patients_1
FROM [RLS].[vw_GP_Events] gp
WHERE SuppliedCode IN (
	SELECT [Code] FROM #AllCodes WHERE [Concept] IN ('severe-mental-illness') AND [Version] = 1
)
	AND (gp.EventDate) <= '2020-01-31'

-- PATIENTS WITH PX OF PSYCHOTROPIC MEDS SINCE 31.07.19

IF OBJECT_ID('tempdb..#Patients_2') IS NOT NULL DROP TABLE #Patients_2;
SELECT 
	DISTINCT m.FK_Patient_Link_ID
INTO #Patients_2
FROM RLS.vw_GP_Medications m
LEFT OUTER JOIN #VersionedSnomedSets s ON s.FK_Reference_SnomedCT_ID = m.FK_Reference_SnomedCT_ID
LEFT OUTER JOIN #VersionedCodeSets c ON c.FK_Reference_Coding_ID = m.FK_Reference_Coding_ID
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients_1)
AND m.MedicationDate > '2019-07-31' 
AND (
	m.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('antipsychotics') AND [Version]=1) OR
    m.FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('antipsychotics') AND [Version]=1)
);

-- FIND PATIENTS THAT HAVE AN SMI DIAGNOSIS AND PX OF PSYCHOTROPIC MEDS SINCE 31.07.20

IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT DISTINCT FK_Patient_Link_ID
INTO #Patients
FROM #Patients_1 WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients_2)


--- find the medication names
IF OBJECT_ID('tempdb..#antipsychotics_descriptions') IS NOT NULL DROP TABLE #antipsychotics_descriptions;
SELECT AL.*, 
	[description] = CASE WHEN CT.[description] IS NOT NULL THEN CT.[description]
						 WHEN RE.[description] IS NOT NULL THEN RE.[description]
						 WHEN SN.[description] IS NOT NULL THEN SN.[description]
						 WHEN EM.[description] IS NOT NULL THEN EM.[description] ELSE NULL END
INTO #antipsychotics_descriptions
FROM #AllCodes AL
LEFT JOIN #codesctv3 CT ON CT.code = AL.Code
LEFT JOIN #codesreadv2 RE ON RE.code = AL.Code
LEFT JOIN #codessnomed SN ON SN.code = AL.Code
LEFT JOIN #codesemis EM ON EM.code = AL.Code
WHERE AL.Concept = 'antipsychotics'
GROUP BY 
	AL.Concept, 
	AL.[Version], 
	AL.[Code], 
	CASE WHEN CT.[description] IS NOT NULL THEN CT.[description]
		WHEN RE.[description] IS NOT NULL THEN RE.[description]
		WHEN SN.[description] IS NOT NULL THEN SN.[description]
		WHEN EM.[description] IS NOT NULL THEN EM.[description] ELSE NULL END

-- extract the main ingredient from the medication name
IF OBJECT_ID('tempdb..#antipsychotics_main_ingredient') IS NOT NULL DROP TABLE #antipsychotics_main_ingredient;
SELECT
	Concept, 
	[Version], 
	[Code], 
	[description],
	MainIngredient = CASE WHEN UPPER([description]) like '%ABILIFY%' THEN 'abilify'
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
INTO #antipsychotics_main_ingredient
FROM #antipsychotics_descriptions

-- Find all prescriptions of antipsychotics for the patient cohort
drop table #antipsychotics_prescribed
SELECT 
	FK_Patient_Link_ID AS PatientId,
	MedicationIngredient = i.MainIngredient,
	PrescriptionDate = CAST(MedicationDate AS DATE)
INTO #antipsychotics_prescribed
FROM RLS.vw_GP_Medications m
LEFT OUTER JOIN #VersionedSnomedSets s ON s.FK_Reference_SnomedCT_ID = m.FK_Reference_SnomedCT_ID
LEFT OUTER JOIN #VersionedCodeSets c ON c.FK_Reference_Coding_ID = m.FK_Reference_Coding_ID
LEFT OUTER JOIN #antipsychotics_main_ingredient i ON i.Code = m.SuppliedCode
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND (
	m.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('antipsychotics') AND [Version]=1) OR
	m.FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('antipsychotics') AND [Version]=1)
);

-- Produce final table of most recent antipsychotic prescriptions for SMI patients

SELECT 
	PatientId, 
	MedicationIngredient,
	MostRecentPrescriptionDate = MAX(PrescriptionDate)
FROM #antipsychotics_prescribed
GROUP BY 
	PatientId, 
	MedicationIngredient

