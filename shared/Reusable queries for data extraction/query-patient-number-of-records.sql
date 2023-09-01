--┌──────────────────────┐
--│ Number of GP records │
--└──────────────────────┘

-- OBJECTIVE: To get the number of GP records for each patient. Some studies have found
-- 						that there are "ghost" patients who have demographic info from the GP spine
--						feed, but who have no other records or medications from their GP. This allows
--						those patients with 0 records to be excluded if required.

-- INPUT: Assumes there exists a temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: A temp table as follows:
-- #GPRecordCount (FK_Patient_Link_ID, NumberOfEvents, NumberOfMedications)
-- 	- FK_Patient_Link_ID - unique patient id
--	- NumberOfEvents - INT
--	- NumberOfMedications - INT

-- Get all patients GP event records count
IF OBJECT_ID('tempdb..#GPEventsCount') IS NOT NULL DROP TABLE #GPEventsCount;
SELECT FK_Patient_Link_ID, COUNT(*) AS NumberOfEvents INTO #GPEventsCount FROM SharedCare.GP_Events
GROUP BY FK_Patient_Link_ID;

-- Get all patients GP medication records count
IF OBJECT_ID('tempdb..#GPMedicationsCount') IS NOT NULL DROP TABLE #GPMedicationsCount;
SELECT FK_Patient_Link_ID, COUNT(*) AS NumberOfMedications INTO #GPMedicationsCount FROM SharedCare.GP_Medications
GROUP BY FK_Patient_Link_ID;

IF OBJECT_ID('tempdb..#GPRecordCount') IS NOT NULL DROP TABLE #GPRecordCount;
SELECT
	p.FK_Patient_Link_ID,
	CASE WHEN NumberOfEvents IS NULL THEN 0 ELSE NumberOfEvents END AS NumberOfEvents,
	CASE WHEN NumberOfMedications IS NULL THEN 0 ELSE NumberOfMedications END AS NumberOfMedications
INTO #GPRecordCount
FROM #Patients p
LEFT OUTER JOIN #GPEventsCount e ON e.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #GPMedicationsCount m ON m.FK_Patient_Link_ID = p.FK_Patient_Link_ID;