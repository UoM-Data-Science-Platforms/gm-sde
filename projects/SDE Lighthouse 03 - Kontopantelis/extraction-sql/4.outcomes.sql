--┌───────────────────────────────────┐
--│ Outcomes for dementia cohort      │
--└───────────────────────────────────┘

---- RESEARCH DATA ENGINEER CHECK ----

--------------------------------------

-- OUTPUT: Data with the following fields
-- Patient Id
-- AdmissionDate (DD-MM-YYYY)
-- DischargeDate (DD-MM-YYYY)


--┌───────────────────────────────────────────────────────────────────┐
--│ Define Cohort for LH003: patients that had a dementia diagnosis   │
--└───────────────────────────────────────────────────────────────────┘

-- OBJECTIVE: To build the cohort of patients needed for LH003. This reduces duplication of code in the template scripts.

-- COHORT: Any patient with a dementia diagnosis between start and end date.

-- INPUT: assumes there exists one temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: Temp tables as follows:
-- #Cohort

DROP TABLE IF EXISTS LH003_Cohort;
CREATE TEMPORARY TABLE LH003_Cohort (GmPseudo NUMBER(38,0), FirstDementiaDate DATE);
INSERT INTO LH003_Cohort VALUES 
(1763539,'2020-06-06'),(2926922,'2020-06-06'),(182597,'2020-06-06'),(1244665,'2020-06-06'),
(3134799,'2020-06-06'),(1544463,'2020-06-06'),(5678816,'2020-06-06'),(169030,'2020-06-06'),
(7015182,'2020-06-06'),(7089792,'2020-06-06');
-- TODO need to know schema where we can write this to

-- types are:



-- SELECT "GmPseudo", MIN("Dementia_DiagnosisDate") AS FirstDementiaDate
-- FROM PRESENTATION.GP_RECORD."LongTermConditionRegister_SecondaryUses"
-- WHERE "Dementia_DiagnosisDate" IS NOT NULL
-- AND "Age" >= 18
-- GROUP BY "GmPseudo"

--|> CODESET dementia-medication-review:1 dementia-care-review:1 medication-review-basic:1 dementia-care-plan:1
--|> CODESET did-not-attend:1 carer:1
--|> CODESET emergency-admission:1 delirium:1 fracture:1 falls:1
--|> CODESET social-care-prescribing-referral:1 social-care-referral:1 safeguarding-referral:1


-- essential
Dementia care review
Medication review (there are codes for medication review, structured medication review and dementia medication review – I can separate these out if useful) yes please separate if possible 
Advance care planning
Referral to social prescribing
Healthcare attendance (just primary care encounters, or hospital as well?) both if possible, and if separated
Unscheduled hospital admission
Delirium
Fall
Fracture

-- nice to have
Continuity of care measures* (??? Not sure if this is a thing likely to be coded, or a group of things that need separating out) This will be hard to measure, it's the number of consultaitons with the same provider as a proportion of all consultations - I think we can just leave this measure are may be too complex in this setting?
Carer type*
Carer review*
Referral to social care*
Referral to safeguarding*
Missed appointment*



--bring together for final output
SELECT 
	PatientId = gp.FK_Patient_Link_ID,
	EventDate = CONVERT(DATE, gp.EventDate),
	[concept] = CASE WHEN s.[concept] IS NOT NULL THEN s.[concept] ELSE c.[concept] END
FROM SharedCare.GP_Events gp
LEFT OUTER JOIN #VersionedSnomedSets s ON s.FK_Reference_SnomedCT_ID = gp.FK_Reference_SnomedCT_ID
LEFT OUTER JOIN #VersionedCodeSets c ON c.FK_Reference_Coding_ID = gp.FK_Reference_Coding_ID
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort) 
	AND (
		gp.FK_Reference_Coding_ID in (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept NOT IN ('dementia'))
		OR gp.FK_Reference_SnomedCT_ID in (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept NOT IN ('dementia'))
	)
AND EventDate BETWEEN @StartDate AND @EndDate

SELECT 
	"FK_Patient_ID" AS PatientID,
	CASE
		WHEN "Field_ID" = 'DEMCPRVW_COD' THEN 'Dementia care plan review'
		WHEN "Field_ID" = 'DEMCPRVWDEC_COD' THEN 'Patient chose not to have dementia care plan review'
		WHEN "Field_ID" = 'MEDRVW_COD' THEN 'Medication review'
		WHEN "Field_ID" = 'STRUCTMEDRVW_COD' THEN 'Structured medication review'
		WHEN "Field_ID" = 'STRMEDRWVDEC_COD' THEN 'Structured medication review declined'
		WHEN "Field_ID" = 'DEMMEDRVW_COD' THEN 'Dementia medication review'
		WHEN "Field_ID" = 'MEDRVWDEC_COD' THEN 'Patient chose not to have a medication review'
		WHEN "Field_ID" = 'SOCPRESREF_COD' THEN 'Referral to social prescribing'
	END AS OutcomeName,
	"EventDate" AS OutcomeDate
FROM INTERMEDIATE.GP_RECORD."EventsClusters"
WHERE "Field_ID" IN ('DEMCPRVW_COD','DEMCPRVWDEC_COD','MEDRVW_COD','STRUCTMEDRVW_COD','STRMEDRWVDEC_COD','DEMMEDRVW_COD','MEDRVWDEC_COD','SOCPRESREF_COD')
