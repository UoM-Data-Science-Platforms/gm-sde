--┌─────────────┐
--│ Medications │
--└─────────────┘

------------------- RDE CHECK ----------------------
-- RDE Name: George Tilston, Date of check: 06/05/21

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
--> EXECUTE query-qof-cohort.sql condition:"Rheumatoid Arthritis" outputtable:Patients

--> CODESET hydroxychloroquine:1 leflunomide:1 methotrexate:1 prednisolone-oral:1 prednisone:1 sulfasalazine:1
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
  m.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('hydroxychloroquine','leflunomide','methotrexate','prednisolone-oral','prednisone','sulfasalazine') AND [Version]=1) OR
  m.FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('hydroxychloroquine','leflunomide','methotrexate','prednisolone-oral','prednisone','sulfasalazine') AND [Version]=1)
);
