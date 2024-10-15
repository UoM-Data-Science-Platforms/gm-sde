--┌────────────────────┐
--│ Patient GP history │
--└────────────────────┘

-- OBJECTIVE: To produce a table showing the start and end dates for each practice the patient
--            has been registered at.

-- ASSUMPTIONS:
--	-	We do not have data on patients who move out of GM, though we do know that it happened. 
--    For these patients we record the GPPracticeCode as OutOfArea
--  - Where two adjacent time periods either overlap, or have a gap between them, we assume that
--    the most recent registration is more accurate and adjust the end date of the first time
--    period accordingly. This is an infrequent occurrence.

-- INPUT: No pre-requisites

-- OUTPUT: A temp table as follows:
-- #PatientGPHistory (FK_Patient_Link_ID, GPPracticeCode, StartDate, EndDate)
--	- FK_Patient_Link_ID - unique patient id
--	- GPPracticeCode - national GP practice id system
--	- StartDate - date the patient registered at the practice
--	- EndDate - date the patient left the practice

-- First let's get the raw data from the GP history table
IF OBJECT_ID('tempdb..#AllGPHistoryData') IS NOT NULL DROP TABLE #AllGPHistoryData;
SELECT 
	FK_Patient_Link_ID, CASE WHEN GPPracticeCode like 'ZZZ%' THEN 'OutOfArea' ELSE GPPracticeCode END AS GPPracticeCode, 
	CASE WHEN StartDate IS NULL THEN '1900-01-01' ELSE CAST(StartDate AS DATE) END AS StartDate, 
	CASE WHEN EndDate IS NULL THEN '2100-01-01' ELSE CAST(EndDate AS DATE) END AS EndDate 
INTO #AllGPHistoryData FROM SharedCare.Patient_GP_History
WHERE FK_Reference_Tenancy_ID=2 -- limit to GP feed makes it easier than trying to deal with the conflicting data coming from acute care
AND (StartDate < EndDate OR EndDate IS NULL) --Some time periods are instantaneous (start = end) - this ignores them
AND GPPracticeCode IS NOT NULL;
--4147852

IF OBJECT_ID('tempdb..#PatientGPHistory') IS NOT NULL DROP TABLE #PatientGPHistory;
CREATE TABLE #PatientGPHistory(FK_Patient_Link_ID BIGINT, GPPracticeCode NVARCHAR(50), StartDate DATE, EndDate DATE);

IF OBJECT_ID('tempdb..#AllGPHistoryDataOrdered') IS NOT NULL DROP TABLE #AllGPHistoryDataOrdered;
CREATE TABLE #AllGPHistoryDataOrdered(FK_Patient_Link_ID BIGINT, GPPracticeCode NVARCHAR(50), StartDate DATE, EndDate DATE, RowNumber INT);

IF OBJECT_ID('tempdb..#AllGPHistoryDataOrderedJoined') IS NOT NULL DROP TABLE #AllGPHistoryDataOrderedJoined;
CREATE TABLE #AllGPHistoryDataOrderedJoined(
  FK_Patient_Link_ID BIGINT,
  GP1 NVARCHAR(50),
  R1 INT,
  S1 DATE,
  E1 DATE,
  GP2 NVARCHAR(50),
  S2 DATE,
  E2 DATE,
  R2 INT,
);

-- Easier to get rid of everyone who only has one GP history entry
IF OBJECT_ID('tempdb..#PatientGPHistoryJustOneEntryIds') IS NOT NULL DROP TABLE #PatientGPHistoryJustOneEntryIds;
SELECT FK_Patient_Link_ID INTO #PatientGPHistoryJustOneEntryIds FROM #AllGPHistoryData
GROUP BY FK_Patient_Link_ID
HAVING COUNT(*) = 1;

-- Holding table for their data
IF OBJECT_ID('tempdb..#PatientGPHistoryJustOneEntry') IS NOT NULL DROP TABLE #PatientGPHistoryJustOneEntry;
SELECT * INTO #PatientGPHistoryJustOneEntry FROM #AllGPHistoryData
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientGPHistoryJustOneEntryIds);

-- Remove from main table
DELETE FROM #AllGPHistoryData
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientGPHistoryJustOneEntryIds);

DECLARE @size INT;
SET @size = (SELECT COUNT(*) FROM #AllGPHistoryData) + 1;

WHILE(@size > (SELECT COUNT(*) FROM #AllGPHistoryData))
BEGIN
  SET @size = (SELECT COUNT(*) FROM #AllGPHistoryData);

  -- Add row numbers so we can join with next row
  TRUNCATE TABLE #AllGPHistoryDataOrdered;
  INSERT INTO #AllGPHistoryDataOrdered
  SELECT *, ROW_NUMBER() OVER (PARTITION BY FK_Patient_Link_ID ORDER BY StartDate) AS RowNumber from #AllGPHistoryData;

  -- Join each patient row with the next one, but only look at the odd numbers to avoid duplicating
  TRUNCATE TABLE #AllGPHistoryDataOrderedJoined;
  INSERT INTO #AllGPHistoryDataOrderedJoined
  SELECT 
    o1.FK_Patient_Link_ID,o1.GPPracticeCode AS GP1,o1.RowNumber AS R1, 
    o1.StartDate AS S1, o1.EndDate AS E1, o2.GPPracticeCode AS GP2, 
    o2.StartDate as S2, o2.EndDate as E2, o2.RowNumber as R2
  FROM #AllGPHistoryDataOrdered o1
  LEFT OUTER JOIN #AllGPHistoryDataOrdered o2 ON o1.FK_Patient_Link_ID = o2.FK_Patient_Link_ID AND o1.RowNumber = o2.RowNumber - 1
  WHERE o1.RowNumber % 2 = 1
  ORDER BY o1.FK_Patient_Link_ID DESC, o1.StartDate;

  -- If GP is the same, then merge the time periods
  TRUNCATE TABLE #PatientGPHistory;
  INSERT INTO #PatientGPHistory
  SELECT FK_Patient_Link_ID, GP1, S1, CASE WHEN E2 > E1 THEN E2 ELSE E1 END AS E
  FROM #AllGPHistoryDataOrderedJoined
  WHERE GP1 = GP2;

  -- If GP is different, first insert the GP2 record
  INSERT INTO #PatientGPHistory
  SELECT FK_Patient_Link_ID, GP2, S2, E2 FROM #AllGPHistoryDataOrderedJoined
  WHERE GP1 != GP2;

  --  then insert the GP1 record
  INSERT into #PatientGPHistory
  SELECT FK_Patient_Link_ID, GP1, S1, S2 FROM #AllGPHistoryDataOrderedJoined
  WHERE GP1 != GP2;

  -- If the GP2 is null, implies it's the last row and didn't have a subsequent
  -- row to match on, so we just put it back in the gp history table
  INSERT into #PatientGPHistory
  SELECT FK_Patient_Link_ID, GP1, S1, E1 FROM #AllGPHistoryDataOrderedJoined
  WHERE GP2 IS NULL;

  -- Nuke the AllGPHistoryData table
  TRUNCATE TABLE #AllGPHistoryData;

  -- Repopulate with the current "final" snapshot
  INSERT INTO #AllGPHistoryData
  SELECT * FROM #PatientGPHistory;

END

-- Finally re-add the people with only one record
INSERT INTO #PatientGPHistory
SELECT * FROM #PatientGPHistoryJustOneEntry;