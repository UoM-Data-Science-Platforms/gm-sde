--┌─────────────────────────────────┐
--│ Cancer RTDS                     │
--└─────────────────────────────────┘


-- OUTPUT: A single table with the following:
--       [PK_RTDS_ID]
--       ,[ExternalID]
--       ,[FK_Patient_ID]
--       ,[FK_Patient_Link_ID]
--       ,[FK_Reference_Tenancy_ID]
--       ,[CreateDate]
--       ,[ModifDate]
--       ,[LoadID]
--       ,[Deleted]
--       ,[HDMModifDate]
--       ,[RTID]
--       ,[Consultant]
--       ,[Radiotherapy Type]
--       ,[Appointment Date]
--       ,[Attended?]
--       ,[Fraction_Given]
--       ,[Planned_Dose]
--       ,[Planned Fraction]
--       ,[Duration_Days]

--Just want the output, not the messages
SET NOCOUNT ON;

SELECT *
FROM [SharedCare].[Cancer_RTDS];