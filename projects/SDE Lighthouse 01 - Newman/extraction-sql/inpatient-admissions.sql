--┌──────────────────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 01 - Newman - Inpatient hospital admissions │
--└──────────────────────────────────────────────────────────────────┘

set(StudyStartDate) = to_date('2020-01-01');
set(StudyEndDate)   = to_date('2023-12-31');

--┌────────────────────────────────────────────────────────────────────────────────────────────┐
--│ Define Cohort for LH001: patients that had pharmacogenetic testing, and matched controls   │
--└────────────────────────────────────────────────────────────────────────────────────────────┘

-- OBJECTIVE: To build the cohort of patients needed for LH001. This reduces duplication of code in the template scripts.

-- COHORT: Any patient with a pharmacogenetic test, or a matched control.

-- OUTPUT: Temp tables as follows:
-- Cohort


USE INTERMEDIATE.GP_RECORD;

set(StudyStartDate) = to_date('2023-06-01');
set(StudyEndDate)   = to_date('2024-06-30');

--ALL DEATHS 

DROP TABLE IF EXISTS Death;
CREATE TEMPORARY TABLE Death AS
SELECT 
    DEATH."GmPseudo",
    TO_DATE(DEATH."RegisteredDateOfDeath") AS DeathDate
FROM PRESENTATION.NATIONAL_FLOWS_PCMD."DS1804_Pcmd" DEATH;

-- GET LATEST SNAPSHOT OF DEMOGRAPHICS TABLE

DROP TABLE IF EXISTS LatestSnapshotAdults;
CREATE TEMPORARY TABLE LatestSnapshotAdults AS
SELECT 
    p.*
FROM INTERMEDIATE.GP_RECORD."DemographicsProtectedCharacteristics" p 
INNER JOIN (
    SELECT "GmPseudo", MAX("Snapshot") AS LatestSnapshot
    FROM INTERMEDIATE.GP_RECORD."DemographicsProtectedCharacteristics" p 
    WHERE DATEDIFF(YEAR, TO_DATE("DateOfBirth"), $StudyStartDate) >= 18 -- adults only
    GROUP BY "GmPseudo"
    ) t2
ON t2."GmPseudo" = p."GmPseudo" AND t2.LatestSnapshot = p."Snapshot";

-- FIND ALL ADULT PATIENTS ALIVE AT STUDY START DATE

DROP TABLE IF EXISTS AlivePatientsAtStart;
CREATE TEMPORARY TABLE AlivePatientsAtStart AS 
SELECT  
    dem.*, 
    Death.DeathDate
FROM LatestSnapshotAdults dem
LEFT JOIN Death ON Death."GmPseudo" = dem."GmPseudo"
WHERE 
    (DeathDate IS NULL OR DeathDate > $StudyStartDate); -- alive on study start date



-- table of pharmacogenetic test patients

------


DROP TABLE IF EXISTS Cohort;
CREATE TEMPORARY TABLE AS
SELECT DISTINCT 
	 "FK_Patient_ID",
	 "GmPseudo"
INTO Cohort
FROM Pharmacogenetic p



---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------


-- get all inpatient admissions
SELECT 
    "GmPseudo"
    , TO_DATE("AdmissionDttm") AS "AdmissionDate"
    , TO_DATE("DischargeDttm") AS "DischargeDate"
	, "AdmissionMethodCode"
	, "AdmissionMethodDesc"
    , "HospitalSpellDuration" AS "LOS_days"
    , "DerPrimaryDiagnosisChapterDescReportingEpisode" AS PrimaryDiagnosisChapter
	, "DerPrimaryDiagnosisCodeReportingEpisode" AS PrimaryDiagnosisCode 
    , "DerPrimaryDiagnosisDescReportingEpisode" AS PrimaryDiagnosisDesc
FROM PRESENTATION.NATIONAL_FLOWS_APC."DS708_Apcs"
WHERE 
-- "ProviderDesc" IN ('Manchester University NHS Foundation Trust', 'Pennine Acute Hospitals NHS Trust', 'Northern Care Alliance NHS Foundation Trust', 'Wrightington, Wigan And Leigh NHS Foundation Trust', 'Stockport NHS Foundation Trust', 'Bolton NHS Foundation Trust', 'Tameside And Glossop Integrated Care NHS Foundation Trust', 'The Christie NHS Foundation Trust') AND
-- FILTER OUT ELECTIVE ??   
TO_DATE("AdmissionDttm") BETWEEN $StudyStartDate AND $StudyEndDate
AND "GmPseudo" IN (SELECT "GmPseudo" FROM cOHORT);

