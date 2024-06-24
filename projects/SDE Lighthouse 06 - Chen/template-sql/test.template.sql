--┌──────────────────────────────────────────┐
--│ SDE Lighthouse study 06 - Chen           │
--└──────────────────────────────────────────┘

set(StudyStartDate) = to_date('2017-01-01');
set(StudyEndDate)   = to_date('2023-12-31');


--> CODESET opioids:1
--> CODESET chronic-pain:1
 
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

-- 	CHRONIC PAIN PATIENTS

DROP TABLE IF EXISTS ChronicPain;
CREATE TEMPORARY TABLE ChronicPain AS
SELECT gp."FK_Patient_ID", "EventDate"
FROM INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" gp
WHERE (
  "FK_Reference_Coding_ID" IN (SELECT FK_Reference_Coding_ID FROM VersionedCodeSets WHERE Concept = 'chronic-pain' AND Version = 1) OR
  "FK_Reference_SnomedCT_ID" IN (SELECT FK_Reference_SnomedCT_ID FROM VersionedSnomedSets WHERE Concept = 'chronic-pain' AND Version = 1)
) 
AND "EventDate" BETWEEN $StudyStartDate and $StudyEndDate ;

-- find first chronic pain code in the study period 
DROP TABLE IF EXISTS FirstPain;
CREATE TEMPORARY TABLE FirstPain AS
SELECT 
	FK_Patient_ID, 
	MIN(TO_DATE(EventDate)) AS FirstPainCodeDate
FROM ChronicPain
GROUP BY FK_Patient_ID;


DROP TABLE IF EXISTS OpioidPrescriptions;
CREATE TEMPORARY TABLE OpioidPrescriptions AS
SELECT 
	gp."FK_Patient_ID", 
	TO_DATE("MedicationDate") AS "MedicationDate", 
	"Dosage", 
	"Quantity", 
	"SuppliedCode",
	fp.FirstPainCodeDate,
	Lag("MedicationDate", 1) OVER 
		(PARTITION BY gp."FK_Patient_ID" ORDER BY "MedicationDate" ASC) AS "PreviousOpioidDate"
FROM INTERMEDIATE.GP_RECORD."GP_Medications_SecondaryUses" gp
INNER JOIN FirstPain fp ON fp.FK_Patient_ID = gp."FK_Patient_ID" 
WHERE 
	(
  "FK_Reference_Coding_ID" IN (SELECT FK_Reference_Coding_ID FROM VersionedCodeSets WHERE Concept = 'opioids' AND Version = 1) OR
  "FK_Reference_SnomedCT_ID" IN (SELECT FK_Reference_SnomedCT_ID FROM VersionedSnomedSets WHERE Concept = 'opioids' AND Version = 1)
  	)
AND "FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM ChronicPain) -- chronic pain patients only 
--AND gp."FK_Patient_ID" NOT IN (SELECT FK_Patient_ID FROM cancer)  -- exclude cancer patients
AND "MedicationDate" BETWEEN $StudyStartDate and $StudyEndDate;    -- only looking at opioid prescriptions in the study period
AND gp."MedicationDate" > fp.FirstPainCodeDate                    -- looking at opioid prescriptions after the first chronic pain code

-- find all patients that have had two prescriptions within 90 days, and calculate the index date as
-- the first prescription that meets the criteria

DROP TABLE IF EXISTS IndexDates;
CREATE TEMPORARY TABLE IndexDates AS
SELECT "FK_Patient_ID", 
	MIN(TO_DATE("PreviousOpioidDate")) AS IndexDate 
FROM OpioidPrescriptions
WHERE DATEDIFF(dd, "PreviousOpioidDate", "MedicationDate") <= 90
GROUP BY "FK_Patient_ID";


