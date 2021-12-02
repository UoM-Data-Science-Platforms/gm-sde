--┌─────────────────────────────────┐
--│ Cancer blood tests              │
--└─────────────────────────────────┘


-- OUTPUT: A single table with the following:
    --   [PK_BloodTest_ID]
    --   ,[FK_Patient_ID]
    --   ,[FK_Patient_Link_ID]
    --   ,[FK_Reference_Tenancy_ID]
    --   ,[ExternalID]
    --   ,[CreateDate]
    --   ,[ModifDate]
    --   ,[LoadID]
    --   ,[Deleted]
    --   ,[HDMModifDate]
    --   ,[RequestDateTime]
    --   ,[TestCodeID]
    --   ,[TestCode]
    --   ,[TestShortDescription]
    --   ,[TestDescription]
    --   ,[TestResultType]
    --   ,[NumericTestResultsValue]
    --   ,[TextResultValue]
  

--Just want the output, not the messages
SET NOCOUNT ON;


/* simulating a select * except one column */
IF OBJECT_ID('tempdb..#TempTable') IS NOT NULL DROP TABLE #TempTable;
SELECT [FK_Patient_Link_ID] AS PatientId, * INTO #TempTable
FROM [SharedCare].[Cancer_BloodTests];

/* Drop the columns that are not needed */
ALTER TABLE #TempTable
DROP COLUMN [PK_BloodTest_ID], [FK_Patient_Link_ID], [FK_Patient_ID];

SELECT * FROM #TempTable;