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

-- OUTPUT: A tables with the following fields:
-- 	- Concept - the clinical concept e.g. the diagnosis, medication, procedure...
--  - Version - the version of the clinical concept
--  - TEXTFORREADME - | Date | Practice system | Population | Patients from ID | Patient from code |

-----------------------------------------------------------------------------------------------------------------------------------------------------------------

--  INSTRUCTIONS (permanent local changes that remain uncommited to master)
		-- these steps ensure that two RDEs can work on code sets at the same time without conflict

-- 1. Open code-sets.js (gm-sde > scripts), edit lines 273 and 274 to add your initials (e.g. "Code_Sets_${projectNameChunked.join('_')}_GT" )
-- 2. Add your initials on the end of any references to "Code_Sets_Code_Set_Checking" in the template files (e.g. "Code_Sets_Code_Set_Checking_GT")
		-- e.g. line 80 in this file

-- INSTRUCTIONS (steps involved each time a script is run)

-- 1. Specify a code set in the template file you want to run (e.g. change 'insert-code-set-here' to 'height') and check version number
-- 2. Ensure there is only a code-set specified in the script you are running (all other template files should have 'insert-concept-here')
-- 3. Run the stitching logic (generate-sql-windows.bat) to produce the extraction files
-- 4. Check the '0.code-sets.csv' file to ensure it contains only the codes you are expecting.
-- 5. Run in snowflake the file '0.code-sets.sql' from the extraction folder (to create an empty code set table for this project)
-- 6. Before running the script you must load the code sets for this project into the code set table in snowflake:
--    a. From the "Database" menu on the far left hand side within snowflake, select "Add Data"
--    b. Select "Load data into a Table"
--    c. Browse to select the 0.code-sets.csv file in this directory
--    d. Select the "SDE_REPOSITORY.SHARED_UTILITIES" schema
--    e. Select the table: "Code_Sets_Code_Set_Checking_YourInitials" and click "Next"
--    f. Select the file format "Delimited files (CSV/TSV)"
--    g. Double check that the preview looks ok and then click "Load"
-- 7. You can now copy the script you are running into snowflake and execute.

-----------------------------------------------------------------------------------------------------------------------------------------------------------------

--> CODESET insert-concept-here:1
--> EXECUTE query-practice-systems-lookup.sql

DROP TABLE IF EXISTS AllCodes;
CREATE TEMPORARY TABLE AllCodes (
  Concept varchar(255) NOT NULL,
  Version INT NOT NULL,
  Code varchar(20) NOT NULL
);



------------------ EDIT THE BELOW QUERY LOCALLY AND DON'T PUSH CHANGES

DROP TABLE IF EXISTS Code_Sets_To_Use;
CREATE TEMPORARY TABLE Code_Sets_To_Use AS
SELECT *
FROM SDE_REPOSITORY.SHARED_UTILITIES."Code_Sets_Code_Set_Checking" -- EDIT THIS LINE TO ADD YOUR INITIALS ON END OF TABLE
WHERE Code IS NOT NULL;

-------------------

-- create terminology-specific code set tables

DROP TABLE IF EXISTS codesctv3;
CREATE TEMPORARY TABLE codesctv3 AS 
SELECT concept, version, code, description,	
FROM Code_Sets_To_Use
WHERE TERMINOLOGY = 'ctv3';

DROP TABLE IF EXISTS codesreadv2;
CREATE TEMPORARY TABLE codesreadv2 AS 
SELECT concept, version, CASE WHEN TERMINOLOGY = 'readv2' AND LEN(CODE) > 5 then substr(CODE, 6, 2) else null end as term , code, description	
FROM Code_Sets_To_Use
WHERE TERMINOLOGY = 'readv2';

DROP TABLE IF EXISTS codessnomed;
CREATE TEMPORARY TABLE codessnomed AS 
SELECT concept, version, code, description
FROM Code_Sets_To_Use
WHERE TERMINOLOGY = 'snomed';

DROP TABLE IF EXISTS codesemis;
CREATE TEMPORARY TABLE codesemis AS 
SELECT concept, version, null as term, code, description
FROM Code_Sets_To_Use
WHERE TERMINOLOGY = 'emis';

-- add all codes into one table

INSERT INTO AllCodes
SELECT concept, version, code from codesctv3;
INSERT INTO AllCodes
SELECT concept, version, code from codesreadv2;
INSERT INTO AllCodes
SELECT concept, version, code from codessnomed;
INSERT INTO AllCodes
SELECT concept, version, code from codesemis;


DROP TABLE IF EXISTS TempRefCodes;
CREATE TEMPORARY TABLE TempRefCodes (
	FK_Reference_Coding_ID BIGINT NOT NULL, 
	concept VARCHAR(255) NOT NULL, 
	version INT NOT NULL
	);

-- Read v2 codes
INSERT INTO TempRefCodes
SELECT "PK_Reference_Coding_ID", dcr.concept, dcr.version
FROM INTERMEDIATE.GP_RECORD."Reference_Coding" rc
INNER JOIN codesreadv2 dcr on dcr.code = rc."MainCode"
WHERE "CodingType" ='ReadCodeV2'
	and (dcr.term = rc."Term" OR dcr.Term IS NULL)
	and "PK_Reference_Coding_ID" != -1;

-- CTV3 codes
INSERT INTO  TempRefCodes
SELECT "PK_Reference_Coding_ID", dcc.concept, dcc.version
FROM INTERMEDIATE.GP_RECORD."Reference_Coding" rc
INNER JOIN codesctv3 dcc on dcc.code = rc."MainCode"
WHERE "CodingType"='CTV3'
	and "PK_Reference_Coding_ID" != -1;

-- EMIS codes with a FK Reference Coding ID
INSERT INTO TempRefCodes
SELECT "FK_Reference_Coding_ID", ce.concept, ce.version
FROM INTERMEDIATE.GP_RECORD."Reference_Local_Code" rlc
INNER JOIN codesemis ce on ce.code = rlc."LocalCode"
WHERE "FK_Reference_Coding_ID" != -1;

DROP TABLE IF EXISTS TempSNOMEDRefCodes;
CREATE TEMPORARY TABLE TempSNOMEDRefCodes (
    FK_Reference_SnomedCT_ID BIGINT NOT NULL, 
    concept VARCHAR(255) NOT NULL, 
    version INT NOT NULL);

-- SNOMED codes
INSERT INTO TempSNOMEDRefCodes
SELECT "PK_Reference_SnomedCT_ID", dcs.concept, dcs.version
FROM INTERMEDIATE.GP_RECORD."Reference_SnomedCT" rs
INNER JOIN codessnomed dcs on dcs.code = rs."ConceptID";

-- EMIS codes with a FK SNOMED ID but without a FK Reference Coding ID
INSERT INTO TempSNOMEDRefCodes
SELECT "FK_Reference_SnomedCT_ID", ce.concept, ce.version
FROM INTERMEDIATE.GP_RECORD."Reference_Local_Code" rlc
INNER JOIN codesemis ce on ce.code = rlc."LocalCode"
WHERE "FK_Reference_Coding_ID" = -1
AND "FK_Reference_SnomedCT_ID" != -1;

-- De-duped tables
DROP TABLE IF EXISTS CodeSets;
CREATE TEMPORARY TABLE CodeSets (FK_Reference_Coding_ID BIGINT NOT NULL, concept VARCHAR(255) NOT NULL);

DROP TABLE IF EXISTS SnomedSets;
CREATE TEMPORARY TABLE SnomedSets (FK_Reference_SnomedCT_ID BIGINT NOT NULL, concept VARCHAR(255) NOT NULL);

DROP TABLE IF EXISTS VersionedCodeSets;
CREATE TEMPORARY TABLE VersionedCodeSets (FK_Reference_Coding_ID BIGINT NOT NULL, Concept VARCHAR(255), Version INT);

DROP TABLE IF EXISTS VersionedSnomedSets;
CREATE TEMPORARY TABLE VersionedSnomedSets (FK_Reference_SnomedCT_ID BIGINT NOT NULL, Concept VARCHAR(255), Version INT);

INSERT INTO VersionedCodeSets
SELECT DISTINCT * FROM TempRefCodes;

INSERT INTO VersionedSnomedSets
SELECT DISTINCT * FROM TempSNOMEDRefCodes;

INSERT INTO CodeSets
SELECT FK_Reference_Coding_ID, c.concept
FROM VersionedCodeSets c
INNER JOIN (
  SELECT concept, MAX(version) AS maxVersion FROM VersionedCodeSets
  GROUP BY concept)
sub ON sub.concept = c.concept AND c.version = sub.maxVersion;

INSERT INTO SnomedSets
SELECT FK_Reference_SnomedCT_ID, c.concept
FROM VersionedSnomedSets c
INNER JOIN (
  SELECT concept, MAX(version) AS maxVersion FROM VersionedSnomedSets
  GROUP BY concept)
sub ON sub.concept = c.concept AND c.version = sub.maxVersion;



-- First get all patients from the GP_Events table who have a Code that exists in the code set table

DROP TABLE IF EXISTS PatientsWithFKCode;
CREATE TEMPORARY TABLE PatientsWithFKCode AS
SELECT "FK_Patient_ID", "FK_Reference_Coding_ID" FROM INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses"
WHERE "FK_Reference_Coding_ID" IN (SELECT "FK_REFERENCE_CODING_ID" FROM VersionedCodeSets);

-- Then get all patients from the GP_Events table who have a matching "FK_Reference_SnomedCT_ID"
DROP TABLE IF EXISTS PatientsWithSNOMEDCode;
CREATE TEMPORARY TABLE PatientsWithSNOMEDCode AS
SELECT "FK_Patient_ID", "FK_Reference_SnomedCT_ID" FROM INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses"
WHERE "FK_Reference_SnomedCT_ID" IN (SELECT "FK_REFERENCE_SNOMEDCT_ID" FROM VersionedSnomedSets);

DROP TABLE IF EXISTS PatientsWithCode;
CREATE TEMPORARY TABLE PatientsWithCode AS
SELECT "FK_Patient_ID", CONCEPT, VERSION FROM PatientsWithFKCode p
INNER JOIN VersionedCodeSets v ON v."FK_REFERENCE_CODING_ID" = p."FK_Reference_Coding_ID"
UNION
SELECT "FK_Patient_ID", CONCEPT, VERSION FROM PatientsWithSNOMEDCode p
INNER JOIN VersionedSnomedSets v ON v."FK_REFERENCE_SNOMEDCT_ID" = p."FK_Reference_SnomedCT_ID"
GROUP BY "FK_Patient_ID", CONCEPT, VERSION;

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

-- Finds all patients with one of the clinical codes in the events table
DROP TABLE IF EXISTS PatientsWithSuppliedCode;
CREATE TEMPORARY TABLE PatientsWithSuppliedCode AS
SELECT "FK_Patient_ID", "SuppliedCode" FROM INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses"
WHERE "SuppliedCode" IN (SELECT CODE FROM AllCodes);


DROP TABLE IF EXISTS PatientsWithSuppliedConcept;
CREATE TEMPORARY TABLE PatientsWithSuppliedConcept AS
SELECT "FK_Patient_ID", CONCEPT, VERSION AS VERSION FROM PatientsWithSuppliedCode p
INNER JOIN AllCodes a on a.Code = p."SuppliedCode"
GROUP BY "FK_Patient_ID", CONCEPT, VERSION;

-- Counts the number of patients for each version of each concept for each clinical system
DROP TABLE IF EXISTS PatientsWithSuppConceptPerSystem;
CREATE TEMPORARY TABLE PatientsWithSuppConceptPerSystem AS
SELECT SYSTEM, CONCEPT, VERSION, count(*) as Count FROM INTERMEDIATE.GP_RECORD."DemographicsProtectedCharacteristics" p
INNER JOIN PracticeSystemLookup s on s.PracticeId = p."PracticeCode"
INNER JOIN PatientsWithSuppliedConcept c on c."FK_Patient_ID" = p."FK_Patient_ID"
WHERE "Snapshot" = $snapshotdate
GROUP BY SYSTEM, CONCEPT, VERSION;

-- Populate table with system/event type possibilities
DROP TABLE IF EXISTS SystemEventCombos;
CREATE TEMPORARY TABLE SystemEventCombos AS
SELECT DISTINCT CONCEPT, VERSION,'EMIS' as SYSTEM FROM AllCodes
UNION
SELECT DISTINCT CONCEPT, VERSION,'TPP' as SYSTEM FROM AllCodes
UNION
SELECT DISTINCT CONCEPT, VERSION,'Vision' as SYSTEM FROM AllCodes;

DROP TABLE IF EXISTS TempFinal;
CREATE TEMPORARY TABLE TempFinal AS
SELECT 
	s.Concept, s.VERSION, pps.SYSTEM, MAX(pps.Count) as Patients, SUM(CASE WHEN p.Count IS NULL THEN 0 ELSE p.Count END) as PatientsWithConcept,
	SUM(CASE WHEN psps.Count IS NULL THEN 0 ELSE psps.Count END) as PatiensWithConceptFromCode,
	SUM(CASE WHEN p.Count IS NULL THEN 0 ELSE 100 * CAST(p.Count AS float)/pps.Count END) as PercentageOfPatients,
	SUM(CASE WHEN psps.Count IS NULL THEN 0 ELSE 100 * CAST(psps.Count AS float)/pps.Count END) as PercentageOfPatientsFromCode
FROM SystemEventCombos s
LEFT OUTER JOIN PatientsWithCodePerSystem p on p.SYSTEM = s.SYSTEM AND p.Concept = s.Concept AND p.VERSION = s.VERSION
INNER JOIN PatientsPerSystem pps ON pps.SYSTEM = s.SYSTEM
LEFT OUTER JOIN PatientsWithSuppConceptPerSystem psps ON psps.SYSTEM = s.SYSTEM AND psps.Concept = s.Concept AND psps.VERSION = s.VERSION
GROUP BY s.Concept, s.VERSION, pps.SYSTEM
ORDER BY s.Concept, s.VERSION, pps.SYSTEM;

-- FINAL EVENT TABLE
SELECT Concept, Version, 
	CONCAT('| ', CURRENT_DATE() , ' | ', System, ' | ', Patients, ' | ',
		PatientsWithConcept, 
		' (',
		case when PercentageOfPatients = 0 then 0 else round(PercentageOfPatients ,2-floor(log(10,abs(PercentageOfPatients )))) end, '%) | ',
		PatiensWithConceptFromCode, 
		' (',
		case when PercentageOfPatientsFromCode = 0 then 0 else round(PercentageOfPatientsFromCode ,2-floor(log(10,abs(PercentageOfPatientsFromCode )))) end, '%) | ') AS TextForReadMe  FROM TempFinal;

{{no-output-table}}