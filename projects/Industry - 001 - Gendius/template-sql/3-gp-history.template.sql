--┌────────────┐
--│ GP history │
--└────────────┘

-- OBJECTIVE: To get the GP history for each patient. NB the first start
--            date for each person may either be the date they started at
--            the practice OR the date they were first loaded into the database.

-- OUTPUT: Data with the following fields
--  - PatientId
--  - StartDate - date (YYYY/MM/DD) - start date at practice
--  - EndDate - date (YYYY/MM/DD) - end date at practice
--  - GPPracticeCode - practice code

--Just want the output, not the messages
SET NOCOUNT ON;

--> EXECUTE query-build-industry-001-cohort.sql extraction-date:2023-09-19

SELECT
  FK_Patient_Link_ID AS PatientId,
  StartDate,
  EndDate,
  GPPracticeCode
FROM SharedCare.Patient_GP_History
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_Tenancy_ID = 2
ORDER BY FK_Patient_Link_ID, StartDate;