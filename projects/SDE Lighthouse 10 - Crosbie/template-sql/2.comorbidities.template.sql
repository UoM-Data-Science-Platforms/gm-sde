--┌───────────────────────────────────────────────────┐
--│ SDE Lighthouse study 10 - Crosbie - comorbidities │
--└───────────────────────────────────────────────────┘

set(StudyStartDate) = to_date('2016-01-01');
set(StudyEndDate)   = to_date('2024-08-01');

DROP TABLE IF EXISTS StandardLTCs;
CREATE TEMPORARY TABLE StandardLTCs AS
SELECT
	"GmPseudo",
	"ADHD_DiagnosisDate", "Anorexia_DiagnosisDate", "Anxiety_DiagnosisDate", "Asthma_DiagnosisDate", 
	"AtrialFibrillation_DiagnosisDate", "Autism_DiagnosisDate", "BlindnessLowVision_DiagnosisDate", "Bronchiectasis_DiagnosisDate", 
	"Bulimia_DiagnosisDate", "Cancer_DiagnosisDate", "ChronicKidneyDisease_DiagnosisDate", "ChronicLiverDisease_DiagnosisDate",
	"ChronicSinusitis_DiagnosisDate", "Constipation_DiagnosisDate", "CoronaryHeartDisease_DiagnosisDate",
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
	"LTCCount_CambridgeMultimorbidityScore","CambridgeMultimorbidityScoreWeight_Consultations", "CambridgeMultimorbidityScoreWeight_Mortality",
	"CambridgeMultimorbidityScoreWeight_EmergencyAdmissions", "CambridgeMultimorbidityScoreWeight_General", "CambridgeMultimorbidityScoreSegment"
FROM INTERMEDIATE.GP_RECORD."LongTermConditionRegister_SecondaryUses"
WHERE "GmPseudo" IN (SELECT "GmPseudo" FROM {{cohort-table}})
	AND "Snapshot" <= $StudyEndDate
QUALIFY row_number() OVER (PARTITION BY "GmPseudo" ORDER BY "Snapshot" DESC) = 1; -- this brings back the values from the most recent snapshot

-- load codesets for conditions not in above LTC table

--> CODESET myocardial-infarction:1 angina:1 tuberculosis:1 venous-thromboembolism:1 pneumonia:1 copd:1 emphysema:1 chronic-bronchitis:1 efi-mobility-problems:1

--  create table of conditions not included in LTC table

DROP TABLE IF EXISTS OtherDiags ;
CREATE TEMPORARY TABLE OtherDiags AS
SELECT DISTINCT
	e."FK_Patient_ID"
	, dem."GmPseudo"
	, to_date("Date") AS "DiagnosisDate"
	, e."SCTID" AS "SnomedCode"
	, cs.concept
	, e."Term" AS "Description"
FROM INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" e
LEFT JOIN {{code-set-table}} cs ON cs.code = e."SuppliedCode"
LEFT OUTER JOIN PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" dem ON dem."FK_Patient_ID" = co."FK_Patient_ID" -- join to demographics table to get GmPseudo
WHERE cs.concept IN ('myocardial-infarction', 'angina', 'tuberculosis', 'venous-thromboembolism', 'pneumonia', 'copd', 'emphysema', 'chronic-bronchitis', 'efi-mobility-problems' )
	AND "FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM {{cohort-table}})
	AND "Date" <= $StudyEndDate;

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
	CASE WHEN concept = 'emphysema' THEN "FirstDiagnosisDate" ELSE 0 END AS "Emphysema_DiagnosisDate",
	CASE WHEN concept = 'chronic-bronchitis' THEN "FirstDiagnosisDate" ELSE 0 END AS "ChronicBronchitis_DiagnosisDate",
	CASE WHEN concept = 'efi-mobility-problems' THEN "MobilityProblems" ELSE 0 END AS "MobilityProblems_DiagnosisDate"
FROM OtherDiagsSummary
GROUP BY "GmPseudo";


-- FINAL TABLE JOIING TOGETHER THE STANDARD DIAGNOSES AND THE OTHERS

{{create-output-table::"LH010-2_Comorbidities"}}
SELECT 
	ltc.*,
	ot."MyocardialInfarction_DiagnosisDate",
	ot."Angina_DiagnosisDate",
	ot."Tuberculosis_DiagnosisDate",
	ot."VenousThromboembolism_DiagnosisDate",
	ot."Pneumonia_DiagnosisDate",
	ot."COPD_DiagnosisDate" AS "COPD_DiagnosisDate",
	ot."Emphysema_DiagnosisDate" AS "Emphysema_DiagnosisDate",
	ot."ChronicBronchitis_DiagnosisDate" AS "ChronicBronchitis_DiagnosisDate",
	ot."MobilityProblems_DiagnosisDate"
FROM StandardLTCs ltc
LEFT JOIN OtherDiagsSummaryWide	 ot ON ot."GmPseudo" = ltc."GmPseudo";

