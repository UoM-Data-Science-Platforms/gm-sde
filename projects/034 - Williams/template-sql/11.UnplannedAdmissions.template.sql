--+--------------------------------------------------------------------------------+
--¦ An unplanned hospital admission                                                ¦
--+--------------------------------------------------------------------------------+

-------- RESEARCH DATA ENGINEER CHECK ---------

-- OUTPUT: Data with the following fields
-- PatientId
-- Date (YYYY/MM/DD) 


-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2019-01-01';

--Just want the output, not the messages
SET NOCOUNT ON;


-- Create a table with all patients (ID)=========================================================================================================================
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT DISTINCT FK_Patient_Link_ID INTO #Patients FROM [RLS].vw_Patient;

--> EXECUTE query-classify-secondary-admissions.sql


-- Create the table of secondary admision===============================================================================================================
SELECT DISTINCT FK_Patient_Link_ID AS PatientId, AdmissionDate AS Date
FROM #AdmissionTypes
WHERE YEAR (AdmissionDate) >= 2019 AND AdmissionType = 'Unplanned';


