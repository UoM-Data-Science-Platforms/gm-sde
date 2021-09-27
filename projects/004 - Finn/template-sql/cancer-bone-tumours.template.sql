--┌─────────────────────────────────┐
--│ Cancer bone tumours             │
--└─────────────────────────────────┘


-- OUTPUT: A single table with the following:
--       [PK_Bone_Tumours_ID]
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
--       ,[DateOfDiagnosis]
--       ,[DateOfDiseaseProgression]
--       ,[DateOfMostRecentSurgery]
--       ,[DateOfOriginalDiagnosis]
--       ,[DateOfRelapse]
--       ,[DateSeen]
--       ,[DateSymptomsFirstNoted]
--       ,[DefinitiveSurgeryPlanned]
--       ,[Diagnosis]
--       ,[DigitNumber]
--       ,[DiseaseFreeFollowingPrimaryTreatment]
--       ,[EntryIntoAClinicalTrial]
--       ,[Grade]
--       ,[GradeFromNewBiopsy]
--       ,[Histology]
--       ,[HistologyFromNewBiopsy]
--       ,[ImmediateProposedManagement]
--       ,[KaposisStaging]
--       ,[KeyWorkerName]
--       ,[ManagementDeclinedByPatient]
--       ,[MetastaticDiseaseIndicator]
--       ,[MultipleSitesKaposis]
--       ,[NewBiopsy]
--       ,[PathStage]
--       ,[PatientAppropriateForGoldStandardsFramework]
--       ,[PatientWasReferredForSecondOpinion]
--       ,[PerformanceStatus]
--       ,[PlannedChemotherapyRegimen]
--       ,[PreviousChemotherapyRegimens]
--       ,[PreviousRadiotherapySites]
--       ,[PreviousSurgeryForThisCancer]
--       ,[PreviousTreatmentForThisCancer]
--       ,[PrimaryDiseaseSite]
--       ,[PrimaryTreatmentGivenWithCurativeIntent]
--       ,[ReferredBy]
--       ,[ReferringHospital]
--       ,[ResectionMarginDistance]
--       ,[ResponsibleConsultant]
--       ,[RibNumber]
--       ,[SeenBy]
--       ,[SeenByKeyWorker]
--       ,[SideOfPrimaryDisease]
--       ,[SitesOfCurrentDisease]
--       ,[SitesOfPlannedRadiotherapy]
--       ,[TreatmentIntent]
--       ,[TreatmentStatusForThisCancer]
--       ,[TrialName]
--       ,[VertebraNumber]
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
FROM [SharedCare].[Cancer_Bone_Tumours];

/* Drop the columns that are not needed */
ALTER TABLE #TempTable
DROP COLUMN [FK_Patient_Link_ID], [FK_Patient_ID];

SELECT * FROM #TempTable;