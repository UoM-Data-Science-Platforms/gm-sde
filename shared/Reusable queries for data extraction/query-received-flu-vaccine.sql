--┌─────────────────────────────────────────────────────┐
--│ Patient received flu vaccine in a given time period │
--└─────────────────────────────────────────────────────┘

-- OBJECTIVE: To find patients who received a flu vaccine in a given time period

-- INPUT: Takes two parameters
--  - date-from: YYYY-MM-DD - the start date of the time period (inclusive)
--  - date-to: YYYY-MM-DD - the end date of the time period (inclusive)
-- Requires one temp table to exist as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: A temp table as follows:
-- #PatientHadFluVaccine (FK_Patient_Link_ID, FluVaccineDate)
-- 	- FK_Patient_Link_ID - unique patient id
--	-	FluVaccineDate - YYYY-MM-DD (first date of flu vaccine in given time period)

-- ASSUMPTIONS:
--	- We look for codes related to the administration of flu vaccines and codes for the vaccine itself

--> CODESETS flu-vaccination
-- First get all patients from the GP_Events table who have a flu vaccination (procedure) code
IF OBJECT_ID('tempdb..#PatientsWithFluVacConcept') IS NOT NULL DROP TABLE #PatientsWithFluVacConcept;
SELECT FK_Patient_Link_ID, CAST(EventDate AS DATE) AS FluVaccineDate
INTO #PatientsWithFluVacConcept
FROM RLS.[vw_GP_Events]
WHERE (
	FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'flu-vaccination' AND [Version] = 1) OR
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'flu-vaccination' AND [Version] = 1)
)
AND EventDate >= '{param:date-from}'
AND EventDate <= '{param:date-to}';

--> CODESETS flu-vaccine
-- Then get all patients from the GP_Medications table who have a flu vaccine (medication) code
INSERT INTO #PatientsWithFluVacConcept
SELECT FK_Patient_Link_ID, CAST(MedicationDate AS DATE) FROM RLS.vw_GP_Medications
WHERE (
	FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'flu-vaccine' AND [Version] = 1) OR
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'flu-vaccine' AND [Version] = 1)
)
and MedicationDate > '{param:date-from}'
and MedicationDate <= '{param:date-to}';

-- Bring all together in final table
IF OBJECT_ID('tempdb..#PatientHadFluVaccine') IS NOT NULL DROP TABLE #PatientHadFluVaccine;
SELECT 
	FK_Patient_Link_ID,
	MIN(FluVaccineDate) AS FluVaccineDate
INTO #PatientHadFluVaccine FROM #PatientsWithFluVacConcept
GROUP BY FK_Patient_Link_ID;
