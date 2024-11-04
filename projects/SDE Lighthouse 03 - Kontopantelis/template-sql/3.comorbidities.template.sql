--┌─────────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 03 - Kontopantelis - comorbidities │
--└─────────────────────────────────────────────────────────┘

-- From application:
--	Table 3: Comorbidities (using full date range available)
--		- PatientID
--		- Condition
--		- FirstDate
--		- LatestDate
--		- ConditionOccurences (number of times appeared)

-- NB1 - just using all the existing comorbidity data in the GP_Record schema.
-- NB2 - this is not the format initially requested, but likely what the team
--			 will transform it into. We can tell them this when providing the data
--			 and change it if required.

{{create-output-table::"LH003-3_Comorbidities"}}
SELECT
	"GmPseudo", "ADHD_DiagnosisDate", "Anorexia_DiagnosisDate", "Asthma_DiagnosisDate", 
	"AtrialFibrillation_DiagnosisDate", "Autism_DiagnosisDate", "BlindnessLowVision_DiagnosisDate", 
	"Bulimia_DiagnosisDate", "Cancer_DiagnosisDate", "ChronicKidneyDisease_DiagnosisDate", "ChronicLiverDisease_DiagnosisDate",
	"ChronicSinusitis_DiagnosisDate", "Constipation_DiagnosisDate", "COPD_DiagnosisDate", "CoronaryHeartDisease_DiagnosisDate",
	"DeafnessHearingLoss_DiagnosisDate", "Dementia_DiagnosisDate", "Depression_DiagnosisDate", "DiverticularDisease_DiagnosisDate", "DownsSyndrome_DiagnosisDate", "Eczema_DiagnosisDate",
	"Epilepsy_DiagnosisDate", "FamilialHypercholesterolemia_DiagnosisDate", "HeartFailure_DiagnosisDate",
	"Hypertension_DiagnosisDate", "LearningDisability_DiagnosisDate", "PainfulCondition_DiagnosisDate",
	"PalliativeCare_DiagnosisDate", "ParkinsonsDisease_DiagnosisDate", "PepticUlcerDisease_DiagnosisDate",
	"PeripheralArterialDisease_DiagnosisDate", "ProstateDisorder_DiagnosisDate", "Psoriasis_DiagnosisDate",
	"RheumatoidArthritis_DiagnosisDate", "Stroke_DiagnosisDate", "ThyroidDisorder_DiagnosisDate", "TIA_DiagnosisDate",
	"FirstLTC", "FirstLTC_DiagnosisDate", "SecondLTC", "SecondLTC_DiagnosisDate", "ThirdLTC",
	"ThirdLTC_DiagnosisDate", "FourthLTC", "FourthLTC_DiagnosisDate", "FifthLTC", "FifthLTC_DiagnosisDate"
FROM INTERMEDIATE.GP_RECORD."LongTermConditionRegister_SecondaryUses"
WHERE "GmPseudo" IN (SELECT "GmPseudo" FROM {{cohort-table}})
QUALIFY row_number() OVER (PARTITION BY "GmPseudo" ORDER BY "Snapshot" DESC) = 1; -- this brings back the values from the most recent snapshot