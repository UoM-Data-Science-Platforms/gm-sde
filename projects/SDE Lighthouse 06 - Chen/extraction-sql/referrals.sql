--┌────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 06 - Chen - referrals         │
--└────────────────────────────────────────────────────┘

--┌───────────────────────────────────────────────────────────────────────────┐
--│ Define Cohort for LH006: patients that had multiple opioid prescriptions  │
--└───────────────────────────────────────────────────────────────────────────┘

-- OBJECTIVE: To build the cohort of patients needed for LH006. This reduces duplication of code in the template scripts.

-- COHORT: Any adult patient with non-chronic cancer pain, who received more than two oral or transdermal opioid prescriptions
--          for 14 days within 90 days, between 2017 and 2023.
--          Excluding patients with a cancer diagnosis within 12 months from index date

-- INPUT: none
-- OUTPUT: Temp tables as follows:
-- Cohort

USE DATABASE INTERMEDIATE;
USE SCHEMA GP_RECORD;

set(StudyStartDate) = to_date('2017-01-01');
set(StudyEndDate)   = to_date('2023-12-31');

--ALL DEATHS 

DROP TABLE IF EXISTS Death;
CREATE TEMPORARY TABLE Death AS
SELECT 
    DEATH."GmPseudo",
    TO_DATE(DEATH."RegisteredDateOfDeath") AS DeathDate
FROM PRESENTATION.NATIONAL_FLOWS_PCMD."DS1804_Pcmd" DEATH;

-- GET LATEST SNAPSHOT OF DEMOGRAPHICS TABLE

DROP TABLE IF EXISTS LatestSnapshotAdults;
CREATE TEMPORARY TABLE LatestSnapshotAdults AS
SELECT 
    p.*
FROM INTERMEDIATE.GP_RECORD."DemographicsProtectedCharacteristics" p 
INNER JOIN (
    SELECT "GmPseudo", MAX("Snapshot") AS LatestSnapshot
    FROM INTERMEDIATE.GP_RECORD."DemographicsProtectedCharacteristics" p 
    WHERE DATEDIFF(YEAR, TO_DATE("DateOfBirth"), $StudyStartDate) >= 18 -- adults only
    GROUP BY "GmPseudo"
    ) t2
ON t2."GmPseudo" = p."GmPseudo" AND t2.LatestSnapshot = p."Snapshot";

-- FIND ALL ADULT PATIENTS ALIVE AT STUDY START DATE

DROP TABLE IF EXISTS AlivePatientsAtStart;
CREATE TEMPORARY TABLE AlivePatientsAtStart AS 
SELECT  
    dem.*, 
    Death.DeathDate
FROM LatestSnapshotAdults dem
LEFT JOIN Death ON Death."GmPseudo" = dem."GmPseudo"
WHERE 
    (DeathDate IS NULL OR DeathDate > $StudyStartDate); -- alive on study start date

-- LOAD CODESETS

DROP TABLE IF EXISTS chronic_pain;
CREATE TEMPORARY TABLE chronic_pain AS
SELECT "FK_Patient_ID", to_date("EventDate") AS "EventDate"
FROM  INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" e
WHERE ( 
  "FK_Reference_Coding_ID" IN (SELECT FK_Reference_Coding_ID FROM SDE_REPOSITORY.SHARED_UTILITIES.VERSIONEDCODESETS_PERMANENT WHERE Concept = 'chronic-pain' AND Version = 1) 
    OR
  "FK_Reference_SnomedCT_ID" IN (SELECT FK_Reference_SnomedCT_ID FROM SDE_REPOSITORY.SHARED_UTILITIES.VERSIONEDSNOMEDSETS_PERMANENT WHERE Concept = 'chronic-pain' AND Version = 1)
      )
AND "EventDate" BETWEEN $StudyStartDate and $StudyEndDate; 

-- find first chronic pain code in the study period 
DROP TABLE IF EXISTS FirstPain;
CREATE TEMPORARY TABLE FirstPain AS
SELECT 
	"FK_Patient_ID", 
	MIN(TO_DATE("EventDate")) AS FirstPainCodeDate
FROM chronic_pain
GROUP BY "FK_Patient_ID";

-- find patients with a cancer code within 12 months either side of first chronic pain code
-- to exclude in next step

DROP TABLE IF EXISTS cancer;
CREATE TEMPORARY TABLE cancer AS
SELECT e."FK_Patient_ID", to_date("EventDate") AS "EventDate"
FROM  INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" e
INNER JOIN FirstPain fp ON fp."FK_Patient_ID" = e."FK_Patient_ID" 
				AND e."EventDate" BETWEEN DATEADD(year, 1, FirstPainCodeDate) AND DATEADD(year, -1, FirstPainCodeDate)
WHERE ( 
  "FK_Reference_Coding_ID" IN (SELECT FK_Reference_Coding_ID FROM SDE_REPOSITORY.SHARED_UTILITIES.VERSIONEDCODESETS_PERMANENT WHERE Concept = 'cancer' AND Version = 1) 
    OR
  "FK_Reference_SnomedCT_ID" IN (SELECT FK_Reference_SnomedCT_ID FROM SDE_REPOSITORY.SHARED_UTILITIES.VERSIONEDSNOMEDSETS_PERMANENT WHERE Concept = 'cancer' AND Version = 1)
      )
AND e."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM chronic_pain); --only look in patients with chronic pain

-- find patients in the chronic pain cohort who received more than 2 opioids
-- for 14 days, within a 90 day period, after their first chronic pain code
-- excluding those with cancer code close to first pain code 

-- first get all opioid prescriptions for the cohort

DROP TABLE IF EXISTS OpioidPrescriptions;
CREATE TEMPORARY TABLE OpioidPrescriptions AS
SELECT 
    ec."FK_Patient_ID"
    , TO_DATE(ec."MedicationDate") AS "MedicationDate"
    , ec."SCTID" AS "SnomedCode"
    , ec."Units"
    , ec."Dosage"
    , ec."Dosage_GP_Medications"
    , ec."MedicationDescription" AS "Description"
	, fp.FirstPainCodeDate
	, TO_DATE(Lag(ec."MedicationDate", 1) OVER 
		(PARTITION BY ec."FK_Patient_ID" ORDER BY "MedicationDate" ASC)) AS "PreviousOpioidDate"
FROM INTERMEDIATE.GP_RECORD."MedicationsClusters" ec
INNER JOIN FirstPain fp ON fp."FK_Patient_ID" = ec."FK_Patient_ID" 
WHERE 
	"Cluster_ID" in ('OPIOIDDRUG_COD') 									-- opioids only
	AND TO_DATE(ec."MedicationDate") > fp.FirstPainCodeDate				-- only prescriptions after the patients first pain code
	AND ec."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM chronic_pain) -- chronic pain patients only 
	AND ec."FK_Patient_ID" NOT IN (SELECT "FK_Patient_ID" FROM cancer)  -- exclude cancer patients
	AND TO_DATE(ec."MedicationDate") BETWEEN $StudyStartDate and $StudyEndDate;    -- only looking at opioid prescriptions in the study period;

-- find all patients that have had two prescriptions within 90 days, and calculate the index date as
-- the first prescription that meets the criteria

DROP TABLE IF EXISTS IndexDates;
CREATE TEMPORARY TABLE IndexDates AS
SELECT "FK_Patient_ID", 
	MIN(TO_DATE("PreviousOpioidDate")) AS IndexDate 
FROM OpioidPrescriptions
WHERE DATEDIFF(dd, "PreviousOpioidDate", "MedicationDate") <= 90
GROUP BY "FK_Patient_ID";

-- create cohort of patients, join to demographics table to get GmPseudo

DROP TABLE IF EXISTS Cohort;
CREATE TEMPORARY TABLE Cohort AS
SELECT DISTINCT
	 i."FK_Patient_ID",
     dem."GmPseudo",
	 i.IndexDate
FROM IndexDates i
LEFT JOIN 
    (SELECT DISTINCT "FK_Patient_ID", "GmPseudo"
     FROM PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses"
    ) dem ON dem."FK_Patient_ID" = i."FK_Patient_ID";



-- >>> Codesets required... Inserting the code set code
--
--┌────────────────────┐
--│ Clinical code sets │
--└────────────────────┘

-- OBJECTIVE: To populate temporary tables with the existing clinical code sets.
--            See the [SQL-generation-process.md](SQL-generation-process.md) for more details.

-- INPUT: No pre-requisites

-- OUTPUT: Five temp tables as follows:
--  AllCodes (Concept, Version, Code)
--  CodeSets (FK_Reference_Coding_ID, Concept)
--  SnomedSets (FK_Reference_SnomedCT_ID, FK_SNOMED_ID)
--  VersionedCodeSets (FK_Reference_Coding_ID, Concept, Version)
--  VersionedSnomedSets (FK_Reference_SnomedCT_ID, Version, FK_SNOMED_ID)

--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
--!!! DO NOT EDIT THIS FILE MANUALLY !!!
--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

--#region Clinical code sets

DROP TABLE IF EXISTS AllCodes;
CREATE TEMPORARY TABLE AllCodes (
  Concept varchar(255) NOT NULL,
  Version INT NOT NULL,
  Code varchar(20) NOT NULL,
  description varchar (255) NULL 
);

DROP TABLE IF EXISTS codesreadv2;
CREATE TEMPORARY TABLE codesreadv2 (
  concept varchar(255) NOT NULL,
  version INT NOT NULL,
	code varchar(20) NOT NULL,
	term varchar(20) NULL,
	description varchar(255) NULL
);

INSERT INTO codesreadv2
VALUES('social-care-prescribing-referral',1,'8H7s.',NULL,'Referral to physical activity programme'),('social-care-prescribing-referral',1,'8H7s.00',NULL,'Referral to physical activity programme'),('social-care-prescribing-referral',1,'8HHH0',NULL,'Referral to local authority weight management programme'),('social-care-prescribing-referral',1,'8HHH000',NULL,'Referral to local authority weight management programme'),('social-care-prescribing-referral',1,'8HHH1',NULL,'Referral to residential weight management programme'),('social-care-prescribing-referral',1,'8HHH100',NULL,'Referral to residential weight management programme'),('social-care-prescribing-referral',1,'8T09.',NULL,'Referral to social prescribing service'),('social-care-prescribing-referral',1,'8T09.00',NULL,'Referral to social prescribing service');
INSERT INTO codesreadv2
VALUES('surgery-referral',1,'8H4l.',NULL,'Referral to general surgery special interest general practitioner'),('surgery-referral',1,'8H4l.00',NULL,'Referral to general surgery special interest general practitioner'),('surgery-referral',1,'8H4m.',NULL,'Referral to minor surgery special interest general practitioner'),('surgery-referral',1,'8H4m.00',NULL,'Referral to minor surgery special interest general practitioner'),('surgery-referral',1,'8H5A.',NULL,'Referred for oral surgery'),('surgery-referral',1,'8H5A.00',NULL,'Referred for oral surgery'),('surgery-referral',1,'8HHS.',NULL,'Referral for minor surgery'),('surgery-referral',1,'8HHS.00',NULL,'Referral for minor surgery'),('surgery-referral',1,'8HJI.',NULL,'Plastic surgery self-referral'),('surgery-referral',1,'8HJI.00',NULL,'Plastic surgery self-referral'),('surgery-referral',1,'8HkM.',NULL,'Referral to hepatobiliary and pancreatic surgery service'),('surgery-referral',1,'8HkM.00',NULL,'Referral to hepatobiliary and pancreatic surgery service'),('surgery-referral',1,'8HlJ2',NULL,'Internal practice referral for minor surgery'),('surgery-referral',1,'8HlJ200',NULL,'Internal practice referral for minor surgery'),('surgery-referral',1,'8Hlv.',NULL,'Referral for pre-bariatric surgery assessment'),('surgery-referral',1,'8Hlv.00',NULL,'Referral for pre-bariatric surgery assessment'),('surgery-referral',1,'8Hm2.',NULL,'Referral to minor surgery clinical assessment service'),('surgery-referral',1,'8Hm2.00',NULL,'Referral to minor surgery clinical assessment service'),('surgery-referral',1,'8Ho0.',NULL,'Referral to dental surgery service'),('surgery-referral',1,'8Ho0.00',NULL,'Referral to dental surgery service'),('surgery-referral',1,'8Ho4.',NULL,'Referral to oral surgery service'),('surgery-referral',1,'8Ho4.00',NULL,'Referral to oral surgery service'),('surgery-referral',1,'8T01.',NULL,'Referral to podiatric surgery service'),('surgery-referral',1,'8T01.00',NULL,'Referral to podiatric surgery service'),('surgery-referral',1,'8T0V.',NULL,'Referral to hand surgery service'),('surgery-referral',1,'8T0V.00',NULL,'Referral to hand surgery service');
  
INSERT INTO AllCodes
SELECT concept, version, code, description from codesreadv2;

DROP TABLE IF EXISTS codesctv3;
CREATE TEMPORARY TABLE codesctv3 (
  concept varchar(255) NOT NULL,
  version INT NOT NULL,
	code varchar(20) NOT NULL,
	term varchar(20) NULL,
	description varchar(255) NULL
);

INSERT INTO codesctv3
VALUES('social-care-prescribing-referral',1,'XaaEC',NULL,'Referral to social prescribing service'),('social-care-prescribing-referral',1,'XaIQY',NULL,'Referral to physical activity programme'),('social-care-prescribing-referral',1,'XaXZ9',NULL,'Referral to local authority weight management programme'),('social-care-prescribing-referral',1,'XaZKe',NULL,'Referral to residential weight management programme');
INSERT INTO codesctv3
VALUES('surgery-referral',1,'8H5A.',NULL,'Referral to oral surgeon (& referred for oral surgery)'),('surgery-referral',1,'8H5A.',NULL,'Referred for oral surgery'),('surgery-referral',1,'8HJI.',NULL,'Plastic surgery self-referral'),('surgery-referral',1,'XaAdt',NULL,'Referral to breast surgery service'),('surgery-referral',1,'XaAdu',NULL,'Referral to cardiothoracic surgery service'),('surgery-referral',1,'XaAdv',NULL,'Referral to thoracic surgery service'),('surgery-referral',1,'XaAdw',NULL,'Referral to cardiac surgery service'),('surgery-referral',1,'XaAdx',NULL,'Referral to dental surgery service'),('surgery-referral',1,'XaAe2',NULL,'Referral to endocrine surgery service'),('surgery-referral',1,'XaAe3',NULL,'Referral to gastrointestinal surgery service'),('surgery-referral',1,'XaAe3',NULL,'Referral to GI surgery service'),('surgery-referral',1,'XaAe4',NULL,'Referral to general gastrointestinal surgery service'),('surgery-referral',1,'XaAe4',NULL,'Referral to general GI surgery service'),('surgery-referral',1,'XaAe5',NULL,'Referral to upper gastrointestinal surgery service'),('surgery-referral',1,'XaAe5',NULL,'Referral to upper GI surgery service'),('surgery-referral',1,'XaAe6',NULL,'Referral to colorectal surgery service'),('surgery-referral',1,'XaAeB',NULL,'Referral to maxillofacial surgery service'),('surgery-referral',1,'XaAeB',NULL,'Referral to oral surgery service'),('surgery-referral',1,'XaAeD',NULL,'Referral to pancreatic surgery service'),('surgery-referral',1,'XaAeF',NULL,'Referral to plastic surgery service'),('surgery-referral',1,'XaAeH',NULL,'Referral to trauma surgery service'),('surgery-referral',1,'XaAes',NULL,'Referral for general surgery domiciliary visit'),('surgery-referral',1,'XaAes',NULL,'Referral for general surgery DV'),('surgery-referral',1,'XaAqj',NULL,'Referral to general dental surgery service'),('surgery-referral',1,'XaAvO',NULL,'Referral to hand surgery service'),('surgery-referral',1,'XaAvT',NULL,'Referral to vascular surgery service'),('surgery-referral',1,'Xab8R',NULL,'Referral for pre-bariatric surgery assessment'),('surgery-referral',1,'XaJub',NULL,'Referral for minor surgery'),('surgery-referral',1,'XaPyv',NULL,'Referral to hepatobiliary and pancreatic surgery service'),('surgery-referral',1,'XaQfL',NULL,'Referral to minor surgery special interest general practitioner'),('surgery-referral',1,'XaQVx',NULL,'Referral to minor surgery clinical assessment service'),('surgery-referral',1,'XaQW0',NULL,'Referral to general surgery special interest general practitioner'),('surgery-referral',1,'XaQyP',NULL,'Internal practice referral for minor surgery'),('surgery-referral',1,'XaZgz',NULL,'Referral to podiatric surgery service'),('surgery-referral',1,'XaPfQ',NULL,'Referral to oral surgeon');
  
INSERT INTO AllCodes
SELECT concept, version, code, description from codesctv3;

DROP TABLE IF EXISTS codessnomed;
CREATE TEMPORARY TABLE codessnomed (
  concept varchar(255) NOT NULL,
  version INT NOT NULL,
	code varchar(20) NOT NULL,
	term varchar(20) NULL,
	description varchar(255) NULL
);

INSERT INTO codessnomed
VALUES('social-care-prescribing-referral',1,'390893007',NULL,'Referral to physical activity program (procedure)'),('social-care-prescribing-referral',1,'871731000000106',NULL,'Referral to social prescribing service'),('social-care-prescribing-referral',1,'837111000000105',NULL,'Referral to residential weight management programme'),('social-care-prescribing-referral',1,'771491000000104',NULL,'Referral to local authority weight management programme');
INSERT INTO codessnomed
VALUES('surgery-referral',1,'183551001',NULL,'Referral to oral surgeon (& referred for oral surgery)'),('surgery-referral',1,'183706004',NULL,'Plastic surgery self-referral (procedure)'),('surgery-referral',1,'306181005',NULL,'Referral to breast surgery service (procedure)'),('surgery-referral',1,'306182003',NULL,'Referral to cardiothoracic surgery service (procedure)'),('surgery-referral',1,'306184002',NULL,'Referral to thoracic surgery service (procedure)'),('surgery-referral',1,'306185001',NULL,'Referral to cardiac surgery service (procedure)'),('surgery-referral',1,'306186000',NULL,'Referral to dental surgery service (procedure)'),('surgery-referral',1,'306190003',NULL,'Referral to endocrine surgery service (procedure)'),('surgery-referral',1,'306191004',NULL,'Referral to gastrointestinal surgery service (procedure)'),('surgery-referral',1,'306192006',NULL,'Referral to general gastrointestinal surgery service (procedure)'),('surgery-referral',1,'306193001',NULL,'Referral to upper gastrointestinal surgery service (procedure)'),('surgery-referral',1,'306194007',NULL,'Referral to colorectal surgery service (procedure)'),('surgery-referral',1,'306197000',NULL,'Referral to pancreatic surgery service (procedure)'),('surgery-referral',1,'306198005',NULL,'Referral to plastic surgery service (procedure)'),('surgery-referral',1,'306200004',NULL,'Referral to trauma surgery service (procedure)'),('surgery-referral',1,'306232004',NULL,'Referral for general surgery domiciliary visit (procedure)'),('surgery-referral',1,'306735003',NULL,'Referral to general dental surgery service (procedure)'),('surgery-referral',1,'306929006',NULL,'Referral to hand surgery service (procedure)'),('surgery-referral',1,'306934005',NULL,'Referral to vascular surgery service (procedure)'),('surgery-referral',1,'383081000000104',NULL,'Referral to hepatobiliary and pancreatic surgery service (procedure)'),('surgery-referral',1,'384712002',NULL,'Referral to oral surgery service (procedure)'),('surgery-referral',1,'406158007',NULL,'Referral to oral surgeon (procedure)'),('surgery-referral',1,'415260000',NULL,'Referral for minor surgery (procedure)'),('surgery-referral',1,'507181000000108',NULL,'Referral to minor surgery clinical assessment service (procedure)'),('surgery-referral',1,'507251000000108',NULL,'Referral to general surgery special interest general practitioner (procedure)'),('surgery-referral',1,'511031000000103',NULL,'Referral to minor surgery special interest general practitioner (procedure)'),('surgery-referral',1,'516771000000105',NULL,'Internal practice referral for minor surgery (procedure)'),('surgery-referral',1,'850181000000103',NULL,'Referral to podiatric surgery service (procedure)'),('surgery-referral',1,'885251000000103',NULL,'Private referral to pain management service (procedure)'),('surgery-referral',1,'907731000000102',NULL,'Referral for pre-bariatric surgery assessment (procedure)');
  
INSERT INTO AllCodes
SELECT concept, version, code, description from codessnomed;

DROP TABLE IF EXISTS codesemis;
CREATE TEMPORARY TABLE codesemis (
  concept varchar(255) NOT NULL,
  version INT NOT NULL,
	code varchar(20) NOT NULL,
	term varchar(20) NULL,
	description varchar(255) NULL
);

INSERT INTO codesemis
VALUES('social-care-prescribing-referral',1,'^ESCTRE651604',NULL,'Referral to physical activity program'),('social-care-prescribing-referral',1,'EMISNQRE582',NULL,'Referral to social prescribing service from other agency');
INSERT INTO codesemis
VALUES('surgery-referral',1,'^ESCTRE595266',NULL,'Referral to breast surgery service'),('surgery-referral',1,'^ESCTRE595267',NULL,'Referral to cardiothoracic surgery service'),('surgery-referral',1,'^ESCTRE595269',NULL,'Referral to thoracic surgery service'),('surgery-referral',1,'^ESCTRE595270',NULL,'Referral to cardiac surgery service'),('surgery-referral',1,'^ESCTRE595276',NULL,'Referral to endocrine surgery service'),('surgery-referral',1,'^ESCTRE595277',NULL,'Referral to gastrointestinal surgery service'),('surgery-referral',1,'^ESCTRE595278',NULL,'Referral to GI surgery service'),('surgery-referral',1,'^ESCTRE595279',NULL,'Referral to general gastrointestinal surgery service'),('surgery-referral',1,'^ESCTRE595280',NULL,'Referral to general GI surgery service'),('surgery-referral',1,'^ESCTRE595281',NULL,'Referral to upper gastrointestinal surgery service'),('surgery-referral',1,'^ESCTRE595282',NULL,'Referral to upper GI surgery service'),('surgery-referral',1,'^ESCTRE595283',NULL,'Referral to colorectal surgery service'),('surgery-referral',1,'^ESCTRE595285',NULL,'Referral to pancreatic surgery service'),('surgery-referral',1,'^ESCTRE595286',NULL,'Referral to plastic surgery service'),('surgery-referral',1,'^ESCTRE595288',NULL,'Referral to trauma surgery service'),('surgery-referral',1,'^ESCTRE595338',NULL,'Referral for general surgery domiciliary visit'),('surgery-referral',1,'^ESCTRE595339',NULL,'Referral for general surgery DV'),('surgery-referral',1,'^ESCTRE596004',NULL,'Referral to general dental surgery service'),('surgery-referral',1,'ESCTRE37',NULL,'Referral to vascular surgery service'),('surgery-referral',1,'EMISD_RE68',NULL,'Referral to dental surgery service'),('surgery-referral',1,'EMISD_RE78',NULL,'Referral to oral surgery service');
  
INSERT INTO AllCodes
SELECT concept, version, code, description from codesemis;


DROP TABLE IF EXISTS TempRefCodes;
CREATE TEMPORARY TABLE TempRefCodes (FK_Reference_Coding_ID BIGINT NOT NULL, concept VARCHAR(255) NOT NULL, version INT NOT NULL, description VARCHAR(255));

-- Read v2 codes
INSERT INTO TempRefCodes
SELECT "PK_Reference_Coding_ID", dcr.concept, dcr.version, dcr.description
FROM INTERMEDIATE.GP_RECORD."Reference_Coding" rc
INNER JOIN codesreadv2 dcr on dcr.code = rc."MainCode"
WHERE "CodingType"='ReadCodeV2'
AND (dcr.term IS NULL OR dcr.term = rc."Term")
and "PK_Reference_Coding_ID" != -1;

-- CTV3 codes
INSERT INTO TempRefCodes
SELECT "PK_Reference_Coding_ID", dcc.concept, dcc.version, dcc.description
FROM INTERMEDIATE.GP_RECORD."Reference_Coding" rc
INNER JOIN codesctv3 dcc on dcc.code = rc."MainCode"
WHERE "CodingType"='CTV3'
and "PK_Reference_Coding_ID" != -1;


-- EMIS codes with a FK Reference Coding ID
INSERT INTO TempRefCodes
SELECT "FK_Reference_Coding_ID", ce.concept, ce.version, ce.description
FROM INTERMEDIATE.GP_RECORD."Reference_Local_Code" rlc
INNER JOIN codesemis ce on ce.code = rlc."LocalCode"
WHERE "FK_Reference_Coding_ID" != -1; 

DROP TABLE IF EXISTS TempSNOMEDRefCodes;
CREATE TEMPORARY TABLE TempSNOMEDRefCodes (FK_Reference_SnomedCT_ID BIGINT NOT NULL, concept VARCHAR(255) NOT NULL, version INT NOT NULL, description VARCHAR(255));

-- SNOMED codes
INSERT INTO TempSNOMEDRefCodes
SELECT "PK_Reference_SnomedCT_ID", dcs.concept, dcs.version, dcs.description
FROM INTERMEDIATE.GP_RECORD."Reference_SnomedCT" rs
INNER JOIN codessnomed dcs on dcs.code = rs."ConceptID";


-- EMIS codes with a FK SNOMED ID but without a FK Reference Coding ID
INSERT INTO TempRefCodes
SELECT "FK_Reference_SnomedCT_ID", ce.concept, ce.version, ce.description
FROM INTERMEDIATE.GP_RECORD."Reference_Local_Code" rlc
INNER JOIN codesemis ce on ce.code = rlc."LocalCode"
WHERE "FK_Reference_Coding_ID" = -1
AND "FK_Reference_SnomedCT_ID" != -1;


-- De-duped tables
DROP TABLE IF EXISTS CodeSets;
CREATE TEMPORARY TABLE CodeSets (FK_Reference_Coding_ID BIGINT NOT NULL, concept VARCHAR(255) NOT NULL, description VARCHAR(255));

DROP TABLE IF EXISTS SnomedSets;
CREATE TEMPORARY TABLE SnomedSets (FK_Reference_SnomedCT_ID BIGINT NOT NULL, concept VARCHAR(255) NOT NULL, description VARCHAR(255));

DROP TABLE IF EXISTS VersionedCodeSets;
CREATE TEMPORARY TABLE VersionedCodeSets (FK_Reference_Coding_ID BIGINT NOT NULL, Concept VARCHAR(255), Version INT, description VARCHAR(255));

DROP TABLE IF EXISTS VersionedSnomedSets;
CREATE TEMPORARY TABLE VersionedSnomedSets (FK_Reference_SnomedCT_ID BIGINT NOT NULL, Concept VARCHAR(255), Version INT, description VARCHAR(255));

INSERT INTO VersionedCodeSets
SELECT DISTINCT * FROM TempRefCodes;

INSERT INTO VersionedSnomedSets
SELECT DISTINCT * FROM TempSNOMEDRefCodes;

INSERT INTO CodeSets
SELECT FK_Reference_Coding_ID, c.concept, description
FROM VersionedCodeSets c
INNER JOIN (
  SELECT concept, MAX(version) AS maxVersion FROM VersionedCodeSets
  GROUP BY concept)
sub ON sub.concept = c.concept AND c.version = sub.maxVersion;

INSERT INTO SnomedSets
SELECT FK_Reference_SnomedCT_ID, c.concept, description
FROM VersionedSnomedSets c
INNER JOIN (
  SELECT concept, MAX(version) AS maxVersion FROM VersionedSnomedSets
  GROUP BY concept)
sub ON sub.concept = c.concept AND c.version = sub.maxVersion;

-- now take the codes from the temporary tables and insert them into the permanent tables in snowflake (where the rows don't exist already)

INSERT INTO SDE_REPOSITORY.SHARED_UTILITIES.versionedcodesets_permanent
SELECT src.*
FROM versionedcodesets AS src
WHERE NOT EXISTS (SELECT *
                  FROM  SDE_REPOSITORY.SHARED_UTILITIES.versionedcodesets_permanent AS tgt
                  WHERE tgt.FK_REFERENCE_CODING_ID = src."FK_REFERENCE_CODING_ID"
                  );

INSERT INTO SDE_REPOSITORY.SHARED_UTILITIES.versionedsnomedsets_permanent
SELECT src.*
FROM versionedsnomedsets AS src
WHERE NOT EXISTS (SELECT *
                  FROM  SDE_REPOSITORY.SHARED_UTILITIES.versionedsnomedsets_permanent AS tgt
                  WHERE tgt.FK_REFERENCE_SNOMEDCT_ID = src."FK_REFERENCE_SNOMEDCT_ID"
                  );

--#endregion

-- >>> Following code sets injected: social-care-prescribing-referral v1/surgery-referral v1

-- ** NEED TO ADD THE BELOW CODE SETS ONCE THEY HAVE BEEN FINALISED
-- acute-pain-service:1 pain-management:1 
/*
SELECT 
	gp."FK_Patient_ID", 
	TO_DATE("EventDate") AS "EventDate", 
	"SuppliedCode",
    "Term",
    CASE WHEN vcs.Concept is not null then vcs.Concept else vss.Concept end as Concept
FROM INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" gp
INNER JOIN VersionedCodeSets vcs ON vcs.FK_Reference_Coding_ID = gp."FK_Reference_Coding_ID" AND vcs.Version =1
INNER JOIN VersionedSnomedSets vss ON vss.FK_Reference_SnomedCT_ID = gp."FK_Reference_SnomedCT_ID" AND vss.Version =1
WHERE 
GP."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM Cohort) AND
vcs.Concept in ('social-care-prescribing-referral', 'surgery-referral') AND
gp."EventDate" BETWEEN $StudyStartDate and $StudyEndDate;    -- only looking at referrals in the study period
*/

DROP TABLE IF EXISTS referrals;
CREATE TEMPORARY TABLE referrals AS
SELECT 
    ec."FK_Patient_ID"
    , TO_DATE(ec."MedicationDate") AS "MedicationDate"
    , ec."SCTID" AS "SnomedCode"
    , ec."Units"
    , ec."Dosage"
    , ec."Dosage_GP_Medications"
    , CASE WHEN ec."Cluster_ID" = 'SOCPRESREF_COD' THEN 'social prescribing referral'
           ELSE 'other' END AS "CodeSet"
    , ec."MedicationDescription" AS "Description"
FROM INTERMEDIATE.GP_RECORD."MedicationsClusters" ec
WHERE "Cluster_ID" in ('SOCPRESREF_COD')
    AND TO_DATE(ec."MedicationDate") BETWEEN $StudyStartDate and $StudyEndDate
    AND ec."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM Cohort);


