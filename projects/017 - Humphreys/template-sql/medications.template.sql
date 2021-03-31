--┌─────────────┐
--│ Medications │
--└─────────────┘

-- All prescriptions of: methotrexate, sulfasalazine, leflunomide, hydroxychloroquine
-- and the glucocorticoids predisolone and predisone.

-- OUTPUT: Data with the following fields
-- 	- PatientId (int)
--	-	GPPracticeCode
--	-	MedicationDate (YYYY-MM-DD)
--	-	SuppliedCode
--	-	MedicationDescription
--	-	DrugType (one of: 'hydroxychloroquine','leflunomide','methotrexate','prednisolone-oral','prednisone' or 'sulfasalazine')
--	-	Quantity
--	-	Dosage
--	-	Units
--	-	RepeatMedicationFlag

--Just want the output, not the messages
SET NOCOUNT ON;

-- For now let's use the in-built QOF rule for the RA cohort. We can refine this over time
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT DISTINCT FK_Patient_Link_ID
INTO #Patients
FROM [RLS].[vw_Cohort_Patient_Registers]
WHERE FK_Cohort_Register_ID IN (
	SELECT PK_Cohort_Register_ID FROM SharedCare.Cohort_Register
	WHERE FK_Cohort_Category_ID IN (
		SELECT PK_Cohort_Category_ID FROM SharedCare.Cohort_Category
		WHERE CategoryName = 'Rheumatoid Arthritis'
	)
);

--> EXECUTE load-code-sets.sql

SELECT 
	FK_Patient_Link_ID AS PatientId,
	GPPracticeCode,
	CAST(MedicationDate AS DATE) AS MedicationDate,
	SuppliedCode,
	MedicationDescription,
	CASE WHEN s.Concept IS NULL THEN c.Concept ELSE s.Concept END AS DrugType,
	Quantity,
	Dosage,
	Units,
	RepeatMedicationFlag
FROM RLS.vw_GP_Medications m
LEFT OUTER JOIN #VersionedSnomedSets s ON s.FK_Reference_SnomedCT_ID = m.FK_Reference_SnomedCT_ID
LEFT OUTER JOIN #VersionedCodeSets c ON c.FK_Reference_Coding_ID = m.FK_Reference_Coding_ID
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('hydroxychloroquine','leflunomide','methotrexate','prednisolone-oral','prednisone','sulfasalazine') AND [Version]=1) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('hydroxychloroquine','leflunomide','methotrexate','prednisolone-oral','prednisone','sulfasalazine') AND [Version]=1)
);
