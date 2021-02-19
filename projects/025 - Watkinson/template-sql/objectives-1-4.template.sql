--┌────────────────────────────────────┐
--│ An example SQL generation template │
--└────────────────────────────────────┘

-- OUTPUT: Data with the following fields
-- 	- PatientId
--  - AgeAtIndexDate
--  - Sex (M/F)
--  - Ethnicity
--  - LSOA
--  - IsCareHomeResident (Y/N)
--  - HasHighClinicalVulnerabilityIndicator (Y/N)
--  - DateOfHighClinicalVulnerabilityIndicator
--  - HasModerateClinicalVulnerabilityIndicator (Y/N)
--  - DateOfModerateClinicalVulnerabilityIndicator
--  - HasCovidHospitalisation (Y/N)
--  - HasCovidDeathWithin28Days (Y/N)
--  - HasCovidVaccine1stDose (Y/N)
--  - HasCovidVaccine2ndDose (Y/N)
--  - DistanceFromHomeTo1stVaccine
--  - DistanceFromHomeTo2ndVaccine
--  - DistanceFromHomeToNearestVaccineHub
--  - DateOfFirstCovidHospitalisation
--  - DateOfDeath
--  - DateOfEntry
--  - DateOfExit

--Just want the output, not the messages
SET NOCOUNT ON;

-- Get all patients
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT PK_Patient_Link_ID as FK_Patient_Link_ID, EthnicMainGroup INTO #Patients FROM [RLS].vw_Patient_Link;

--> EXECUTE query-patient-year-of-birth.sql

-- Remove patients who were <16 on 1st Feb 2020
DELETE FROM #PatientYearOfBirth WHERE 2020 - YearOfBirth <= 16;
IF OBJECT_ID('tempdb..#Temp') IS NOT NULL DROP TABLE #Temp;
SELECT p.FK_Patient_Link_ID, EthnicMainGroup INTO #Temp FROM #Patients p
	INNER JOIN #PatientYearOfBirth y ON y.FK_Patient_Link_ID = p.FK_Patient_Link_ID;
TRUNCATE TABLE #Patients;
INSERT INTO #Patients
SELECT * FROM #Temp;

--> EXECUTE query-patient-lsoa.sql
--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-care-home-resident.sql

--> EXECUTE load-code-sets.sql

SELECT FK_Patient_Link_ID, MIN(EventDate) FROM [RLS].[vw_GP_Events]
WHERE (
  FK_Coding_ID IN (SELECT FK_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'hypertension' AND Version = 2) OR
  FK_SNOMED_ID IN (SELECT FK_SNOMED_ID FROM #VersionedSnomedSets WHERE Concept = 'hypertension' AND Version = 2)
)
GROUP BY FK_Patient_Link_ID