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
--> EXECUTE query-patient-practice-and-ccg.sql

-- Delete code H171. in #AllCodes table==================================================================================================================================
-- This will delete 5 codes: Cat allergy, Dander (animal) allergy, House dust allergy, Feather allergy, House dust mite allergy
DELETE FROM #AllCodes WHERE Code = 'H171.'

-- Create a table of all patients with GP events after the start date========================================================================================================
IF OBJECT_ID('tempdb..#AllergyAll') IS NOT NULL DROP TABLE #AllergyAll;
SELECT DISTINCT p.FK_Patient_Link_ID, TRY_CONVERT(DATE, EventDate) AS EventDate, SuppliedCode, gp.GPPracticeCode
INTO #AllergyAll
FROM SharedCare.GP_Events p
LEFT OUTER JOIN #PatientPractice gp ON p.FK_Patient_Link_ID = gp.FK_Patient_Link_ID
WHERE (SuppliedCode IN (SELECT Code FROM #AllCodes WHERE (Concept = 'allergy' AND [Version] = 1)))
      AND EventDate < @EndDate;


-- Found 2 codes with strange strikes in practice P87002. Exclude these codes in this practice==================================================================
DELETE FROM #AllergyAll WHERE (GPPracticeCode = 'P87002' AND SuppliedCode = 'TJC24') 
                              OR (GPPracticeCode = 'P87002' AND SuppliedCode = 'TJC47')


-- Create the table of new allergy code=============================================================================================================
SELECT FK_Patient_Link_ID AS PatientId, MIN(EventDate) AS Date
FROM #AllergyAll
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude)
GROUP BY FK_Patient_Link_ID, SuppliedCode
HAVING YEAR(MIN(EventDate)) >= 2019;
