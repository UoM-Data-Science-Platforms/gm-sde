USE SCHEMA SDE_REPOSITORY.SHARED_UTILITIES;

--┌────────────────────────────────────┐
--│ LH010 Patient file                 │
--└────────────────────────────────────┘

-- Cohort: >50s in 2016

set(StudyStartDate) = to_date('2016-01-01');
set(StudyEndDate)   = to_date('2024-08-01');



-- GET ALL PATIENTS THAT HAD A LUNG HEALTH CHECK - FROM THE LINKED MFT DATA

---------------------------------------------



--ALL DEATHS 

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
        ON OM."XSeqNo" = DEATH."XSeqNo" AND OM."DiagnosisOriginalMentionNumber" = 1;

-- GET LATEST SNAPSHOT OF DEMOGRAPHICS TABLE

DROP TABLE IF EXISTS LatestSnapshotAdults;
CREATE TEMPORARY TABLE LatestSnapshotAdults AS
SELECT 
    p.*
FROM INTERMEDIATE.GP_RECORD."DemographicsProtectedCharacteristics" p 
INNER JOIN (
    SELECT "GmPseudo", MAX("Snapshot") AS LatestSnapshot
    FROM INTERMEDIATE.GP_RECORD."DemographicsProtectedCharacteristics" p 
    WHERE DATEDIFF(YEAR, TO_DATE("DateOfBirth"), $StudyStartDate) >= 50 -- over 50s only at study start date
    GROUP BY "GmPseudo"
    ) t2
ON t2."GmPseudo" = p."GmPseudo" AND t2.LatestSnapshot = p."Snapshot";

-- FIND ALL ADULT OVER 50s ALIVE AT STUDY START DATE

DROP TABLE IF EXISTS AliveAdultsAtStart;
CREATE TEMPORARY TABLE AliveAdultsAtStart AS 
SELECT  
    dem.*, 
    Death.DeathDate
FROM LatestSnapshotAdults dem
LEFT JOIN Death ON Death."GmPseudo" = dem."GmPseudo"
WHERE 
    (DeathDate IS NULL OR DeathDate > $StudyStartDate); -- alive on study start date


-- GET COHORT OF PATIENTS THAT HAD A LUNG HEALTH CHECK

DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_10_Crosbie";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_10_Crosbie" AS 
SELECT "GmPseudo", "FK_Patient_ID" 
FROM LatestSnapshotAdults
--LEFT OUTER JOIN **LUNGHEALTHCHECKTABLE**



-- PERSONAL HISTORY OF CANCER - TO JOIN TO LATER
-- THIS CODE INCLUDES ANY PATIENT IF THEY HAVE EVER HAD A SNAPSHOT INDICATING CANCER

DROP TABLE IF EXISTS PersonalHistoryCancer;
CREATE TEMPORARY TABLE PersonalHistoryCancer AS 
SELECT DISTINCT ltc."GmPseudo", "FK_Patient_ID"
FROM PRESENTATION.GP_RECORD."LongTermConditionRegister_SecondaryUses" ltc
WHERE ("Cancer_QOF" is not null or "Cancer_DiagnosisDate" is not null or "Cancer_DiagnosisAge" is not null or "Cancer_QOF_DiagnosedL5Y" is not null)
	AND "GmPseudo" IN (SELECT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_10_Crosbie");

-- BMI is available in demographics table, but for height and weight we need to use GMCR code sets

-- >>> Codesets required... Inserting the code set code
-- >>> Codesets extracted into 0.code-sets.sql
-- >>> Following code sets injected: height v1/weight v1

DROP TABLE IF EXISTS HeightWeight ;
CREATE TEMPORARY TABLE HeightWeight AS
SELECT DISTINCT
	e."FK_Patient_ID"
	, dem."GmPseudo"
	, to_date("EventDate") AS "Date"
	, e."Value"
	, e."SCTID" AS "SnomedCode"
	, cs.concept
	, e."Term" AS "Description"
FROM INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" e
LEFT OUTER JOIN SDE_REPOSITORY.SHARED_UTILITIES."Code_Sets_SDE_Lighthouse_10_Crosbie" cs ON cs.code = e."SuppliedCode"
LEFT OUTER JOIN PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" dem ON dem."FK_Patient_ID" = e."FK_Patient_ID" -- join to demographics table to get GmPseudo
WHERE cs.concept IN ('height', 'weight')
	AND e."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_10_Crosbie")
	AND "EventDate" <= '2016-01-01';

-- FIND CLOSEST HEIGHT AND WEIGHT INFO BEFORE 2016 (START DATE)
DROP TABLE IF EXISTS HeightWeightClosestDate ;
CREATE TEMPORARY TABLE HeightWeightClosestDate AS
SELECT "GmPseudo"
	, concept
	, MAX("Date") as "ClosestDate"
FROM HeightWeight 
GROUP BY "GmPseudo"
	, concept;

-- JOIN HEIGHT AND WEIGHT TABLE TO MAX DATE TABLE TO GET MOST RELEVANT VALUE
DROP TABLE IF EXISTS HeightWeightFinal ;
CREATE TEMPORARY TABLE HeightWeightFinal AS
SELECT hw."GmPseudo",
	hw."Date",
	hw.concept,
	MAX("Value") AS "Value" -- WHERE THERE ARE DUPLICATE VALUES ON SAME DATE, TAKE THE MAX
FROM HeightWeight hw
LEFT JOIN HeightWeightClosestDate hwc ON hwc."GmPseudo" = hw."GmPseudo"  AND hwc."ClosestDate" = hw."Date"
GROUP BY hw."GmPseudo",
	hw."Date",
	hw.concept;

-- FIND DATE OF FIRST STATIN PRESCRIPTION
DROP TABLE IF EXISTS Statins ;
CREATE TEMPORARY TABLE Statins AS
SELECT	c."GmPseudo"
    , MIN(TO_DATE(ec."MedicationDate")) AS "MinStatinDate"
FROM INTERMEDIATE.GP_RECORD."MedicationsClusters" ec
INNER JOIN SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_10_Crosbie" c ON c."FK_Patient_ID" = ec."FK_Patient_ID"
WHERE ec."Field_ID" = 'Statin'
	AND ec."MedicationDate" < '2016-01-01'
GROUP BY c."GmPseudo";

-- FIND DATE OF FIRST RESPIRATORY-RELATED PRESCRIPTION
DROP TABLE IF EXISTS COPDmeds;
CREATE TEMPORARY TABLE COPDMeds AS
SELECT	c."GmPseudo"
    , MIN(TO_DATE(ec."MedicationDate")) AS "MinCOPDMedDate"
FROM INTERMEDIATE.GP_RECORD."MedicationsClusters" ec
INNER JOIN SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_10_Crosbie" c ON c."FK_Patient_ID" = ec."FK_Patient_ID"
WHERE ec."Field_ID" = 'COPDICSDRUG_COD'
	AND ec."MedicationDate" < '2016-01-01'
GROUP BY c."GmPseudo";



-- FOR THE ABOVE COHORT, GET ALL REQUIRED DEMOGRAPHICS


-- ... processing [[create-output-table::"1_Patients"]] ... 
-- ... Need to create an output table called "1_Patients" and replace 
-- ... the GmPseudo column with a study-specific random patient id.

-- First we create a table in an area only visible to the RDEs which contains
-- the GmPseudos. THESE CANNOT BE RELEASED TO END USERS.
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."1_Patients_WITH_PSEUDO_IDS";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."1_Patients_WITH_PSEUDO_IDS" AS
SELECT
	 dem."GmPseudo", 
	 dem."Sex",
	 dem."DateOfBirth" AS "MonthOfBirth", 
	 dem."Age",
	 dem."IMD_Decile",
	 dem."EthnicityLatest_Category",
	 dem."PracticeCode", 
	 dth.DeathDate,
     dth."DiagnosisOriginalMentionCode" AS "ReasonForDeathCode",
     dth."DiagnosisOriginalMentionDesc" AS "ReasonForDeathDesc",
	 dem."Frailty", -- 92% missingness
	 CASE WHEN hwf.concept = 'height' THEN hwf."Value" END AS "Height",
	 CASE WHEN hwf.concept = 'height' THEN hwf."Date"  END AS "Height_Date",
	 CASE WHEN hwf.concept = 'weight' THEN hwf."Value" END AS "Weight",
	 CASE WHEN hwf.concept = 'weight' THEN hwf."Date"  END AS "Weight_Date",
	 dem."BMI",
	 dem."BMI_Date",
	 dem."BMI_Description",
	 CASE WHEN phc."GmPseudo" IS NOT NULL THEN 1 ELSE 0 END AS "PersonalHistoryOfCancer",
	 -- TODO: family history of lung cancer
	 dem."AlcoholStatus",
	 dem."Alcohol_Date",
	 dem."AlcoholConsumption",
	 dem."SmokingStatus",
	 dem."Smoking_Date",
	 dem."SmokingConsumption",
	 CASE WHEN st."GmPseudo" IS NOT NULL THEN 1 ELSE 0 END AS "StatinPrescribedBeforeJan2016",
	 st."MinStatinDate" AS "EarliestStatinPrescription_Date",
	 CASE WHEN copd."GmPseudo" IS NOT NULL THEN 1 ELSE 0 END AS "COPDMedPrescribedBeforeJan2016",
	 copd."MinCOPDMedDate" AS "EarliestCOPDMedPrescription_Date"
FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_10_Crosbie"  co
LEFT OUTER JOIN PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" dem ON dem."GmPseudo" = co."GmPseudo"
LEFT OUTER JOIN Death dth ON dth."GmPseudo" = co."GmPseudo"
LEFT OUTER JOIN PersonalHistoryCancer phc ON phc."GmPseudo" = co."GmPseudo"
LEFT OUTER JOIN HeightWeightFinal hwf ON hwf."GmPseudo" = co."GmPseudo"
LEFT OUTER JOIN Statins st ON st."GmPseudo" = co."GmPseudo"
LEFT OUTER JOIN COPDMeds copd ON copd."GmPseudo" = co."GmPseudo"
QUALIFY row_number() OVER (PARTITION BY dem."GmPseudo" ORDER BY "Snapshot" DESC) = 1;

-- Then we check to see if there are any new GmPseudo ids. We do this by making a temp table 
-- of all "new" GmPseudo ids. I.e. any GmPseudo ids that we've already got a unique id for
-- for this study are excluded
DROP TABLE IF EXISTS "AllPseudos_SDE_Lighthouse_10_Crosbie";
CREATE TEMPORARY TABLE "AllPseudos_SDE_Lighthouse_10_Crosbie" AS
SELECT DISTINCT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."1_Patients_WITH_PSEUDO_IDS"
EXCEPT
SELECT "GmPseudo" FROM "Patient_ID_Mapping_SDE_Lighthouse_10_Crosbie";

-- Find the highest currently assigned id. Ids are given incrementally, so now ones
-- need to start at +1 of the current highest
SET highestPatientId = (
    SELECT IFNULL(MAX("StudyPatientPseudoId"),0) FROM "Patient_ID_Mapping_SDE_Lighthouse_10_Crosbie"
);

-- Make a study specific hash for each new GmPseudo and insert it
-- into the patient lookup table
INSERT INTO "Patient_ID_Mapping_SDE_Lighthouse_10_Crosbie"
SELECT
    "GmPseudo", -- the GM SDE patient ids for patients in this cohort
    SHA2(CONCAT('SDE_Lighthouse_10_Crosbie', "GmPseudo")) AS "Hash", -- used to provide a random (study-specific) ordering for the patient ids we provide
    $highestPatientId + ROW_NUMBER() OVER (ORDER BY "Hash") -- the patient id that we provide to the analysts
FROM "AllPseudos_SDE_Lighthouse_10_Crosbie";

-- Finally, we select from the output table which includes the GmPseudos, in order
-- to populate the table for the end users where the GmPseudo fields are redacted via a function
-- created in the 0.code-sets.sql file
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."1_Patients";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."1_Patients" AS
SELECT SDE_REPOSITORY.SHARED_UTILITIES.gm_pseudo_hash_SDE_Lighthouse_10_Crosbie("GmPseudo") AS "PatientID", * EXCLUDE "GmPseudo"
FROM SDE_REPOSITORY.SHARED_UTILITIES."1_Patients_WITH_PSEUDO_IDS";