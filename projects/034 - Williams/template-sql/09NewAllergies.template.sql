--+---------------------------------------------------------------------------+
--¦ Patients with a new allergy code                                          ¦
--+---------------------------------------------------------------------------+

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

--> CODESET allergy:1


-- Create a table of all patients with GP events after the start date========================================================================================================
IF OBJECT_ID('tempdb..#AllergyAll') IS NOT NULL DROP TABLE #AllergyAll;
SELECT DISTINCT FK_Patient_Link_ID, TRY_CONVERT(DATE, EventDate) AS EventDate, FK_Reference_Coding_ID
INTO #AllergyAll
FROM SharedCare.GP_Events
WHERE (SuppliedCode IN (SELECT Code FROM #AllCodes WHERE (Concept = 'allergy' AND [Version] = 1)))
      AND EventDate < @EndDate;


-- Create the table of new allergy code=============================================================================================================
SELECT FK_Patient_Link_ID AS PatientId, MIN(EventDate) AS Date
FROM #AllergyAll
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude)
GROUP BY FK_Patient_Link_ID, FK_Reference_Coding_ID
HAVING YEAR(MIN(EventDate)) >= 2019;
