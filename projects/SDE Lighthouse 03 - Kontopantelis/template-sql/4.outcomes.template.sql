--┌───────────────────────────────────┐
--│ Outcomes for dementia cohort      │
--└───────────────────────────────────┘

---- RESEARCH DATA ENGINEER CHECK ----

--------------------------------------

-- OUTPUT: Data with the following fields
-- Patient Id
-- AdmissionDate (DD-MM-YYYY)
-- DischargeDate (DD-MM-YYYY)


--> EXECUTE query-build-lh003-cohort.sql

--> CODESET dementia-medication-review:1 dementia-care-review:1 medication-review-basic:1 dementia-care-plan:1
--> CODESET did-not-attend:1 carer:1
--> CODESET emergency-admission:1 delirium:1 fracture:1 falls:1
--> CODESET social-care-prescribing-referral:1 social-care-referral:1 safeguarding-referral:1


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
