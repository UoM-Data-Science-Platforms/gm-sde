--┌─────────────┐
--│ Cohort data │
--└─────────────┘

-- OUTPUT:
--  Patient ID
--  Sex
--  Year of Birth
--  Ethnicity
--  Townsend Score
--  GPPracticeCode
--  Date of Thyroid disorder diagnosis
--  Specific Hypothyroid disease Code (NB - as they might have more than one will put this into a new file #4)
--  Any other thyroid diagnoses (NB - as they might have more than one will put this into a new file #4)
--  BMI values (NB - as the request is for multiple values, these are moved to the longitudinal test result file)
--  Month of Death recorded (any causes)

-- Just want the output, not the messages
SET NOCOUNT ON;

-- Get the cohort of patients
--> EXECUTE query-build-rq065-cohort.sql
-- 2m30
--> EXECUTE query-build-rq065-cohort-events.sql
-- 2m08

--> EXECUTE query-patient-sex.sql
-- 26s
--> EXECUTE query-patient-lsoa.sql
-- 34s
--> EXECUTE query-patient-townsend.sql
-- 10s
--> EXECUTE query-patient-practice-and-ccg.sql
-- 42s

--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:hypothyroidism version:1 temp-table-name:#PatientHYPOTHYROIDISM
-- 7s

SELECT
	p.FK_Patient_Link_ID AS PatientId,
	sex.Sex,
	yob.YearOfBirth,
	pl.EthnicMainGroup AS Ethnicity,
	town.TownsendScoreHigherIsMoreDeprived,
  town.TownsendQuintileHigherIsMoreDeprived,
	pp.GPPracticeCode,
  hypo.DateOfFirstDiagnosis AS DateOfHypothyroidismDiagnosis,
  YEAR(pl.DeathDate) AS DeathDateYear,
	MONTH(pl.DeathDate) AS DeathDateMonth
FROM #Patients p
LEFT OUTER JOIN #PatientPractice pp ON pp.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientTownsend town ON town.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN SharedCare.Patient_Link pl ON pl.PK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientHYPOTHYROIDISM hypo ON hypo.FK_Patient_Link_ID = p.FK_Patient_Link_ID
--14s