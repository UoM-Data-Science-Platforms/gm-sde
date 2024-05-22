--┌──────────────────────────────────────────────────────────────────────────────────┐
--│ Create counting tables for each medications based on GPMedications table - RQ051 │
--└──────────────────────────────────────────────────────────────────────────────────┘
-- OBJECTIVE: To build the counting tables for each mental medications for RQ051. This reduces duplication of code in the template scripts.

-- COHORT: Any patient in the [RLS].[vw_GP_Medications]

-- NOTE: Need to fill the '{param:medication}' and '{param:version}' and {param:medicationname}

-- INPUT: Assumes there exists one temp table as follows:
-- #GPMedications (FK_Patient_Link_ID, MedicationDate, FK_Reference_Coding_ID, FK_Reference_SnomedCT_ID)

-- OUTPUT: Temp tables as follows:
-- #First{param:medicationname}Counts

------------------------------------------------------------------------------------------------------------------------------------------------------------
--> CODESET {param:medication}:{param:version}

-- Table for episode counts
IF OBJECT_ID('tempdb..#First{param:medicationname}Counts') IS NOT NULL DROP TABLE #First{param:medicationname}Counts;
SELECT YEAR(MedicationDate) AS YearOfEpisode, MONTH(MedicationDate) AS MonthOfEpisode, COUNT(*) AS Frequency --need number per month per person
INTO #First{param:medicationname}Counts
FROM (
  -- First we deduplicate to ensure only 1 med per day is counted
  SELECT FK_Patient_Link_ID, MedicationDate
  FROM #GPMedications
  WHERE SuppliedCode IN (SELECT Code FROM #AllCodes WHERE Concept = '{param:medication}' AND Version = '{param:version}') 
  AND MedicationDate >= '2019-01-01'
  AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
  GROUP BY FK_Patient_Link_ID, MedicationDate
) sub
GROUP BY FK_Patient_Link_ID, YEAR(MedicationDate), MONTH(MedicationDate);
