--┌─────────────────────────────────┐
--│ Cancer Uterus                   │
--└─────────────────────────────────┘


-- OUTPUT: A single table with the following:
--       [PK_Uterus_Cancer_ID]
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
--       ,[BaselineMorbidity]
--       ,[BaselineMorbidityCTCAE]
--       ,[BaselineMorbidityMeasurements]
--       ,[BasisOfDiagnosis]
--       ,[BMI]
--       ,[BowelFunction]
--       ,[ClinicalFrailtyScale]
--       ,[ClinicalStage]
--       ,[ConsultantConferred]
--       ,[CurrentDiseaseStatusForThisCancer]
--       ,[CurrentProgressiveDisease]
--       ,[DateOfDiagnosis]
--       ,[DateOfDiseaseProgression]
--       ,[DateOfOriginalDiagnosis]
--       ,[DateOfRelapse]
--       ,[DateSeen]
--       ,[DateSymptomsFirstNoted]
--       ,[DefinitiveSurgeryPlanned]
--       ,[Diagnosis]
--       ,[Differentiation]
--       ,[DifferentiationFromNewBiopsy]
--       ,[DiseaseFreeFollowingPrimaryTreatment]
--       ,[EntryIntoAClinicalTrial]
--       ,[FurtherPreviousChemotherapyDetails]
--       ,[Height]
--       ,[Histology]
--       ,[HistologyFromNewBiopsy]
--       ,[ImmediateProposedManagement]
--       ,[KeyWorkerName]
--       ,[LVSI]
--       ,[LVSIFromNewBiopsy]
--       ,[ManagementDeclinedByPatient]
--       ,[MarkerDetailsRelapse]
--       ,[MyometriumNote]
--       ,[NewBiopsy]
--       ,[NumberOfProceduresForThisCancer]
--       ,[PathStage]
--       ,[PatientAppropriateForGoldStandardsFramework]
--       ,[PatientWasReferredForSecondOpinion]
--       ,[PatientRecordedMorbidity]
--       ,[PerformanceStatus]
--       ,[PlannedAccess]
--       ,[PlannedChemotherapyRegimen]
--       ,[PlannedSurgicalProcedures]
--       ,[PreviousChemotherapyLines]
--       ,[PreviousChemotherapyRegimen1]
--       ,[PreviousChemotherapyRegimen2]
--       ,[PreviousChemotherapyRegimen3]
--       ,[PreviousHormonalTreatmentForBreastCancer]
--       ,[PreviousRadiotherapyCentre]
--       ,[PreviousRadiotherapySite]
--       ,[PreviousSurgicalProcedureForThisCancer]
--       ,[PreviousSurgicalProcedureForThisCancer2]
--       ,[PreviousSurgicalProcedureForThisCancer3]
--       ,[PreviousTreatmentForThisCancer]
--       ,[PrimaryDiseaseSite]
--       ,[PrimaryTreatmentGivenWithCurativeIntent]
--       ,[RectalUrgencyBaseline]
--       ,[ReferredBy]
--       ,[ReferringHospital]
--       ,[ResponsibleConsultant]
--       ,[SeenBy]
--       ,[SeenByKeyWorker]
--       ,[SexualFunction]
--       ,[SiteSOfCurrentDisease]
--       ,[SubsequentBrachytherapyPlanned]
--       ,[SubsequentChemotherapyPlanned]
--       ,[SubsequentRadiotherapyPlanned]
--       ,[SynchronousOvarianTumour]
--       ,[TreatmentIntent]
--       ,[TreatmentStatusForThisCancer]
--       ,[TreatmentTypeBrachytherapy]
--       ,[TrialName]
--       ,[TruncatedDataCapture]
--       ,[UrgencyOfDefecationBaseline]
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
FROM [SharedCare].[Cancer_Uterus];

/* Drop the columns that are not needed */
ALTER TABLE #TempTable
DROP COLUMN [FK_Patient_Link_ID], [FK_Patient_ID];

SELECT * FROM #TempTable;