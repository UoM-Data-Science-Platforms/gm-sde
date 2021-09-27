--┌─────────────────────────────────┐
--│ Cancer COG Form Neuro-oncology CNS│
--└─────────────────────────────────┘


-- OUTPUT: A single table with the following:
--       [PK_COG_Form_Neuro-oncology_CNS_ID]
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
--       ,[<\/B><I>Diagnosis<\/I><B>]
--       ,[<\/B><I>PrognosticMarkers<\/I><B>]
--       ,[<B><I>DataSpecificTo<\/I><\/B>]
--       ,[1P\/19QStatus]
--       ,[ACEComorbidities]
--       ,[BasisOfDiagnosis]
--       ,[BasisOfHistology]
--       ,[ConsultantConferred]
--       ,[DateOfDiagnosis]
--       ,[DateSeen]
--       ,[DefinitionOfResidualDisease]
--       ,[Diagnosis]
--       ,[Differentiation]
--       ,[DiseaseStatusAtPresentation]
--       ,[ECOGPerformanceStatus]
--       ,[EntryIntoAClinicalTrial]
--       ,[ER]
--       ,[FurtherProposedManagement]
--       ,[Histology]
--       ,[IDH1]
--       ,[ImmediateProposedManagement]
--       ,[Ki67]
--       ,[MGMTMethylationStatus]
--       ,[NonBrainPrimary]
--       ,[PerformanceStatusAvailable]
--       ,[PR]
--       ,[PrimaryDiseaseSite]
--       ,[ReferredBy]
--       ,[ReferringHospital]
--       ,[ResponsibleConsultant]
--       ,[SeenBy]
--       ,[Side]
--       ,[SurgicalExtent]
--       ,[TreatmentIntent]
--       ,[TumourLocationAndExtent]
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
SELECT [FK_Patient_Link_ID] AS PatientID, * INTO #TempTable
FROM [SharedCare].[Cancer_COG_Form_Neuro-oncology_CNS];

/* Drop the columns that are not needed */
ALTER TABLE #TempTable
DROP COLUMN [FK_Patient_Link_ID], [FK_Patient_ID];

SELECT * FROM #TempTable;