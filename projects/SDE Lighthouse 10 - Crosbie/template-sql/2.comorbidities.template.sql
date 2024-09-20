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
FROM GP_RECORD."LongTermConditionRegister_Diagnosis"
WHERE "GmPseudo" IN (SELECT "GmPseudo" FROM {{cohort-table}})
QUALIFY row_number() OVER (PARTITION BY "GmPseudo" ORDER BY "Snapshot" DESC) = 1; -- this brings back the values from the most recent snapshot

-- load codesets for conditions not in above LTC table

--> CODESET myocardial-infarction:1 angina:1 tuberculosis:1 venous-thromboembolism:1 pneumonia:1 copd:1 efi-mobility-problems:1 efi-vision-problems:1

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
LEFT JOIN {{code-set-table}} cs ON cs.code = e."SuppliedCode"
LEFT OUTER JOIN PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" dem ON dem."FK_Patient_ID" = co."FK_Patient_ID" -- join to demographics table to get GmPseudo
WHERE cs.concept IN ('myocardial-infarction', 'angina', 'tuberculosis', 'venous-thromboembolism', 'pneumonia', 'copd', 'efi-mobility-problems', 'efi-vision-problems')
	AND "FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM {{cohort-table}});

-- for each patient, find each comorbidity and the date of first diagnosis

DROP TABLE IF EXISTS OtherDiagsSummary;
CREATE TABLE AS 
SELECT "GmPseudo", 
	concept, MIN("DiagnosisDate") AS "FirstDiagnosisDate"   
FROM OtherDiags
GROUP BY "GmPseudo", concept

-- convert to wide format ready to join to the standard LTCs

DROP TABLE IF EXISTS OtherDiagsSummaryWide;
CREATE TEMPORARY TABLE OtherDiagsSummaryWide
SELECT "GmPseudo",
	CASE WHEN concept = 'myocardial-infarction' THEN "FirstDiagnosisDate" ELSE 0 END AS "MyocardialInfarction_DiagnosisDate",
	CASE WHEN concept = 'angina' THEN "FirstDiagnosisDate" ELSE 0 END AS "Angina_DiagnosisDate",
	CASE WHEN concept = 'tuberculosis' THEN "FirstDiagnosisDate" ELSE 0 END AS "Tuberculosis_DiagnosisDate",
	CASE WHEN concept = 'venous-thromboembolism' THEN "FirstDiagnosisDate" ELSE 0 END AS "VenousThromboembolism_DiagnosisDate",
	CASE WHEN concept = 'pneumonia' THEN "FirstDiagnosisDate" ELSE 0 END AS "Pneumonia_DiagnosisDate",
	CASE WHEN concept = 'copd' THEN "FirstDiagnosisDate" ELSE 0 END AS "COPD_DiagnosisDate",
	CASE WHEN concept = 'efi-mobility-problems' THEN "MobilityProblems" ELSE 0 END AS "MobilityProblems_DiagnosisDate",
	CASE WHEN concept = 'efi-vision-problems' THEN "VisionProblems" ELSE 0 END AS "VisionProblems_DiagnosisDate"
FROM OtherDiagsSummary
GROUP BY "GmPseudo";


-- FINAL TABLE JOIING TOGETHER THE STANDARD DIAGNOSES AND THE OTHERS

{{create-output-table::"2_Comorbidities"}}
SELECT 
	ltc.*,
	ot."MyocardialInfarction_DiagnosisDate",
	ot."Angina_DiagnosisDate",
	ot."Tuberculosis_DiagnosisDate",
	ot."VenousThromboembolism_DiagnosisDate",
	ot."Pneumonia_DiagnosisDate",
	ot."COPD_DiagnosisDate" AS "COPD_DiagnosisDateGMCRCodeSet",
	ot."MobilityProblems_DiagnosisDate",
	ot."VisionProblems_DiagnosisDate"
FROM StandardLTCs ltc
LEFT JOIN OtherDiagsSummaryWide	 ot ON ot."GmPseudo" = ltc."GmPseudo";

