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
--LEFT OUTER JOIN **LUNGHEALTHCHECKTABLE**
WHERE DATEDIFF(YEAR, "DateOfBirth",$StudyStartDate) >= 50  -- over 50 in 2016
LIMIT 1000; --THIS IS TEMPORARY


-- PERSONAL HISTORY OF CANCER - TO JOIN TO LATER
-- THIS CODE INCLUDES ANY PATIENT IF THEY HAVE EVER HAD A SNAPSHOT INDICATING CANCER

DROP TABLE IF EXISTS PersonalHistoryCancer;
CREATE TEMPORARY TABLE PersonalHistoryCancer AS 
SELECT DISTINCT ltc."GmPseudo", "FK_Patient_ID"
FROM PRESENTATION.GP_RECORD."LongTermConditionRegister_SecondaryUses" ltc
WHERE ("Cancer_QOF" is not null or "Cancer_DiagnosisDate" is not null or "Cancer_DiagnosisAge" is not null or "Cancer_QOF_DiagnosedL5Y" is not null)
	AND "GmPseudo" IN {{cohort-table}};

-- COPD meds

DROP TABLE IF EXISTS COPDMeds;
CREATE TEMPORARY TABLE COPDMeds AS 
SELECT c."GmPseudo"
    , MIN(TO_DATE(ec."MedicationDate")) AS "MinCOPDMedDate"
FROM INTERMEDIATE.GP_RECORD."Combined_EventsMedications_Clusters_SecondaryUses" ec
INNER JOIN {{cohort-table}} c ON c."FK_Patient_ID" = ec."FK_Patient_ID"
WHERE "Field_ID" IN ('COPDICSDRUG_COD')
	AND TO_DATE(ec."MedicationDate") <=  $StudyStartDate
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

-- reasonable adjustment flag

--> CODESET reasonable-adjustment-category5:1 reasonable-adjustment-category6:1 reasonable-adjustment-category7:1 
--> CODESET reasonable-adjustment-category8:1 reasonable-adjustment-category9:1 reasonable-adjustment-category10:1

DROP TABLE IF EXISTS ReasonableAdjustment;
CREATE TEMPORARY TABLE ReasonableAdjustment AS 
SELECT c."GmPseudo"
	, "Field_ID" AS concept
    , MIN(TO_DATE(ec."Date")) AS "MinDate"
FROM INTERMEDIATE.GP_RECORD."Combined_EventsMedications_Clusters_SecondaryUses" ec
INNER JOIN {{cohort-table}} c ON c."FK_Patient_ID" = ec."FK_Patient_ID"
WHERE "Field_ID" IN ('AIREQPROF_COD', 'AIFORMAT_COD', 'AIMETHOD_COD', 'AICOMSUP_COD' )
	AND TO_DATE(ec."Date") <=  $StudyStartDate
UNION ALL
-- reasonable adjustment categories 5 - 10
SELECT 
	 dem."GmPseudo"
	, cs.concept
	, MIN(to_date("EventDate")) AS "MinDate"
FROM INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" e
LEFT JOIN {{code-set-table}} cs ON cs.code = e."SuppliedCode"
LEFT OUTER JOIN AlivePatientsAtStart dem ON dem."FK_Patient_ID" = co."FK_Patient_ID" -- to get GmPseudo
WHERE cs.concept IN ('reasonable-adjustment-category5', 'reasonable-adjustment-category6', 'reasonable-adjustment-category7', 
					'reasonable-adjustment-category8', 'reasonable-adjustment-category9', 'reasonable-adjustment-category10')
	AND "FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM {{cohort-table}});
GROUP BY dem."GmPseudo", "Field_ID";

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
	 dth.DeathDate,
     dth."DiagnosisOriginalMentionCode" AS "ReasonForDeathCode",
     dth."DiagnosisOriginalMentionDesc" AS "ReasonForDeathDesc",
	 dem."Frailty",
	 dem."BMI",
	 dem."BMI_Date",
	 dem."BMI_Description",
	 CASE WHEN phc."GmPseudo" IS NOT NULL THEN 1 ELSE 0 END AS "PersonalHistoryOfCancer",
	 -- TODO: family history of lung cancer
	 dem."AlcoholStatus",
	 dem."Alcohol_Date",
	 dem."AlcoholConsumption",
	 dem."SmokingStatus",
	 dem."Smoking_Date",
	 dem."SmokingConsumption",
	 CASE WHEN copd."GmPseudo" IS NOT NULL THEN 1 ELSE 0 END AS "HistoryOfCOPDMeds",
	 copd."MinCOPDMedDate",
	 CASE WHEN stat."GmPseudo" IS NOT NULL THEN 1 ELSE 0 END AS "HistoryOfStatins",
	 stat."MinStatinDate",
	 CASE WHEN reas."GmPseudo" IS NOT NULL THEN 1 ELSE 0 END AS "ReasonableAdjustmentFlag",
	 reas."MinReasonableAdjustmentDate"
FROM {{cohort-table}}  co
LEFT OUTER JOIN PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" dem ON dem."GmPseudo" = co."GmPseudo"
LEFT OUTER JOIN Death dth ON dth."GmPseudo" = co."GmPseudo"
LEFT OUTER JOIN PersonalHistoryCancer phc ON phc."GmPseudo" = co."GmPseudo"
LEFT OUTER JOIN COPDMeds copd ON copd."GmPseudo" = co."GmPseudo" 
LEFT OUTER JOIN Statins stat ON stat."GmPseudo" = co."GmPseudo" 
LEFT OUTER JOIN ReasonableAdjustment reas ON reas."GmPseudo" = co."GmPseudo"
QUALIFY row_number() OVER (PARTITION BY dem."GmPseudo" ORDER BY "Snapshot" DESC) = 1;