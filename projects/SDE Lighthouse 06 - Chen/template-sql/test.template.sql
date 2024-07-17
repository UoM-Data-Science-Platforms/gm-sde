--┌──────────────────────────────────────────┐
--│ SDE Lighthouse study 06 - Chen           │
--└──────────────────────────────────────────┘

set(StudyStartDate) = to_date('2017-01-01');
set(StudyEndDate)   = to_date('2023-12-31');

--> CODESET nsaids:1 opioids:1
 
-- Deaths 
 
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

-- 	Prescriptions

DROP TABLE IF EXISTS Prescriptions;
CREATE TEMPORARY TABLE Prescriptions AS
SELECT 
	gp."FK_Patient_ID", 
	TO_DATE("MedicationDate") AS "MedicationDate", 
	"Dosage", 
	"Quantity", 
	"SuppliedCode",
    "MedicationDescription"
FROM INTERMEDIATE.GP_RECORD."GP_Medications_SecondaryUses" gp
INNER JOIN VersionedCodeSets vcs ON vcs.FK_Reference_Coding_ID = gp."FK_Reference_Coding_ID" AND vcs.Version =1
INNER JOIN VersionedSnomedSets vss ON vss.FK_Reference_SnomedCT_ID = gp."FK_Reference_SnomedCT_ID" AND vss.Version =1
WHERE 
GP."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM AlivePatientsAtStart) AND
-- vcs.Concept not in ('chronic-pain', 'opioids', 'cancer') AND
-- vss.Concept not in ('chronic-pain', 'opioids', 'cancer') AND
gp."MedicationDate" BETWEEN $StudyStartDate and $StudyEndDate;    -- only looking at prescriptions in the study period

