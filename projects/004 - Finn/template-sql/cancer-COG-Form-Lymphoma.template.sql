--┌─────────────────────────────────┐
--│ Cancer COG Form Lymphoma        │
--└─────────────────────────────────┘


-- OUTPUT: A single table with the following:
--       [PK_COG_Form_Lymphoma_ID]
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
--       ,[ActionFollowingReferralForSecondOpinion]
--       ,[AddedToEndOfLifeCarePathway]
--       ,[BoneMarrowInvolvement]
--       ,[ClinicalStage]
--       ,[ConsultantConferred]
--       ,[DateBiopsyPerformed]
--       ,[DateSeen]
--       ,[DateSymptomsFirstNoted]
--       ,[Diagnosis]
--       ,[DiseaseStatusAtPresentation]
--       ,[ECOGPerformanceStatus]
--       ,[EntryIntoAClinicalTrial]
--       ,[ExtranodalSiteS]
--       ,[FurtherPreviousChemotherapyDetails]
--       ,[Histology]
--       ,[HistologyReviewCentre]
--       ,[HIVStatus]
--       ,[ImmediateProposedManagement]
--       ,[IsThisTheDateOfDiagnosis]
--       ,[KeyWorkerName]
--       ,[NumberOfExtranodalSites]
--       ,[OtherExtraNodalSiteS]
--       ,[OtherPreviousTreatmentForLymphoma]
--       ,[PatientWasReferredForSecondOpinion]
--       ,[PreTreatmentLDH]
--       ,[PreviousChemotherapyLines]
--       ,[PreviousChemotherapyRegimen1]
--       ,[PreviousChemotherapyRegimen2]
--       ,[PreviousChemotherapyRegimen3]
--       ,[PreviousTreatmentForLymphoma]
--       ,[PrimaryDiseaseSite]
--       ,[ProposedChemotherapyRegimen]
--       ,[ReferredBy]
--       ,[ReferringHospital]
--       ,[RepeatBiopsyRequired]
--       ,[ResponsibleConsultant]
--       ,[SeenBy]
--       ,[SeenByKeyWorker]
--       ,[SeenByPalliativeCareSpecialist]
--       ,[StatusOfThisDiagnosis]
--       ,[TreatmentIntent]
--       ,[WhereBiopsyPerformed]
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
FROM [SharedCare].[Cancer_COG_Form_Lymphoma];

/* Drop the columns that are not needed */
ALTER TABLE #TempTable
DROP COLUMN [PK_COG_Form_Lymphoma_ID], [FK_Patient_Link_ID], [FK_Patient_ID];

SELECT * FROM #TempTable;