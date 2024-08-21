--┌─────────────────────────────┐
--│ Adverse Drug Reactions      │
--└─────────────────────────────┘

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

USE INTERMEDIATE.GP_RECORD;

set(StartDate) = to_date('2012-01-01');
set(EndDate) = to_date('2024-06-30');

-- find adverse reactions from GP events table

SELECT DISTINCT
	e."FK_Patient_ID"
	, to_date("EventDate") AS "DiagnosisDate"
	, e."SCTID" AS "SnomedCode"
	, co.concept AS "Concept"
	, e."Term" AS "Description"
FROM INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" e
LEFT JOIN SDE_REPOSITORY.SHARED_UTILITIES.AllCodesPermanent co ON co.CODE = e."SCTID"
WHERE co.concept = 'adverse-reaction'
--AND e."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM Cohort)
AND TO_DATE("EventDate") BETWEEN $StartDate AND $EndDate;

