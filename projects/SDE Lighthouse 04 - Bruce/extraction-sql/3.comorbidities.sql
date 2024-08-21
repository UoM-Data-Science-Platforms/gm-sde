--┌──────────────────────────────────────────────────┐
--│ SDE Lighthouse study 04 - Newman - comorbidities │
--└──────────────────────────────────────────────────┘

-- Requested all comorbidities from cprd cambridge code set. Will provide the list from the clusters.

--┌───────────────────────────────────────────────────────────────┐
--│ Define Cohort for LH004: patients that had an SLE diagnosis   │
--└───────────────────────────────────────────────────────────────┘

-- OBJECTIVE: To build the cohort of patients needed for LH004. This reduces duplication of code in the template scripts.

-- COHORT: Any patient with a SLE diagnosis between start and end date.

-- INPUT: None

-- OUTPUT: Temp tables as follows:
-- #Cohort

DECLARE @StudyStartDate datetime;
SET @StudyStartDate = '2020-01-01'; 

--┌───────────────────────────────────────────────────────────┐
--│ Create table of patients who are registered with a GM GP  │
--└───────────────────────────────────────────────────────────┘

-- INPUT REQUIREMENTS: @StudyStartDate

-- Find all patients alive at start date
IF OBJECT_ID('tempdb..#PossiblePatients') IS NOT NULL DROP TABLE #PossiblePatients;
SELECT PK_Patient_Link_ID as FK_Patient_Link_ID, EthnicMainGroup, EthnicGroupDescription, DeathDate INTO #PossiblePatients FROM [SharedCare].Patient_Link
WHERE 
	(DeathDate IS NULL OR (DeathDate >= @StudyStartDate))

-- Find all patients registered with a GP
IF OBJECT_ID('tempdb..#PatientsWithGP') IS NOT NULL DROP TABLE #PatientsWithGP;
SELECT DISTINCT FK_Patient_Link_ID INTO #PatientsWithGP FROM [SharedCare].Patient
where FK_Reference_Tenancy_ID = 2
AND GPPracticeCode NOT LIKE 'ZZZ%';

-- Make cohort from patients alive at start date and registered with a GP
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT pp.* INTO #Patients FROM #PossiblePatients pp
INNER JOIN #PatientsWithGP gp on gp.FK_Patient_Link_ID = pp.FK_Patient_Link_ID;

------------------------------------------

-- OUTPUT: #Patients
--┌───────────────┐
--│ Year of birth │
--└───────────────┘

-- OBJECTIVE: To get the year of birth for each patient.

-- INPUT: Assumes there exists a temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: A temp table as follows:
-- #PatientYearOfBirth (FK_Patient_Link_ID, YearOfBirth)
-- 	- FK_Patient_Link_ID - unique patient id
--	- YearOfBirth - INT

-- ASSUMPTIONS:
--	- Patient data is obtained from multiple sources. Where patients have multiple YOBs we determine the YOB as follows:
--	-	If the patients has a YOB in their primary care data feed we use that as most likely to be up to date
--	-	If every YOB for a patient is the same, then we use that
--	-	If there is a single most recently updated YOB in the database then we use that
--	-	Otherwise we take the highest YOB for the patient that is not in the future

-- Get all patients year of birth for the cohort
IF OBJECT_ID('tempdb..#AllPatientYearOfBirths') IS NOT NULL DROP TABLE #AllPatientYearOfBirths;
SELECT 
	FK_Patient_Link_ID,
	FK_Reference_Tenancy_ID,
	HDMModifDate,
	YEAR(Dob) AS YearOfBirth
INTO #AllPatientYearOfBirths
FROM SharedCare.Patient p
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND Dob IS NOT NULL;


-- If patients have a tenancy id of 2 we take this as their most likely YOB
-- as this is the GP data feed and so most likely to be up to date
IF OBJECT_ID('tempdb..#PatientYearOfBirth') IS NOT NULL DROP TABLE #PatientYearOfBirth;
SELECT FK_Patient_Link_ID, MIN(YearOfBirth) as YearOfBirth INTO #PatientYearOfBirth FROM #AllPatientYearOfBirths
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_Tenancy_ID = 2
GROUP BY FK_Patient_Link_ID
HAVING MIN(YearOfBirth) = MAX(YearOfBirth);

-- Find the patients who remain unmatched
IF OBJECT_ID('tempdb..#UnmatchedYobPatients') IS NOT NULL DROP TABLE #UnmatchedYobPatients;
SELECT FK_Patient_Link_ID INTO #UnmatchedYobPatients FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientYearOfBirth;

-- If every YOB is the same for all their linked patient ids then we use that
INSERT INTO #PatientYearOfBirth
SELECT FK_Patient_Link_ID, MIN(YearOfBirth) FROM #AllPatientYearOfBirths
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedYobPatients)
GROUP BY FK_Patient_Link_ID
HAVING MIN(YearOfBirth) = MAX(YearOfBirth);

-- Find any still unmatched patients
TRUNCATE TABLE #UnmatchedYobPatients;
INSERT INTO #UnmatchedYobPatients
SELECT FK_Patient_Link_ID FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientYearOfBirth;

-- If there is a unique most recent YOB then use that
INSERT INTO #PatientYearOfBirth
SELECT p.FK_Patient_Link_ID, MIN(p.YearOfBirth) FROM #AllPatientYearOfBirths p
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(HDMModifDate) MostRecentDate FROM #AllPatientYearOfBirths
	WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedYobPatients)
	GROUP BY FK_Patient_Link_ID
) sub ON sub.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND sub.MostRecentDate = p.HDMModifDate
GROUP BY p.FK_Patient_Link_ID
HAVING MIN(YearOfBirth) = MAX(YearOfBirth);

-- Find any still unmatched patients
TRUNCATE TABLE #UnmatchedYobPatients;
INSERT INTO #UnmatchedYobPatients
SELECT FK_Patient_Link_ID FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientYearOfBirth;

-- Otherwise just use the highest value (with the exception that can't be in the future)
INSERT INTO #PatientYearOfBirth
SELECT FK_Patient_Link_ID, MAX(YearOfBirth) FROM #AllPatientYearOfBirths
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedYobPatients)
GROUP BY FK_Patient_Link_ID
HAVING MAX(YearOfBirth) <= YEAR(GETDATE());

-- Tidy up - helpful in ensuring the tempdb doesn't run out of space mid-query
DROP TABLE #AllPatientYearOfBirths;
DROP TABLE #UnmatchedYobPatients;

-- >>> Codesets required... Inserting the code set code
-- >>> Codesets extracted into 0.code-sets.sql
-- >>> Following code sets injected: sle v1

------- EXCLUSIONS: PI wants to exclude the following: lupus pernio, neonatal lupus, drug-induced lupus, tuberculosis, cutaneous lupus without a corresponding 
------- systemic diagnosis, codes relating to a diagnostic test

------- lupus pernio, drug-induced lupus, and neonatal lupus code sets have been created - but prevalence suggests they are unused


-- >>> Following code sets injected: tuberculosis v1

-- table of sle coding events

IF OBJECT_ID('tempdb..#SLECodes') IS NOT NULL DROP TABLE #SLECodes;
SELECT FK_Patient_Link_ID, EventDate
INTO #SLECodes
FROM SharedCare.[GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'sle' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'sle' AND Version = 1)
)
GROUP BY FK_Patient_Link_ID, EventDate

-- table of patients that meet the exclusion criteria: turberculosis, lupus pernio, drug-induced lupus, neonatal lupus

IF OBJECT_ID('tempdb..#Exclusions') IS NOT NULL DROP TABLE #Exclusions;
SELECT FK_Patient_Link_ID AS PatientId, EventDate
INTO #Exclusions
FROM SharedCare.[GP_Events]
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'tuberculosis' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'tuberculosis' AND Version = 1)
)
GROUP BY FK_Patient_Link_ID, EventDate


-- create cohort of patients with an SLE diagnosis in the study period

IF OBJECT_ID('tempdb..#Cohort') IS NOT NULL DROP TABLE #Cohort;
SELECT
	 p.FK_Patient_Link_ID
	,yob.YearOfBirth
	,p.EthnicGroupDescription
	,p.DeathDate
INTO #Cohort
FROM #Patients p
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE 
	p.FK_Patient_Link_ID IN (SELECT DISTINCT FK_Patient_Link_ID FROM #SLECodes)
	AND p.FK_Patient_Link_ID NOT IN (SELECT DISTINCT FK_Patient_Link_ID FROM #Exclusions)
AND 2020 - YearOfBirth > 18

---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------


-- >>> Following code sets injected: hepatitis-a v1/hepatitis-b v1/hepatitis-c v1/hepatitis-d v1/tuberculosis v1

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