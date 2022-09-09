--+--------------------------------------------------------------------------------+
--¦ OOH or A&E attendance                                                          ¦
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
FROM RLS.vw_Patient_GP_History
GROUP BY FK_Patient_Link_ID
HAVING MIN(StartDate) < '2022-06-01';

IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #Patients 
FROM #PatientsToInclude;


-- Create the final table==========================================================================================================================================
-- No OOH data is available so this is only for A&E attendance
SELECT DISTINCT FK_Patient_Link_ID AS PatientID, TRY_CONVERT(DATE, AttendanceDate) AS Date
FROM [RLS].[vw_Acute_AE]
WHERE EventType = 'Attendance' AND TRY_CONVERT(DATE, AttendanceDate) >= @StartDate AND TRY_CONVERT(DATE, AttendanceDate) < @EndDate
      AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);