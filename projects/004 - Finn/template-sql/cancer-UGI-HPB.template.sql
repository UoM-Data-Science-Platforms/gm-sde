--┌─────────────────────────────────┐
--│ Cancer UGI HPB                  │
--└─────────────────────────────────┘


-- OUTPUT: A single table with the following:
--       [PK_UGI_HPB_ID]
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
--       ,[AnalDefunctioning]
--       ,[BasisOfDiagnosis]
--       ,[BodyMassIndex]
--       ,[ClinicalFrailtyScale]
--       ,[ClinicalNodalStagingTable]
--       ,[ClinicalStage]
--       ,[ConsultantConferred]
--       ,[CriteriaForGeneticCounsellingReferral]
--       ,[CurrentDiseaseStatusForThisCancer]
--       ,[CurrentProgressiveDisease]
--       ,[DateOfBiopsy]
--       ,[DateOfDiagnosis]
--       ,[DateOfDiseaseProgression]
--       ,[DateOfFDGPET]
--       ,[DateOfFirstRadiologicalImagingSuggestingMalignancy]
--       ,[DateOfOriginalDiagnosis]
--       ,[DateOfReferralForGeneticCounselling]
--       ,[DateOfRelapse]
--       ,[DateOfSmokingCessation]
--       ,[DateOfSurgery]
--       ,[DateSeen]
--       ,[DateSymptomsFirstNoted]
--       ,[DefinitiveSurgeryPlanned]
--       ,[DiabeticStatus]
--       ,[Diagnosis]
--       ,[Differentiation]
--       ,[DifferentiationFromNewBiopsy]
--       ,[DiseaseFreeFollowingPrimaryTreatment]
--       ,[EntryIntoAClinicalTrial]
--       ,[EstimationOfPrognosis]
--       ,[EstimationOfWeightLoss]
--       ,[FDGPETFindings]
--       ,[HasAFDGPETBeenRequested]
--       ,[HasThePatientBeenReferredForGeneticCounselling]
--       ,[HasThePatientBeenReferredToTheCommunityDietitian]
--       ,[HasThePatientExperiencedWeightLossPriorToThisAppointment]
--       ,[HasThePatientHadAFDGPET]
--       ,[HasThePatientReceivedPreviousTreatmentForThisCancer]
--       ,[Height]
--       ,[Histology]
--       ,[HistologyFromNewBiopsy]
--       ,[ImmediateProposedManagement]
--       ,[IndwellingBiliaryStent]
--       ,[IsThereAnyPersonalOrFamilyHistoryOfCancer]
--       ,[IsThisTheDateOfDiagnosis]
--       ,[KeyWorkerName]
--       ,[LVSI]
--       ,[ManagementDeclinedByPatient]
--       ,[MetastaticDiseaseIndicator]
--       ,[NameOfClinicalTrial]
--       ,[NewBiopsy]
--       ,[NodalSurgery]
--       ,[OtherPreviousTreatmentForThisCancer]
--       ,[OtherSiteSOfCurrentDisease]
--       ,[OverHowManyMonths]
--       ,[PathStage]
--       ,[PatientAppropriateForGoldStandardsFramework]
--       ,[PatientAwarenessOfPrognosis]
--       ,[PatientWasReferredForSecondOpinion]
--       ,[PerformanceStatus]
--       ,[PlannedChemotherapyRegimen]
--       ,[PreviousChemotherapyLines]
--       ,[PreviousChemotherapyRegimen2]
--       ,[PreviousChemotherapyRegimen3]
--       ,[PreviousChemotherapyRegimens]
--       ,[PreviousSurgicalProcedureForThisCancer]
--       ,[PreviousTreatmentForThisCancer]
--       ,[PrimaryDiseaseSite]
--       ,[PrimaryTreatmentGivenWithCurativeIntent]
--       ,[RStage]
--       ,[ReferredBy]
--       ,[ReferringHospital]
--       ,[ResectionMarginDistance]
--       ,[ResponsibleConsultant]
--       ,[SeenBy]
--       ,[SeenByKeyWorker]
--       ,[SitesOfCurrentDisease]
--       ,[SmokingHistory]
--       ,[TreatmentIntent]
--       ,[TreatmentStatusForThisCancer]
--       ,[TrialName]
--       ,[TumourResection]
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
FROM [SharedCare].[Cancer_UGI_HPB];

/* Drop the columns that are not needed */
ALTER TABLE #TempTable
DROP COLUMN [PK_UGI_HPB_ID], [FK_Patient_Link_ID], [FK_Patient_ID];

SELECT * FROM #TempTable;