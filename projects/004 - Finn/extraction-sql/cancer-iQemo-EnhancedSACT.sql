--┌─────────────────────────────────┐
--│ Cancer iQemo EnhancedSACT       │
--└─────────────────────────────────┘


-- OUTPUT: A single table with the following:
--       [PK_iQemo_EnhancedSACT_ID]
--       ,[FK_Patient_ID]
--       ,[FK_Patient_Link_ID]
--       ,[FK_Reference_Tenancy_ID]
--       ,[CreateDate]
--       ,[ModifDate]
--       ,[LoadID]
--       ,[Deleted]
--       ,[HDMModifDate]
--       ,[PrimaryDiagnosisICD]
--       ,[PrimaryDiagnosisDescription]
--       ,[SubDiagnosisDescription]
--       ,[Consultant]
--       ,[ConsultantGMCCode]
--       ,[ConsultantSpecialityCode]
--       ,[TNMStageGrouping]
--       ,[PrescriptionDate]
--       ,[PrescribedBy]
--       ,[ScreenedDate]
--       ,[ScreenedBy]
--       ,[Screened]
--       ,[GoAheadGivenDate]
--       ,[GoAheadGivenBy]
--       ,[RegimenLocal]
--       ,[RegimenNational]
--       ,[ProgrammeNumber]
--       ,[RegimenNumber]
--       ,[RegimenStartDate]
--       ,[TreatmentIntent]
--       ,[TreatmentIntentDescription]
--       ,[DecisionToTreatDate]
--       ,[PerformanceStatusAtStartOfRegimen]
--       ,[CoMorbidityAdjustment]
--       ,[ClinicalTrial]
--       ,[ChemoRadiation]
--       ,[PlannedCycles]
--       ,[OPCSProcurementCode]
--       ,[OPCSDeliveryCode]
--       ,[RegimenCancelled]
--       ,[CycleCancelled]
--       ,[CycleCancellationReason]
--       ,[DayCancelled]
--       ,[DrugCancelled]
--       ,[CycleNumber]
--       ,[CycleStartDate]
--       ,[PerformanceStatusAtStartOfCycle]
--       ,[CycleCompleted]
--       ,[DrugCategoryID]
--       ,[DrugCategoryName]
--       ,[DrugName]
--       ,[AdministrationStatus]
--       ,[AdministrationDate]
--       ,[ActualDose]
--       ,[ActualDoseUnit]
--       ,[RouteSACTCode]
--       ,[RouteOfAdministration]
--       ,[LocationOfAdministration]
--       ,[PrivatePatient]
--       ,[PharmacyUnit]
--       ,[RegimenDateOfFinalTreatment]
--       ,[RegimenModificationDoseReduction]
--       ,[RegimenModificationTimeDelay]
--       ,[RegimenOutcomeSummary]
--       ,[SACTSubmission]
--       ,[DateCreated]
--       ,[DateUpdated]
--       ,[DrugFormDescription]
--       ,[ProtonActivity] 

--Just want the output, not the messages
SET NOCOUNT ON;


/* simulating a select * except one column */
IF OBJECT_ID('tempdb..#TempTable') IS NOT NULL DROP TABLE #TempTable;
SELECT [FK_Patient_Link_ID] AS PatientID, * INTO #TempTable
FROM [SharedCare].[Cancer_iQemo_EnhancedSACT];

/* Drop the columns that are not needed */
ALTER TABLE #TempTable
DROP COLUMN [FK_Patient_Link_ID], [FK_Patient_ID];

SELECT * FROM #TempTable;