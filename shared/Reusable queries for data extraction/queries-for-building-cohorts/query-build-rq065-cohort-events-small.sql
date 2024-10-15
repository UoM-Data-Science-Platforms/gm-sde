--┌───────────────────────────────────────────────────────────────────────┐
--│ Get all events for RQ065 cohort - but only the suppliedcode and date  │
--└───────────────────────────────────────────────────────────────────────┘

------------------------------------------------------------------------------

-- Create a table of events for all the people in our cohort.
IF OBJECT_ID('tempdb..#PatientEventData') IS NOT NULL DROP TABLE #PatientEventData;
SELECT 
  FK_Patient_Link_ID,
  CAST(EventDate AS DATE) AS EventDate,
  SuppliedCode
INTO #PatientEventData
FROM [SharedCare].GP_Events
WHERE SuppliedCode IN (SELECT [Code] FROM #AllCodes)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);
--23s

-- 4. Add indexes for future speed increase
DROP INDEX IF EXISTS eventFKData3 ON #PatientEventData;
CREATE INDEX eventFKData3 ON #PatientEventData (SuppliedCode) INCLUDE (FK_Patient_Link_ID, EventDate);
--5s