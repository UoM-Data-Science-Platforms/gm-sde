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

--TODO|> CODESET advance-care-planning:1
--> CODESET delirium:1 fracture:1 falls:1 social-care-referral:1 safeguarding-referral:1


DROP TABLE IF EXISTS OutcomeCodes;
CREATE TEMPORARY TABLE OutcomeCodes AS
SELECT GmPseudo, "SuppliedCode", to_date("EventDate") as EventDate
FROM LH003_Cohort cohort
LEFT OUTER JOIN INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" events 
    ON events."FK_Patient_ID" = cohort.FK_Patient_ID
WHERE "SuppliedCode" IN (SELECT code FROM AllCodes WHERE concept IN (
	'delirium','fracture','falls','social-care-referral','advance-care-planning','safeguarding-referral'
));


-- -- essential
--DONE--REFSET Dementia care plan review
--DONE--REFSET Medication review (there are codes for medication review, structured medication review and dementia medication review – I can separate these out if useful) yes please separate if possible 
-- Advance care planning
--DONE--REFSET Referral to social prescribing
--DONE-- Healthcare attendance (just primary care encounters, or hospital as well?) both if possible, and if separated
--DONE-- Unscheduled hospital admission
--DONE-- Delirium
--DONE-- Fall
--DONE-- Fracture

-- -- nice to have
-- Continuity of care measures* (??? Not sure if this is a thing likely to be coded, or a group of things that need separating out) This will be hard to measure, it's the number of consultaitons with the same provider as a proportion of all consultations - I think we can just leave this measure are may be too complex in this setting?
-- Carer type*
-- Carer review*
--DONE-- Referral to social care*
--DONE-- Referral to safeguarding*
-- Missed appointment*

-- gp admissions
select "GmPseudo" AS "PatientID", 'GP encounter' AS "OutcomeName", "EventDate" AS "OutcomeDate"
from "Contacts_Proxy"
WHERE "GmPseudo" IN (SELECT GmPseudo FROM LH003_Cohort)
AND "EventDate" >= '2006-01-01'
UNION
-- hospital admissions
select top 100
    SUBSTRING("Der_Pseudo_NHS_Number", 2)::INT AS "GmPseudo",
    CASE
        WHEN "Admission_Method" IN ('11','12','13') THEN 'Elective Hospital Admission'
        -- WHEN "Admission_Method" = '11' THEN 'Elective Admission: Waiting list (11)'
        -- WHEN "Admission_Method" = '12' THEN 'Elective Admission: Booked (12)'
        -- WHEN "Admission_Method" = '13' THEN 'Elective Admission: Planned (13)'
        WHEN "Admission_Method" IN ('21','22','23','24','25','2A','2B','2C','2D','28') THEN 'Emergency Hospital Admission'
        -- WHEN "Admission_Method" = '21' THEN 'Emergency Admission: Emergency Care or dental casualty department (21)'
        -- WHEN "Admission_Method" = '22' THEN 'Emergency Admission: GP (22)'
        -- WHEN "Admission_Method" = '23' THEN 'Emergency Admission: Bed bureau (23)'
        -- WHEN "Admission_Method" = '24' THEN 'Emergency Admission: Consultant Clinic (24)'
        -- WHEN "Admission_Method" = '25' THEN 'Emergency Admission: Mental Health Crisis Resolution Team (25)'
        -- WHEN "Admission_Method" = '2A' THEN 'Emergency Admission: Emergency Care Department of another provider where the PATIENT had not been admitted (2A)'
        -- WHEN "Admission_Method" = '2B' THEN 'Emergency Admission: Transfer of an admitted PATIENT from another Hospital Provider in an emergency (2B)'
        -- WHEN "Admission_Method" = '2C' THEN 'Emergency Admission: Baby born at home as intended (2C)'
        -- WHEN "Admission_Method" = '2D' THEN 'Emergency Admission: Other emergency admission (2D)'
        -- WHEN "Admission_Method" = '28' THEN 'Emergency Admission: Other [being replaced by 2A-2D] (28)'
        WHEN "Admission_Method" IN ('31','32') THEN 'Maternity Hospital Admission'
        -- WHEN "Admission_Method" = '31' THEN 'Maternity Admission: Admitted ante partum (31)'
        -- WHEN "Admission_Method" = '32' THEN 'Maternity Admission: Admitted post partum (32)'
        WHEN "Admission_Method" IN ('82','83') THEN 'Other Hospital Admission - Birth of Baby'
        -- WHEN "Admission_Method" = '82' THEN 'Other Admission: Birth of a baby within Health Care Provider (82)'
        -- WHEN "Admission_Method" = '83' THEN 'Other Admission: Baby born outside the Health Care Provider (83)'
        WHEN "Admission_Method" = '81' THEN 'Non-emergency admission via hospital transfer'
        -- WHEN "Admission_Method" = '81' THEN 'Other Admission: Transfer of any admitted PATIENT from other Hospital Provider other than in an emergency (81)'
    END AS OutcomeName,
    TO_DATE("Admission_Date") AS OutcomeDate
from NATIONAL_FLOWS_APC."tbl_Data_SUS_APCS"
WHERE "GmPseudo" IN (SELECT GmPseudo FROM LH003_Cohort)
AND TO_DATE("Admission_Date") >= '2006-01-01'
UNION
-- Things we get from GP_Events
SELECT
    GmPseudo AS PatientID,
    CASE
        WHEN "SuppliedCode" IN (SELECT code FROM AllCodes WHERE concept='delirium') THEN 'Delirium'
        WHEN "SuppliedCode" IN (SELECT code FROM AllCodes WHERE concept='fracture') THEN 'Fracture'
        WHEN "SuppliedCode" IN (SELECT code FROM AllCodes WHERE concept='falls') THEN 'Fall'
        WHEN "SuppliedCode" IN (SELECT code FROM AllCodes WHERE concept='social-care-referral') THEN 'Social Care Referral'
        WHEN "SuppliedCode" IN (SELECT code FROM AllCodes WHERE concept='advance-care-planning') THEN 'Advance Care Planning'
        WHEN "SuppliedCode" IN (SELECT code FROM AllCodes WHERE concept='safeguarding-referral') THEN 'Safeguarding Referral'
    END AS OutcomeName,
    EventDate AS OutcomeDate
FROM OutcomeCodes
WHERE EventDate >= '2006-01-01'
UNION
-- Things we get from REFSETs
SELECT 
	GmPseudo,
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
	TO_DATE("EventDate")
FROM LH003_Cohort cohort
LEFT OUTER JOIN INTERMEDIATE.GP_RECORD."EventsClusters" events 
    ON events."FK_Patient_ID" = cohort.FK_Patient_ID
WHERE "Field_ID" IN ('DEMCPRVW_COD','DEMCPRVWDEC_COD','MEDRVW_COD','STRUCTMEDRVW_COD','STRMEDRWVDEC_COD','DEMMEDRVW_COD','MEDRVWDEC_COD','SOCPRESREF_COD')
AND TO_DATE("EventDate") >= '2006-01-01';


