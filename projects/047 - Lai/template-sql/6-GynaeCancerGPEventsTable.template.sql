﻿--+--------------------------------------------------------------------------------+
--¦ Gynae cancer information from the GPEvents table (cohort 2)                    ¦
--+--------------------------------------------------------------------------------+

-------- RESEARCH DATA ENGINEER CHECK ---------
-- George Tilston 06/10/23

-- OUTPUT: Data with the following fields
-- PatientId
-- EventDate (YYYY-MM-DD)
-- GynaeCancerRelatedCode (code values)


--> CODESET gynaecological-cancer:1


-- Set the start date
DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2011-01-01';
SET @EndDate = '2023-09-22';

--Just want the output, not the messages
SET NOCOUNT ON;


-- Create the gynae cancer cohort========================================================================================================
IF OBJECT_ID('tempdb..#GynaeCohort') IS NOT NULL DROP TABLE #GynaeCohort;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #GynaeCohort
FROM SharedCare.GP_Events
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'gynaecological-cancer' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'gynaecological-cancer' AND Version = 1)
) AND EventDate >= @StartDate AND EventDate < @EndDate;


-- Create a table with all patients within the gynae cohort=========================================================================================================================
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT PK_Patient_Link_ID AS FK_Patient_Link_ID INTO #Patients
FROM SharedCare.Patient_Link
WHERE PK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #GynaeCohort);


-- Select event date and skin cancer related codes====================================================================================================================
IF OBJECT_ID('tempdb..#Table') IS NOT NULL DROP TABLE #Table;
SELECT DISTINCT FK_Patient_Link_ID AS PatientId, 
				CONVERT(date, EventDate) AS EventDate, 
				FK_Reference_Coding_ID,
				FK_Reference_SnomedCT_ID
INTO #Table
FROM SharedCare.GP_Events
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'gynaecological-cancer' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'gynaecological-cancer' AND Version = 1)
)     AND EventDate < @EndDate
      AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);

SELECT DISTINCT PatientId, 
	            EventDate, 
		    CASE
		    WHEN c.MainCode IS NOT NULL THEN c.MainCode
		    ELSE s.ConceptID
		    END AS GynaeCancerRelatedClinicalCode
FROM #Table t
LEFT OUTER JOIN SharedCare.Reference_Coding c ON c.PK_Reference_Coding_ID = t.FK_Reference_Coding_ID
LEFT OUTER JOIN SharedCare.Reference_SnomedCT s ON s.PK_Reference_SnomedCT_ID = t.FK_Reference_SnomedCT_ID
ORDER BY PatientId, EventDate;



