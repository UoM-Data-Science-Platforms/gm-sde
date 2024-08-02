--┌─────────────────────────────────────────────────┐
--│ Finds missing codes using the existing mappings │
--└─────────────────────────────────────────────────┘

-- OBJECTIVE: To find clinical codes that may be missing from a codeset. It does this purely
--            based on the mappings between the terminologies held in the INTERMEDIATE.GP_Record "schema"
--						of the GMCR. A good example would be when there is a new codeset that is only
--						defined in a single terminology. This script will find all the codes from the 
--						other 3 terminologies in use in the GMCR.
--						Due to the nature of the mappings, it is possible that a newly discovered code
--						may in turn find additional codes from its mappings. Therefore this script will
--						continue to run until no new codes are found, or if 5 iterations are reached. 
--						This is to protect against the situation where an incorrect mapping leads to a
--						code set with many incorrect codes.

-- INPUT: No pre-requisites

-- OUTPUT: The final select query lists all the missing codes. It shows the terminology, code,
--         and the description of the code. The final column shows which iteration of the script
--         it was found in. The higher the iteration the less likely it is that the code is correct,
--         and therefore codes like these should be checked carefully.

--> CODESET alimemazine:1 alprazolam:1 alverine:1 atenolol:1 captopril:1 cimetidine:1 clorazepate:1 colchicine:1

--TODO doing stuff with CTV3 and "Term" codes - perhaps need to allow the CTV3 codes in 
--the code sets to have 10 characters - 5 is the equivalent of the root readv2 code
--while 10 is when you only want a specific synonym

-- Create a table to collate the final output
DROP TABLE IF EXISTS CodeCheckOutput;
CREATE TEMPORARY TABLE CodeCheckOutput (
	Concept varchar(255) NOT NULL,
  Terminology varchar(255) NOT NULL,
  Code varchar(20), 
  "Term" varchar(20), 
  Description varchar(255) NULL,
  Iteration INT,
	CodeFromWhichThisWasFound varchar(20),
	TerminologyOfCodeFromWhichThisWasFound varchar(20) 
);

-- If we find missing codes based on mappings between terminologies, then those new codes
-- may help us find more codes. Therefore we iterate until we find no more new codes.
-- However, we also stop if we get to 5 iterations as this is likely because a dodgy mapping
-- has caused us to get codes we don't need. If more than 5 iterations are actually required
-- then the code below can be tweaked.
DROP TABLE IF EXISTS TEMP_Concepts;
CREATE TEMPORARY TABLE TEMP_Concepts AS
select distinct Concept from AllCodes;


DECLARE
		counter INT;
    iteration INT; 
    newinsertions INT;
    concept VARCHAR(255);
BEGIN
	counter := (SELECT COUNT(*) FROM TEMP_Concepts);

	WHILE (counter > 0) DO
		concept := (SELECT TOP 1 Concept FROM TEMP_Concepts ORDER BY Concept ASC);
		iteration := 0;
		newinsertions := 1;
		WHILE ( newinsertions > 0 AND iteration < 5) DO
			-- Update so we know how many times round we've gone
				iteration := iteration + 1;
				newinsertions := 0;

			-- First we find all foreign keys based on existing codes

				-- Find all FKs for the EMIS codes
				DROP TABLE IF EXISTS FKsFromEMIS;
				CREATE TEMPORARY TABLE FKsFromEMIS AS
				SELECT "FK_Reference_Coding_ID" AS CodeId, "LocalCode" AS SourceCode, 'EMIS' AS SourceTerminology
				FROM INTERMEDIATE.GP_Record."Reference_Local_Code"
				WHERE "LocalCode" IN (SELECT code FROM codesemis WHERE Concept = :concept)
				AND "FK_Reference_Coding_ID"!=-1;

				-- Find all FKs for the SNOMED codes
				DROP TABLE IF EXISTS FKsFromSNOMED;
				CREATE TEMPORARY TABLE FKsFromSNOMED AS
				SELECT "PK_Reference_Coding_ID" AS CodeId, "SnomedCT_ConceptID" AS SourceCode, 'SNOMED' AS SourceTerminology
				FROM INTERMEDIATE.GP_Record."Reference_Coding"
				WHERE "SnomedCT_ConceptID" IN (SELECT code FROM codessnomed WHERE Concept = :concept)
				AND "PK_Reference_Coding_ID"!=-1;

				-- Find all FKs for the Readv2 codes
				DROP TABLE IF EXISTS FKsFromReadv2;
				CREATE TEMPORARY TABLE FKsFromReadv2 AS
				SELECT A."PK_Reference_Coding_ID" AS CodeId, CASE WHEN A."Term" IS NULL THEN A."MainCode" ELSE CONCAT(A."MainCode", A."Term") END AS SourceCode, 'Readv2' AS SourceTerminology
				FROM INTERMEDIATE.GP_Record."Reference_Coding" A
				INNER JOIN codesreadv2 B ON Code = "MainCode" AND ( term = A."Term" OR term IS NULL)  and Concept = :concept
				WHERE "CodingType"='ReadCodeV2'
				AND "PK_Reference_Coding_ID"!=-1;

				-- Find all FKs for the CTV3 codes
				DROP TABLE IF EXISTS FKsFromCTV3;
				CREATE TEMPORARY TABLE FKsFromCTV3 AS
				SELECT "PK_Reference_Coding_ID" AS CodeId, "MainCode" AS SourceCode, 'CTV3' AS SourceTerminology
				FROM INTERMEDIATE.GP_Record."Reference_Coding" A
				INNER JOIN codesctv3 B ON Code = "MainCode" AND ( term = A."Term" OR term IS NULL)  and Concept = :concept
				WHERE "CodingType"='CTV3'
				AND "PK_Reference_Coding_ID"!=-1;

				-- Bring together to get all FKs
				DROP TABLE IF EXISTS FKs;
				CREATE TEMPORARY TABLE FKs AS
				SELECT CodeId, SourceCode, SourceTerminology FROM FKsFromCTV3
				UNION
				SELECT CodeId, SourceCode, SourceTerminology FROM FKsFromEMIS
				UNION
				SELECT CodeId, SourceCode, SourceTerminology FROM FKsFromReadv2
				UNION
				SELECT CodeId, SourceCode, SourceTerminology FROM FKsFromSNOMED;

			-- Now do the same but this time to get the SNOMED foreign keys
				-- Find all SNOMED FKs for the EMIS codes
				DROP TABLE IF EXISTS SNOFKsFromEMIS;
				CREATE TEMPORARY TABLE SNOFKsFromEMIS AS
				SELECT "FK_Reference_SnomedCT_ID" AS SnomedId, "LocalCode" AS SourceCode, 'EMIS' AS SourceTerminology
				FROM INTERMEDIATE.GP_Record."Reference_Local_Code"
				WHERE "LocalCode" IN (SELECT code FROM codesemis WHERE Concept = :concept)
				AND "FK_Reference_SnomedCT_ID"!=-1;

				-- Find all SNOMED FKs for the SNOMED codes
				DROP TABLE IF EXISTS SNOFKsFromSNOMED;
				CREATE TEMPORARY TABLE SNOFKsFromSNOMED AS
				SELECT "PK_Reference_SnomedCT_ID" AS SnomedId, "ConceptID" AS SourceCode, 'SNOMED' AS SourceTerminology
				FROM INTERMEDIATE.GP_Record."Reference_SnomedCT"
				WHERE "ConceptID" IN (SELECT code FROM codessnomed WHERE Concept = :concept)
				AND "PK_Reference_SnomedCT_ID"!=-1;

				-- Find all SNOMED FKs for the Readv2 codes
				DROP TABLE IF EXISTS SNOFKsFromReadv2;
				CREATE TEMPORARY TABLE SNOFKsFromReadv2 AS
				SELECT "FK_Reference_SnomedCT_ID" AS SnomedId, CASE WHEN "Term" IS NULL THEN "MainCode" ELSE CONCAT("MainCode", "Term") END AS SourceCode, 'Readv2' AS SourceTerminology
				FROM INTERMEDIATE.GP_Record."Reference_Coding" A
				INNER JOIN codesreadv2 B ON Code = "MainCode" AND ( term = A."Term" OR term IS NULL)  and Concept = :concept
				WHERE "CodingType"='ReadCodeV2'
				AND "FK_Reference_SnomedCT_ID"!=-1;

				-- Find all SNOMED FKs for the CTV3 codes
				DROP TABLE IF EXISTS SNOFKsFromCTV3;
				CREATE TEMPORARY TABLE SNOFKsFromCTV3 AS
				SELECT "FK_Reference_SnomedCT_ID" AS SnomedId, "MainCode" AS SourceCode, 'CTV3' AS SourceTerminology
				FROM INTERMEDIATE.GP_Record."Reference_Coding" A
				INNER JOIN codesctv3 B ON Code = "MainCode" AND ( term = A."Term" OR term IS NULL)  and Concept = :concept
				WHERE "CodingType"='CTV3'
				AND "FK_Reference_SnomedCT_ID"!=-1;

				-- Bring together to get all SNOMED FKs
				DROP TABLE IF EXISTS SNOFKs;
				CREATE TEMPORARY TABLE SNOFKs AS
				SELECT SnomedId, SourceCode, SourceTerminology FROM SNOFKsFromCTV3
				UNION
				SELECT SnomedId, SourceCode, SourceTerminology FROM SNOFKsFromEMIS
				UNION
				SELECT SnomedId, SourceCode, SourceTerminology FROM SNOFKsFromReadv2
				UNION
				SELECT SnomedId, SourceCode, SourceTerminology FROM SNOFKsFromSNOMED;

			-- Now we find EMIS codes from the foreign keys that we don't already
			-- have in our code set
			DROP TABLE IF EXISTS NewEMIS;
			CREATE TEMPORARY TABLE NewEMIS AS
			SELECT "LocalCode" AS Code, "LocalCodeDescription" AS Description, SourceCode, SourceTerminology
			FROM INTERMEDIATE.GP_Record."Reference_Local_Code" rlc
			INNER JOIN FKs f ON f.CodeId = rlc."FK_Reference_Coding_ID"
			WHERE "LocalCode" NOT IN (SELECT Code FROM codesemis WHERE Concept = :concept)
			UNION
			SELECT "LocalCode", "LocalCodeDescription", SourceCode, SourceTerminology
			FROM INTERMEDIATE.GP_Record."Reference_Local_Code" rlc
			INNER JOIN SNOFKs f ON f.SnomedId = rlc."FK_Reference_SnomedCT_ID"
			WHERE "LocalCode" NOT IN (SELECT Code FROM codesemis WHERE Concept = :concept);

			newinsertions := newinsertions + (SELECT COUNT(*) FROM NewEMIS);

			-- If we found new ones we add them to the codesemis table so the 
			-- next pass can use them to potentially find new codes
			INSERT INTO codesemis
			SELECT :concept,1,Code,null,Description FROM NewEMIS;

			INSERT INTO CodeCheckOutput
			SELECT :concept,'EMIS',Code,null,Description,:iteration, SourceCode, SourceTerminology FROM NewEMIS;

			-- Now we find Readv2 codes from the foreign keys that we don't already
			-- have in our code set
			DROP TABLE IF EXISTS NewReadv2;
			CREATE TEMPORARY TABLE NewReadv2 AS
			SELECT
				CASE
					WHEN "Term" IS NULL THEN "MainCode"
					ELSE CONCAT("MainCode", "Term")
				END AS Code,
				"Term",
				CASE
					WHEN "FullDescription" IS NOT NULL THEN "FullDescription" 
					WHEN "Term198" IS NOT NULL THEN "Term198" 
					WHEN "Term60" IS NOT NULL THEN "Term60" 
					WHEN "Term30" IS NOT NULL THEN "Term30" 
				END AS Description, SourceCode, SourceTerminology
			FROM INTERMEDIATE.GP_Record."Reference_Coding" rlc
			INNER JOIN FKs f ON f.CodeId = rlc."PK_Reference_Coding_ID"
			WHERE "CodingType"='ReadCodeV2'
			AND "MainCode" NOT IN (SELECT Code FROM codesreadv2 WHERE Concept = :concept)
			UNION
			SELECT
				CASE
					WHEN "Term" IS NULL THEN "MainCode"
					ELSE CONCAT("MainCode", "Term")
				END AS Code,
				"Term",
				CASE
					WHEN "FullDescription" IS NOT NULL THEN "FullDescription" 
					WHEN "Term198" IS NOT NULL THEN "Term198" 
					WHEN "Term60" IS NOT NULL THEN "Term60" 
					WHEN "Term30" IS NOT NULL THEN "Term30" 
				END AS Description, SourceCode, SourceTerminology
			FROM INTERMEDIATE.GP_Record."Reference_Coding" rlc
			INNER JOIN SNOFKs f ON f.SnomedId = rlc."FK_Reference_SnomedCT_ID"
			WHERE "CodingType"='ReadCodeV2'
			AND "MainCode" NOT IN (SELECT Code FROM codesreadv2 WHERE Concept = :concept);

			newinsertions := newinsertions + (SELECT COUNT(*) FROM NewReadv2);

			-- If we found new ones we add them to the codesreadv2 table so the 
			-- next pass can use them to potentially find new codes
			INSERT INTO codesreadv2
			SELECT :concept,1,Code,null,Description FROM NewReadv2;

			INSERT INTO CodeCheckOutput
			SELECT :concept,'Readv2',Code,"Term",Description,:iteration, SourceCode, SourceTerminology FROM NewReadv2;

			-- Now we find CTV3 codes from the foreign keys that we don't already
			-- have in our code set
			DROP TABLE IF EXISTS NewCTV3;
			CREATE TEMPORARY TABLE NewCTV3 AS
			SELECT
				"MainCode" AS Code,
				"Term",
				CASE
					WHEN "FullDescription" IS NOT NULL AND "FullDescription"!='' THEN "FullDescription" 
					WHEN "Term198" IS NOT NULL AND "Term198"!='' THEN "Term198" 
					WHEN "Term60" IS NOT NULL AND "Term60"!='' THEN "Term60" 
					WHEN "Term30" IS NOT NULL AND "Term30"!='' THEN "Term30" 
				END AS Description, SourceCode, SourceTerminology
			FROM INTERMEDIATE.GP_Record."Reference_Coding" rlc
			INNER JOIN FKs f ON f.CodeId = rlc."PK_Reference_Coding_ID"
			WHERE "CodingType"='CTV3'
			AND "MainCode" NOT IN (SELECT Code FROM codesctv3 WHERE Concept = :concept)
			UNION
			SELECT
				"MainCode" AS Code,
				"Term",
				CASE
					WHEN "FullDescription" IS NOT NULL AND "FullDescription"!='' THEN "FullDescription" 
					WHEN "Term198" IS NOT NULL AND "Term198"!='' THEN "Term198" 
					WHEN "Term60" IS NOT NULL AND "Term60"!='' THEN "Term60" 
					WHEN "Term30" IS NOT NULL AND "Term30"!='' THEN "Term30" 
				END AS Description, SourceCode, SourceTerminology
			FROM INTERMEDIATE.GP_Record."Reference_Coding" rlc
			INNER JOIN SNOFKs f ON f.SnomedId = rlc."FK_Reference_SnomedCT_ID"
			WHERE "CodingType"='CTV3'
			AND "MainCode" NOT IN (SELECT Code FROM codesctv3 WHERE Concept = :concept);
			
			newinsertions := newinsertions + (SELECT COUNT(*) FROM NewReadv2);
			

			-- If we found new ones we add them to the codesctv3 table so the 
			-- next pass can use them to potentially find new codes
			INSERT INTO codesctv3
			SELECT :concept,1,Code,"Term",Description FROM NewCTV3;

			INSERT INTO CodeCheckOutput
			SELECT :concept,'CTV3',Code,"Term",Description,:iteration, SourceCode, SourceTerminology FROM NewCTV3;

			-- Now we find SNOMED codes from the foreign keys that we don't already
			-- have in our code set
			DROP TABLE IF EXISTS NewSNOMED;
			CREATE TEMPORARY TABLE NewSNOMED AS
			SELECT "ConceptID" AS Code, "Term" AS Description, SourceCode, SourceTerminology
			FROM INTERMEDIATE.GP_Record."Reference_SnomedCT" rlc
			INNER JOIN SNOFKs f ON f.SnomedId = rlc."PK_Reference_SnomedCT_ID"
			WHERE "ConceptID" NOT IN (SELECT Code FROM codessnomed WHERE Concept = :concept);

			newinsertions := newinsertions + (SELECT COUNT(*) FROM NewSNOMED);


			-- If we found new ones we add them to the codessnomed table so the 
			-- next pass can use them to potentially find new codes
			INSERT INTO codessnomed
			SELECT :concept,1,Code,null,Description FROM NewSNOMED;

			INSERT INTO CodeCheckOutput
			SELECT :concept, 'SNOMED',Code,null,Description,:iteration, SourceCode, SourceTerminology FROM NewSNOMED;
		END WHILE;

		-- If NewInsertions is not 0 then it means the iteration hasn't finished yet
		IF (newinsertions > 0) THEN
			SELECT CONCAT(:concept, ' had more than 5 iterations were performed. Please read the notes at the top of this file.');
		END IF;

		DELETE FROM TEMP_Concepts WHERE Concept = :concept;
		counter := (SELECT COUNT(*) FROM TEMP_Concepts);
	END WHILE;
END;

-- Final output
SELECT 
	Concept,
	Terminology, 
	Code,
	"Term",
	Description,
	Iteration,
	listagg(CONCAT(CodeFromWhichThisWasFound, '(',TerminologyOfCodeFromWhichThisWasFound,')'),', ') WITHIN GROUP (ORDER BY CodeFromWhichThisWasFound) AS FoundFrom
FROM CodeCheckOutput
GROUP BY Concept,Terminology, Code, "Term", Description, Iteration
ORDER BY Concept,Iteration, Terminology, Code, Description

