--┌──────────────────────────────────────────────────┐
--│ SDE Lighthouse study 04 - Newman - comorbidities │
--└──────────────────────────────────────────────────┘

-- Requested all comorbidities from cprd cambridge code set. Will provide the list from the clusters.

--> EXECUTE query-build-lh004-cohort.sql

--> CODESET hepatitis-a:1 hepatitis-b:1 hepatitis-c:1 hepatitis-d:1 tuberculosis:1

CREATE TEMPORARY TABLE HepAndTuberculosisCodes AS
SELECT PatientID, EventDate, SuppliedCode
FROM GP_Events
WHERE SuppliedCode IN (SELECT code FROM AllCodes WHERE concept IN ('hepatitis-a','hepatitis-b','hepatitis-c','hepatitis-d','tuberculosis'));

CREATE TEMPORARY TABLE HepA AS
SELECT PatientID, MIN(EventDate) AS HepADate
FROM HepAndTuberculosisCodes
WHERE SuppliedCode IN (SELECT code FROM AllCodes WHERE concept IN ('hepatitis-a'))
GROUP BY PatientID;

CREATE TEMPORARY TABLE HepB AS
SELECT PatientID, MIN(EventDate) AS HepBDate
FROM HepAndTuberculosisCodes
WHERE SuppliedCode IN (SELECT code FROM AllCodes WHERE concept IN ('hepatitis-b'))
GROUP BY PatientID;

CREATE TEMPORARY TABLE HepC AS
SELECT PatientID, MIN(EventDate) AS HepCDate
FROM HepAndTuberculosisCodes
WHERE SuppliedCode IN (SELECT code FROM AllCodes WHERE concept IN ('hepatitis-c'))
GROUP BY PatientID;

CREATE TEMPORARY TABLE HepD AS
SELECT PatientID, MIN(EventDate) AS HepDDate
FROM HepAndTuberculosisCodes
WHERE SuppliedCode IN (SELECT code FROM AllCodes WHERE concept IN ('hepatitis-d'))
GROUP BY PatientID;

CREATE TEMPORARY TABLE Tuberculosis AS
SELECT PatientID, MIN(EventDate) AS TuberculosisDate
FROM HepAndTuberculosis
WHERE SuppliedCode IN (SELECT code FROM AllCodes WHERE concept IN ('tuberculosis'))
GROUP BY PatientID;

CREATE TEMPORARY TABLE HepAndTuberculosis AS
SELECT
	GmPseudo, 
	CASE WHEN HepA.PatientID IS NOT NULL THEN HepADate ELSE NULL END AS HepADate,
	CASE WHEN HepB.PatientID IS NOT NULL THEN HepBDate ELSE NULL END AS HepBDate,
	CASE WHEN HepC.PatientID IS NOT NULL THEN HepCDate ELSE NULL END AS HepCDate,
	CASE WHEN HepD.PatientID IS NOT NULL THEN HepDDate ELSE NULL END AS HepDDate,
	CASE WHEN Tuberculosis.PatientID IS NOT NULL THEN TuberculosisDate ELSE NULL END AS TuberculosisDate
FROM LH004_Cohort c
LEFT OUTER JOIN HepA ON HepA.PatientID = c.GmPseudo
LEFT OUTER JOIN HepB ON HepB.PatientID = c.GmPseudo
LEFT OUTER JOIN HepC ON HepC.PatientID = c.GmPseudo
LEFT OUTER JOIN HepD ON HepD.PatientID = c.GmPseudo
LEFT OUTER JOIN Tuberculosis ON Tuberculosis.PatientID = c.GmPseudo;

SELECT
	"GmPseudo", "ADHD_DiagnosisDate", "Anorexia_DiagnosisDate", "Anxiety_DiagnosisDate", "Asthma_DiagnosisDate", 
	"AtrialFibrillation_DiagnosisDate", "Autism_DiagnosisDate", "BlindnessLowVision_DiagnosisDate", "Bronchiectasis_DiagnosisDate", 
	"Bulimia_DiagnosisDate", "Cancer_DiagnosisDate", "ChronicKidneyDisease_DiagnosisDate", "ChronicLiverDisease_DiagnosisDate",
	"ChronicSinusitis_DiagnosisDate", "Constipation_DiagnosisDate", "COPD_DiagnosisDate", "CoronaryHeartDisease_DiagnosisDate",
	"DeafnessHearingLoss_DiagnosisDate", "Dementia_DiagnosisDate", "Depression_DiagnosisDate", "DiabetesType1_DiagnosisDate",
	"DiabetesType2_DiagnosisDate", "DiverticularDisease_DiagnosisDate", "DownsSyndrome_DiagnosisDate", "Eczema_DiagnosisDate",
	"Epilepsy_DiagnosisDate", "FamilialHypercholesterolemia_DiagnosisDate", "HeartFailure_DiagnosisDate", "HepADate", "HepBDate",
	"HepCDate", "HepDDate", "Hypertension_DiagnosisDate", "Immunosuppression_DiagnosisDate",
	"InflammatoryBowelDisease_Crohns_DiagnosisDate", "IrritableBowelSyndrome_DiagnosisDate", "LearningDisability_DiagnosisDate",
	"MentalHealth_SeriousMentalIllness_DiagnosisDate", "Migraine_DiagnosisDate", "MultipleSclerosis_DiagnosisDate",
	"NonDiabeticHyperglycemia_DiagnosisDate", "Obesity_DiagnosisDate", "Osteoporosis_DiagnosisDate", "PainfulCondition_DiagnosisDate",
	"PalliativeCare_DiagnosisDate", "ParkinsonsDisease_DiagnosisDate", "PepticUlcerDisease_DiagnosisDate",
	"PeripheralArterialDisease_DiagnosisDate", "ProstateDisorder_DiagnosisDate", "Psoriasis_DiagnosisDate",
	"RheumatoidArthritis_DiagnosisDate", "Stroke_DiagnosisDate", "ThyroidDisorder_DiagnosisDate", "TIA_DiagnosisDate",
	"TuberculosisDate", "FirstLTC", "FirstLTC_DiagnosisDate", "SecondLTC", "SecondLTC_DiagnosisDate", "ThirdLTC",
	"ThirdLTC_DiagnosisDate", "FourthLTC", "FourthLTC_DiagnosisDate", "FifthLTC", "FifthLTC_DiagnosisDate"
FROM HepAndTuberculosis h
LEFT OUTER JOIN GP_RECORD."LongTermConditionRegister_Diagnosis" ltc ON ltc.GmPseudo = h.GmPseudo
QUALIFY row_number() OVER (PARTITION BY "GmPseudo" ORDER BY "Snapshot" DESC) = 1; -- this brings back the values from the most recent snapshot