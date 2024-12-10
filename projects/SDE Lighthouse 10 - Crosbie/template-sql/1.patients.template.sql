--┌────────────────────────────────────┐
--│ LH010 Patient file                 │
--└────────────────────────────────────┘

-- Cohort: >50s in 2016
-- study team will do the cohort matching, so we provide all over 50s in 2016 (with a flag to tell them which patients had a lung health check).

set(StudyStartDate) = to_date('2016-01-01');
set(StudyEndDate)   = to_date('2024-10-31');

--> EXECUTE query-get-possible-patients.sql

DROP TABLE IF EXISTS PatientsToInclude;
CREATE TEMPORARY TABLE PatientsToInclude AS
SELECT *
FROM GPRegPatients 
WHERE ("DeathDate" IS NULL OR "DeathDate" > $StudyStartDate) -- alive on study start date
	AND 
	("leftGMDate" IS NULL OR "leftGMDate" > $StudyEndDate) -- don't include patients who left GM mid study (as we lose their data)
	AND DATEDIFF(YEAR, "DateOfBirth", $StudyStartDate) >= 50;   -- over 50 in 2016


-- GET COHORT OF PATIENTS THAT HAD A LUNG HEALTH CHECK

DROP TABLE IF EXISTS {{cohort-table}};
CREATE TABLE {{cohort-table}} AS 
SELECT "GmPseudo", "FK_Patient_ID"
	-- ,flag to identify LHC patients
FROM PatientsToInclude
--LEFT OUTER JOIN **LUNGHEALTHCHECKTABLE** -- left join to identify who had a lung health check, but keep all over 50s
LIMIT 1000; --THIS IS TEMPORARY


-- PERSONAL HISTORY OF CANCER - TO JOIN TO LATER
-- THIS CODE INCLUDES ANY PATIENT IF THEY HAVE EVER HAD A SNAPSHOT INDICATING CANCER

DROP TABLE IF EXISTS PersonalHistoryCancer;
CREATE TEMPORARY TABLE PersonalHistoryCancer AS 
SELECT DISTINCT ltc."GmPseudo", "FK_Patient_ID"
FROM PRESENTATION.GP_RECORD."LongTermConditionRegister_SecondaryUses" ltc
WHERE ("Cancer_QOF" is not null or "Cancer_DiagnosisDate" is not null or "Cancer_DiagnosisAge" is not null or "Cancer_QOF_DiagnosedL5Y" is not null)
	AND "GmPseudo" IN (SELECT "GmPseudo" FROM {{cohort-table}});


-- POLYPHARMACY TABLE - HOW MAN BNF CHAPTERS HAS A PATIENT BEEN PRESCRIBED IN LAST 120 DAYS (AT STUDY START DATE)

DROP TABLE IF EXISTS Polypharmacy;
CREATE TEMPORARY TABLE Polypharmacy AS
SELECT pol."GmPseudo", pol."Snapshot", pol."Polypharmacy_Last120Days"
FROM INTERMEDIATE.GP_RECORD."Polypharmacy_Summary_SecondaryUses" pol
INNER JOIN {{cohort-table}} c ON c."FK_Patient_ID" = pol."FK_Patient_ID"
QUALIFY ROW_NUMBER() OVER (PARTITION BY pol."GmPseudo" ORDER BY pol."Snapshot" asc) = 1;

-- COPD meds

DROP TABLE IF EXISTS COPDMeds;
CREATE TEMPORARY TABLE COPDMeds AS 
SELECT c."GmPseudo"
    , MIN(TO_DATE(ec."Date")) AS "MinCOPDMedDate"
FROM INTERMEDIATE.GP_RECORD."Combined_EventsMedications_Clusters_SecondaryUses" ec
INNER JOIN {{cohort-table}} c ON c."FK_Patient_ID" = ec."FK_Patient_ID"
WHERE "Field_ID" IN ('COPDICSDRUG_COD')
	AND TO_DATE(ec."Date") <=  $StudyStartDate
GROUP BY c."GmPseudo";

-- Statins

DROP TABLE IF EXISTS Statins;
CREATE TEMPORARY TABLE Statins AS 
SELECT c."GmPseudo"
    , MIN(TO_DATE(ec."Date")) AS "MinStatinDate"
FROM INTERMEDIATE.GP_RECORD."Combined_EventsMedications_Clusters_SecondaryUses" ec
INNER JOIN {{cohort-table}} c ON c."FK_Patient_ID" = ec."FK_Patient_ID"
WHERE "Field_ID" IN ('Statin')
	AND TO_DATE(ec."Date") <=  $StudyStartDate
GROUP BY c."GmPseudo";

-- reasonable adjustment flags https://digital.nhs.uk/services/reasonable-adjustment-flag
-- flags 1 to 4 are already available as clusters in the GP Record, but 5 to 10 needed building as code sets

--> CODESET reasonable-adjustment-category5:1 reasonable-adjustment-category6:1 reasonable-adjustment-category7:1 
--> CODESET reasonable-adjustment-category8:1 reasonable-adjustment-category9:1 reasonable-adjustment-category10:1

DROP TABLE IF EXISTS ReasonableAdjustment;
CREATE TEMPORARY TABLE ReasonableAdjustment AS 
SELECT "GmPseudo", concept, MIN("Date") AS "MinDate" FROM (
SELECT c."GmPseudo"
	, "Field_ID" AS concept
    , TO_DATE(ec."Date") AS "Date"
FROM INTERMEDIATE.GP_RECORD."Combined_EventsMedications_Clusters_SecondaryUses" ec
INNER JOIN {{cohort-table}} c ON c."FK_Patient_ID" = ec."FK_Patient_ID"
WHERE "Field_ID" IN ('AIREQPROF_COD', 'AIFORMAT_COD', 'AIMETHOD_COD', 'AICOMSUP_COD' )
	AND TO_DATE(ec."Date") <=  $StudyStartDate
UNION ALL
-- reasonable adjustment categories 5 - 10
SELECT 
	 dem."GmPseudo"
	, cs.concept
	, to_date("EventDate") AS "Date"
FROM INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" e
LEFT JOIN SDE_REPOSITORY.SHARED_UTILITIES."Code_Sets_SDE_Lighthouse_10_Crosbie" cs ON cs.code = e."SuppliedCode"
LEFT OUTER JOIN PatientsToInclude dem ON dem."FK_Patient_ID" = e."FK_Patient_ID" -- to get GmPseudo
WHERE cs.concept IN ('reasonable-adjustment-category5', 'reasonable-adjustment-category6', 'reasonable-adjustment-category7', 
					'reasonable-adjustment-category8', 'reasonable-adjustment-category9', 'reasonable-adjustment-category10')
	AND e."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_10_Crosbie_GT")
)
GROUP BY "GmPseudo", concept;

-- CONVERT REASONABLE ADJUSTMENT TABLE TO WIDE TO JOIN TO
DROP TABLE IF EXISTS ReasonableAdjustmentWide;
CREATE TEMPORARY TABLE ReasonableAdjustmentWide AS
SELECT "GmPseudo",
    CASE WHEN Concept = 'AICOMSUP_COD' THEN "MinDate" ELSE NULL END AS ReasAdjust_Cat1,
    CASE WHEN Concept = 'AIREQPROF_COD' THEN "MinDate" ELSE NULL END AS ReasAdjust_Cat2,
    CASE WHEN Concept = 'AIMETHOD_COD' THEN "MinDate" ELSE NULL END AS ReasAdjust_Cat3,
    CASE WHEN Concept = 'AIFORMAT_COD' THEN "MinDate" ELSE NULL END AS ReasAdjust_Cat4,
    CASE WHEN Concept = 'reasonable-adjustment-category5' THEN "MinDate" ELSE NULL END AS ReasAdjust_Cat5,
    CASE WHEN Concept = 'reasonable-adjustment-category6' THEN "MinDate" ELSE NULL END AS ReasAdjust_Cat6,
    CASE WHEN Concept = 'reasonable-adjustment-category7' THEN "MinDate" ELSE NULL END AS ReasAdjust_Cat7,
    CASE WHEN Concept = 'reasonable-adjustment-category8' THEN "MinDate" ELSE NULL END AS ReasAdjust_Cat8,
    CASE WHEN Concept = 'reasonable-adjustment-category9' THEN "MinDate" ELSE NULL END AS ReasAdjust_Cat9,
    CASE WHEN Concept = 'reasonable-adjustment-category10' THEN "MinDate" ELSE NULL END AS ReasAdjust_Cat10
FROM REASONABLEADJUSTMENT;

-- FOR THE ABOVE COHORT, GET ALL REQUIRED DEMOGRAPHICS

{{create-output-table::"LH010-1_Patients"}}
SELECT
	 dem."Snapshot",
	 dem."GmPseudo", 
	 dem."Sex",
	 dem."DateOfBirth" AS "MonthOfBirth", 
	 dem."Age",
	 dem."IMD_Decile",
	 dem."EthnicityLatest_Category",
	 dem."PracticeCode", 
	 DATE_TRUNC(month, dth.DeathDate) AS "DeathMonth", -- day of death masked
     dth."DiagnosisOriginalMentionCode" AS "ReasonForDeathCode",
     dth."DiagnosisOriginalMentionDesc" AS "ReasonForDeathDesc",
	 dem."Frailty",
	 dem."BMI",
	 dem."BMI_Date",
	 dem."BMI_Description",
	 CASE WHEN phc."GmPseudo" IS NOT NULL THEN 1 ELSE 0 END AS "PersonalHistoryOfCancer",
	 dem."AlcoholStatus",
	 dem."Alcohol_Date",
	 dem."AlcoholConsumption",
	 dem."SmokingStatus",
	 dem."Smoking_Date",
	 dem."SmokingConsumption",
	 pol."Polypharmacy_Last120Days" AS "Polypharmacy_BNFParagraphs_Last120Days",
	 pol."Snapshot" AS "DateForPolypharmacyCount",
	 CASE WHEN copd."GmPseudo" IS NOT NULL THEN 1 ELSE 0 END AS "HistoryOfCOPDMeds",
	 copd."MinCOPDMedDate",
	 CASE WHEN stat."GmPseudo" IS NOT NULL THEN 1 ELSE 0 END AS "HistoryOfStatins",
	 stat."MinStatinDate",
	 reas.ReasAdjust_Cat1 AS "ReasonableAdjustment1_MinDate",
     reas.ReasAdjust_Cat2 AS "ReasonableAdjustment2_MinDate",
     reas.ReasAdjust_Cat3 AS "ReasonableAdjustment3_MinDate",
     reas.ReasAdjust_Cat4 AS "ReasonableAdjustment4_MinDate",
     reas.ReasAdjust_Cat5 AS "ReasonableAdjustment5_MinDate",
     reas.ReasAdjust_Cat6 AS "ReasonableAdjustment6_MinDate",
     reas.ReasAdjust_Cat7 AS "ReasonableAdjustment7_MinDate",
     reas.ReasAdjust_Cat8 AS "ReasonableAdjustment8_MinDate",
     reas.ReasAdjust_Cat9 AS "ReasonableAdjustment9_MinDate",
     reas.ReasAdjust_Cat10 AS "ReasonableAdjustment10_MinDate"
FROM {{cohort-table}}  co
LEFT OUTER JOIN PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" dem ON dem."GmPseudo" = co."GmPseudo"
LEFT OUTER JOIN Death dth ON dth."GmPseudo" = co."GmPseudo"
LEFT OUTER JOIN PersonalHistoryCancer phc ON phc."GmPseudo" = co."GmPseudo"
LEFT OUTER JOIN COPDMeds copd ON copd."GmPseudo" = co."GmPseudo" 
LEFT OUTER JOIN Statins stat ON stat."GmPseudo" = co."GmPseudo" 
LEFT OUTER JOIN ReasonableAdjustmentWide reas ON reas."GmPseudo" = co."GmPseudo"
LEFT OUTER JOIN Polypharmacy pol ON pol."GmPseudo" = co."GmPseudo"
QUALIFY row_number() OVER (PARTITION BY dem."GmPseudo" ORDER BY "Snapshot" DESC) = 1;