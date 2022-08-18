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

--> CODESET efi-activity-limitation:1 efi-anaemia:1 efi-arthritis:1 efi-atrial-fibrillation:1 efi-chd:1 efi-ckd:1
--> CODESET efi-diabetes:1 efi-dizziness:1 efi-dyspnoea:1 efi-falls:1 efi-foot-problems:1 efi-fragility-fracture:1
--> CODESET efi-hearing-loss:1 efi-heart-failure:1 efi-heart-valve-disease:1 efi-housebound:1 efi-hypertension:1
--> CODESET efi-hypotension:1 efi-cognitive-problems:1 efi-mobility-problems:1 efi-osteoporosis:1
--> CODESET efi-parkinsons:1 efi-peptic-ulcer:1 efi-pvd:1 efi-care-requirement:1 efi-respiratory-disease:1
--> CODESET efi-skin-ulcer:1 efi-sleep-disturbance:1 efi-social-vulnerability:1 efi-stroke-tia:1 efi-thyroid-disorders:1
--> CODESET efi-urinary-incontinence:1 efi-urinary-system-disease:1 efi-vision-problems:1 efi-weight-loss:1 

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
  [Iteration] INT
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
		SELECT FK_Reference_Coding_ID AS CodeId
		INTO #FKsFromEMIS
		FROM SharedCare.Reference_Local_Code
		WHERE LocalCode IN (SELECT [code] FROM #codesemis)
		AND FK_Reference_Coding_ID!=-1;

		-- Find all FKs for the SNOMED codes
		IF OBJECT_ID('tempdb..#FKsFromSNOMED') IS NOT NULL DROP TABLE #FKsFromSNOMED;
		SELECT PK_Reference_Coding_ID AS CodeId
		INTO #FKsFromSNOMED
		FROM SharedCare.Reference_Coding
		WHERE SnomedCT_ConceptID IN (SELECT [code] FROM #codessnomed)
		AND PK_Reference_Coding_ID!=-1;

		-- Find all FKs for the Readv2 codes
		IF OBJECT_ID('tempdb..#FKsFromReadv2') IS NOT NULL DROP TABLE #FKsFromReadv2;
		SELECT PK_Reference_Coding_ID AS CodeId
		INTO #FKsFromReadv2
		FROM SharedCare.Reference_Coding
		WHERE EXISTS (SELECT * FROM #codesreadv2 WHERE Code = MainCode AND (Term = SharedCare.Reference_Coding.Term OR Term IS NULL))
		AND CodingType='ReadCodeV2'
		AND PK_Reference_Coding_ID!=-1;

		-- Find all FKs for the CTV3 codes
		IF OBJECT_ID('tempdb..#FKsFromCTV3') IS NOT NULL DROP TABLE #FKsFromCTV3;
		SELECT PK_Reference_Coding_ID AS CodeId
		INTO #FKsFromCTV3
		FROM SharedCare.Reference_Coding
		WHERE EXISTS (SELECT * FROM #codesctv3 WHERE Code = MainCode AND (Term = SharedCare.Reference_Coding.Term OR Term IS NULL))
		AND CodingType='CTV3'
		AND PK_Reference_Coding_ID!=-1;

		-- Bring together to get all FKs
		IF OBJECT_ID('tempdb..#FKs') IS NOT NULL DROP TABLE #FKs;
		SELECT CodeId INTO #FKs FROM #FKsFromCTV3
		UNION
		SELECT CodeId FROM #FKsFromEMIS
		UNION
		SELECT CodeId FROM #FKsFromReadv2
		UNION
		SELECT CodeId FROM #FKsFromSNOMED;

	-- Now do the same but this time to get the SNOMED foreign keys
		-- Find all SNOMED FKs for the EMIS codes
		IF OBJECT_ID('tempdb..#SNOFKsFromEMIS') IS NOT NULL DROP TABLE #SNOFKsFromEMIS;
		SELECT FK_Reference_SnomedCT_ID AS SnomedId
		INTO #SNOFKsFromEMIS
		FROM SharedCare.Reference_Local_Code
		WHERE LocalCode IN (SELECT [code] FROM #codesemis)
		AND FK_Reference_SnomedCT_ID!=-1;

		-- Find all SNOMED FKs for the SNOMED codes
		IF OBJECT_ID('tempdb..#SNOFKsFromSNOMED') IS NOT NULL DROP TABLE #SNOFKsFromSNOMED;
		SELECT PK_Reference_SnomedCT_ID AS SnomedId
		INTO #SNOFKsFromSNOMED
		FROM SharedCare.Reference_SnomedCT
		WHERE ConceptID IN (SELECT [code] FROM #codessnomed)
		AND PK_Reference_SnomedCT_ID!=-1;

		-- Find all SNOMED FKs for the Readv2 codes
		IF OBJECT_ID('tempdb..#SNOFKsFromReadv2') IS NOT NULL DROP TABLE #SNOFKsFromReadv2;
		SELECT FK_Reference_SnomedCT_ID AS SnomedId
		INTO #SNOFKsFromReadv2
		FROM SharedCare.Reference_Coding
		WHERE EXISTS (SELECT * FROM #codesreadv2 WHERE Code = MainCode AND (Term = SharedCare.Reference_Coding.Term OR Term IS NULL))
		AND CodingType='ReadCodeV2'
		AND FK_Reference_SnomedCT_ID!=-1;

		-- Find all SNOMED FKs for the CTV3 codes
		IF OBJECT_ID('tempdb..#SNOFKsFromCTV3') IS NOT NULL DROP TABLE #SNOFKsFromCTV3;
		SELECT FK_Reference_SnomedCT_ID AS SnomedId
		INTO #SNOFKsFromCTV3
		FROM SharedCare.Reference_Coding
		WHERE EXISTS (SELECT * FROM #codesctv3 WHERE Code = MainCode AND (Term = SharedCare.Reference_Coding.Term OR Term IS NULL))
		AND CodingType='CTV3'
		AND FK_Reference_SnomedCT_ID!=-1;

		-- Bring together to get all SNOMED FKs
		IF OBJECT_ID('tempdb..#SNOFKs') IS NOT NULL DROP TABLE #SNOFKs;
		SELECT SnomedId INTO #SNOFKs FROM #SNOFKsFromCTV3
		UNION
		SELECT SnomedId FROM #SNOFKsFromEMIS
		UNION
		SELECT SnomedId FROM #SNOFKsFromReadv2
		UNION
		SELECT SnomedId FROM #SNOFKsFromSNOMED;

	-- Now we find EMIS codes from the foreign keys that we don't already
	-- have in our code set
	IF OBJECT_ID('tempdb..#NewEMIS') IS NOT NULL DROP TABLE #NewEMIS;
	SELECT LocalCode AS Code, LocalCodeDescription AS [Description] INTO #NewEMIS FROM SharedCare.Reference_Local_Code
	WHERE FK_Reference_Coding_ID IN (SELECT CodeId FROM #FKs)
	AND LocalCode NOT IN (SELECT Code FROM #codesemis)
	UNION
	SELECT LocalCode, LocalCodeDescription FROM SharedCare.Reference_Local_Code
	WHERE FK_Reference_SnomedCT_ID IN (SELECT SnomedId FROM #SNOFKs)
	AND LocalCode NOT IN (SELECT Code FROM #codesemis);
	SELECT @NewInsertions = @NewInsertions + @@ROWCOUNT;

	-- If we found new ones we add them to the #codesemis table so the 
	-- next pass can use them to potentially find new codes
	INSERT INTO #codesemis
	SELECT '',1,Code,null,[Description] FROM #NewEMIS;

	INSERT INTO #CodeCheckOutput
	SELECT 'EMIS',Code,null,[Description],@Iteration FROM #NewEMIS;

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
		END AS [Description] INTO #NewReadv2
	FROM SharedCare.Reference_Coding
	WHERE PK_Reference_Coding_ID IN (SELECT CodeId FROM #FKs)
	AND CodingType='ReadCodeV2'
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
		END AS [Description]
	FROM SharedCare.Reference_Coding
	WHERE FK_Reference_SnomedCT_ID IN (SELECT SnomedId FROM #SNOFKs)
	AND CodingType='ReadCodeV2'
	AND MainCode NOT IN (SELECT Code FROM #codesreadv2);
	SELECT @NewInsertions = @NewInsertions + @@ROWCOUNT;

	-- If we found new ones we add them to the #codesreadv2 table so the 
	-- next pass can use them to potentially find new codes
	INSERT INTO #codesreadv2
	SELECT '',1,Code,null,[Description] FROM #NewReadv2;

	INSERT INTO #CodeCheckOutput
	SELECT 'Readv2',Code,Term,[Description],@Iteration FROM #NewReadv2;

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
		END AS [Description] INTO #NewCTV3
	FROM SharedCare.Reference_Coding
	WHERE PK_Reference_Coding_ID IN (SELECT CodeId FROM #FKs)
	AND CodingType='CTV3'
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
		END AS [Description]
	FROM SharedCare.Reference_Coding
	WHERE FK_Reference_SnomedCT_ID IN (SELECT SnomedId FROM #SNOFKs)
	AND CodingType='CTV3'
	AND MainCode NOT IN (SELECT Code FROM #codesctv3);
	SELECT @NewInsertions = @NewInsertions + @@ROWCOUNT;

	-- If we found new ones we add them to the #codesctv3 table so the 
	-- next pass can use them to potentially find new codes
	INSERT INTO #codesctv3
	SELECT '',1,Code,Term,[Description] FROM #NewCTV3;

	INSERT INTO #CodeCheckOutput
	SELECT 'CTV3',Code,Term,[Description],@Iteration FROM #NewCTV3;

	-- Now we find SNOMED codes from the foreign keys that we don't already
	-- have in our code set
	IF OBJECT_ID('tempdb..#NewSNOMED') IS NOT NULL DROP TABLE #NewSNOMED;
	SELECT ConceptID AS Code, Term AS [Description] INTO #NewSNOMED FROM SharedCare.Reference_SnomedCT
	WHERE PK_Reference_SnomedCT_ID IN (SELECT SnomedId FROM #SNOFKs)
	AND ConceptID NOT IN (SELECT Code FROM #codessnomed);
	SELECT @NewInsertions = @NewInsertions + @@ROWCOUNT;


	-- If we found new ones we add them to the #codessnomed table so the 
	-- next pass can use them to potentially find new codes
	INSERT INTO #codessnomed
	SELECT '',1,Code,null,[Description] FROM #NewSNOMED;

	INSERT INTO #CodeCheckOutput
	SELECT 'SNOMED',Code,null,[Description],@Iteration FROM #NewSNOMED;
END

-- If NewInsertions is not 0 then it means the iteration hasn't finished yet
IF @NewInsertions > 0
SELECT 'More than 5 iterations were performed. Please read the notes at the top of this file.';

-- Final output
SELECT * FROM #CodeCheckOutput
ORDER BY Iteration, Terminology, Code, [Description]