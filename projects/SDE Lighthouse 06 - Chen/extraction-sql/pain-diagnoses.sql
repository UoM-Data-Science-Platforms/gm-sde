--┌────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 06 - pain diagnoses           │
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

-- find patients with chronic pain

DROP TABLE IF EXISTS chronic_pain;
CREATE TEMPORARY TABLE chronic_pain AS
SELECT "FK_Patient_ID", to_date("EventDate") AS "EventDate"
FROM  INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" e
WHERE "SuppliedCode" IN (SELECT code FROM SDE_REPOSITORY.SHARED_UTILITIES.AllCodesPermanent WHERE Concept = 'chronic-pain' AND Version = 1) 
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
WHERE "SuppliedCode" IN (SELECT code FROM SDE_REPOSITORY.SHARED_UTILITIES.AllCodesPermanent WHERE Concept = 'cancer' AND Version = 1)
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



-- !!NOTE!! : many codes will feature in both the 'chronic pain' code set and the more specific code set, and therefore feature twice in the final table.
-- this is the case because we would miss some chronic pain codes if we only keep the specific code sets
-- PI will be informed about this

-- find diagnosis codes that exist in the clusters tables

DROP TABLE IF EXISTS diagnosesClusters;
CREATE TEMPORARY TABLE diagnosesClusters AS
SELECT 
    ec."FK_Patient_ID"
    , TO_DATE(ec."EventDate") AS "DiagnosisDate"
    , ec."SCTID" AS "SnomedCode"
    , CASE WHEN ((lower("Term") like '%neuropa%' AND lower("Term") like '%diab%'))  THEN  'diabetic-neuropathy'
           WHEN ("Cluster_ID" = 'eFI2_PeripheralNeuropathy')                        THEN  'peripheral-neuropathy' 
		   WHEN ("Cluster_ID" = 'RARTH_COD') THEN 'rheumatoid-arthritis'
		   WHEN ("Cluster_ID" = 'eFI2_Osteoarthritis') THEN 'osteoarthritis'
		   WHEN	("Cluster_ID" = 'eFI2_BackPainTimeSensitive') THEN 'back-pain' -- in last 5 years
           ELSE 'other' END AS "Concept"
    , ec."Term" AS "Description"
FROM INTERMEDIATE.GP_RECORD."EventsClusters" ec
WHERE 
	(
	((lower("Term") like '%neuropa%' AND lower("Term") like '%diab%'))  OR -- diabetic neuropathy
	("Cluster_ID" = 'eFI2_PeripheralNeuropathy') OR -- peripheral neuropathy
	("Cluster_ID" = 'RARTH_COD') OR -- rheumatoid arthritis diagnosis codes
	("Cluster_ID" = 'eFI2_Osteoarthritis') OR -- osteoarthritis
	("Cluster_ID" = 'eFI2_BackPainTimeSensitive') -- back pain in last 5 years
	)
AND TO_DATE(ec."EventDate") BETWEEN $StudyStartDate and $StudyEndDate;
    AND ec."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM Cohort);

-- find diagnoses codes that don't exist in a cluster

DROP TABLE IF EXISTS diagnoses;
CREATE TEMPORARY TABLE diagnoses AS
SELECT 
	e."FK_Patient_ID"
	, to_date("EventDate") AS "DiagnosisDate"
	, e."SCTID" AS "SnomedCode"
	, ac.concept
	, e."Term" AS "Description"
FROM  INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" e
--LEFT JOIN SDE_REPOSITORY.SHARED_UTILITIES.VERSIONEDCODESETS_PERMANENT co ON co.FK_Reference_Coding_ID = e."FK_Reference_Coding_ID"
--LEFT JOIN SDE_REPOSITORY.SHARED_UTILITIES.VERSIONEDSNOMEDSETS_PERMANENT sn ON sn.FK_Reference_SnomedCT_ID = e."FK_Reference_SnomedCT_ID"
LEFT JOIN SDE_REPOSITORY.SHARED_UTILITIES.AllCodesPermanent ac ON ac.CODE = e."SuppliedCode" 
WHERE
ac.CONCEPT IN ('chronic-pain', 'neck-problems','neuropathic-pain', 'chest-pain','post-herpetic-neuralgia', 'ankylosing-spondylitis',
				'psoriatic-arthritis', 'fibromyalgia', 'temporomandibular-pain', 'phantom-limb-pain', 'chronic-pancreatitis' )
/*( 
  "FK_Reference_Coding_ID" IN (SELECT FK_Reference_Coding_ID FROM SDE_REPOSITORY.SHARED_UTILITIES.VERSIONEDCODESETS_PERMANENT WHERE Concept IN 
  ('chronic-pain', 'neck-problems', 'neuropathic-pain', 'chest-pain', 'post-herpetic-neuralgia', 'ankylosing-spondylitis', 'psoriatic-arthritis', 'fibromyalgia', 'temporomandibular-pain', 'phantom-limb-pain', 'chronic-pancreatitis') AND Version = 1) 
    OR
  "FK_Reference_SnomedCT_ID" IN (SELECT FK_Reference_SnomedCT_ID FROM SDE_REPOSITORY.SHARED_UTILITIES.VERSIONEDSNOMEDSETS_PERMANENT WHERE Concept IN   
  ('chronic-pain', 'neck-problems', 'neuropathic-pain', 'chest-pain', 'post-herpetic-neuralgia','ankylosing-spondylitis', 'psoriatic-arthritis', 'fibromyalgia', 'temporomandibular-pain', 'phantom-limb-pain', 'chronic-pancreatitis') AND Version = 1))*/
AND e."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM Cohort)
AND TO_DATE("EventDate") BETWEEN $StudyStartDate AND $StudyEndDate;

-- final table combining diagnoses from clusters and those from research code set tables

SELECT * from diagnoses
UNION ALL
SELECT * from DIAGNOSESCLUSTERS