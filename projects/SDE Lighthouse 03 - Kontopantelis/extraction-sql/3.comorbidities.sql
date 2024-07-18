--┌─────────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 03 - Kontopantelis - comorbidities │
--└─────────────────────────────────────────────────────────┘

--┌───────────────────────────────────────────────────────────────────┐
--│ Define Cohort for LH003: patients that had a dementia diagnosis   │
--└───────────────────────────────────────────────────────────────────┘

-- OBJECTIVE: To build the cohort of patients needed for LH003. This reduces duplication of code in the template scripts.

-- COHORT: Any patient with a dementia diagnosis between start and end date.

-- INPUT: assumes there exists one temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: Temp tables as follows:
-- #Cohort

USE INTERMEDIATE.GP_RECORD;

DROP TABLE IF EXISTS LH003_Cohort;
CREATE TEMPORARY TABLE LH003_Cohort (GmPseudo NUMBER(38,0), FK_Patient_ID NUMBER(38,0), FirstDementiaDate DATE);
INSERT INTO LH003_Cohort VALUES 
(1763539,621461,'2020-06-06'),(2926922,3190449,'2020-06-06'),(182597,389047,'2020-06-06'),(1244665,2004259,'2020-06-06'),
(3134799,1954132,'2020-06-06'),(1544463,292350,'2020-06-06'),(5678816,1084994,'2020-06-06'),(169030,1023513,'2020-06-06'),
(7015182,293331,'2020-06-06'),(7089792,824405,'2020-06-06');

-- TODO need to know schema where we can write this to

-- types are:



-- SELECT "GmPseudo", MIN("Dementia_DiagnosisDate") AS FirstDementiaDate
-- FROM PRESENTATION.GP_RECORD."LongTermConditionRegister_SecondaryUses"
-- WHERE "Dementia_DiagnosisDate" IS NOT NULL
-- AND "Age" >= 18
-- GROUP BY "GmPseudo"

SELECT
	"GmPseudo", "ADHD_DiagnosisDate", "Anorexia_DiagnosisDate", "Anxiety_DiagnosisDate", "Asthma_DiagnosisDate", 
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
	"RheumatoidArthritis_DiagnosisDate", "Stroke_DiagnosisDate", "ThyroidDisorder_DiagnosisDate", "TIA_DiagnosisDate",
	"FirstLTC", "FirstLTC_DiagnosisDate", "SecondLTC", "SecondLTC_DiagnosisDate", "ThirdLTC",
	"ThirdLTC_DiagnosisDate", "FourthLTC", "FourthLTC_DiagnosisDate", "FifthLTC", "FifthLTC_DiagnosisDate"
FROM GP_RECORD."LongTermConditionRegister_Diagnosis"
WHERE "GmPseudo" IN (SELECT GmPseudo FROM LH003_Cohort)
QUALIFY row_number() OVER (PARTITION BY "GmPseudo" ORDER BY "Snapshot" DESC) = 1; -- this brings back the values from the most recent snapshot