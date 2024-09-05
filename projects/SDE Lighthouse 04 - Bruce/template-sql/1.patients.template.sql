--┌────────────────────────────────────┐
--│ LH004 Patient file                 │
--└────────────────────────────────────┘

-- From application:
--	Data File 1: Patient Demographics
--	- PatientId
--	- Sex
--	- YearOfBirth
--	- Ethnicity
--	- IMDQuartile
--	- SmokerEver
--	- SmokerCurrent
--	- BMI
--	- AlcoholIntake
--	- DateOfSLEdiagnosis
--	- DateOfLupusNephritisDiagnosis
--	- CKDStage
--	- EgfrResult
--	- EgfrDate
--	- CreatinineResult
--	- CreatinineDate
--	-	LDLCholesterol
--	- LDLCholesterolDate
--	-	HDLCholesterol
--	- HDLCholesterolDate
--	-	Triglycerides
--	- TrigylceridesDate 
-- 
--	All values need most recent value

-- smoking, alcohol are based on most recent codes available

-- Data file 7 - mortality - include here
-- From application:
--  DeathDate
--  CauseOfDeath

-- Find all patients with SLE
--> CODESET sle:1
DROP TABLE IF EXISTS LH004_SLE_Dx;
CREATE TEMPORARY TABLE LH004_SLE_Dx AS
SELECT "FK_Patient_ID", MIN(CAST("EventDate" AS DATE)) AS "FirstSLEDiagnosis"
FROM INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses"
WHERE "SuppliedCode" IN (SELECT code FROM {{code-set-table}} WHERE concept = 'sle')
GROUP BY "FK_Patient_ID";

-- Create a temporary cohort table to link gmpseudo with fk_patient_id
-- but also get the other columns required from the demographic table
DROP TABLE IF EXISTS {{cohort-table}};
CREATE TABLE {{cohort-table}} AS
SELECT
	"GmPseudo",
	lh."FK_Patient_ID",
	"FirstSLEDiagnosis",
	"Sex",
	YEAR("DateOfBirth") AS "YearOfBirth",
	"EthnicityLatest" AS "Ethnicity",
	"EthnicityLatest_Category" AS "EthnicityCategory",
	"IMD_Decile" AS "IMD2019Decile1IsMostDeprived10IsLeastDeprived",
	"SmokingStatus",
	"SmokingConsumption",
	"BMI",
	"BMI_Date" AS "BMIDate",
	"AlcoholStatus",
	"AlcoholConsumption",
FROM PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" demo
INNER JOIN LH004_SLE_Dx lh ON lh."FK_Patient_ID" = demo."FK_Patient_ID"
QUALIFY row_number() OVER (PARTITION BY demo."GmPseudo" ORDER BY "Snapshot" DESC) = 1;


-- Get eGFRs
DROP TABLE IF EXISTS LH004_eGFR;
CREATE TEMPORARY TABLE LH004_eGFR AS
SELECT DISTINCT "GmPseudo", 
    last_value("eGFR") OVER (PARTITION BY "GmPseudo" ORDER BY "EventDate") AS "eGFRValue", 
    last_value(CAST("EventDate" AS DATE)) OVER (PARTITION BY "GmPseudo" ORDER BY "EventDate") AS "eGFRDate"
FROM INTERMEDIATE.GP_RECORD."Readings_eGFR"
WHERE "GmPseudo" IN (SELECT "GmPseudo" FROM {{cohort-table}});

-- Get creatinine
DROP TABLE IF EXISTS LH004_creatinine;
CREATE TEMPORARY TABLE LH004_creatinine AS
SELECT DISTINCT "GmPseudo", 
    last_value("SerumCreatinine") OVER (PARTITION BY "GmPseudo" ORDER BY "EventDate") AS "SerumCreatinineValue", 
    last_value(CAST("EventDate" AS DATE)) OVER (PARTITION BY "GmPseudo" ORDER BY "EventDate") AS "SerumCreatinineDate"
FROM INTERMEDIATE.GP_RECORD."Readings_SerumCreatinine"
WHERE "GmPseudo" IN (SELECT "GmPseudo" FROM {{cohort-table}});

-- Get hdl cholesterol
DROP TABLE IF EXISTS LH004_hdl;
CREATE TEMPORARY TABLE LH004_hdl AS
SELECT DISTINCT "GmPseudo", 
    last_value("HDL") OVER (PARTITION BY "GmPseudo" ORDER BY "EventDate") AS "HDLValue", 
    last_value(CAST("EventDate" AS DATE)) OVER (PARTITION BY "GmPseudo" ORDER BY "EventDate") AS "HDLDate"
FROM INTERMEDIATE.GP_RECORD."Readings_Cholesterol"
WHERE "GmPseudo" IN (SELECT "GmPseudo" FROM {{cohort-table}})
AND "HDL" IS NOT NULL;

-- Get ldl cholesterol
DROP TABLE IF EXISTS LH004_ldl;
CREATE TEMPORARY TABLE LH004_ldl AS
SELECT DISTINCT "GmPseudo", 
    last_value("LDL") OVER (PARTITION BY "GmPseudo" ORDER BY "EventDate") AS "LDLValue", 
    last_value(CAST("EventDate" AS DATE)) OVER (PARTITION BY "GmPseudo" ORDER BY "EventDate") AS "LDLDate"
FROM INTERMEDIATE.GP_RECORD."Readings_Cholesterol"
WHERE "GmPseudo" IN (SELECT "GmPseudo" FROM {{cohort-table}})
AND "LDL" IS NOT NULL;

-- Get triglycerides
DROP TABLE IF EXISTS LH004_triglycerides;
CREATE TEMPORARY TABLE LH004_triglycerides AS
SELECT DISTINCT "GmPseudo", 
    last_value("Triglycerides") OVER (PARTITION BY "GmPseudo" ORDER BY "EventDate") AS "TriglyceridesValue", 
    last_value(CAST("EventDate" AS DATE)) OVER (PARTITION BY "GmPseudo" ORDER BY "EventDate") AS "TriglyceridesDate"
FROM INTERMEDIATE.GP_RECORD."Readings_Cholesterol"
WHERE "GmPseudo" IN (SELECT "GmPseudo" FROM {{cohort-table}})
AND "Triglycerides" IS NOT NULL;

-- Create a temp table of all SuppliedCodes required to get
-- the next several queries in order to make them a lot faster.
DROP TABLE IF EXISTS LH004_cohort_codes;
CREATE TEMPORARY TABLE LH004_cohort_codes AS
SELECT "FK_Patient_ID", "SuppliedCode", CAST("EventDate" AS DATE) AS "EventDate"
FROM INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses"
WHERE "SuppliedCode" IN (SELECT code FROM {{code-set-table}} WHERE concept in ('lupus-nephritis','ckd-stage-1','ckd-stage-2','ckd-stage-3','ckd-stage-4','ckd-stage-5'))
AND "FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM {{cohort-table}});

-- Get Lupus neprhitis
--> CODESET lupus-nephritis:1
DROP TABLE IF EXISTS LH004_lupus_nephritis;
CREATE TEMPORARY TABLE LH004_lupus_nephritis AS
SELECT "FK_Patient_ID", MIN("EventDate") AS "FirstLupusNephritisDiagnosis"
FROM LH004_cohort_codes
WHERE "SuppliedCode" IN (SELECT code FROM {{code-set-table}} WHERE concept = 'lupus-nephritis')
GROUP BY "FK_Patient_ID";

--> CODESET ckd-stage-1:1
DROP TABLE IF EXISTS LH004_ckd_1;
CREATE TEMPORARY TABLE LH004_ckd_1 AS
SELECT "FK_Patient_ID", MIN("EventDate") AS "FirstCKD1Diagnosis"
FROM LH004_cohort_codes
WHERE "SuppliedCode" IN (SELECT code FROM {{code-set-table}} WHERE concept = 'ckd-stage-1')
GROUP BY "FK_Patient_ID";

--> CODESET ckd-stage-2:1
DROP TABLE IF EXISTS LH004_ckd_2;
CREATE TEMPORARY TABLE LH004_ckd_2 AS
SELECT "FK_Patient_ID", MIN("EventDate") AS "FirstCKD2Diagnosis"
FROM LH004_cohort_codes
WHERE "SuppliedCode" IN (SELECT code FROM {{code-set-table}} WHERE concept = 'ckd-stage-2')
GROUP BY "FK_Patient_ID";

--> CODESET ckd-stage-3:1
DROP TABLE IF EXISTS LH004_ckd_3;
CREATE TEMPORARY TABLE LH004_ckd_3 AS
SELECT "FK_Patient_ID", MIN("EventDate") AS "FirstCKD3Diagnosis"
FROM LH004_cohort_codes
WHERE "SuppliedCode" IN (SELECT code FROM {{code-set-table}} WHERE concept = 'ckd-stage-3')
GROUP BY "FK_Patient_ID";

--> CODESET ckd-stage-4:1
DROP TABLE IF EXISTS LH004_ckd_4;
CREATE TEMPORARY TABLE LH004_ckd_4 AS
SELECT "FK_Patient_ID", MIN("EventDate") AS "FirstCKD4Diagnosis"
FROM LH004_cohort_codes
WHERE "SuppliedCode" IN (SELECT code FROM {{code-set-table}} WHERE concept = 'ckd-stage-4')
GROUP BY "FK_Patient_ID";

--> CODESET ckd-stage-5:1
DROP TABLE IF EXISTS LH004_ckd_5;
CREATE TEMPORARY TABLE LH004_ckd_5 AS
SELECT "FK_Patient_ID", MIN("EventDate") AS "FirstCKD5Diagnosis"
FROM LH004_cohort_codes
WHERE "SuppliedCode" IN (SELECT code FROM {{code-set-table}} WHERE concept = 'ckd-stage-5')
GROUP BY "FK_Patient_ID";

{{create-output-table::"LH004-1_Patients"}}
SELECT
	sle."GmPseudo",
	sle."Sex",
	sle."YearOfBirth",
	sle."Ethnicity",
	sle."EthnicityCategory",
	sle."IMD2019Decile1IsMostDeprived10IsLeastDeprived",
	sle."SmokingStatus",
	sle."SmokingConsumption",
	sle."BMI",
	sle."BMIDate",
	sle."AlcoholStatus",
	sle."AlcoholConsumption",
	"FirstSLEDiagnosis",
	"FirstLupusNephritisDiagnosis",
	"FirstCKD1Diagnosis",
	"FirstCKD2Diagnosis",
	"FirstCKD3Diagnosis",
	"FirstCKD4Diagnosis",
	"FirstCKD5Diagnosis",
	"eGFRValue", 
	"eGFRDate",
	"SerumCreatinineValue", 
	"SerumCreatinineDate",
	"HDLValue", 
	"HDLDate",
	"LDLValue", 
	"LDLDate",
	"TriglyceridesValue", 
	"TriglyceridesDate",
	mortality."RegisteredDateOfDeath",
  mortality."DiagnosisUnderlyingCode" AS "DiagnosisUnderlyingICD10Code",
  mortality."DiagnosisUnderlyingDesc"
FROM {{cohort-table}} sle
    LEFT OUTER JOIN LH004_eGFR egfr ON egfr."GmPseudo" = sle."GmPseudo"
    LEFT OUTER JOIN LH004_creatinine creat ON creat."GmPseudo" = sle."GmPseudo"
    LEFT OUTER JOIN LH004_hdl hdl ON hdl."GmPseudo" = sle."GmPseudo"
    LEFT OUTER JOIN LH004_ldl ldl ON ldl."GmPseudo" = sle."GmPseudo"
    LEFT OUTER JOIN LH004_triglycerides triglycerides ON triglycerides."GmPseudo" = sle."GmPseudo"
    LEFT OUTER JOIN LH004_lupus_nephritis nephritis ON nephritis."FK_Patient_ID" = sle."FK_Patient_ID"
    LEFT OUTER JOIN LH004_ckd_1 ckd1 ON ckd1."FK_Patient_ID" = sle."FK_Patient_ID"
    LEFT OUTER JOIN LH004_ckd_2 ckd2 ON ckd2."FK_Patient_ID" = sle."FK_Patient_ID"
    LEFT OUTER JOIN LH004_ckd_3 ckd3 ON ckd3."FK_Patient_ID" = sle."FK_Patient_ID"
    LEFT OUTER JOIN LH004_ckd_4 ckd4 ON ckd4."FK_Patient_ID" = sle."FK_Patient_ID"
    LEFT OUTER JOIN LH004_ckd_5 ckd5 ON ckd5."FK_Patient_ID" = sle."FK_Patient_ID"
    LEFT OUTER JOIN PRESENTATION.NATIONAL_FLOWS_PCMD."DS1804_Pcmd" mortality ON mortality."GmPseudo" = sle."GmPseudo";