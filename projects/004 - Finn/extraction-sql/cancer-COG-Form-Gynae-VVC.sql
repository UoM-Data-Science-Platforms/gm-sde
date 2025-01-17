--┌─────────────────────────────────┐
--│ Cancer COG Form Gynae VVC       │
--└─────────────────────────────────┘


-- OUTPUT: A single table with the following:
--       [PK_COG_Form_Gynae_VVC_ID]
--       ,[ExternalID]
--       ,[CreateDate]
--       ,[ModifDate]
--       ,[LoadID]
--       ,[Deleted]
--       ,[HDMModifDate]
--       ,[FK_Reference_Tenancy_ID]
--       ,[FK_Patient_Link_ID]
--       ,[FK_Patient_ID]
--       ,[NhsNo]
--       ,[FormInstance]
--       ,[FormDataID]
--       ,[FormID]
--       ,[ExamKey]
--       ,[CRISOrderNo]
--       ,[StatusID]
--       ,[Date]
--       ,[FormLoadedTS]
--       ,[EventKey]
--       ,[DeleteFlag]
--       ,[TStemp]
--       ,[ConsultantID]
--       ,[BatchUpdate]
--       ,[DateCreated]
--       ,[CreatedBy]
--       ,[DateModified]
--       ,[ModifiedBy]
--       ,[ACEComorbidities]
--       ,[BasisOfDiagnosis]
--       ,[BowelFunction]
--       ,[ClinicalStage]
--       ,[ConsultantConferred]
--       ,[DateOfDiagnosis]
--       ,[DateSeen]
--       ,[DateSymptomsFirstNoted]
--       ,[DefinitionOfResidualDisease]
--       ,[Differentiation]
--       ,[DiseaseStatusAtPresentation]
--       ,[ECOGPerformanceStatus]
--       ,[EntryIntoAClinicalTrial]
--       ,[FurtherProposedManagement]
--       ,[Histology]
--       ,[HIVStatus]
--       ,[ImmediateProposedManagement]
--       ,[IsThisTheDateOfDiagnosis]
--       ,[LymphovascularSpaceInvasion]
--       ,[NodalStatus]
--       ,[OtherPelvicSurgery]
--       ,[OtherPreviousPelvicSurgery]
--       ,[PathStage]
--       ,[PelvicStatus]
--       ,[PreviousGynaecologicalSurgery]
--       ,[PrimaryDiseaseSite]
--       ,[ReferredBy]
--       ,[ReferringHospital]
--       ,[ResponsibleConsultant]
--       ,[SeenBy]
--       ,[SexualFunction]
--       ,[SmokingHistory]
--       ,[TreatmentIntent]
--       ,[TumourSizeCm]
--       ,[UrinaryFunction]
--       ,[CreatedBySurname]
--       ,[CreatedByForename]
--       ,[CreatedByUserDepartment]
--       ,[CreatedByUserEmployer]
--       ,[ModifiedBySurname]
--       ,[ModifiedByForename]
--       ,[ModifiedByUserDepartment]
--       ,[ModifiedByUserEmployer]
  

--Just want the output, not the messages
SET NOCOUNT ON;


/* simulating a select * except one column */
IF OBJECT_ID('tempdb..#TempTable') IS NOT NULL DROP TABLE #TempTable;
SELECT [FK_Patient_Link_ID] AS PatientId, * INTO #TempTable
FROM [SharedCare].[Cancer_COG_Form_Gynae_VVC];

/* Drop the columns that are not needed */
ALTER TABLE #TempTable
DROP COLUMN [PK_COG_Form_Gynae_VVC_ID], [FK_Patient_Link_ID], [FK_Patient_ID];

SELECT * FROM #TempTable;