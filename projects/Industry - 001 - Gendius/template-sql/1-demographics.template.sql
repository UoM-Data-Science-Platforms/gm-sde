--┌──────────────────────┐
--│ Patient demographics │
--└──────────────────────┘

-- OUTPUT: Data with the following fields
--  - PatientID
--  - Practice (P27001/P27001/etc..)
--  - 2019IMDDecile1IsMostDeprived10IsLeastDeprived (integer 1-10)
--  - QuarterOfBirth (YYYY-MM-DD)
--  - YearMonthOfT2DDiagnosis (earliest diagnosis date - YYYY-MM)
--  - Sex (M/F)
--  - Height (most recent)
--  - Ethnicity (suppressed grouping is sufficient)
--  - YearMonthFirstSGLT2i prescription
--  - YearMonthFirstACE-I prescription
--  - YearMonthFirstARB prescription
--  - YearMonthCKDstage 3-5 diagnosis (earliest diagnosis date)
--  - YearMonthHFdiagnosis (earliest diagnosis date)
--  - YearMonthCVDdiagnosis (earliest diagnosis date)
--  - YearMonthCancerdiagnosis (earliest diagnosis date)
--  - YearMonthDeath

--Just want the output, not the messages
SET NOCOUNT ON;

--> EXECUTE query-build-industry-001-cohort.sql extraction-date:2023-09-19

--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-year-of-birth.sql
--> EXECUTE query-patient-imd.sql
--> EXECUTE query-patient-practice-and-ccg.sql
--> EXECUTE query-get-height.sql all-patients:false gp-events-table:#PatientEventData

--> EXECUTE query-get-first-prescription.sql all-patients:false gp-medications-table:#PatientMedicationData code-set:ace-inhibitor version:2 temp-table-name:#PatientACEI
--> EXECUTE query-get-first-prescription.sql all-patients:false gp-medications-table:#PatientMedicationData code-set:angiotensin-receptor-blockers version:1 temp-table-name:#PatientARB
--> EXECUTE query-get-first-prescription.sql all-patients:false gp-medications-table:#PatientMedicationData code-set:sglt2-inhibitors version:1 temp-table-name:#PatientSGLT2i

--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:heart-failure version:1 temp-table-name:#PatientHF
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:cancer version:3 temp-table-name:#PatientCANCER

-- To get first CVD diagnosis we first find the earliest date for each CVD component
-- PI has requested: CHD, stroke, TIA, PAD, aortic aneurysm and heart failure (but we already have heart-failure from above)
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:coronary-heart-disease version:2 temp-table-name:#PatientCHD
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:stroke version:1 temp-table-name:#PatientSTROKE
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:tia version:1 temp-table-name:#PatientTIA
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:aortic-aneurysm version:1 temp-table-name:#PatientAA
--> EXECUTE query-get-first-diagnosis.sql all-patients:false gp-events-table:#PatientEventData code-set:peripheral-arterial-disease version:1 temp-table-name:#PatientPAD

-- Now bring together
IF OBJECT_ID('tempdb..#PatientCVD') IS NOT NULL DROP TABLE #PatientCVD;
SELECT FK_Patient_Link_ID, MIN(DateOfFirstDiagnosis) AS DateOfFirstDiagnosis
INTO #PatientCVD
FROM (
	SELECT FK_Patient_Link_ID, DateOfFirstDiagnosis FROM #PatientCHD
	UNION
	SELECT FK_Patient_Link_ID, DateOfFirstDiagnosis FROM #PatientSTROKE
	UNION
	SELECT FK_Patient_Link_ID, DateOfFirstDiagnosis FROM #PatientTIA
	UNION
	SELECT FK_Patient_Link_ID, DateOfFirstDiagnosis FROM #PatientAA
	UNION
	SELECT FK_Patient_Link_ID, DateOfFirstDiagnosis FROM #PatientPAD
	UNION
	SELECT FK_Patient_Link_ID, DateOfFirstDiagnosis FROM #PatientHF
) sub
GROUP BY FK_Patient_Link_ID;

SELECT
	p.FK_Patient_Link_ID AS PatientId,
	pp.GPPracticeCode,
	imd.IMD2019Decile1IsMostDeprived10IsLeastDeprived,
	yob.YearOfBirth,
	YEAR(t2d.DateOfFirstDiagnosis) AS FirstT2DYear,
	MONTH(t2d.DateOfFirstDiagnosis) AS FirstT2DMonth,
	sex.Sex,
	h.HeightInCentimetres,
	pl.EthnicMainGroup AS Ethnicity,
	YEAR(acei.FirstPrescriptionDate) AS FirstAceiYear,
	MONTH(acei.FirstPrescriptionDate) AS FirstAceiMonth,
	YEAR(arb.FirstPrescriptionDate) AS FirstArbYear,
	MONTH(arb.FirstPrescriptionDate) AS FirstArbMonth,
	YEAR(sglt2i.FirstPrescriptionDate) AS FirstSglt2iYear,
	MONTH(sglt2i.FirstPrescriptionDate) AS FirstSglt2iMonth,
	c.FirstCkdDiagnosisYear,
	c.FirstCkdDiagnosisMonth,
	YEAR(hf.DateOfFirstDiagnosis) AS FirstHFYear,
	MONTH(hf.DateOfFirstDiagnosis) AS FirstHFMonth,
	YEAR(cvd.DateOfFirstDiagnosis) AS FirstCVDYear,
	MONTH(cvd.DateOfFirstDiagnosis) AS FirstCVDMonth,
	YEAR(cancer.DateOfFirstDiagnosis) AS FirstCancerYear,
	MONTH(cancer.DateOfFirstDiagnosis) AS FirstCancerMonth,
  YEAR(c.DeathDate) AS DeathDateYear,
	MONTH(c.DeathDate) AS DeathDateMonth
FROM #Patients p
LEFT OUTER JOIN #Cohort c ON c.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientPractice pp ON pp.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientIMDDecile imd ON imd.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN SharedCare.Patient_Link pl ON pl.PK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientHeight h ON h.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientT2D t2d ON t2d.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientACEI acei ON acei.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientARB arb ON arb.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSGLT2i sglt2i ON sglt2i.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientHF hf ON hf.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientCANCER cancer ON cancer.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientCVD cvd ON cvd.FK_Patient_Link_ID = p.FK_Patient_Link_ID