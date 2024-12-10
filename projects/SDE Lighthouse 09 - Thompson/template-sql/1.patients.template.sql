--┌──────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 09 - Thompson - Patients file   │
--└──────────────────────────────────────────────────────┘

-- Cohort: 30-70 year old women, alive in 2020

set(StudyStartDate) = to_date('2020-01-01');
set(StudyEndDate)   = to_date('2024-10-31');

--> EXECUTE query-get-possible-patients.sql

DROP TABLE IF EXISTS PatientsToInclude;
CREATE TEMPORARY TABLE PatientsToInclude AS
SELECT *
FROM GPRegPatients 
WHERE ("DeathDate" IS NULL OR "DeathDate" > $StudyStartDate) -- alive on study start date
	AND 
	("leftGMDate" IS NULL OR "leftGMDate" > $StudyEndDate) -- don't include patients who left GM mid study (as we lose their data)
	AND DATEDIFF(YEAR, "DateOfBirth", $StudyStartDate) BETWEEN 30 AND 70;   -- 30 to 70 in 2016

-- GET COHORT OF WOMEN 30 - 70 YEARS OLD

DROP TABLE IF EXISTS {{cohort-table}};
CREATE TABLE {{cohort-table}} AS 
SELECT DISTINCT "GmPseudo", "FK_Patient_ID" 
FROM PatientsToInclude ap
	WHERE "Sex" = 'F'; --females only

-- FOR THE ABOVE COHORT, GET ALL REQUIRED DEMOGRAPHICS

{{create-output-table::"LH009-1_Patients"}}
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
	 dem."BMI",
	 dem."BMI_Date",
	 dem."BMI_Description",
	 dem."AlcoholStatus",
	 dem."Alcohol_Date",
	 dem."AlcoholConsumption",
	 dem."SmokingStatus",
	 dem."Smoking_Date",
	 dem."SmokingConsumption"
FROM {{cohort-table}}  co
LEFT OUTER JOIN PatientsToInclude dem ON dem."GmPseudo" = co."GmPseudo"
LEFT OUTER JOIN Death dth ON dth."GmPseudo" = co."GmPseudo"
QUALIFY row_number() OVER (PARTITION BY dem."GmPseudo" ORDER BY "Snapshot" DESC) = 1;