USE SCHEMA SDE_REPOSITORY.SHARED_UTILITIES;

--┌────────────────────────────────────┐
--│ LH010 Patient file                 │
--└────────────────────────────────────┘

-- Cohort: >50s in 2016

set(StudyStartDate) = to_date('2016-01-01');
set(StudyEndDate)   = to_date('2024-08-01');


--┌─────────────────────────────────────────────────────────────────┐
--│ Create table of patients who were alive at the study start date │
--└─────────────────────────────────────────────────────────────────┘

-- ** any patients opted out of sharing GP data would not appear in the final table

-- this script requires an input of StudyStartDate

-- takes one parameter: 
-- minimum-age : integer - The minimum age of the group of patients. Typically this would be 0 (all patients) or 18 (all adults)

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

DROP TABLE IF EXISTS LatestSnapshot;
CREATE TEMPORARY TABLE LatestSnapshot AS
SELECT 
    p.*
FROM PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" p 
INNER JOIN (
    SELECT "GmPseudo", MAX("Snapshot") AS LatestSnapshot
    FROM PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" p 
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
FROM LatestSnapshot dem
LEFT JOIN Death ON Death."GmPseudo" = dem."GmPseudo"
WHERE 
    (DeathDate IS NULL OR DeathDate > $StudyStartDate); -- alive on study start date


-- GET COHORT OF PATIENTS THAT HAD A LUNG HEALTH CHECK

DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_10_Crosbie";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_10_Crosbie" AS 
SELECT "GmPseudo", "FK_Patient_ID" 
FROM AlivePatientsAtStart
--LEFT OUTER JOIN **LUNGHEALTHCHECKTABLE**
WHERE DATEDIFF(YEAR, "DateOfBirth",$StudyStartDate) >= 50  -- over 50 in 2016
LIMIT 1000; --THIS IS TEMPORARY


-- PERSONAL HISTORY OF CANCER - TO JOIN TO LATER
-- THIS CODE INCLUDES ANY PATIENT IF THEY HAVE EVER HAD A SNAPSHOT INDICATING CANCER

DROP TABLE IF EXISTS PersonalHistoryCancer;
CREATE TEMPORARY TABLE PersonalHistoryCancer AS 
SELECT DISTINCT ltc."GmPseudo", "FK_Patient_ID"
FROM PRESENTATION.GP_RECORD."LongTermConditionRegister_SecondaryUses" ltc
WHERE ("Cancer_QOF" is not null or "Cancer_DiagnosisDate" is not null or "Cancer_DiagnosisAge" is not null or "Cancer_QOF_DiagnosedL5Y" is not null)
	AND "GmPseudo" IN SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_10_Crosbie";

-- COPD meds

DROP TABLE IF EXISTS COPDMeds;
CREATE TEMPORARY TABLE COPDMeds AS 
SELECT c."GmPseudo"
    , MIN(TO_DATE(ec."MedicationDate")) AS "MinCOPDMedDate"
FROM INTERMEDIATE.GP_RECORD."Combined_EventsMedications_Clusters_SecondaryUses" ec
INNER JOIN SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_10_Crosbie" c ON c."FK_Patient_ID" = ec."FK_Patient_ID"
WHERE "Field_ID" IN ('COPDICSDRUG_COD')
	AND TO_DATE(ec."MedicationDate") <=  $StudyStartDate
GROUP BY c."GmPseudo";

-- Statins

DROP TABLE IF EXISTS Statins;
CREATE TEMPORARY TABLE Statins AS 
SELECT c."GmPseudo"
    , MIN(TO_DATE(ec."MedicationDate")) AS "MinStatinDate"
FROM INTERMEDIATE.GP_RECORD."Combined_EventsMedications_Clusters_SecondaryUses" ec
INNER JOIN SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_10_Crosbie" c ON c."FK_Patient_ID" = ec."FK_Patient_ID"
WHERE "Field_ID" IN ('Statin')
	AND TO_DATE(ec."MedicationDate") <=  $StudyStartDate
GROUP BY c."GmPseudo";

-- reasonable adjustment flag

-- >>> Codesets required... Inserting the code set code
-- >>> Codesets extracted into 0.code-sets.sql
-- >>> Following code sets injected: reasonable-adjustment-category5 v1/reasonable-adjustment-category6 v1/reasonable-adjustment-category7 v1
-- >>> Following code sets injected: reasonable-adjustment-category8 v1/reasonable-adjustment-category9 v1/reasonable-adjustment-category10 v1

DROP TABLE IF EXISTS ReasonableAdjustment;
CREATE TEMPORARY TABLE ReasonableAdjustment AS 
SELECT c."GmPseudo"
	, "Field_ID" AS concept
    , MIN(TO_DATE(ec."MedicationDate")) AS "MinDate"
FROM INTERMEDIATE.GP_RECORD."Combined_EventsMedications_Clusters_SecondaryUses" ec
INNER JOIN SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_10_Crosbie" c ON c."FK_Patient_ID" = ec."FK_Patient_ID"
WHERE "Field_ID" IN ('AIREQPROF_COD', 'AIFORMAT_COD', 'AIMETHOD_COD', 'AICOMSUP_COD' )
	AND TO_DATE(ec."MedicationDate") <=  $StudyStartDate
UNION ALL
-- reasonable adjustment categories 5 - 10
SELECT 
	 dem."GmPseudo"
	, cs.concept
	, MIN(to_date("EventDate")) AS "MinDate"
FROM INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" e
LEFT JOIN SDE_REPOSITORY.SHARED_UTILITIES."Code_Sets_SDE_Lighthouse_10_Crosbie" cs ON cs.code = e."SuppliedCode"
LEFT OUTER JOIN AlivePatientsAtStart dem ON dem."FK_Patient_ID" = co."FK_Patient_ID" -- to get GmPseudo
WHERE cs.concept IN ('reasonable-adjustment-category5', 'reasonable-adjustment-category6', 'reasonable-adjustment-category7', 
					'reasonable-adjustment-category8', 'reasonable-adjustment-category9', 'reasonable-adjustment-category10')
	AND "FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_10_Crosbie");
GROUP BY dem."GmPseudo", "Field_ID";

-- FOR THE ABOVE COHORT, GET ALL REQUIRED DEMOGRAPHICS


-- ... processing [[create-output-table::"LH010-1_Patients"]] ... 
-- ... Need to create an output table called "LH010-1_Patients" and replace 
-- ... the GmPseudo column with a study-specific random patient id.

-- First we create a table in an area only visible to the RDEs which contains
-- the GmPseudos. THESE CANNOT BE RELEASED TO END USERS.
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH010-1_Patients_WITH_PSEUDO_IDS";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH010-1_Patients_WITH_PSEUDO_IDS" AS
SELECT
	 dem."Snapshot",
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
	 dem."Frailty",
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
	 CASE WHEN copd."GmPseudo" IS NOT NULL THEN 1 ELSE 0 END AS "HistoryOfCOPDMeds",
	 copd."MinCOPDMedDate",
	 CASE WHEN stat."GmPseudo" IS NOT NULL THEN 1 ELSE 0 END AS "HistoryOfStatins",
	 stat."MinStatinDate",
	 CASE WHEN reas."GmPseudo" IS NOT NULL THEN 1 ELSE 0 END AS "ReasonableAdjustmentFlag",
	 reas."MinReasonableAdjustmentDate"
FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_10_Crosbie"  co
LEFT OUTER JOIN PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" dem ON dem."GmPseudo" = co."GmPseudo"
LEFT OUTER JOIN Death dth ON dth."GmPseudo" = co."GmPseudo"
LEFT OUTER JOIN PersonalHistoryCancer phc ON phc."GmPseudo" = co."GmPseudo"
LEFT OUTER JOIN COPDMeds copd ON copd."GmPseudo" = co."GmPseudo" 
LEFT OUTER JOIN Statins stat ON stat."GmPseudo" = co."GmPseudo" 
LEFT OUTER JOIN ReasonableAdjustment reas ON reas."GmPseudo" = co."GmPseudo"
QUALIFY row_number() OVER (PARTITION BY dem."GmPseudo" ORDER BY "Snapshot" DESC) = 1;

-- Then we check to see if there are any new GmPseudo ids. We do this by making a temp table 
-- of all "new" GmPseudo ids. I.e. any GmPseudo ids that we've already got a unique id for
-- for this study are excluded
DROP TABLE IF EXISTS "AllPseudos_SDE_Lighthouse_10_Crosbie";
CREATE TEMPORARY TABLE "AllPseudos_SDE_Lighthouse_10_Crosbie" AS
SELECT DISTINCT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."LH010-1_Patients_WITH_PSEUDO_IDS"
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
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH010-1_Patients";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH010-1_Patients" AS
SELECT SDE_REPOSITORY.SHARED_UTILITIES.gm_pseudo_hash_SDE_Lighthouse_10_Crosbie("GmPseudo") AS "PatientID",
	* EXCLUDE "GmPseudo"
FROM SDE_REPOSITORY.SHARED_UTILITIES."LH010-1_Patients_WITH_PSEUDO_IDS";