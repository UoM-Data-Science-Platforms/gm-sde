--┌─────────────────────────────────┐
--│ Cancer Thyroid and Parathyroid  │
--└─────────────────────────────────┘


-- OUTPUT: A single table with the following:
--       [PK_Thyroid_And_Parathyroid_ID]
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
--       ,[AlteredAirway]
--       ,[BasisOfDiagnosis]
--       ,[BenignEyeDiseaseKimi]
--       ,[BodyMassIndex]
--       ,[CapsularInvasion]
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
--       ,[DefinitiveTreatmentPlanned]
--       ,[Diagnosis]
--       ,[Differentiation]
--       ,[DifferentiationFromNewBiopsy]
--       ,[DiseasePattern]
--       ,[DiseaseFreeFollowingPrimaryTreatment]
--       ,[EarSubsite]
--       ,[EntryIntoAClinicalTrial]
--       ,[ExtraCapsularSpread]
--       ,[ExtraParathyroidExtension]
--       ,[ExtraThyroidExtension]
--       ,[Height]
--       ,[HistolHasBeenTest]
--       ,[Histology]
--       ,[HistologySecondProcedure]
--       ,[HistologyThirdProcedure]
--       ,[HistologyFromNewBiopsy]
--       ,[HPVStatus]
--       ,[HypopharynxSubsite]
--       ,[ImmediateProposedManagement]
--       ,[InvolvedNodes]
--       ,[IsSubsequentRadiotherapyPlanned]
--       ,[IsSubsequentRAIPlanned]
--       ,[IsTheSizeOfTheLargestLesionKnown]
--       ,[KeyWorkerName]
--       ,[LarynxSubsite]
--       ,[LVSI]
--       ,[ManagementDeclinedByPatient]
--       ,[MetastaticDiseaseIndicator]
--       ,[MixedHistologyDetailsOfSecondProcedure]
--       ,[MixedHistologyDetailsOfThirdProcedure]
--       ,[MixedHistologyDetails]
--       ,[MixedHistologyNewBiopsy]
--       ,[MutifocalDiseaseWithinTheThyroidGland]
--       ,[NewBiopsy]
--       ,[NodalExtraCapsularExtension]
--       ,[NodalStatus]
--       ,[NoseAndSinusesSubsite]
--       ,[NoseSubsite]
--       ,[NumberOfInvolvedNodesCentral]
--       ,[NumberOfInvolvedNodesLeftLateral]
--       ,[NumberOfInvolvedNodesRightLateral]
--       ,[NumberOfNodesResectedLeft]
--       ,[NumberOfNodesResectedRight]
--       ,[NumberOfPositiveNodesLeft]
--       ,[NumberOfPositiveNodesRight]
--       ,[NumberOfSurgicalProceduresToPrimarySite]
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
--       ,[PreviousRadioiodineTreatment]
--       ,[PreviousRadiotherapySite]
--       ,[PreviousSACTForParathyroidCancer]
--       ,[PreviousSACTForThyroidCancer]
--       ,[PreviousSACTRegimens]
--       ,[PreviousSurgicalProcedureForThisCancer]
--       ,[PreviousTreatmentForThisCancer]
--       ,[PrimaryDiseaseSite]
--       ,[PrimaryTreatmentGivenWithCurativeIntent]
--       ,[ReferredBy]
--       ,[ReferringHospital]
--       ,[ResectionMarginDistance]
--       ,[ResponsibleConsultant]
--       ,[SalivaryGlandsSubsite]
--       ,[SeenBy]
--       ,[SeenByKeyWorker]
--       ,[SitesOfCurrentDisease]
--       ,[SizeOfLargestLesion]
--       ,[SmokingHistory]
--       ,[SupraglottisSubsite]
--       ,[TreatmentIntent]
--       ,[TreatmentStatusForThisCancer]
--       ,[TrialName]
--       ,[VascularInvasion]
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
FROM [SharedCare].[Cancer_Thyroid_And_Parathyroid];

/* Drop the columns that are not needed */
ALTER TABLE #TempTable
DROP COLUMN [PK_Thyroid_And_Parathyroid_ID], [FK_Patient_Link_ID], [FK_Patient_ID];

SELECT * FROM #TempTable;