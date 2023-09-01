--+--------------------------------------------------------------------------------+
--¦ An unplanned hospital admission                                                ¦
--+--------------------------------------------------------------------------------+

-------- RESEARCH DATA ENGINEER CHECK ---------

-- OUTPUT: Data with the following fields
-- PatientId
-- Date (YYYY/MM/DD) 


-- Set the start date
DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2019-01-01';
SET @EndDate = '2022-06-01';

--Just want the output, not the messages
SET NOCOUNT ON;


-- Create a table with all patients (ID)=========================================================================================================================
IF OBJECT_ID('tempdb..#PatientsToInclude') IS NOT NULL DROP TABLE #PatientsToInclude;
SELECT FK_Patient_Link_ID INTO #PatientsToInclude
FROM SharedCare.Patient_GP_History
GROUP BY FK_Patient_Link_ID
HAVING MIN(StartDate) < '2022-06-01';

IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #Patients 
FROM #PatientsToInclude;

--> EXECUTE query-classify-secondary-admissions.sql


-- Create the table of secondary admision===============================================================================================================
SELECT DISTINCT FK_Patient_Link_ID AS PatientId, AdmissionDate AS Date, AcuteProvider AS HospitalTrust
FROM #AdmissionTypes
WHERE AdmissionDate >= @StartDate AND AdmissionDate < @EndDate 
      AND AdmissionType = 'Unplanned' AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude)
ORDER BY FK_Patient_Link_ID;


