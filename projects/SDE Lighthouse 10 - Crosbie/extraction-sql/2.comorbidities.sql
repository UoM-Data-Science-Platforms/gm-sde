USE SCHEMA SDE_REPOSITORY.SHARED_UTILITIES;

--┌───────────────────────────────────────────────────┐
--│ SDE Lighthouse study 10 - Crosbie - comorbidities │
--└───────────────────────────────────────────────────┘

DROP TABLE IF EXISTS StandardLTCs;
CREATE TEMPORARY TABLE StandardLTCs AS
SELECT
	"GmPseudo",
	"ADHD_DiagnosisDate", "Anorexia_DiagnosisDate", "Anxiety_DiagnosisDate", "Asthma_DiagnosisDate", 
	"AtrialFibrillation_DiagnosisDate", "Autism_DiagnosisDate", "BlindnessLowVision_DiagnosisDate", "Bronchiectasis_DiagnosisDate", 
	"Bulimia_DiagnosisDate", "Cancer_DiagnosisDate", "ChronicKidneyDisease_DiagnosisDate", "ChronicLiverDisease_DiagnosisDate",
	"ChronicSinusitis_DiagnosisDate", "Constipation_DiagnosisDate", "COPD_DiagnosisDate", "CoronaryHeartDisease_DiagnosisDate",
	"DeafnessHearingLoss_DiagnosisDate", "Dementia_DiagnosisDate", "Depression_DiagnosisDate", "DiabetesType1_DiagnosisDate",
	"DiabetesType2_DiagnosisDate", "DiverticularDisease_DiagnosisDate", "DownsSyndrome_DiagnosisDate", "Eczema_DiagnosisDate",
	"Epilepsy_DiagnosisDate", "FamilialHypercholesterolemia_DiagnosisDate", "HeartFailure_DiagnosisDate",
	"Hypertension_DiagnosisDate", "Immunosuppression_DiagnosisDate",
	"InflammatoryBowelDisease_Crohns_DiagnosisDate", "IrritableBowelSyndrome_DiagnosisDate", "LearningDisability_DiagnosisDate",
	"MentalHealth_SeriousMentalIllness_DiagnosisDate", "Migraine_DiagnosisDate", "MultipleSclerosis_DiagnosisDate",
	"NonDiabeticHyperglycemia_DiagnosisDate", "Obesity_DiagnosisDate", "Osteoporosis_DiagnosisDate", "PainfulCondition_DiagnosisDate",
	"PalliativeCare_DiagnosisDate", "ParkinsonsDisease_DiagnosisDate", "PepticUlcerDisease_DiagnosisDate",
	"PeripheralArterialDisease_DiagnosisDate", "ProstateDisorder_DiagnosisDate", "Psoriasis_DiagnosisDate",
	"RheumatoidArthritis_DiagnosisDate", "Stroke_DiagnosisDate", "ThyroidDisorder_DiagnosisDate", "TIA_DiagnosisDate"
FROM INTERMEDIATE.GP_RECORD."LongTermConditionRegister_Diagnosis"
WHERE "GmPseudo" IN (SELECT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_10_Crosbie")
QUALIFY row_number() OVER (PARTITION BY "GmPseudo" ORDER BY "Snapshot" DESC) = 1; -- this brings back the values from the most recent snapshot

-- load codesets for conditions not in above LTC table

-- >>> Codesets required... Inserting the code set code
-- >>> Codesets extracted into 0.code-sets.sql
-- >>> Following code sets injected: myocardial-infarction v1/angina v1/tuberculosis v1/venous-thromboembolism v1/pneumonia v1/copd v1/efi-mobility-problems v1/efi-vision-problems v1

--  create table of conditions not included in LTC table

DROP TABLE IF EXISTS OtherDiags ;
CREATE TEMPORARY TABLE OtherDiags AS
SELECT DISTINCT
	e."FK_Patient_ID"
	, dem."GmPseudo"
	, to_date("EventDate") AS "DiagnosisDate"
	, e."SCTID" AS "SnomedCode"
	, cs.concept
	, e."Term" AS "Description"
FROM INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" e
LEFT JOIN SDE_REPOSITORY.SHARED_UTILITIES."Code_Sets_SDE_Lighthouse_10_Crosbie" cs ON cs.code = e."SuppliedCode"
LEFT OUTER JOIN PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" dem ON dem."FK_Patient_ID" = e."FK_Patient_ID" -- join to demographics table to get GmPseudo
WHERE cs.concept IN ('myocardial-infarction', 'angina', 'tuberculosis', 'venous-thromboembolism', 
					'pneumonia', 'copd', 'emphysema', 'chronic-bronchitis', 'efi-mobility-problems', 'efi-vision-problems')
	AND e."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_10_Crosbie");

-- for each patient, find each comorbidity and the date of first diagnosis

DROP TABLE IF EXISTS OtherDiagsSummary;
CREATE TEMPORARY TABLE OtherDiagsSummary AS 
SELECT "GmPseudo", 
	concept, 
    MIN("DiagnosisDate") AS "FirstDiagnosisDate"   
FROM OtherDiags
GROUP BY "GmPseudo", concept;

-- convert to wide format ready to join to the standard LTCs

DROP TABLE IF EXISTS OtherDiagsSummaryWide;
CREATE TEMPORARY TABLE OtherDiagsSummaryWide AS
SELECT "GmPseudo",
	MAX(CASE WHEN concept = 'myocardial-infarction' THEN "FirstDiagnosisDate" ELSE null END) AS "MyocardialInfarction_DiagnosisDate",
	MAX(CASE WHEN concept = 'angina' THEN "FirstDiagnosisDate" ELSE null END) AS "Angina_DiagnosisDate",
	MAX(CASE WHEN concept = 'tuberculosis' THEN "FirstDiagnosisDate" ELSE null END) AS "Tuberculosis_DiagnosisDate",
	MAX(CASE WHEN concept = 'venous-thromboembolism' THEN "FirstDiagnosisDate" ELSE null END) AS "VenousThromboembolism_DiagnosisDate",
	MAX(CASE WHEN concept = 'pneumonia' THEN "FirstDiagnosisDate" ELSE null END) AS "Pneumonia_DiagnosisDate",
	MAX(CASE WHEN concept = 'copd' THEN "FirstDiagnosisDate" ELSE null END) AS "COPD_DiagnosisDate",
	MAX(CASE WHEN concept = 'emphysema' THEN "FirstDiagnosisDate" ELSE null END) AS "Emphysema_DiagnosisDate",
	MAX(CASE WHEN concept = 'chronic-bronchitis' THEN "FirstDiagnosisDate" ELSE null END) AS "ChronicBronchitis_DiagnosisDate",
	MAX(CASE WHEN concept = 'efi-mobility-problems' THEN "FirstDiagnosisDate" ELSE null END) AS "MobilityProblems_DiagnosisDate",
	MAX(CASE WHEN concept = 'efi-vision-problems' THEN "FirstDiagnosisDate" ELSE null END) AS "VisionProblems_DiagnosisDate" 
FROM OtherDiagsSummary
GROUP BY "GmPseudo";

-- FINAL TABLE JOIING TOGETHER THE STANDARD DIAGNOSES AND THE OTHERS


-- ... processing [[create-output-table::"2_Comorbidities"]] ... 
-- ... Need to create an output table called "2_Comorbidities" and replace 
-- ... the GmPseudo column with a study-specific random patient id.

-- First we create a table in an area only visible to the RDEs which contains
-- the GmPseudos. THESE CANNOT BE RELEASED TO END USERS.
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."2_Comorbidities_WITH_PSEUDO_IDS";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."2_Comorbidities_WITH_PSEUDO_IDS" AS
SELECT 
	ltc.*,
	ot."MyocardialInfarction_DiagnosisDate",
	ot."Angina_DiagnosisDate",
	ot."Tuberculosis_DiagnosisDate",
	ot."VenousThromboembolism_DiagnosisDate",
	ot."Pneumonia_DiagnosisDate",
	ot."COPD_DiagnosisDate" AS "COPD_DiagnosisDate_GMCRCodeSet", -- as there is a COPD code set in the standard LTC table, specify that this is the GMCR one
	ot."Emphysema_DiagnosisDate",
	ot."ChronicBronchitis_DiagnosisDate",
	ot."MobilityProblems_DiagnosisDate",
	ot."VisionProblems_DiagnosisDate"
FROM StandardLTCs ltc
LEFT JOIN OtherDiagsSummaryWide	 ot ON ot."GmPseudo" = ltc."GmPseudo";

-- Then we check to see if there are any new GmPseudo ids. We do this by making a temp table 
-- of all "new" GmPseudo ids. I.e. any GmPseudo ids that we've already got a unique id for
-- for this study are excluded
DROP TABLE IF EXISTS "AllPseudos_SDE_Lighthouse_10_Crosbie";
CREATE TEMPORARY TABLE "AllPseudos_SDE_Lighthouse_10_Crosbie" AS
SELECT DISTINCT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."2_Comorbidities_WITH_PSEUDO_IDS"
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
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."2_Comorbidities";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."2_Comorbidities" AS
SELECT SDE_REPOSITORY.SHARED_UTILITIES.gm_pseudo_hash_SDE_Lighthouse_10_Crosbie("GmPseudo") AS "PatientID", * EXCLUDE "GmPseudo"
FROM SDE_REPOSITORY.SHARED_UTILITIES."2_Comorbidities_WITH_PSEUDO_IDS";

