--┌───────────────────────────────────┐
--│ Outcomes for dementia cohort      │
--└───────────────────────────────────┘

---- RESEARCH DATA ENGINEER CHECK ----

--------------------------------------

-- From application:
--  Table 4: Outcomes (2006 to present)
--  - PatientID
--  - OutcomeName (e.g. dementia care review, referral to social prescribing)
--  - OutcomeDate

--  Outcomes include: 
--  - Care processes
--      - dementia care reviews (INCLUDED HERE)
--      - anticholinergic medication burden (IN MEDICATION FILE)
--      - potentially inappropriate prescribing rates (IN MEDICATION FILE)
--      - antipsychotic use (IN MEDICATION FILE)
--      - medication review within 6 weeks of commencing an antipsychotic (INCLUDED HERE PLUS MEDICATION FILE)
--      - medication review (INCLUDED HERE)
--      - appropriate anti-dementia medication prescribing (IN MEDICATION FILE)
--      - advance care planning (NOT INCLUDED - WAS OPTIONAL FROM PI)
--      - continuity of care measures (NOT INCLUDED - WAS OPTIONAL FROM PI - ALSO WE DON'T HAVE CLINICIAN LEVEL DATA SO NOT POSSIBLE)
--      - carer type (NOT INCLUDED - WAS OPTIONAL FROM PI)
--      - carer review (NOT INCLUDED - WAS OPTIONAL FROM PI)
--      - referrals to social prescribing (INCLUDED HERE)
--      - social care referrals (INCLUDED HERE)
--      - safeguarding referrals (INCLUDED HERE)
--  - Healthcare utilisation factors:
--      - frequency of attendance  (INCLUDED HERE - gp encounter and hospital admission by type)
--      - missed appointments (NOT INCLUDED - WAS OPTIONAL FROM PI)
--  - Key adverse clinical outcomes: 
--      - All-cause mortality (IN THE PATIENTS FILE)
--      - unscheduled hospital admissions (INCLUDED HERE)
--      - delirium (INCLUDED HERE)
--      - falls (INCLUDED HERE)
--      - fractures (INCLUDED HERE)


set(StudyStartDate) = to_date('2006-01-01');
set(StudyEndDate)   = to_date('2024-06-30');

--TODO|> CODESET advance-care-planning:1
--> CODESET delirium:1 fracture:1 falls:1 social-care-referral:1 safeguarding-referral:1


DROP TABLE IF EXISTS "OutcomeCodes";
CREATE TEMPORARY TABLE "OutcomeCodes" AS
SELECT "GmPseudo", "SuppliedCode", to_date("EventDate") as "EventDate"
FROM {{cohort-table}} cohort
LEFT OUTER JOIN INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" events 
    ON events."FK_Patient_ID" = cohort."FK_Patient_ID"
WHERE "SuppliedCode" IN (SELECT code FROM {{code-set-table}} WHERE concept IN (
	'delirium','fracture','falls','social-care-referral','advance-care-planning','safeguarding-referral'
));

{{create-output-table::"LH003-4_Outcomes"}}
-- gp admissions
SELECT 
    contacts."GmPseudo", 
    'GP encounter' AS "OutcomeName", 
    contacts."EventDate" AS "OutcomeDate"
FROM INTERMEDIATE.GP_RECORD."Contacts_Proxy_Detail_SecondaryUses" contacts
WHERE contacts."Contact" = 1
    AND contacts."GmPseudo" IN (
        SELECT cohort."GmPseudo" FROM {{cohort-table}} cohort
    )
    AND contacts."EventDate" BETWEEN $StudyStartDate AND $StudyEndDate

UNION

-- Hospital admissions
SELECT TOP 100
    SUBSTRING(admissions."Der_Pseudo_NHS_Number", 2)::INT AS "GmPseudo",
    CASE
        -- [11] Elective Admission: Waiting list | [12] Elective Admission: Booked | [13] Elective Admission: Planned
        WHEN "Admission_Method" IN ('11','12','13') THEN 'Elective Hospital Admission'
        -- [21] Emergency Admission: Emergency Care or dental casualty department | [22] Emergency Admission: GP
        -- [23] Emergency Admission: Bed bureau | [24] Emergency Admission: Consultant Clinic
        -- [25] Emergency Admission: Mental Health Crisis Resolution Team
        -- [2A] Emergency Admission: Emergency Care Department of another provider where the PATIENT had not been admitted
        -- [2B] Emergency Admission: Transfer of an admitted PATIENT from another Hospital Provider in an emergency
        -- [2C] Emergency Admission: Baby born at home as intended | [2D] Emergency Admission: Other emergency admission
        -- [28] Emergency Admission: Other [being replaced by 2A-2D]
        WHEN "Admission_Method" IN ('21','22','23','24','25','2A','2B','2C','2D','28') THEN 'Emergency Hospital Admission'
        -- [31] Maternity Admission: Admitted ante partum | [32] Maternity Admission: Admitted post partum
        WHEN "Admission_Method" IN ('31','32') THEN 'Maternity Hospital Admission'
        -- [82] Other Admission: Birth of a baby within Health Care Provider | [83] Other Admission: Baby born outside the Health Care Provider
        WHEN "Admission_Method" IN ('82','83') THEN 'Other Hospital Admission - Birth of Baby'
        -- [81] Other Admission: Transfer of any admitted PATIENT from other Hospital Provider other than in an emergency
        WHEN "Admission_Method" = '81' THEN 'Non-emergency admission via hospital transfer'
    END,  -- "OutcomeName"
    TO_DATE(admissions."Admission_Date") AS "OutcomeDate"
FROM INTERMEDIATE.NATIONAL_FLOWS_APC."tbl_Data_SUS_APCS" admissions
WHERE SUBSTRING(admissions."Der_Pseudo_NHS_Number", 2)::INT IN (
        SELECT cohort."GmPseudo" FROM {{cohort-table}} cohort
    )
    AND TO_DATE(admissions."Admission_Date") BETWEEN $StudyStartDate AND $StudyEndDate

UNION

-- Events from GP_Events
SELECT 
    outcomes."GmPseudo",
    CASE
        WHEN c."CONCEPT"='delirium' THEN 'Delirium'
        WHEN c."CONCEPT"='fracture' THEN 'Fracture'
        WHEN c."CONCEPT"='falls' THEN 'Fall'
        WHEN c."CONCEPT"='social-care-referral' THEN 'Social Care Referral'
        WHEN c."CONCEPT"='advance-care-planning' THEN 'Advance Care Planning'
        WHEN c."CONCEPT"='safeguarding-referral' THEN 'Safeguarding Referral'
    END AS "OutcomeName",
    outcomes."EventDate" AS "OutcomeDate"
FROM "OutcomeCodes" outcomes
LEFT JOIN {{code-set-table}} c 
    ON c.code = outcomes."SuppliedCode"
WHERE outcomes."EventDate" BETWEEN $StudyStartDate AND $StudyEndDate

UNION

-- Events from REFSETs
SELECT 
    cohort."GmPseudo",
    CASE
        WHEN events."Field_ID" = 'DEMCPRVW_COD' THEN 'Dementia care plan review'
        WHEN events."Field_ID" = 'DEMCPRVWDEC_COD' THEN 'Patient chose not to have dementia care plan review'
        WHEN events."Field_ID" = 'MEDRVW_COD' THEN 'Medication review'
        WHEN events."Field_ID" = 'STRUCTMEDRVW_COD' THEN 'Structured medication review'
        WHEN events."Field_ID" = 'STRMEDRWVDEC_COD' THEN 'Structured medication review declined'
        WHEN events."Field_ID" = 'DEMMEDRVW_COD' THEN 'Dementia medication review'
        WHEN events."Field_ID" = 'MEDRVWDEC_COD' THEN 'Patient chose not to have a medication review'
        WHEN events."Field_ID" = 'SOCPRESREF_COD' THEN 'Referral to social prescribing'
    END AS "OutcomeName",
    TO_DATE(events."EventDate") AS "OutcomeDate"
FROM {{cohort-table}} cohort
LEFT JOIN INTERMEDIATE.GP_RECORD."Combined_EventsMedications_Clusters_SecondaryUses" events 
    ON events."FK_Patient_ID" = cohort."FK_Patient_ID"
WHERE events."Field_ID" IN (
        'DEMCPRVW_COD', 'DEMCPRVWDEC_COD', 'MEDRVW_COD', 'STRUCTMEDRVW_COD', 
        'STRMEDRWVDEC_COD', 'DEMMEDRVW_COD', 'MEDRVWDEC_COD', 'SOCPRESREF_COD'
    )
    AND TO_DATE(events."EventDate") BETWEEN $StudyStartDate AND $StudyEndDate;



