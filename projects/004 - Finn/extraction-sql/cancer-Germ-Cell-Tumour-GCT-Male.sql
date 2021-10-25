--┌─────────────────────────────────┐
--│ Cancer Germ Cell Tumour GCT Male│
--└─────────────────────────────────┘


-- OUTPUT: A single table with the following:
--       [PK_Germ_Cell_Tumour_GCT_Male_ID]
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
--       ,[AFPMostRecent]
--       ,[AFPPostOrchidectomy]
--       ,[BasisOfDiagnosis]
--       ,[Ca125PriorToInitialTreatment]
--       ,[ClinicalStage]
--       ,[ConsultantConferred]
--       ,[CurrentDiseaseStatus]
--       ,[CurrentDiseaseStatusForThisCancer]
--       ,[CurrentProgressiveDisease]
--       ,[DateOfBiopsy]
--       ,[DateOfDiagnosis]
--       ,[DateOfDiseaseProgression]
--       ,[DateOfOriginalDiagnosis]
--       ,[DateOfRelapse]
--       ,[DateOfSurgery]
--       ,[DateSeen]
--       ,[DateSymptomsFirstNoted]
--       ,[DefinitiveSurgeryPlanned]
--       ,[Diagnosis]
--       ,[Differentiation]
--       ,[DiseaseFreeFollowingPrimaryTreatment]
--       ,[EntryIntoAClinicalTrial]
--       ,[HcgMostRecent]
--       ,[HcgPostOrchidectomy]
--       ,[Histology]
--       ,[HistologyFromNewBiopsy]
--       ,[HistologyFromNewBiopsyReviewedBySMDT]
--       ,[IGCCCPrognosisNSGCT]
--       ,[IGCCCPrognosisSeminoma]
--       ,[IGCCCScoreNSGCT]
--       ,[IGCCCScoreSeminoma]
--       ,[IGCCCGPrognosticGroupAtDiagnosis]
--       ,[IGCCCGPrognosticGroupPriorToThisReferral]
--       ,[ImmediateProposedManagement]
--       ,[IsThisTheDateOfDiagnosis]
--       ,[KeyWorkerName]
--       ,[LDHMostRecent]
--       ,[LDHPostOrchidectomy]
--       ,[ManagementDeclinedByPatient]
--       ,[MetastaticDiseaseIndicator]
--       ,[MostRecentCa125PriorToThisReferral]
--       ,[NewBiopsy]
--       ,[NumberOfProceduresForThisCancer]
--       ,[OriginalHistologyReviewedBySMDT]
--       ,[OtherPreviousTreatmentForThisCancer]
--       ,[PathologicalTStage]
--       ,[PatientAppropriateForGoldStandardsFramework]
--       ,[PatientWasReferredForSecondOpinion]
--       ,[PerformanceStatus]
--       ,[PlannedChemotherapyRegimen]
--       ,[PreviousChemotherapyLines]
--       ,[PreviousChemotherapyRegimen1]
--       ,[PreviousChemotherapyRegimen3]
--       ,[PreviousChemotherapyRegimens]
--       ,[PreviousRadiotherapySite]
--       ,[PreviousSurgicalProcedureForThisCancer]
--       ,[PreviousSurgicalProcedureForThisCancer2]
--       ,[PreviousTreatmentForThisCancer]
--       ,[PrimaryDiseaseSite]
--       ,[PrimaryTreatmentGivenWithCurativeIntent]
--       ,[ReferredBy]
--       ,[ReferringHospital]
--       ,[ResponsibleConsultant]
--       ,[SeenBy]
--       ,[SeenByKeyWorker]
--       ,[Side]
--       ,[SitesOfCurrentDisease]
--       ,[SitesOfCurrentDiseaseReviewedBySMDT]
--       ,[StageReviewedBySMDT]
--       ,[SubsequentChemotherapyPlanned]
--       ,[SynchronousBilateralTumours]
--       ,[TesticularDescent]
--       ,[TreatmentIntent]
--       ,[TreatmentStatusForThisCancer]
--       ,[TrialName]
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
FROM [SharedCare].[Cancer_Germ_Cell_Tumour_GCT_Male];

/* Drop the columns that are not needed */
ALTER TABLE #TempTable
DROP COLUMN [FK_Patient_Link_ID], [FK_Patient_ID];

SELECT * FROM #TempTable;