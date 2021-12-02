--┌─────────────────────────────────┐
--│ Cancer clinical outcomes        │
--└─────────────────────────────────┘


-- OUTPUT: A single table with the following:
--       [PK_Clinical_Outcomes_Forms_Stage_ID]
--       ,[FK_Patient_ID]
--       ,[FK_Patient_Link_ID]
--       ,[FK_Reference_Tenancy_ID]
--       ,[ExternalID]
--       ,[CreateDate]
--       ,[ModifDate]
--       ,[LoadID]
--       ,[Deleted]
--       ,[HDMModifDate]
--       ,[Date of Death]
--       ,[Date of Birth]
--       ,[Age]
--       ,[Patients Postcode]
--       ,[date_seen]
--       ,[primary_disease_site]
--       ,[side]
--       ,[histology]
--       ,[responsible_consultant]
--       ,[stage_table_link]
--       ,[FormName]
--       ,[stage_grouping]
--       ,[stage_grouping_full]
--       ,[T]
--       ,[N]
--       ,[M]
--       ,[date_of_diagnosis]
--       ,[date_of_relapse]
--       ,[basis_of_diagnosis]
--       ,[referring_hospital]
--       ,[date_symptoms_first_noted]
--       ,[performance_status]
--       ,[comorbidities_score]
--       ,[differentiation]
--       ,[ACE_comorbidities]
--       ,[treatment_intent]
--       ,[immediate_proposed_management]
--       ,[FIGO]
--       ,[FullAnnArborStage]
--       ,[Ann Arbor]
--       ,[Ann Arbor Extranodality]
--       ,[Ann Arbor Bulk]
--       ,[Ann Arbor Splenic Involvement]
--       ,[Ann Arbor Symptoms]
--       ,[Masaoka Stage]
--       ,[Seen_by]
--       ,[responsible_consultant_title]
--       ,[treatment_status_for_this_cancer]
--       ,[current_disease_status_for_this_cancer]
--       ,[previous_treatment]
--       ,[sites_of_current_disease]
--       ,[metastatic_disease_indicator]
--       ,[M_Code]
--       ,[reporting_site]
--       ,[icd_10]
--       ,[primary_disease_site_specific]
--       ,[referring_hospital_code]
--       ,[stage_type]
--       ,[FormID]
--       ,[Provenance]
--       ,[FormFamName]
--       ,[FormTypeID]
--       ,[FormTypeName]
--       ,[Pathway Type]
  

--Just want the output, not the messages
SET NOCOUNT ON;


/* simulating a select * except one column */
IF OBJECT_ID('tempdb..#TempTable') IS NOT NULL DROP TABLE #TempTable;
SELECT [FK_Patient_Link_ID] AS PatientId, * INTO #TempTable
FROM [SharedCare].[Cancer_Clinical_Outcomes];

/* Drop the columns that are not needed */
ALTER TABLE #TempTable
DROP COLUMN [PK_Clinical_Outcomes_Forms_Stage_ID], [FK_Patient_Link_ID], [FK_Patient_ID];

SELECT * FROM #TempTable;