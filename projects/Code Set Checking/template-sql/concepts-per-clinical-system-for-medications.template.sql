--┌───────────────────────────────────────┐
--│ Clinical concepts per clinical system │
--└───────────────────────────────────────┘

-- OBJECTIVE: To provide a report on the proportion of patients who have a particular
--            clinical concept in their record, broken down by clinical system. Because
--            different clinical systems use different clinical code terminologies, if
--            the percentage of patients with a particular condition is similar across 
--            clinical systems then we can be confident in our code sets. If there is a
--            discrepancy then this could be due to faulty code sets, or it could be an
--            underlying issue with the GMCR. Finally there is a possibility that because
--            TPP and Vision have relatively few patients compared with EMIS in GM, that
--            differences in the demographics of the TPP and Vision practices, or random
--            chance, will result in differences that are non indicative of any problem.

-- INPUT: No pre-requisites

-- OUTPUT: Two tables (one for events and one for medications) with the following fields
-- 	- Concept - the clinical concept e.g. the diagnosis, medication, procedure...
--  - Version - the version of the clinical concept
--  - System  - the clinical system (EMIS/Vision/TPP)
--  - PatientsWithConcept  - the number of patients with a clinical code for this concept in their record
--  - Patients  - the number of patients for this system supplier
--  - PercentageOfPatients  - the percentage of patients for this system supplier with this concept

--> CODESET insert-concept-here:1
--> EXECUTE query-practice-systems-lookup-SNOWFLAKE.sql

DROP TABLE IF EXISTS VersionedCodeSets;
CREATE TEMPORARY TABLE VersionedCodeSets AS
SELECT 	CONCEPT,
	VERSION,
	TERMINOLOGY,
	CODE,
	DESCRIPTION 
FROM SDE_REPOSITORY.SHARED_UTILITIES."Code_Sets_Code_Set_Checking";

-- First get all patients from the GP_Medications table who have a Code that exists in the code set table

DROP TABLE IF EXISTS PatientsWithCode;
CREATE TEMPORARY TABLE PatientsWithCode AS
SELECT "FK_Patient_ID", "SuppliedCode", CONCEPT, VERSION  
FROM INTERMEDIATE.GP_RECORD."GP_Medications_SecondaryUses" p
INNER JOIN VersionedCodeSets v ON v.CODE = p."SuppliedCode"
GROUP BY "FK_Patient_ID", "SuppliedCode", CONCEPT, VERSION;

SET snapshotdate = (SELECT MAX("Snapshot") FROM INTERMEDIATE.GP_RECORD."DemographicsProtectedCharacteristics");

-- Counts the number of patients for each version of each concept for each clinical system
DROP TABLE IF EXISTS PatientsWithCodePerSystem;
CREATE TEMPORARY TABLE PatientsWithCodePerSystem AS
SELECT SYSTEM, CONCEPT, VERSION, count(*) as Count
FROM INTERMEDIATE.GP_RECORD."DemographicsProtectedCharacteristics" p
INNER JOIN PracticeSystemLookup s on s.PracticeId = p."PracticeCode"
INNER JOIN PatientsWithCode c on c."FK_Patient_ID" = p."FK_Patient_ID"
WHERE "Snapshot" = $snapshotdate
GROUP BY SYSTEM, CONCEPT, VERSION;
--00:01:08


-- Counts the number of patients per system
DROP TABLE IF EXISTS PatientsPerSystem;
CREATE TEMPORARY TABLE PatientsPerSystem AS
SELECT SYSTEM, count(*) as Count FROM INTERMEDIATE.GP_RECORD."DemographicsProtectedCharacteristics" p
INNER JOIN PracticeSystemLookup s on s.PracticeId = p."PracticeCode"
WHERE "Snapshot" = $snapshotdate
GROUP BY SYSTEM;
--00:00:15


-- Populate table with system/event type possibilities
DROP TABLE IF EXISTS SystemEventCombos;
CREATE TEMPORARY TABLE SystemEventCombos AS
SELECT DISTINCT CONCEPT, VERSION,'EMIS' as SYSTEM FROM VersionedCodeSets
UNION
SELECT DISTINCT CONCEPT, VERSION,'TPP' as SYSTEM FROM VersionedCodeSets
UNION
SELECT DISTINCT CONCEPT, VERSION,'Vision' as SYSTEM FROM VersionedCodeSets;

DROP TABLE IF EXISTS TempFinal;
CREATE TEMPORARY TABLE TempFinal AS
SELECT 
	s.Concept, s.VERSION, pps.SYSTEM, MAX(pps.Count) as Patients, SUM(CASE WHEN p.Count IS NULL THEN 0 ELSE p.Count END) as PatientsWithConcept,
	SUM(CASE WHEN p.Count IS NULL THEN 0 ELSE 100 * CAST(p.Count AS float)/pps.Count END) as PercentageOfPatients,
FROM SystemEventCombos s
LEFT OUTER JOIN PatientsWithCodePerSystem p on p.SYSTEM = s.SYSTEM AND p.Concept = s.Concept AND p.VERSION = s.VERSION
INNER JOIN PatientsPerSystem pps ON pps.SYSTEM = s.SYSTEM
GROUP BY s.Concept, s.VERSION, pps.SYSTEM
ORDER BY s.Concept, s.VERSION, pps.SYSTEM;

-- FINAL EVENT TABLE
SELECT Concept, Version, 
	CONCAT('| ', CURRENT_DATE() , ' | ', System, ' | ', Patients, ' | ',
		PatientsWithConcept, 
		' (',
		case when PercentageOfPatients = 0 then 0 else round(PercentageOfPatients ,2-floor(log(10,abs(PercentageOfPatients )))) end, '%) | ') AS TextForReadMe  FROM TempFinal;

{{no-output-table}}