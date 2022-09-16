--+--------------------------------------------------------------------------------+
--¦ 3 or more GP encounters in 7 days                                              ¦
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


--> EXECUTE query-patient-gp-encounters.sql all-patients:F gp-events-table:[RLS].[vw_GP_Events] start-date:'2019-01-01' end-date:'2022-06-01'


-- Find the first last and the second last of each GP encounter for each patient=========================================================================
IF OBJECT_ID('tempdb..#Table') IS NOT NULL DROP TABLE #Table;
SELECT *,
		LAG(EncounterDate, 1) OVER (PARTITION BY FK_Patient_Link_ID ORDER BY EncounterDate) AS First_last_GP_encounter,
		LAG(EncounterDate, 2) OVER (PARTITION BY FK_Patient_Link_ID ORDER BY EncounterDate) AS Second_last_GP_encounter
INTO #Table
FROM #GPEncounters;


-- The final table=======================================================================================================================================
-- Do some checks
IF OBJECT_ID('tempdb..#TableCheck') IS NOT NULL DROP TABLE #TableCheck;
SELECT *,
		CASE WHEN EncounterDate <= DATEADD(DAY, 7, First_last_GP_encounter) AND EncounterDate <= DATEADD(DAY, 7, Second_last_GP_encounter)
	    THEN 'Y' ELSE 'N' END AS Check_criteria
INTO #TableCheck
FROM #Table;

-- Create the final table
SELECT FK_Patient_Link_ID AS PatientId, EncounterDate AS Date
FROM #TableCheck
WHERE Check_criteria = 'Y' AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude)
      AND EncounterDate >= @StartDate AND EncounterDate < @EndDate;


