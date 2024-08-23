--┌───────────────────────────────────────────────────────────────────────────────────────────────┐
--│ This file loads whichever code set is specified, and inserts into a permanent snowflake table │
--└───────────────────────────────────────────────────────────────────────────────────────────────┘

-- INPUT: Two parameters
--  - code-set: string - the name of the code set to be used. Must be one from the repository.
--  - version: number - the code set version

USE DATABASE INTERMEDIATE;
USE SCHEMA GP_RECORD;

--> CODESET {param:code-set}:{param:version}
/*
INSERT INTO SDE_REPOSITORY.SHARED_UTILITIES.versionedsnomedsets_permanent
SELECT src.*
FROM versionedsnomedsets AS src
WHERE NOT EXISTS (SELECT *
                  FROM  SDE_REPOSITORY.SHARED_UTILITIES.versionedsnomedsets_permanent AS tgt
                  WHERE tgt.FK_REFERENCE_SNOMEDCT_ID = src."FK_REFERENCE_SNOMEDCT_ID"
                  );

INSERT INTO SDE_REPOSITORY.SHARED_UTILITIES.versionedcodesets_permanent
SELECT src.*
FROM versionedcodesets AS src
WHERE NOT EXISTS (SELECT *
                  FROM  SDE_REPOSITORY.SHARED_UTILITIES.versionedcodesets_permanent AS tgt
                  WHERE tgt.FK_REFERENCE_CODING_ID = src."FK_REFERENCE_CODING_ID"
                  );
*/
INSERT INTO SDE_REPOSITORY.SHARED_UTILITIES.AllCodesPermanent
SELECT *
FROM AllCodes AS src
WHERE NOT EXISTS (SELECT *
                  FROM  SDE_REPOSITORY.SHARED_UTILITIES.AllCodesPermanent AS tgt
                  WHERE tgt.Code = src.Code 
				  AND tgt.concept = src.concept
                  );

---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
