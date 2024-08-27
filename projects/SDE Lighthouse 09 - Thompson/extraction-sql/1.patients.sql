USE SDE_REPOSITORY.SHARED_UTILITIES;
--┌─────────────────────────────────────┐
--│ SDE Lighthouse study 09 - Thompson  │
--└─────────────────────────────────────┘

-- From appliction
--	Inclusion criteria
--	● Included within GMCR with up-to-standard data.
--	● All women aged between 30 years and 70 years that were alive in 2020.

-- Female sex aged 30-70
--  - PatientId
--  - YearAndMonthOfBirth
--  - YearAndMonthOfDeath
--  - Ethnicity
--  - LSOA
--  - IMD (deprivation decile, 1 to 10)
--  - Comorbidities (list here - https://www.phpc.cam.ac.uk/pcu/research/researchgroups/crmh/cprd_cam/codelists/v11/)

TODO currently setting year range to be 1950-1951 to keep cohort small for testing
NEEDS CHANGING

DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_09_Thompson";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_09_Thompson" AS
SELECT 
	cohort."GmPseudo",
	"FK_Patient_ID",
	YEAR("DateOfBirth") AS "YearOfBirth",
	"EthnicityLatest" AS "Ethnicity",
	"EthnicityLatest_Category" AS "EthnicityCategory",
	LSOA21 AS "LSOA",
	"IMD_Decile" AS "IMD2019Decile1IsMostDeprived10IsLeastDeprived"
FROM PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" cohort
LEFT OUTER JOIN PRESENTATION.NATIONAL_FLOWS_PCMD."DS1804_Pcmd" mortality
	ON mortality."GmPseudo" = cohort."GmPseudo"
WHERE cohort."Sex" = 'F'
AND (YEAR("RegisteredDateOfDeath") IS NULL OR YEAR("RegisteredDateOfDeath") >= 2020)
AND YEAR("DateOfBirth") BETWEEN 1950 AND 1951
QUALIFY row_number() OVER (PARTITION BY cohort."GmPseudo" ORDER BY "Snapshot" DESC) = 1;

DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH009-1_Patients";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH009-1_Patients" AS
SELECT
	c."GmPseudo" AS "PatientID", "YearOfBirth", "Ethnicity", "EthnicityCategory", "LSOA", "IMD2019Decile1IsMostDeprived10IsLeastDeprived",
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
FROM INTERMEDIATE.GP_RECORD."LongTermConditionRegister_Diagnosis" ltc
INNER JOIN SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_09_Thompson" c ON c."GmPseudo" = ltc."GmPseudo"
QUALIFY row_number() OVER (PARTITION BY ltc."GmPseudo" ORDER BY "Snapshot" DESC) = 1; -- this brings back the values from the most recent snapshot