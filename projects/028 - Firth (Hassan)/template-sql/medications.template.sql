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

--> EXECUTE load-code-sets.sql

-- Define medication cohort -- 

--FIND PATIENTS THAT HAVE AN SMI DIAGNOSIS AS OF 31.01.20

IF OBJECT_ID('tempdb..#Patients_1') IS NOT NULL DROP TABLE #Patients_1;
SELECT distinct gp.FK_Patient_Link_ID 
INTO #Patients_1
FROM [RLS].[vw_GP_Events] gp
LEFT OUTER JOIN #Patients p ON p.PK_Patient_ID = gp.FK_Patient_ID
WHERE SuppliedCode IN (
	SELECT [Code] FROM #AllCodes WHERE [Concept] IN ('severe-mental-illness') AND [Version] = 1
)
	AND (gp.EventDate) <= '2020-01-31'

-- PATIENTS WITH PX OF PSYCHOTROPIC MEDS SINCE 31.07.19

IF OBJECT_ID('tempdb..#Patients_2') IS NOT NULL DROP TABLE #Patients_2;
SELECT 
	DISTINCT FK_Patient_Link_ID
INTO #Patients_2
FROM RLS.vw_GP_Medications m
LEFT OUTER JOIN #VersionedSnomedSets s ON s.FK_Reference_SnomedCT_ID = m.FK_Reference_SnomedCT_ID
LEFT OUTER JOIN #VersionedCodeSets c ON c.FK_Reference_Coding_ID = m.FK_Reference_Coding_ID
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND m.EventDate > '2019-07-31' AND (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('antipsychotics') AND [Version]=1) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('antipsychotics') AND [Version]=1)
);

-- FIND PATIENTS THAT HAVE AN SMI DIAGNOSIS AND PX OF PSYCHOTROPIC MEDS SINCE 31.07.20

IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT DISTINCT FK_Patient_Link_ID
INTO #Patients
FROM #Patients_1 WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients_2)



-- Find all prescriptions of antipsychotics for the patient cohort

SELECT 
	FK_Patient_Link_ID AS PatientId,
	MedicationDescription,
	PrescriptionDate = EventDate,
	Quantity,
	Dosage,
	Units
INTO #antipsychotics_prescribed
FROM RLS.vw_GP_Medications m
LEFT OUTER JOIN #VersionedSnomedSets s ON s.FK_Reference_SnomedCT_ID = m.FK_Reference_SnomedCT_ID
LEFT OUTER JOIN #VersionedCodeSets c ON c.FK_Reference_Coding_ID = m.FK_Reference_Coding_ID
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('antipsychotics') AND [Version]=1) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('antipsychotics') AND [Version]=1)
);

SELECT 
	PatientId, 
	MedicationDescription,
	MostRecentPrescriptionDate = MAX(PrescriptionDate)
FROM #antipsychotics_prescribed
GROUP BY 
	PatientId, 
	MedicationDescription,