--┌──────────────────────────────────────────────┐
--│ SDE Lighthouse study 06 - Patients           │
--└──────────────────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK ------------
-- Richard Williams	2024-08-30	Review complete --
--------------------------------------------------

--┌───────────────────────────────────────────────────────────────────────────┐
--│ Define Cohort for LH006: patients that had multiple opioid prescriptions  │
--└───────────────────────────────────────────────────────────────────────────┘

-- OBJECTIVE: To build the cohort of patients needed for LH006. This reduces duplication of code in the template scripts.

-- COHORT: Any adult patient with non-chronic cancer pain, who received more than two oral or transdermal opioid prescriptions
--          for 14 days within 90 days, between 2017 and 2023.
--          Excluding patients with a cancer diagnosis within 12 months from index date
--			Opioids should exclude the main addiction substitutes

-- INPUT: none
-- OUTPUT: Temp tables as follows:
-- Cohort

set(StudyStartDate) = to_date('2017-01-01');
set(StudyEndDate)   = to_date('2024-10-31');

--> CODESET chronic-pain:1 cancer:1

--> EXECUTE query-get-possible-patients.sql

DROP TABLE IF EXISTS PatientsToInclude;
CREATE TEMPORARY TABLE PatientsToInclude AS
SELECT 
FROM GPRegPatients 
WHERE ("DeathDate" IS NULL OR "DeathDate" > $StudyStartDate) -- alive on study start date
	AND 
	("leftGMDate" IS NULL OR "leftGMDate" > $StudyEndDate) -- don't include patients who left GM mid study (as we lose their data)
	AND DATEDIFF(YEAR, "DateOfBirth", $StudyStartDate) >= 18; -- OVER 18s ONLY

-- find patients with chronic pain

DROP TABLE IF EXISTS chronic_pain;
CREATE TEMPORARY TABLE chronic_pain AS
SELECT "FK_Patient_ID", to_date("EventDate") AS "EventDate"
FROM  INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" e
WHERE "SuppliedCode" IN (SELECT code FROM {{code-set-table}} WHERE concept = 'chronic-pain' AND Version = 1) 
AND "EventDate" BETWEEN $StudyStartDate and $StudyEndDate
AND "FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM PatientsToInclude); -- only include alive patients at study start

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
WHERE "SuppliedCode" IN (SELECT code FROM {{code-set-table}} WHERE concept = 'cancer' AND Version = 1)
AND e."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM chronic_pain) --only look in patients with chronic pain
AND e."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM PatientsToInclude); -- only include alive patients at study start 


-- find patients in the chronic pain cohort who received more than 2 opioids
-- for 14 days, within a 90 day period, after their first chronic pain code
-- excluding those with cancer code close to first pain code 

-- first get all opioid prescriptions for the cohort

DROP TABLE IF EXISTS OpioidPrescriptions;
CREATE TEMPORARY TABLE OpioidPrescriptions AS
SELECT 
    ec."FK_Patient_ID"
    , TO_DATE(ec."Date") AS "MedicationDate"
    , ec."SCTID" AS "SnomedCode"
    , ec."Dosage"
    , ec."DosageUnits"
    , ec."Term" AS "Description"
	, fp.FirstPainCodeDate
	, TO_DATE(Lag(ec."Date", 1) OVER 
		(PARTITION BY ec."FK_Patient_ID" ORDER BY "Date" ASC)) AS "PreviousOpioidDate"
FROM INTERMEDIATE.GP_RECORD."Combined_EventsMedications_Clusters_SecondaryUses" ec
INNER JOIN FirstPain fp ON fp."FK_Patient_ID" = ec."FK_Patient_ID" 
WHERE 
	"Cluster_ID" in ('OPIOIDDRUG_COD') 									-- opioids only (excluding heroin substitutes)
	AND TO_DATE(ec."Date") > fp.FirstPainCodeDate				-- only prescriptions after the patients first pain code
	AND ec."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM chronic_pain) -- chronic pain patients only 
	AND ec."FK_Patient_ID" NOT IN (SELECT "FK_Patient_ID" FROM cancer)  -- exclude cancer patients
	AND TO_DATE(ec."Date") BETWEEN $StudyStartDate and $StudyEndDate;    -- only looking at opioid prescriptions in the study period;

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

DROP TABLE IF EXISTS {{cohort-table}};
CREATE TABLE {{cohort-table}} AS
SELECT DISTINCT
	 i."FK_Patient_ID",
     dem."GmPseudo",
	 i.IndexDate
FROM IndexDates i
LEFT JOIN -- join to demographics table to get GmPseudo
    (SELECT DISTINCT "FK_Patient_ID", "GmPseudo"
     FROM PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses"
    ) dem ON dem."FK_Patient_ID" = i."FK_Patient_ID";

-- create cohort of patients
-- join to demographic table to get ethnicity and date of birth

{{create-output-table::"LH006-1_Patients"}}
SELECT
	 dem."GmPseudo", 
	 dem."Sex",
	 dem."DateOfBirth" AS "YearAndMonthOfBirth", 
	 dem."Age",
	 dem."IMD_Decile" AS "IMDDecile",
	 dem."EthnicityLatest_Category",
	 dem."PracticeCode", 
	 DATE_TRUNC(month, dth.DeathDate) AS "DeathYearAndMonth",
     dth."DiagnosisOriginalMentionCode" AS "ReasonForDeathCode",
     dth."DiagnosisOriginalMentionDesc" AS "ReasonForDeathDesc",
	 co.IndexDate AS "IndexDate"
FROM {{cohort-table}}  co
LEFT OUTER JOIN PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" dem ON dem."GmPseudo" = co."GmPseudo"
LEFT OUTER JOIN Death dth ON dth."GmPseudo" = co."GmPseudo"
QUALIFY row_number() OVER (PARTITION BY dem."GmPseudo" ORDER BY "Snapshot" DESC) = 1;