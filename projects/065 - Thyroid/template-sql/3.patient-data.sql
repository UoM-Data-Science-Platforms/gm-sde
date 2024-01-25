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
--> EXECUTE query-build-rq065-cohort-events.sql

--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-year-of-birth.sql
--> EXECUTE query-patient-lsoa.sql
--> EXECUTE query-patient-townsend.sql
--> EXECUTE query-patient-practice-and-ccg.sql

--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:hypothyroidism version:1 temp-table-name:#PatientHYPOTHYROIDISM

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
