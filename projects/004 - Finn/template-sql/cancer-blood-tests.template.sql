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

SELECT *
FROM [SharedCare].[Cancer_BloodTests];