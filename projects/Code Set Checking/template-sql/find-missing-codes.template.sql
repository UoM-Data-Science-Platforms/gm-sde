--┌─────────────────────────────────────────────────┐
--│ Finds missing codes using the existing mappings │
--└─────────────────────────────────────────────────┘

-- OBJECTIVE: To find clinical codes that may be missing from a codeset. It does this purely
--            based on the mappings between the terminologies held in the SharedCare schema
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

--Just want the output, not the messages
SET NOCOUNT ON;

--> CODESET insert-concept-here:1

--TODO doing stuff with CTV3 and Term codes - perhaps need to allow the CTV3 codes in 
--the code sets to have 10 characters - 5 is the equivalent of the root readv2 code
--while 10 is when you only want a specific synonym

-- Create a table to collate the final output
IF OBJECT_ID('tempdb..#CodeCheckOutput') IS NOT NULL DROP TABLE #CodeCheckOutput;
CREATE TABLE #CodeCheckOutput (
  [Terminology] [varchar](255) NOT NULL,
  [Code] [varchar](20) COLLATE Latin1_General_CS_AS NOT NULL,
  [Term] [varchar](20) COLLATE Latin1_General_CS_AS NULL,
  [Description] [varchar](255) NULL,
  [Iteration] INT,
	[CodeFromWhichThisWasFound] [varchar](20) COLLATE Latin1_General_CS_AS NULL,
	[TerminologyOfCodeFromWhichThisWasFound] [varchar](20) COLLATE Latin1_General_CS_AS NULL
)ON [PRIMARY];

-- If we find missing codes based on mappings between terminologies, then those new codes
-- may help us find more codes. Therefore we iterate until we find no more new codes.
-- However, we also stop if we get to 5 iterations as this is likely because a dodgy mapping
-- has caused us to get codes we don't need. If more than 5 iterations are actually required
-- then the code below can be tweaked.
DECLARE @Iteration INT; 
SET @Iteration=0;
DECLARE @NewInsertions INT; 
SET @NewInsertions=1;
WHILE ( @NewInsertions > 0 AND @Iteration < 5)
BEGIN  

	-- Update so we know how many times round we've gone
		SET @Iteration = @Iteration + 1;
		SET @NewInsertions=0;

	-- First we find all foreign keys based on existing codes

		-- Find all FKs for the EMIS codes
		IF OBJECT_ID('tempdb..#FKsFromEMIS') IS NOT NULL DROP TABLE #FKsFromEMIS;
		SELECT FK_Reference_Coding_ID AS CodeId, LocalCode AS SourceCode, 'EMIS' AS SourceTerminology
		INTO #FKsFromEMIS
		FROM SharedCare.Reference_Local_Code
		WHERE LocalCode IN (SELECT [code] FROM #codesemis)
		AND FK_Reference_Coding_ID!=-1;

		-- Find all FKs for the SNOMED codes
		IF OBJECT_ID('tempdb..#FKsFromSNOMED') IS NOT NULL DROP TABLE #FKsFromSNOMED;
		SELECT PK_Reference_Coding_ID AS CodeId, SnomedCT_ConceptID AS SourceCode, 'SNOMED' AS SourceTerminology
		INTO #FKsFromSNOMED
		FROM SharedCare.Reference_Coding
		WHERE SnomedCT_ConceptID IN (SELECT [code] FROM #codessnomed)
		AND PK_Reference_Coding_ID!=-1;

		-- Find all FKs for the Readv2 codes
		IF OBJECT_ID('tempdb..#FKsFromReadv2') IS NOT NULL DROP TABLE #FKsFromReadv2;
		SELECT PK_Reference_Coding_ID AS CodeId, CASE WHEN Term IS NULL THEN MainCode ELSE CONCAT(MainCode, Term) END AS SourceCode, 'Readv2' AS SourceTerminology
		INTO #FKsFromReadv2
		FROM SharedCare.Reference_Coding
		WHERE EXISTS (SELECT * FROM #codesreadv2 WHERE Code = MainCode AND (Term = SharedCare.Reference_Coding.Term OR Term IS NULL))
		AND CodingType='ReadCodeV2'
		AND PK_Reference_Coding_ID!=-1;

		-- Find all FKs for the CTV3 codes
		IF OBJECT_ID('tempdb..#FKsFromCTV3') IS NOT NULL DROP TABLE #FKsFromCTV3;
		SELECT PK_Reference_Coding_ID AS CodeId, MainCode AS SourceCode, 'CTV3' AS SourceTerminology
		INTO #FKsFromCTV3
		FROM SharedCare.Reference_Coding
		WHERE EXISTS (SELECT * FROM #codesctv3 WHERE Code = MainCode AND (Term = SharedCare.Reference_Coding.Term OR Term IS NULL))
		AND CodingType='CTV3'
		AND PK_Reference_Coding_ID!=-1;

		-- Bring together to get all FKs
		IF OBJECT_ID('tempdb..#FKs') IS NOT NULL DROP TABLE #FKs;
		SELECT CodeId, SourceCode, SourceTerminology INTO #FKs FROM #FKsFromCTV3
		UNION
		SELECT CodeId, SourceCode, SourceTerminology FROM #FKsFromEMIS
		UNION
		SELECT CodeId, SourceCode, SourceTerminology FROM #FKsFromReadv2
		UNION
		SELECT CodeId, SourceCode, SourceTerminology FROM #FKsFromSNOMED;

	-- Now do the same but this time to get the SNOMED foreign keys
		-- Find all SNOMED FKs for the EMIS codes
		IF OBJECT_ID('tempdb..#SNOFKsFromEMIS') IS NOT NULL DROP TABLE #SNOFKsFromEMIS;
		SELECT FK_Reference_SnomedCT_ID AS SnomedId, LocalCode AS SourceCode, 'EMIS' AS SourceTerminology
		INTO #SNOFKsFromEMIS
		FROM SharedCare.Reference_Local_Code
		WHERE LocalCode IN (SELECT [code] FROM #codesemis)
		AND FK_Reference_SnomedCT_ID!=-1;

		-- Find all SNOMED FKs for the SNOMED codes
		IF OBJECT_ID('tempdb..#SNOFKsFromSNOMED') IS NOT NULL DROP TABLE #SNOFKsFromSNOMED;
		SELECT PK_Reference_SnomedCT_ID AS SnomedId, ConceptID AS SourceCode, 'SNOMED' AS SourceTerminology
		INTO #SNOFKsFromSNOMED
		FROM SharedCare.Reference_SnomedCT
		WHERE ConceptID IN (SELECT [code] FROM #codessnomed)
		AND PK_Reference_SnomedCT_ID!=-1;

		-- Find all SNOMED FKs for the Readv2 codes
		IF OBJECT_ID('tempdb..#SNOFKsFromReadv2') IS NOT NULL DROP TABLE #SNOFKsFromReadv2;
		SELECT FK_Reference_SnomedCT_ID AS SnomedId, CASE WHEN Term IS NULL THEN MainCode ELSE CONCAT(MainCode, Term) END AS SourceCode, 'Readv2' AS SourceTerminology
		INTO #SNOFKsFromReadv2
		FROM SharedCare.Reference_Coding
		WHERE EXISTS (SELECT * FROM #codesreadv2 WHERE Code = MainCode AND (Term = SharedCare.Reference_Coding.Term OR Term IS NULL))
		AND CodingType='ReadCodeV2'
		AND FK_Reference_SnomedCT_ID!=-1;

		-- Find all SNOMED FKs for the CTV3 codes
		IF OBJECT_ID('tempdb..#SNOFKsFromCTV3') IS NOT NULL DROP TABLE #SNOFKsFromCTV3;
		SELECT FK_Reference_SnomedCT_ID AS SnomedId, MainCode AS SourceCode, 'CTV3' AS SourceTerminology
		INTO #SNOFKsFromCTV3
		FROM SharedCare.Reference_Coding
		WHERE EXISTS (SELECT * FROM #codesctv3 WHERE Code = MainCode AND (Term = SharedCare.Reference_Coding.Term OR Term IS NULL))
		AND CodingType='CTV3'
		AND FK_Reference_SnomedCT_ID!=-1;

		-- Bring together to get all SNOMED FKs
		IF OBJECT_ID('tempdb..#SNOFKs') IS NOT NULL DROP TABLE #SNOFKs;
		SELECT SnomedId, SourceCode, SourceTerminology INTO #SNOFKs FROM #SNOFKsFromCTV3
		UNION
		SELECT SnomedId, SourceCode, SourceTerminology FROM #SNOFKsFromEMIS
		UNION
		SELECT SnomedId, SourceCode, SourceTerminology FROM #SNOFKsFromReadv2
		UNION
		SELECT SnomedId, SourceCode, SourceTerminology FROM #SNOFKsFromSNOMED;

	-- Now we find EMIS codes from the foreign keys that we don't already
	-- have in our code set
	IF OBJECT_ID('tempdb..#NewEMIS') IS NOT NULL DROP TABLE #NewEMIS;
	SELECT LocalCode AS Code, LocalCodeDescription AS [Description], SourceCode, SourceTerminology
	INTO #NewEMIS FROM SharedCare.Reference_Local_Code rlc
	INNER JOIN #FKs f ON f.CodeId = rlc.FK_Reference_Coding_ID
	WHERE LocalCode NOT IN (SELECT Code FROM #codesemis)
	UNION
	SELECT LocalCode, LocalCodeDescription, SourceCode, SourceTerminology FROM SharedCare.Reference_Local_Code rlc
	INNER JOIN #SNOFKs f ON f.SnomedId = rlc.FK_Reference_SnomedCT_ID
	WHERE LocalCode NOT IN (SELECT Code FROM #codesemis);
	SELECT @NewInsertions = @NewInsertions + @@ROWCOUNT;

	-- If we found new ones we add them to the #codesemis table so the 
	-- next pass can use them to potentially find new codes
	INSERT INTO #codesemis
	SELECT '',1,Code,null,[Description] FROM #NewEMIS;

	INSERT INTO #CodeCheckOutput
	SELECT 'EMIS',Code,null,[Description],@Iteration, SourceCode, SourceTerminology FROM #NewEMIS;

	-- Now we find Readv2 codes from the foreign keys that we don't already
	-- have in our code set
	IF OBJECT_ID('tempdb..#NewReadv2') IS NOT NULL DROP TABLE #NewReadv2;
	SELECT
		CASE
			WHEN Term IS NULL THEN MainCode
			ELSE CONCAT(MainCode, Term)
		END AS Code,
		Term,
		CASE
			WHEN FullDescription IS NOT NULL THEN FullDescription COLLATE Latin1_General_CS_AS
			WHEN Term198 IS NOT NULL THEN Term198 COLLATE Latin1_General_CS_AS
			WHEN Term60 IS NOT NULL THEN Term60 COLLATE Latin1_General_CS_AS
			WHEN Term30 IS NOT NULL THEN Term30 COLLATE Latin1_General_CS_AS
		END AS [Description], SourceCode, SourceTerminology INTO #NewReadv2
	FROM SharedCare.Reference_Coding rlc
	INNER JOIN #FKs f ON f.CodeId = rlc.PK_Reference_Coding_ID
	WHERE CodingType='ReadCodeV2'
	AND MainCode NOT IN (SELECT Code FROM #codesreadv2)
	UNION
	SELECT
		CASE
			WHEN Term IS NULL THEN MainCode
			ELSE CONCAT(MainCode, Term)
		END AS Code,
		Term,
		CASE
			WHEN FullDescription IS NOT NULL THEN FullDescription COLLATE Latin1_General_CS_AS
			WHEN Term198 IS NOT NULL THEN Term198 COLLATE Latin1_General_CS_AS
			WHEN Term60 IS NOT NULL THEN Term60 COLLATE Latin1_General_CS_AS
			WHEN Term30 IS NOT NULL THEN Term30 COLLATE Latin1_General_CS_AS
		END AS [Description], SourceCode, SourceTerminology
	FROM SharedCare.Reference_Coding rlc
	INNER JOIN #SNOFKs f ON f.SnomedId = rlc.FK_Reference_SnomedCT_ID
	WHERE CodingType='ReadCodeV2'
	AND MainCode NOT IN (SELECT Code FROM #codesreadv2);
	SELECT @NewInsertions = @NewInsertions + @@ROWCOUNT;

	-- If we found new ones we add them to the #codesreadv2 table so the 
	-- next pass can use them to potentially find new codes
	INSERT INTO #codesreadv2
	SELECT '',1,Code,null,[Description] FROM #NewReadv2;

	INSERT INTO #CodeCheckOutput
	SELECT 'Readv2',Code,Term,[Description],@Iteration, SourceCode, SourceTerminology FROM #NewReadv2;

	-- Now we find CTV3 codes from the foreign keys that we don't already
	-- have in our code set
	IF OBJECT_ID('tempdb..#NewCTV3') IS NOT NULL DROP TABLE #NewCTV3;
	SELECT
		MainCode AS Code,
		Term,
		CASE
			WHEN FullDescription IS NOT NULL AND FullDescription!='' THEN FullDescription COLLATE Latin1_General_CS_AS
			WHEN Term198 IS NOT NULL AND Term198!='' THEN Term198 COLLATE Latin1_General_CS_AS
			WHEN Term60 IS NOT NULL AND Term60!='' THEN Term60 COLLATE Latin1_General_CS_AS
			WHEN Term30 IS NOT NULL AND Term30!='' THEN Term30 COLLATE Latin1_General_CS_AS
		END AS [Description], SourceCode, SourceTerminology INTO #NewCTV3
	FROM SharedCare.Reference_Coding rlc
	INNER JOIN #FKs f ON f.CodeId = rlc.PK_Reference_Coding_ID
	WHERE CodingType='CTV3'
	AND MainCode NOT IN (SELECT Code FROM #codesctv3)
	UNION
	SELECT
		MainCode AS Code,
		Term,
		CASE
			WHEN FullDescription IS NOT NULL AND FullDescription!='' THEN FullDescription COLLATE Latin1_General_CS_AS
			WHEN Term198 IS NOT NULL AND Term198!='' THEN Term198 COLLATE Latin1_General_CS_AS
			WHEN Term60 IS NOT NULL AND Term60!='' THEN Term60 COLLATE Latin1_General_CS_AS
			WHEN Term30 IS NOT NULL AND Term30!='' THEN Term30 COLLATE Latin1_General_CS_AS
		END AS [Description], SourceCode, SourceTerminology
	FROM SharedCare.Reference_Coding rlc
	INNER JOIN #SNOFKs f ON f.SnomedId = rlc.FK_Reference_SnomedCT_ID
	WHERE CodingType='CTV3'
	AND MainCode NOT IN (SELECT Code FROM #codesctv3);
	SELECT @NewInsertions = @NewInsertions + @@ROWCOUNT;

	-- If we found new ones we add them to the #codesctv3 table so the 
	-- next pass can use them to potentially find new codes
	INSERT INTO #codesctv3
	SELECT '',1,Code,Term,[Description] FROM #NewCTV3;

	INSERT INTO #CodeCheckOutput
	SELECT 'CTV3',Code,Term,[Description],@Iteration, SourceCode, SourceTerminology FROM #NewCTV3;

	-- Now we find SNOMED codes from the foreign keys that we don't already
	-- have in our code set
	IF OBJECT_ID('tempdb..#NewSNOMED') IS NOT NULL DROP TABLE #NewSNOMED;
	SELECT ConceptID AS Code, Term AS [Description], SourceCode, SourceTerminology
	INTO #NewSNOMED FROM SharedCare.Reference_SnomedCT rlc
	INNER JOIN #SNOFKs f ON f.SnomedId = rlc.PK_Reference_SnomedCT_ID
	WHERE ConceptID NOT IN (SELECT Code FROM #codessnomed);
	SELECT @NewInsertions = @NewInsertions + @@ROWCOUNT;


	-- If we found new ones we add them to the #codessnomed table so the 
	-- next pass can use them to potentially find new codes
	INSERT INTO #codessnomed
	SELECT '',1,Code,null,[Description] FROM #NewSNOMED;

	INSERT INTO #CodeCheckOutput
	SELECT 'SNOMED',Code,null,[Description],@Iteration, SourceCode, SourceTerminology FROM #NewSNOMED;
END

-- If NewInsertions is not 0 then it means the iteration hasn't finished yet
IF @NewInsertions > 0
SELECT 'More than 5 iterations were performed. Please read the notes at the top of this file.';

-- Final output
SELECT 
	Terminology, 
	Code,
	Term,
	[Description],
	Iteration,
	STRING_AGG(CONCAT(CodeFromWhichThisWasFound, '(',TerminologyOfCodeFromWhichThisWasFound,')'),', ') WITHIN GROUP (ORDER BY CodeFromWhichThisWasFound) AS FoundFrom
FROM #CodeCheckOutput
GROUP BY Terminology, Code, Term, Description, Iteration
ORDER BY Iteration, Terminology, Code, [Description]