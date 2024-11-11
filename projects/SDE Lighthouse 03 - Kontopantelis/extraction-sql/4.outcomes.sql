USE SCHEMA SDE_REPOSITORY.SHARED_UTILITIES;

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
set(StudyEndDate)   = to_date('2024-10-31');

--TODO|> CODESET advance-care-planning:1
-- >>> Codesets required... Inserting the code set code
-- >>> Codesets extracted into 0.code-sets.sql
-- >>> Following code sets injected: delirium v1/fracture v1/falls v1/social-care-referral v1/safeguarding-referral v1


DROP TABLE IF EXISTS "OutcomeCodes";
CREATE TEMPORARY TABLE "OutcomeCodes" AS
SELECT "GmPseudo", "SuppliedCode", to_date("EventDate") as "EventDate"
FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_03_Kontopantelis" cohort
LEFT OUTER JOIN INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" events 
    ON events."FK_Patient_ID" = cohort."FK_Patient_ID"
WHERE "SuppliedCode" IN (SELECT code FROM SDE_REPOSITORY.SHARED_UTILITIES."Code_Sets_SDE_Lighthouse_03_Kontopantelis" WHERE concept IN (
	'delirium','fracture','falls','social-care-referral','advance-care-planning','safeguarding-referral'
));


-- ... processing [[create-output-table::"LH003-4_Outcomes"]] ... 
-- ... Need to create an output table called "LH003-4_Outcomes" and replace 
-- ... the GmPseudo column with a study-specific random patient id.

-- First we create a table in an area only visible to the RDEs which contains
-- the GmPseudos. THESE CANNOT BE RELEASED TO END USERS.
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH003-4_Outcomes_WITH_PSEUDO_IDS";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH003-4_Outcomes_WITH_PSEUDO_IDS" AS
-- gp admissions
SELECT 
    contacts."GmPseudo", 
    'GP encounter' AS "OutcomeName", 
    contacts."EventDate" AS "OutcomeDate"
FROM INTERMEDIATE.GP_RECORD."Contacts_Proxy_Detail_SecondaryUses" contacts
WHERE contacts."Contact" = 1
    AND contacts."GmPseudo" IN (
        SELECT cohort."GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_03_Kontopantelis" cohort
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
        SELECT cohort."GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_03_Kontopantelis" cohort
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
LEFT JOIN SDE_REPOSITORY.SHARED_UTILITIES."Code_Sets_SDE_Lighthouse_03_Kontopantelis" c 
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
FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_03_Kontopantelis" cohort
LEFT JOIN INTERMEDIATE.GP_RECORD."Combined_EventsMedications_Clusters_SecondaryUses" events 
    ON events."FK_Patient_ID" = cohort."FK_Patient_ID"
WHERE events."Field_ID" IN (
        'DEMCPRVW_COD', 'DEMCPRVWDEC_COD', 'MEDRVW_COD', 'STRUCTMEDRVW_COD', 
        'STRMEDRWVDEC_COD', 'DEMMEDRVW_COD', 'MEDRVWDEC_COD', 'SOCPRESREF_COD'
    )
    AND TO_DATE(events."EventDate") BETWEEN $StudyStartDate AND $StudyEndDate;

-- Then we check to see if there are any new GmPseudo ids. We do this by making a temp table 
-- of all "new" GmPseudo ids. I.e. any GmPseudo ids that we've already got a unique id for
-- for this study are excluded
DROP TABLE IF EXISTS "AllPseudos_SDE_Lighthouse_03_Kontopantelis";
CREATE TEMPORARY TABLE "AllPseudos_SDE_Lighthouse_03_Kontopantelis" AS
SELECT DISTINCT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."LH003-4_Outcomes_WITH_PSEUDO_IDS"
EXCEPT
SELECT "GmPseudo" FROM "Patient_ID_Mapping_SDE_Lighthouse_03_Kontopantelis";

-- Find the highest currently assigned id. Ids are given incrementally, so now ones
-- need to start at +1 of the current highest
SET highestPatientId = (
    SELECT IFNULL(MAX("StudyPatientPseudoId"),0) FROM "Patient_ID_Mapping_SDE_Lighthouse_03_Kontopantelis"
);

-- Make a study specific hash for each new GmPseudo and insert it
-- into the patient lookup table
INSERT INTO "Patient_ID_Mapping_SDE_Lighthouse_03_Kontopantelis"
SELECT
    "GmPseudo", -- the GM SDE patient ids for patients in this cohort
    SHA2(CONCAT('SDE_Lighthouse_03_Kontopantelis', "GmPseudo")) AS "Hash", -- used to provide a random (study-specific) ordering for the patient ids we provide
    $highestPatientId + ROW_NUMBER() OVER (ORDER BY "Hash") -- the patient id that we provide to the analysts
FROM "AllPseudos_SDE_Lighthouse_03_Kontopantelis";

-- Finally, we select from the output table which includes the GmPseudos, in order
-- to populate the table for the end users where the GmPseudo fields are redacted via a function
-- created in the 0.code-sets.sql file
DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH003-4_Outcomes";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH003-4_Outcomes" AS
SELECT SDE_REPOSITORY.SHARED_UTILITIES.gm_pseudo_hash_SDE_Lighthouse_03_Kontopantelis("GmPseudo") AS "PatientID",
	* EXCLUDE "GmPseudo"
FROM SDE_REPOSITORY.SHARED_UTILITIES."LH003-4_Outcomes_WITH_PSEUDO_IDS";



