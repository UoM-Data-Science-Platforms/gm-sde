--┌────────────────────────────────────┐
--│ LH010 Patient file                 │
--└────────────────────────────────────┘

-- Cohort: >50s in 2016

set(StudyStartDate) = to_date('2016-01-01');
set(StudyEndDate)   = to_date('2024-08-01');

--> EXECUTE query-get-possible-patients.sql minimum-age:18

-- GET COHORT OF PATIENTS THAT HAD A LUNG HEALTH CHECK

DROP TABLE IF EXISTS {{cohort-table}};
CREATE TABLE {{cohort-table}} AS 
SELECT "GmPseudo", "FK_Patient_ID" 
FROM AlivePatientsAtStart
WHERE DATEDIFF(YEAR, "DateOfBirth",$StudyStartDate) >= 50  -- over 50 in 2016
LEFT OUTER JOIN **LUNGHEALTHCHECKTABLE**
LIMIT 1000 --THIS IS TEMPORARY


-- PERSONAL HISTORY OF CANCER - TO JOIN TO LATER
-- THIS CODE INCLUDES ANY PATIENT IF THEY HAVE EVER HAD A SNAPSHOT INDICATING CANCER

DROP TABLE IF EXISTS PersonalHistoryCancer;
CREATE TEMPORARY TABLE PersonalHistoryCancer AS 
SELECT DISTINCT ltc."GmPseudo", "FK_Patient_ID"
FROM LongTermConditionRegister_SecondaryUses ltc
WHERE ("Cancer_QOF" is not null or "Cancer_DiagnosisDate" is not null or "Cancer_DiagnosisAge" is not null or "Cancer_QOF_DiagnosedL5Y" is not null)
	AND "GmPseudo" IN {{cohort-table}}

-- COPD meds

DROP TABLE IF EXISTS COPDMeds;
CREATE TEMPORARY TABLE COPDMeds AS 
SELECT c."GmPseudo"
    , MIN(TO_DATE(ec."MedicationDate")) AS "MinCOPDMedDate"
FROM INTERMEDIATE.GP_RECORD."MedicationsClusters" ec
INNER JOIN {{cohort-table}} c ON c."FK_Patient_ID" = ec."FK_Patient_ID"
WHERE "Field_ID" IN ('COPDICSDRUG_COD')
	AND TO_DATE(ec."MedicationDate") <=  $StudyStartDate

-- Statins

DROP TABLE IF EXISTS Statins;
CREATE TEMPORARY TABLE Statins AS 
SELECT c."GmPseudo"
    , MIN(TO_DATE(ec."MedicationDate")) AS "MinStatinDate"
FROM INTERMEDIATE.GP_RECORD."MedicationsClusters" ec
INNER JOIN {{cohort-table}} c ON c."FK_Patient_ID" = ec."FK_Patient_ID"
WHERE "Field_ID" IN ('Statin')
	AND TO_DATE(ec."MedicationDate") <=  $StudyStartDate
GROUP BY ec."FK_Patient_ID"
	, c."GmPseudo"


-- FOR THE ABOVE COHORT, GET ALL REQUIRED DEMOGRAPHICS

{{create-output-table::"1_Patients"}}
SELECT
	 dem."Snapshot",
	 dem."GmPseudo", 
	 dem."Sex",
	 dem."DateOfBirth" AS "MonthOfBirth", 
	 dem."Age",
	 dem."IMD_Decile",
	 dem."EthnicityLatest_Category",
	 dem."PracticeCode", 
	 dth.DeathDate,
     dth."DiagnosisOriginalMentionCode" AS "ReasonForDeathCode",
     dth."DiagnosisOriginalMentionDesc" AS "ReasonForDeathDesc",
	 dem."Frailty", -- 92% missingness
	 dem."BMI",
	 dem."BMI_Date",
	 dem."BMI_Description",
	 CASE WHEN phc."GmPseudo" IS NOT NULL THEN 1 ELSE 0 END AS 'PersonalHistoryOfCancer',
	 -- TODO: family history of lung cancer
	 dem."AlcoholStatus",
	 dem."Alcohol_Date",
	 dem."AlcoholConsumption",
	 dem."SmokingStatus",
	 dem."Smoking_Date",
	 dem."SmokingConsumption"
	 dem."SmokingConsumption",
	 CASE WHEN copd."GmPseudo" IS NOT NULL THEN 1 ELSE 0 END AS "HistoryOfCOPDMeds",
	 copd."MinCOPDMedDate",
	 CASE WHEN stat."GmPseudo" IS NOT NULL THEN 1 ELSE 0 END AS "HistoryOfStatins",
	 copd."MinStatinDate"
FROM {{cohort-table}}  co
LEFT OUTER JOIN PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" dem ON dem."GmPseudo" = co."GmPseudo"
LEFT OUTER JOIN Death dth ON dth."GmPseudo" = co."GmPseudo"
LEFT OUTER JOIN PersonalHistoryCancer phc ON phc."GmPseudo" = co."GmPseudo"
LEFT OUTER JOIN COPDMeds copd ON copd."GmPseudo" = co."GmPseudo" 
LEFT OUTER JOIN Statins stat ON stat."GmPseudo" = co."GmPseudo" 
QUALIFY row_number() OVER (PARTITION BY dem."GmPseudo" ORDER BY "Snapshot" DESC) = 1;