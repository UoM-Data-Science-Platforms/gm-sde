--┌──────────────────────────────────────────────────┐
--│ SDE Lighthouse study 04 - Newman - comorbidities │
--└──────────────────────────────────────────────────┘

-- From application:
--	Comorbidities from: https://www.phpc.cam.ac.uk/pcu/research/research-groups/crmh/cprd_cam/codelists/v11/ 
--	as well as tuberculosis, viral hepatitis (A, B, C and D) and antiphospholipid syndrome

--> CODESET hepatitis-a:1 hepatitis-b:1 hepatitis-c:1 hepatitis-d:1
--> CODESET tuberculosis:1 antiphospholipid-syndrome:1

DROP TABLE IF EXISTS LH004_HepAndTuberculosisCodes;
CREATE TEMPORARY TABLE LH004_HepAndTuberculosisCodes AS
SELECT "FK_Patient_ID", CAST("EventDate" AS DATE) AS "EventDate", "SuppliedCode"
FROM INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses"
WHERE "SuppliedCode" IN (
	SELECT code FROM {{code-set-table}} 
	WHERE concept IN ('hepatitis-a','hepatitis-b','hepatitis-c','hepatitis-d','tuberculosis','antiphospholipid-syndrome')
)
AND "FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM {{cohort-table}});

DROP TABLE IF EXISTS LH004_HepA;
CREATE TEMPORARY TABLE LH004_HepA AS
SELECT "FK_Patient_ID", MIN("EventDate") AS HepADate
FROM LH004_HepAndTuberculosisCodes
WHERE "SuppliedCode" IN (SELECT code FROM {{code-set-table}} WHERE concept IN ('hepatitis-a'))
GROUP BY "FK_Patient_ID";

DROP TABLE IF EXISTS LH004_HepB;
CREATE TEMPORARY TABLE LH004_HepB AS
SELECT "FK_Patient_ID", MIN("EventDate") AS HepBDate
FROM LH004_HepAndTuberculosisCodes
WHERE "SuppliedCode" IN (SELECT code FROM {{code-set-table}} WHERE concept IN ('hepatitis-b'))
GROUP BY "FK_Patient_ID";

DROP TABLE IF EXISTS LH004_HepC;
CREATE TEMPORARY TABLE LH004_HepC AS
SELECT "FK_Patient_ID", MIN("EventDate") AS HepCDate
FROM LH004_HepAndTuberculosisCodes
WHERE "SuppliedCode" IN (SELECT code FROM {{code-set-table}} WHERE concept IN ('hepatitis-c'))
GROUP BY "FK_Patient_ID";

DROP TABLE IF EXISTS LH004_HepD;
CREATE TEMPORARY TABLE LH004_HepD AS
SELECT "FK_Patient_ID", MIN("EventDate") AS HepDDate
FROM LH004_HepAndTuberculosisCodes
WHERE "SuppliedCode" IN (SELECT code FROM {{code-set-table}} WHERE concept IN ('hepatitis-d'))
GROUP BY "FK_Patient_ID";

DROP TABLE IF EXISTS LH004_Tuberculosis;
CREATE TEMPORARY TABLE LH004_Tuberculosis AS
SELECT "FK_Patient_ID", MIN("EventDate") AS TuberculosisDate
FROM LH004_HepAndTuberculosisCodes
WHERE "SuppliedCode" IN (SELECT code FROM {{code-set-table}} WHERE concept IN ('tuberculosis'))
GROUP BY "FK_Patient_ID";

DROP TABLE IF EXISTS LH004_AntiphospholipidSyndrome;
CREATE TEMPORARY TABLE LH004_AntiphospholipidSyndrome AS
SELECT "FK_Patient_ID", MIN("EventDate") AS AntiphospholipidSyndromeDate
FROM LH004_HepAndTuberculosisCodes
WHERE "SuppliedCode" IN (SELECT code FROM {{code-set-table}} WHERE concept IN ('antiphospholipid-syndrome'))
GROUP BY "FK_Patient_ID";

DROP TABLE IF EXISTS LH004_HepAndTuberculosis;
CREATE TEMPORARY TABLE LH004_HepAndTuberculosis AS
SELECT
	c."GmPseudo", 
	CASE WHEN hepa."FK_Patient_ID" IS NOT NULL THEN HepADate ELSE NULL END AS "HepA_DiagnosisDate",
	CASE WHEN hepb."FK_Patient_ID" IS NOT NULL THEN HepBDate ELSE NULL END AS "HepB_DiagnosisDate",
	CASE WHEN hepc."FK_Patient_ID" IS NOT NULL THEN HepCDate ELSE NULL END AS "HepC_DiagnosisDate",
	CASE WHEN hepd."FK_Patient_ID" IS NOT NULL THEN HepDDate ELSE NULL END AS "HepD_DiagnosisDate",
	CASE WHEN tuberculosis."FK_Patient_ID" IS NOT NULL THEN TuberculosisDate ELSE NULL END AS "Tuberculosis_DiagnosisDate",
	CASE WHEN antiphos."FK_Patient_ID" IS NOT NULL THEN AntiphospholipidSyndromeDate ELSE NULL END AS "AntiphospholipidSyndrome_DiagnosisDate"
FROM {{cohort-table}} c
LEFT OUTER JOIN LH004_HepA hepa ON hepa."FK_Patient_ID" = c."FK_Patient_ID"
LEFT OUTER JOIN LH004_HepB hepb ON hepb."FK_Patient_ID" = c."FK_Patient_ID"
LEFT OUTER JOIN LH004_HepC hepc ON hepc."FK_Patient_ID" = c."FK_Patient_ID"
LEFT OUTER JOIN LH004_HepD hepd ON hepd."FK_Patient_ID" = c."FK_Patient_ID"
LEFT OUTER JOIN LH004_Tuberculosis tuberculosis ON tuberculosis."FK_Patient_ID" = c."FK_Patient_ID"
LEFT OUTER JOIN LH004_AntiphospholipidSyndrome antiphos ON antiphos."FK_Patient_ID" = c."FK_Patient_ID";

DROP TABLE IF EXISTS {{project-schema}}."LH004-3_comorbidities";
CREATE TABLE {{project-schema}}."LH004-3_comorbidities" AS
SELECT
	h."GmPseudo" AS "PatientID", "ADHD_DiagnosisDate", "Anorexia_DiagnosisDate", "AntiphospholipidSyndrome_DiagnosisDate",
	"Anxiety_DiagnosisDate", "Asthma_DiagnosisDate", "AtrialFibrillation_DiagnosisDate", "Autism_DiagnosisDate",
	"BlindnessLowVision_DiagnosisDate", "Bronchiectasis_DiagnosisDate", "Bulimia_DiagnosisDate",
	"Cancer_DiagnosisDate", "ChronicKidneyDisease_DiagnosisDate", "ChronicLiverDisease_DiagnosisDate",
	"ChronicSinusitis_DiagnosisDate", "Constipation_DiagnosisDate", "COPD_DiagnosisDate", "CoronaryHeartDisease_DiagnosisDate",
	"DeafnessHearingLoss_DiagnosisDate", "Dementia_DiagnosisDate", "Depression_DiagnosisDate", "DiabetesType1_DiagnosisDate",
	"DiabetesType2_DiagnosisDate", "DiverticularDisease_DiagnosisDate", "DownsSyndrome_DiagnosisDate", "Eczema_DiagnosisDate",
	"Epilepsy_DiagnosisDate", "FamilialHypercholesterolemia_DiagnosisDate", "HeartFailure_DiagnosisDate", "HepA_DiagnosisDate",
	"HepB_DiagnosisDate",	"HepC_DiagnosisDate", "HepD_DiagnosisDate", "Hypertension_DiagnosisDate",
	"Immunosuppression_DiagnosisDate",	"InflammatoryBowelDisease_Crohns_DiagnosisDate",
	"IrritableBowelSyndrome_DiagnosisDate", "LearningDisability_DiagnosisDate",
	"MentalHealth_SeriousMentalIllness_DiagnosisDate", "Migraine_DiagnosisDate", "MultipleSclerosis_DiagnosisDate",
	"NonDiabeticHyperglycemia_DiagnosisDate", "Obesity_DiagnosisDate", "Osteoporosis_DiagnosisDate",
	"PainfulCondition_DiagnosisDate",	"PalliativeCare_DiagnosisDate", "ParkinsonsDisease_DiagnosisDate",
	"PepticUlcerDisease_DiagnosisDate", "PeripheralArterialDisease_DiagnosisDate", "ProstateDisorder_DiagnosisDate",
	"Psoriasis_DiagnosisDate", "RheumatoidArthritis_DiagnosisDate", "Stroke_DiagnosisDate", "ThyroidDisorder_DiagnosisDate",
	"TIA_DiagnosisDate",	"Tuberculosis_DiagnosisDate"
FROM LH004_HepAndTuberculosis h
LEFT OUTER JOIN INTERMEDIATE.GP_RECORD."LongTermConditionRegister_Diagnosis" ltc ON ltc."GmPseudo" = h."GmPseudo"
QUALIFY row_number() OVER (PARTITION BY ltc."GmPseudo" ORDER BY "Snapshot" DESC) = 1; -- this brings back the values from the most recent snapshot