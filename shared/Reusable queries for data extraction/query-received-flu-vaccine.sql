--┌─────────────────────────────────────────────────────┐
--│ Patient received flu vaccine in a given time period │
--└─────────────────────────────────────────────────────┘

-- OBJECTIVE: To find patients who received a flu vaccine in a given time period

-- INPUT: Takes three parameters
--  - date-from: YYYY-MM-DD - the start date of the time period (inclusive)
--  - date-to: YYYY-MM-DD - the end date of the time period (inclusive)
-- 	- id: string - an id flag to enable multiple temp tables to be created
-- Requires one temp table to exist as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: A temp table as follows:
-- #PatientHadFluVaccine{id} (FK_Patient_Link_ID, FluVaccineDate)
--	- FK_Patient_Link_ID - unique patient id
--	- FluVaccineDate - YYYY-MM-DD (first date of flu vaccine in given time period)

-- ASSUMPTIONS:
--	- We look for codes related to the administration of flu vaccines and codes for the vaccine itself

--> CODESET flu-vaccination:1
-- First get all patients from the GP_Events table who have a flu vaccination (procedure) code
IF OBJECT_ID('tempdb..#PatientsWithFluVacConcept{param:id}') IS NOT NULL DROP TABLE #PatientsWithFluVacConcept{param:id};
SELECT FK_Patient_Link_ID, CAST(EventDate AS DATE) AS FluVaccineDate
INTO #PatientsWithFluVacConcept{param:id}
FROM RLS.[vw_GP_Events]
WHERE (
	FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'flu-vaccination' AND [Version] = 1) OR
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'flu-vaccination' AND [Version] = 1)
)
AND EventDate >= '{param:date-from}'
AND EventDate <= '{param:date-to}';

--> CODESET flu-vaccine:1
-- Then get all patients from the GP_Medications table who have a flu vaccine (medication) code
INSERT INTO #PatientsWithFluVacConcept{param:id}
SELECT FK_Patient_Link_ID, CAST(MedicationDate AS DATE) FROM RLS.vw_GP_Medications
WHERE (
	FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'flu-vaccine' AND [Version] = 1) OR
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'flu-vaccine' AND [Version] = 1)
)
and MedicationDate >= '{param:date-from}'
and MedicationDate <= '{param:date-to}';

-- Bring all together in final table
IF OBJECT_ID('tempdb..#PatientHadFluVaccine{param:id}') IS NOT NULL DROP TABLE #PatientHadFluVaccine{param:id};
SELECT 
	FK_Patient_Link_ID,
	MIN(FluVaccineDate) AS FluVaccineDate
INTO #PatientHadFluVaccine{param:id} FROM #PatientsWithFluVacConcept{param:id}
GROUP BY FK_Patient_Link_ID;
