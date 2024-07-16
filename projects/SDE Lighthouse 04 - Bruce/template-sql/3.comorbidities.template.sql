--┌──────────────────────────────────────────────────┐
--│ SDE Lighthouse study 04 - Newman - comorbidities │
--└──────────────────────────────────────────────────┘

-- Requested all comorbidities from cprd cambridge code set. Will provide the list from the clusters.

--> EXECUTE query-build-lh004-cohort.sql

SELECT
	"GmPseudo", "ADHD_DiagnosisDate", "ADHD_DiagnosisAge", "Anorexia_DiagnosisDate", "Anorexia_DiagnosisAge", 
	"Anxiety_DiagnosisDate", "Anxiety_DiagnosisAge", "Asthma_DiagnosisDate", "Asthma_DiagnosisAge",
	"AtrialFibrillation_DiagnosisDate", "AtrialFibrillation_DiagnosisAge", "Autism_DiagnosisDate", "Autism_DiagnosisAge",
	"BlindnessLowVision_DiagnosisDate", "BlindnessLowVision_DiagnosisAge", "Bronchiectasis_DiagnosisDate", "Bronchiectasis_DiagnosisAge",
	"Bulimia_DiagnosisDate", "Bulimia_DiagnosisAge", "Cancer_DiagnosisDate", "Cancer_DiagnosisAge",
	"ChronicKidneyDisease_DiagnosisDate", "ChronicKidneyDisease_DiagnosisAge",
	"ChronicLiverDisease_DiagnosisDate", "ChronicLiverDisease_DiagnosisAge", "ChronicSinusitis_DiagnosisDate", "ChronicSinusitis_DiagnosisAge",
	"Constipation_DiagnosisDate", "Constipation_DiagnosisAge", "COPD_DiagnosisDate", "COPD_DiagnosisAge",
	"CoronaryHeartDisease_DiagnosisDate", "CoronaryHeartDisease_DiagnosisAge", "DeafnessHearingLoss_DiagnosisDate", "DeafnessHearingLoss_DiagnosisAge",
	"Dementia_DiagnosisDate", "Dementia_DiagnosisAge", "Depression_DiagnosisDate", "Depression_DiagnosisAge",
	"DiabetesType1_DiagnosisDate", "DiabetesType1_DiagnosisAge", "DiabetesType2_DiagnosisDate", "DiabetesType2_DiagnosisAge",
	"DiverticularDisease_DiagnosisDate", "DiverticularDisease_DiagnosisAge", "DownsSyndrome_DiagnosisDate", "DownsSyndrome_DiagnosisAge",
	"Eczema_DiagnosisDate", "Eczema_DiagnosisAge", "Epilepsy_DiagnosisDate", "Epilepsy_DiagnosisAge",
	"FamilialHypercholesterolemia_DiagnosisDate", "FamilialHypercholesterolemia_DiagnosisAge",
	"HeartFailure_DiagnosisDate", "HeartFailure_DiagnosisAge", "Hypertension_DiagnosisDate", "Hypertension_DiagnosisAge",
	"Immunosuppression_DiagnosisDate", "Immunosuppression_DiagnosisAge",
	"InflammatoryBowelDisease_Crohns_DiagnosisDate", "InflammatoryBowelDisease_Crohns_DiagnosisAge",
	"IrritableBowelSyndrome_DiagnosisDate", "IrritableBowelSyndrome_DiagnosisAge",
	"LearningDisability_DiagnosisDate", "LearningDisability_DiagnosisAge",
	"MentalHealth_SeriousMentalIllness_DiagnosisDate", "MentalHealth_SeriousMentalIllness_DiagnosisAge",
	"Migraine_DiagnosisDate", "Migraine_DiagnosisAge", "MultipleSclerosis_DiagnosisDate", "MultipleSclerosis_DiagnosisAge",
	"NonDiabeticHyperglycemia_DiagnosisDate", "NonDiabeticHyperglycemia_DiagnosisAge", "Obesity_DiagnosisDate", "Obesity_DiagnosisAge",
	"Osteoporosis_DiagnosisDate", "Osteoporosis_DiagnosisAge", "PainfulCondition_DiagnosisDate", "PainfulCondition_DiagnosisAge",
	"PalliativeCare_DiagnosisDate", "PalliativeCare_DiagnosisAge", "ParkinsonsDisease_DiagnosisDate", "ParkinsonsDisease_DiagnosisAge",
	"PepticUlcerDisease_DiagnosisDate", "PepticUlcerDisease_DiagnosisAge",
	"PeripheralArterialDisease_DiagnosisDate", "PeripheralArterialDisease_DiagnosisAge",
	"ProstateDisorder_DiagnosisDate", "ProstateDisorder_DiagnosisAge", "Psoriasis_DiagnosisDate", "Psoriasis_DiagnosisAge",
	"RheumatoidArthritis_DiagnosisDate", "RheumatoidArthritis_DiagnosisAge", "Stroke_DiagnosisDate", "Stroke_DiagnosisAge",
	"ThyroidDisorder_DiagnosisDate", "ThyroidDisorder_DiagnosisAge", "TIA_DiagnosisDate", "TIA_DiagnosisAge",
	"FirstLTC", "FirstLTC_DiagnosisDate", "FirstLTC_DiagnosisAge", "SecondLTC", "SecondLTC_DiagnosisDate", "SecondLTC_DiagnosisAge",
	"ThirdLTC", "ThirdLTC_DiagnosisDate", "ThirdLTC_DiagnosisAge", "FourthLTC", "FourthLTC_DiagnosisDate", "FourthLTC_DiagnosisAge",
	"FifthLTC", "FifthLTC_DiagnosisDate", "FifthLTC_DiagnosisAge"
FROM GP_RECORD."LongTermConditionRegister_Diagnosis"
QUALIFY row_number() OVER (PARTITION BY "GmPseudo" ORDER BY "Snapshot" DESC) = 1 -- this brings back the values from the most recent snapshot