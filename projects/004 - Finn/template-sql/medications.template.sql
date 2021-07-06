--┌─────────────────────────────────┐
--│ Medications                     │
--└─────────────────────────────────┘

-- All medications for all patients in the study cohort one year before the index date.

-- OUTPUT: Data with the following fields
--     PK: MedicationID
--     FK: PatientID
--     FirstMedicationDate
--     LastMedicationDate 
--     Reference Coding ID 
--     Supplied Code 
--     Quantity
--     Dosage 
--     Last Issue Date
--     RepeatMedicationFlag e.g. (Y, N, Null)
--     SnomedCT Identifier


--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2019-02-01';

-- Get all the patients in the cohort
--> EXECUTE query-cancer-cohort-matching.sql
-- OUTPUTS: #Patients2


SELECT 
	FK_Patient_Link_ID AS PatientId,
	CAST(MedicationDate AS DATE) AS MedicationDate,
	SuppliedCode,
	MedicationDescription,
	CASE WHEN s.Concept IS NULL THEN c.Concept ELSE s.Concept END AS DrugType,
	Quantity,
	Dosage,
	LastIssueDate,
	Units, --??? 
	RepeatMedicationFlag
FROM RLS.vw_GP_Medications m
LEFT OUTER JOIN #VersionedSnomedSets s ON s.FK_Reference_SnomedCT_ID = m.FK_Reference_SnomedCT_ID
LEFT OUTER JOIN #VersionedCodeSets c ON c.FK_Reference_Coding_ID = m.FK_Reference_Coding_ID
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients2)
AND MedicationDate >= @StartDate;

-- AND (
--   m.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept IN ('hydroxychloroquine','leflunomide','methotrexate','prednisolone-oral','prednisone','sulfasalazine') AND [Version]=1) OR
--   m.FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept IN ('hydroxychloroquine','leflunomide','methotrexate','prednisolone-oral','prednisone','sulfasalazine') AND [Version]=1)
-- );
