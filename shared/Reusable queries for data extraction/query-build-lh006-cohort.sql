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

--> CODESET cancer:1 chronic-pain:1
--> CODESET opioids:1      

-- table of chronic pain coding events

DROP TABLE IF EXISTS chronic_pain;
CREATE TEMPORARY TABLE chronic_pain AS
SELECT gp."FK_Patient_ID", "EventDate"
FROM INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" gp
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM VersionedCodeSets WHERE Concept = 'chronic-pain' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM VersionedSnomedSets WHERE Concept = 'chronic-pain' AND Version = 1)
) 
AND "EventDate" BETWEEN $StudyStartDate and $StudyEndDate 

-- find first chronic pain code in the study period 
DROP TABLE IF EXISTS FirstPain
CREATE TEMPORARY TABLE FirstPain AS
SELECT 
	FK_Patient_ID, 
	MIN(TO_DATE(EventDate)) AS FirstPainCodeDate
FROM chronic_pain
GROUP BY FK_Patient_ID

-- find patients with a cancer code within 12 months either side of first chronic pain code
-- to exclude in next step

DROP TABLE IF EXISTS cancer
CREATE TEMPORARY TABLE cancer AS
SELECT gp."FK_Patient_ID", "EventDate" 
FROM INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" gp
LEFT JOIN FirstPain fp ON fp.FK_Patient_ID = gp.FK_Patient_ID 
				AND gp.EventDate BETWEEN DATEADD(year, 1, FirstPainCodeDate) AND DATEADD(year, -1, FirstPainCodeDate)
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM VersionedCodeSets WHERE Concept = 'cancer' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM VersionedSnomedSets WHERE Concept = 'cancer' AND Version = 1)
)
AND "FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM chronic_pain)

-- find patients in the chronic pain cohort who received more than 2 opioids
-- for 14 days, within a 90 day period, after their first chronic pain code
-- excluding those with cancer code close to first pain code 

-- first get all opioid prescriptions for the cohort

DROP TABLE IF EXISTS OpioidPrescriptions
CREATE TEMPORARY TABLE OpioidPrescriptions
SELECT 
	gp."FK_Patient_ID", 
	TO_DATE("MedicationDate") AS "MedicationDate", 
	"Dosage", 
	"Quantity", 
	"SuppliedCode",
	fp.FirstPainCodeDate,
	Lag("MedicationDate", 1) OVER 
		(PARTITION BY gp."FK_Patient_ID" ORDER BY "MedicationDate" ASC) AS "PreviousOpioidDate"
FROM INTERMEDIATE.GP_RECORD."GP_Medications_SecondaryUses" gp
INNER JOIN FirstPain fp ON fp.FK_Patient_ID = gp."FK_Patient_ID" 
WHERE 
	(
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM VersionedCodeSets WHERE Concept = 'opioids' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM VersionedSnomedSets WHERE Concept = 'opioids' AND Version = 1)
  	)
AND "FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM chronic_pain) -- chronic pain patients only 
AND gp."FK_Patient_ID" NOT IN (SELECT FK_Patient_ID FROM cancer)  -- exclude cancer patients
AND "MedicationDate" BETWEEN $StudyStartDate and $StudyEndDate    -- only looking at opioid prescriptions in the study period
AND gp."MedicationDate" > fp.FirstPainCodeDate                    -- looking at opioid prescriptions after the first chronic pain code

-- find all patients that have had two prescriptions within 90 days, and calculate the index date as
-- the first prescription that meets the criteria

DROP TABLE IF EXISTS IndexDates
CREATE TEMPORARY TABLE IndexDates AS
SELECT FK_Patient_ID, 
	MIN(PreviousOpioidDate) AS IndexDate 
FROM OpioidPrescriptions
WHERE DATEDIFF(dd, PreviousOpioidDate, MedicationDate) <= 90
GROUP BY FK_Patient_ID



--- death table to join to later

DROP TABLE IF EXISTS Death;
CREATE TEMPORARY TABLE Death AS
SELECT 
    DEATH."GmPseudo",
    TO_DATE(DEATH."RegisteredDateOfDeath") AS DeathDate,
    OM."DiagnosisOriginalMentionCode",
    OM."DiagnosisOriginalMentionDesc",
    OM."DiagnosisOriginalMentionChapterCode",
    OM."DiagnosisOriginalMentionChapterDesc",
    OM."DiagnosisOriginalMentionCategory1Code",
    OM."DiagnosisOriginalMentionCategory1Desc"
FROM PRESENTATION.NATIONAL_FLOWS_PCMD."DS1804_Pcmd" DEATH
LEFT JOIN PRESENTATION.NATIONAL_FLOWS_PCMD."DS1804_PcmdDiagnosisOriginalMentions" OM 
        ON OM."XSeqNo" = DEATH."XSeqNo" AND OM."DiagnosisOriginalMentionNumber" = 1
WHERE "GmPseudo" IN (SELECT "GmPseudo" FROM virtualWards);

-- create cohort of patients
-- join to demographic table to get ethnicity and date of birth

DROP TABLE IF EXISTS Cohort
CREATE TEMPORARY TABLE Cohort AS
SELECT
	 i.FK_Patient_ID,
	 p."GmPseudo",
	 p.Sex,
	 p.Age,
	 p.TOWNSEND_SCORE_LSOA_2011,
	 p.EthnicityLatest_Category,
	 P.PracticeCode, 
	 TO_DATE(death.RegisteredDateOfDeath) AS DeathDate,
	 P."DateOfBirth", 
	 i.IndexDate
FROM IndexDates i
LEFT OUTER JOIN        -- use row_number to filter demographics table to most recent snapshot
	(
	SELECT 
		*, 
		ROW_NUMBER() OVER (PARTITION BY FK_Patient_ID ORDER BY Snapshot DESC) AS ROWNUM
	FROM PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics" p 
	) dem	ON p.FK_Patient_ID = i.FK_Patient_ID
WHERE dem.ROWNUM = 1
---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
