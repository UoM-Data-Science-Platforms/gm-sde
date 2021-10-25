--┌─────────────────────────────────┐
--│ Cancer head and neck            │
--└─────────────────────────────────┘


-- OUTPUT: A single table with the following:
--       [PK_Head_And_Neck_ID]
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
--       ,[AlcoholIntake]
--       ,[BasisOfDiagnosis]
--       ,[BodyMassIndex]
--       ,[BowelFunction]
--       ,[ClinicalStage]
--       ,[ConsultantConferred]
--       ,[CurrentDiseaseStatusForThisCancer]
--       ,[CurrentProgressiveDisease]
--       ,[DateOfDiagnosis]
--       ,[DateOfDiseaseProgression]
--       ,[DateOfOriginalDiagnosis]
--       ,[DateOfRelapse]
--       ,[DateOfSmokingCessation]
--       ,[DateOfSurgery]
--       ,[DateSeen]
--       ,[DateSymptomsFirstNoted]
--       ,[DefinitiveSurgeryPlanned]
--       ,[DefinitiveTreatmentPlanned]
--       ,[Diagnosis]
--       ,[Differentiation]
--       ,[DifferentiationFromNewBiopsy]
--       ,[DiseaseFreeFollowingPrimaryTreatment]
--       ,[DoesThePatientHaveATracheostomy]
--       ,[EarSubsite]
--       ,[EntryIntoAClinicalTrial]
--       ,[Height]
--       ,[HistolHasBeenTest]
--       ,[Histology]
--       ,[HistologyFromNewBiopsy]
--       ,[HPVStatus]
--       ,[HypopharynxSubsite]
--       ,[ImmediateProposedManagement]
--       ,[KeyWorkerName]
--       ,[LarynxSubsite]
--       ,[LVSI]
--       ,[LVSIFromNewBiopsy]
--       ,[ManagementDeclinedByPatient]
--       ,[MetastaticDiseaseIndicator]
--       ,[NewBiopsy]
--       ,[NodalExtraCapsularExtension]
--       ,[NodalStatus]
--       ,[NoseAndSinusesSubsite]
--       ,[NoseSubsite]
--       ,[NumberOfNodesResectedLeft]
--       ,[NumberOfNodesResectedRight]
--       ,[NumberOfPositiveNodesLeft]
--       ,[NumberOfPositiveNodesRight]
--       ,[NumberOfProceduresForThisCancer]
--       ,[OralCavitySubsite]
--       ,[OropharynxSubsite]
--       ,[PackYears]
--       ,[PathStage]
--       ,[PatientAppropriateForGoldStandardsFramework]
--       ,[PatientWasReferredForSecondOpinion]
--       ,[PerformanceStatus]
--       ,[PharynxSubsite]
--       ,[PlannedConcurrentSACTRegimen]
--       ,[PlannedDefinitiveTreatment]
--       ,[PlannedSACTRegimen]
--       ,[PlannedTotalNumberOfFractions]
--       ,[PreviousConcurrentSACTRegimens]
--       ,[PreviousHormonalTreatmentForBreastCancer]
--       ,[PreviousRadiotherapyCentre]
--       ,[PreviousRadiotherapySite]
--       ,[PreviousSACTLines]
--       ,[PreviousSACTRegimen2]
--       ,[PreviousSACTRegimen3]
--       ,[PreviousSACTRegimens]
--       ,[PreviousSurgicalProcedureForThisCancer]
--       ,[PreviousSurgicalProcedureForThisCancer2]
--       ,[PreviousSurgicalProcedureForThisCancer3]
--       ,[PreviousTreatmentForThisCancer]
--       ,[PrimaryDiseaseSite]
--       ,[PrimaryTreatmentGivenWithCurativeIntent]
--       ,[ReferredBy]
--       ,[ReferredToOrSeenByDentist]
--       ,[ReferredToOrSeenByDietitian]
--       ,[ReferredToOrSeenByHealthPromotionAdvisor]
--       ,[ReferredToOrSeenBySpeechAndLanguageTherapist]
--       ,[ReferringHospital]
--       ,[ResectionMarginDistance]
--       ,[ResponsibleConsultant]
--       ,[SalivaryGlandsSubsite]
--       ,[SeenBy]
--       ,[SeenByKeyWorker]
--       ,[SexualFunction]
--       ,[SitesOfCurrentDisease]
--       ,[SitesOfPlannedRadiotherapy]
--       ,[SmokingHistory]
--       ,[SubsequentBrachytherapyPlanned]
--       ,[SubsequentChemotherapyPlanned]
--       ,[SubsequentRadiotherapyPlanned]
--       ,[SupraglottisSubsite]
--       ,[SynchronousOvarianTumour]
--       ,[Tracheostomy]
--       ,[TreatmentIntent]
--       ,[TreatmentStatusForThisCancer]
--       ,[TrialName]
--       ,[UrinaryFunction]
--       ,[Weight]
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
FROM [SharedCare].[Cancer_Head_and_Neck];

/* Drop the columns that are not needed */
ALTER TABLE #TempTable
DROP COLUMN [FK_Patient_Link_ID], [FK_Patient_ID];

SELECT * FROM #TempTable;