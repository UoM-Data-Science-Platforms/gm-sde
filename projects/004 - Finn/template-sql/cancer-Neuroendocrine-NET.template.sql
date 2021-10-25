--┌─────────────────────────────────┐
--│ Cancer Neuroendocrine NET       │
--└─────────────────────────────────┘


-- OUTPUT: A single table with the following:
--       [PK_Neuroendocrine_NET_ID]
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
--       ,[BasisOfDiagnosis]
--       ,[ClinicalStage]
--       ,[ConsultantConferred]
--       ,[CurrentDiseaseStatusForThisCancer]
--       ,[CurrentProgressiveDisease]
--       ,[DateOfBiopsy]
--       ,[DateOfDiagnosis]
--       ,[DateOfDiseaseProgression]
--       ,[DateOfOriginalDiagnosis]
--       ,[DateOfRelapse]
--       ,[DateOfSmokingCessation]
--       ,[DateOfSurgery]
--       ,[DateSeen]
--       ,[DateSymptomsFirstNoted]
--       ,[DefinitiveSurgeryPlanned]
--       ,[Diagnosis]
--       ,[DiseaseFreeFollowingPrimaryTreatment]
--       ,[EntryIntoAClinicalTrial]
--       ,[FamilialSyndrome]
--       ,[FamilialSyndromeType]
--       ,[Histology]
--       ,[HistologyFromNewBiopsy]
--       ,[ImmediateProposedManagement]
--       ,[IsThisAFunctioningTumour]
--       ,[IsThisTheDateOfDiagnosis]
--       ,[KeyWorkerName]
--       ,[LVSI]
--       ,[ManagementDeclinedByPatient]
--       ,[MetastaticDiseaseIndicator]
--       ,[MIB1ScoreKi67]
--       ,[MultipleTumours]
--       ,[NewBiopsy]
--       ,[NumberOfProceduresForThisCancer]
--       ,[OtherPreviousTreatmentForThisCancer]
--       ,[OtherSiteSOfCurrentDisease]
--       ,[PathStage]
--       ,[PatientAppropriateForGoldStandardsFramework]
--       ,[PatientWasReferredForSecondOpinion]
--       ,[PerformanceStatus]
--       ,[PlannedChemotherapyRegimen]
--       ,[PlannedEmbolisationType]
--       ,[PlannedRadionuclideTherapy]
--       ,[PlannedSomatostatinAnalogue]
--       ,[PlannedTyrosineKinaseInhibitor]
--       ,[PNETType]
--       ,[PreviousChemotherapyLines]
--       ,[PreviousChemotherapyRegimen1]
--       ,[PreviousChemotherapyRegimen2]
--       ,[PreviousChemotherapyRegimen3]
--       ,[PreviousEmbolisationType]
--       ,[PreviousRadionuclideTherapy]
--       ,[PreviousSurgeryForThisCancer]
--       ,[PreviousSurgicalProcedureForThisCancer]
--       ,[PreviousSurgicalProcedureForThisCancer2]
--       ,[PreviousSurgicalProcedureForThisCancer3]
--       ,[PreviousTreatmentForThisCancer]
--       ,[PreviousTyrosineKinaseInhibitor]
--       ,[PrimaryDiseaseSite]
--       ,[PrimaryDiseaseSiteNET]
--       ,[PrimaryTreatmentGivenWithCurativeIntent]
--       ,[ReferredBy]
--       ,[ReferringHospital]
--       ,[ResidualDiseaseType]
--       ,[ResponsibleConsultant]
--       ,[SecretoryHormone]
--       ,[SeenBy]
--       ,[SeenByKeyWorker]
--       ,[SiteSOfCurrentDisease]
--       ,[SmokingHistory]
--       ,[TreatmentIntent]
--       ,[TreatmentStatusForThisCancer]
--       ,[TrialName]
--       ,[TruncatedDataCapture]
--       ,[TumourSizeCm]
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
FROM [SharedCare].[Cancer_Neuroendocrine_NET];

/* Drop the columns that are not needed */
ALTER TABLE #TempTable
DROP COLUMN [FK_Patient_Link_ID], [FK_Patient_ID];

SELECT * FROM #TempTable;